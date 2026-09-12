import AppKit

extension Notification.Name {
    public static let songTopSettingsChanged = Notification.Name("com.songtop.settingsChanged")
}

public enum DisplayMode: Int {
    case hoverDropdown = 0
    case alwaysFloating = 1
    case menuBarOnly = 2
}

public final class FloatingPillWindowController: NSObject {
    private var pillPanel: NSPanel?
    private var pillView: FloatingPillView?
    private var detector: YouTubeDetector
    
    // Dedicated background timer for cursor tracking (immune to main runloop freezes)
    private var mouseTrackerTimer: DispatchSourceTimer?
    private let mouseQueue = DispatchQueue(label: "com.songtop.mousetracker", qos: .userInteractive)
    
    private var retractTimer: Timer?
    private var hoverStartTime: Date?
    
    // Cached frame for thread-safe access from mouseQueue
    private var cachedPillRect: NSRect = .zero
    private var isPillVisibleInternal: Bool = false
    
    // Trigger zone visual guide panel
    private var guidePanel: NSPanel?
    private var guideLabel: NSTextField?
    private var guideHideTimer: Timer?
    public private(set) var isGuidePinned: Bool = false
    
    public private(set) var isDroppedDown: Bool = false
    private var isHoveringActive: Bool = false
    private var lastTrackId: String = ""
    
    // Customizable scan dimensions
    public var scanWidth: CGFloat = 850 {
        didSet {
            UserDefaults.standard.set(Double(scanWidth), forKey: "scanWidth")
        }
    }
    public var scanHeight: CGFloat = 75 {
        didSet {
            UserDefaults.standard.set(Double(scanHeight), forKey: "scanHeight")
        }
    }
    public var hoverDelay: Double = 0.0 {
        didSet {
            UserDefaults.standard.set(hoverDelay, forKey: "hoverDelay")
        }
    }
    public var peekDuration: Double = 5.0 {
        didSet {
            UserDefaults.standard.set(peekDuration, forKey: "peekDuration")
        }
    }
    public var autoPeekEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoPeekEnabled, forKey: "autoPeekEnabled")
        }
    }
    
    public var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isPillEnabled")
            if !isEnabled {
                retract(immediately: true)
                stopMouseTracking()
            } else {
                startMouseTracking()
                if !hoverDropOnly {
                    dropDown()
                }
            }
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        }
    }
    
    public var hoverDropOnly: Bool = true {
        didSet {
            UserDefaults.standard.set(hoverDropOnly, forKey: "hoverDropOnly")
            if !hoverDropOnly {
                dropDown()
            } else {
                retract()
            }
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        }
    }
    
    public var displayMode: DisplayMode {
        get {
            if !isEnabled { return .menuBarOnly }
            return hoverDropOnly ? .hoverDropdown : .alwaysFloating
        }
        set {
            switch newValue {
            case .hoverDropdown:
                isEnabled = true
                hoverDropOnly = true
            case .alwaysFloating:
                isEnabled = true
                hoverDropOnly = false
            case .menuBarOnly:
                isEnabled = false
            }
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        }
    }
    
    public init(detector: YouTubeDetector) {
        self.detector = detector
        super.init()
        
        if UserDefaults.standard.object(forKey: "isPillEnabled") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "isPillEnabled")
        }
        if UserDefaults.standard.object(forKey: "hoverDropOnly") != nil {
            self.hoverDropOnly = UserDefaults.standard.bool(forKey: "hoverDropOnly")
        }
        if UserDefaults.standard.object(forKey: "scanWidth") != nil {
            self.scanWidth = CGFloat(UserDefaults.standard.double(forKey: "scanWidth"))
        }
        if UserDefaults.standard.object(forKey: "scanHeight") != nil {
            self.scanHeight = CGFloat(UserDefaults.standard.double(forKey: "scanHeight"))
        }
        if UserDefaults.standard.object(forKey: "hoverDelay") != nil {
            self.hoverDelay = UserDefaults.standard.double(forKey: "hoverDelay")
        }
        if UserDefaults.standard.object(forKey: "peekDuration") != nil {
            self.peekDuration = UserDefaults.standard.double(forKey: "peekDuration")
        }
        if UserDefaults.standard.object(forKey: "autoPeekEnabled") != nil {
            self.autoPeekEnabled = UserDefaults.standard.bool(forKey: "autoPeekEnabled")
        }
        
        startMouseTracking()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMouseTracking()
        retractTimer?.invalidate()
        guideHideTimer?.invalidate()
    }
    
    @objc private func screenParametersChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isDroppedDown {
                self.repositionPanel()
            }
        }
    }
    
    private func startMouseTracking() {
        stopMouseTracking()
        guard isEnabled else { return }
        
        let timer = DispatchSource.makeTimerSource(queue: mouseQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(40)) // 25 times a second
        timer.setEventHandler { [weak self] in
            self?.checkMousePositionBackground()
        }
        timer.resume()
        self.mouseTrackerTimer = timer
    }
    
    private func stopMouseTracking() {
        mouseTrackerTimer?.cancel()
        mouseTrackerTimer = nil
    }
    
    private func checkMousePositionBackground() {
        guard isEnabled && hoverDropOnly else { return }
        
        let mouse = NSEvent.mouseLocation
        
        // Find the screen under the mouse, or fallback to main
        let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let screen = activeScreen else { return }
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        // Comprehensive trigger zone respecting macOS Menu Bar settings:
        // - Spans from the absolute top of the screen (screenFrame.maxY)
        // - Reaches through the menu bar down into the visible frame by scanHeight
        let effectiveWidth = min(scanWidth, screenFrame.width * 0.95)
        let triggerTop = screenFrame.maxY
        let triggerBottom = visibleFrame.maxY - scanHeight
        let triggerRect = NSRect(
            x: screenFrame.midX - (effectiveWidth / 2),
            y: triggerBottom,
            width: effectiveWidth,
            height: triggerTop - triggerBottom
        )
        
        let inTrigger = NSPointInRect(mouse, triggerRect)
        let inPill = isPillVisibleInternal && NSPointInRect(mouse, cachedPillRect)
        
        // Update guide live indicator if active
        if isGuidePinned || (guidePanel != nil && guidePanel!.alphaValue > 0.05) {
            DispatchQueue.main.async { [weak self] in
                self?.updateGuideAppearance(isInside: inTrigger)
            }
        }
        
        if inTrigger {
            if hoverDelay > 0.01 {
                if hoverStartTime == nil {
                    hoverStartTime = Date()
                }
                let elapsed = Date().timeIntervalSince(hoverStartTime!)
                if elapsed < hoverDelay {
                    return
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.retractTimer?.invalidate()
                self.retractTimer = nil
                self.isHoveringActive = true
                if !self.isDroppedDown {
                    self.dropDown()
                }
            }
        } else if inPill {
            hoverStartTime = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.retractTimer?.invalidate()
                self.retractTimer = nil
                self.isHoveringActive = true
            }
        } else {
            hoverStartTime = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.isHoveringActive || self.isDroppedDown {
                    self.isHoveringActive = false
                    if self.retractTimer == nil {
                        // 0.5s grace period before retracting
                        self.retractTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                            self?.retract()
                        }
                    }
                }
            }
        }
    }
    
    public func toggleGuide() {
        if isGuidePinned {
            hideTriggerZoneGuide()
        } else {
            isGuidePinned = true
            showTriggerZoneGuide(temporarily: false)
        }
    }
    
    public func hideTriggerZoneGuide() {
        isGuidePinned = false
        guideHideTimer?.invalidate()
        guideHideTimer = nil
        guard let panel = guidePanel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
    
    public func showTriggerZoneGuide(temporarily: Bool = true) {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let screen = activeScreen else { return }
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        let effectiveWidth = min(scanWidth, screenFrame.width * 0.95)
        let triggerTop = screenFrame.maxY
        let triggerBottom = visibleFrame.maxY - scanHeight
        let triggerHeight = triggerTop - triggerBottom
        let targetRect = NSRect(
            x: screenFrame.midX - (effectiveWidth / 2),
            y: triggerBottom,
            width: effectiveWidth,
            height: triggerHeight
        )
        
        if guidePanel == nil {
            let panel = NSPanel(
                contentRect: targetRect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            
            let view = NSView(frame: NSRect(origin: .zero, size: targetRect.size))
            view.wantsLayer = true
            view.layer?.cornerRadius = 10
            
            let lbl = NSTextField(labelWithString: "")
            lbl.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            lbl.textColor = .white
            lbl.alignment = .center
            view.addSubview(lbl)
            
            panel.contentView = view
            self.guideLabel = lbl
            self.guidePanel = panel
        }
        
        guard let panel = guidePanel else { return }
        
        panel.setFrame(targetRect, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: targetRect.size)
        
        let inTrigger = NSPointInRect(mouse, targetRect)
        updateGuideAppearance(isInside: inTrigger)
        
        panel.orderFront(nil)
        panel.animator().alphaValue = 1.0
        
        if temporarily && !isGuidePinned {
            guideHideTimer?.invalidate()
            guideHideTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
                guard let self = self, !self.isGuidePinned else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    self.guidePanel?.animator().alphaValue = 0.0
                }, completionHandler: {
                    self.guidePanel?.orderOut(nil)
                })
            }
        }
    }
    
    private func updateGuideAppearance(isInside: Bool) {
        guard let panel = guidePanel, let view = panel.contentView, let label = guideLabel else { return }
        let targetRect = panel.frame
        label.frame = NSRect(x: 0, y: max(4, (targetRect.height - 20) / 2), width: targetRect.width, height: 20)
        
        if isInside {
            view.layer?.backgroundColor = NSColor(red: 0.15, green: 0.8, blue: 0.4, alpha: 0.32).cgColor
            view.layer?.borderWidth = 2.0
            view.layer?.borderColor = NSColor(red: 0.2, green: 0.95, blue: 0.45, alpha: 0.95).cgColor
            label.stringValue = "🎯 Cursor Inside Hover Zone (Active!) — \(Int(scanWidth))px × \(Int(scanHeight))px"
        } else {
            view.layer?.backgroundColor = NSColor(red: 0.1, green: 0.55, blue: 1.0, alpha: 0.20).cgColor
            view.layer?.borderWidth = 1.5
            view.layer?.borderColor = NSColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.85).cgColor
            label.stringValue = "🎯 Hover Zone: \(Int(scanWidth))px wide × \(Int(scanHeight))px reach"
        }
    }
    
    public func update(track: TrackInfo?) {
        guard isEnabled else {
            retract(immediately: true)
            return
        }
        
        let trackUrl = track?.url ?? ""
        let isNewTrack = (!trackUrl.isEmpty && trackUrl != lastTrackId)
        lastTrackId = trackUrl
        
        if isDroppedDown || !hoverDropOnly {
            updateContent(track: track)
        }
        
        if !hoverDropOnly {
            dropDown()
        } else if isNewTrack && autoPeekEnabled {
            peek(duration: peekDuration)
        }
    }
    
    public func peek(duration: TimeInterval = 5.0) {
        guard isEnabled else { return }
        dropDown()
        
        retractTimer?.invalidate()
        retractTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isHoveringActive {
                self.retract()
            }
        }
    }
    
    private func setupPillPanel() -> (NSPanel, FloatingPillView) {
        if let panel = pillPanel, let pv = pillView {
            return (panel, pv)
        }
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // High floating level so it displays smoothly above browser windows
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        let pv = FloatingPillView(frame: NSRect(x: 0, y: 0, width: 440, height: 48))
        pv.onOpenTab = { [weak detector] in
            if let t = detector?.currentTrack {
                detector?.focusTab(track: t)
            }
        }
        pv.onCopyTitle = { [weak detector] in
            if let t = detector?.currentTrack {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(t.displayTitle, forType: .string)
            }
        }
        pv.onDismiss = { [weak self] in
            self?.retract(immediately: false)
        }
        
        panel.contentView = pv
        self.pillView = pv
        self.pillPanel = panel
        
        return (panel, pv)
    }
    
    private func updateContent(track: TrackInfo?) {
        let (panel, pv) = setupPillPanel()
        pv.update(with: track)
        let fittingSize = pv.calculateFittingSize()
        panel.setContentSize(fittingSize)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
    }
    
    public func dropDown() {
        guard let screen = NSScreen.main else { return }
        let (panel, pv) = setupPillPanel()
        
        pv.update(with: detector.currentTrack)
        let fittingSize = pv.calculateFittingSize()
        panel.setContentSize(fittingSize)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
        
        let visibleFrame = screen.visibleFrame
        let targetX = visibleFrame.midX - (fittingSize.width / 2)
        // Anchor directly underneath the user's macOS Menu Bar
        let targetY = visibleFrame.maxY - fittingSize.height - 6
        
        isDroppedDown = true
        isPillVisibleInternal = true
        cachedPillRect = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height).insetBy(dx: -40, dy: -30)
        
        panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
    }
    
    public func retract(immediately: Bool = false) {
        guard let panel = pillPanel, isDroppedDown || panel.isVisible else { return }
        isDroppedDown = false
        isPillVisibleInternal = false
        cachedPillRect = .zero
        retractTimer?.invalidate()
        retractTimer = nil
        
        if immediately {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            if !self.isDroppedDown {
                panel.orderOut(nil)
            }
        })
    }
    
    private func repositionPanel() {
        guard let screen = NSScreen.main, let panel = pillPanel, let pv = pillView else { return }
        let fittingSize = pv.calculateFittingSize()
        let visibleFrame = screen.visibleFrame
        let targetX = visibleFrame.midX - (fittingSize.width / 2)
        let targetY = visibleFrame.maxY - fittingSize.height - 6
        cachedPillRect = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height).insetBy(dx: -40, dy: -30)
        panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
    }
}
