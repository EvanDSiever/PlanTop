import AppKit

public final class FloatingPillWindowController: NSObject {
    private var pillPanel: NSPanel?
    private var pillView: FloatingPillView?
    private var detector: YouTubeDetector
    
    // Dedicated background timer for cursor tracking (immune to main runloop freezes)
    private var mouseTrackerTimer: DispatchSourceTimer?
    private let mouseQueue = DispatchQueue(label: "com.songtop.mousetracker", qos: .userInteractive)
    
    private var retractTimer: Timer?
    
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
        timer.schedule(deadline: .now(), repeating: .milliseconds(50)) // 20 times a second
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
        let effectiveWidth = min(scanWidth, screenFrame.width * 0.9)
        let triggerTop = screenFrame.maxY
        let triggerBottom = visibleFrame.maxY - scanHeight
        let triggerRect = NSRect(
            x: screenFrame.midX - (effectiveWidth / 2),
            y: triggerBottom,
            width: effectiveWidth,
            height: triggerTop - triggerBottom
        )
        
        // Pill area when dropped down
        var pillRect: NSRect = .zero
        var currentDroppedDown = false
        
        DispatchQueue.main.sync {
            currentDroppedDown = self.isDroppedDown
            if let panel = self.pillPanel, currentDroppedDown {
                // Add comfortable 40px margin around the pill
                pillRect = panel.frame.insetBy(dx: -40, dy: -30)
            }
        }
        
        let inTrigger = NSPointInRect(mouse, triggerRect)
        let inPill = currentDroppedDown && NSPointInRect(mouse, pillRect)
        let shouldBeOpen = inTrigger || inPill
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if shouldBeOpen {
                self.retractTimer?.invalidate()
                self.retractTimer = nil
                self.isHoveringActive = true
                
                if !self.isDroppedDown {
                    self.dropDown()
                }
            } else {
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
        // Anchor directly underneath the user's macOS Menu Bar (or screen top if menu bar is hidden)
        let targetY = visibleFrame.maxY - fittingSize.height - 6
        
        isDroppedDown = true
        
        // Position on-screen within valid visible bounds (never place offscreen to avoid macOS WindowServer clamping bugs)
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
        panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
    }
}
