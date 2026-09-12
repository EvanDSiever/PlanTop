import AppKit

public final class FloatingPillWindowController: NSObject {
    private var pillPanel: NSPanel?
    private var pillView: FloatingPillView?
    private var detector: YouTubeDetector
    
    private var mousePollingTimer: Timer?
    private var retractTimer: Timer?
    
    private var isDroppedDown: Bool = false
    private var isHoveringActive: Bool = false
    private var lastTrackId: String = ""
    
    // Scan dimensions
    public var scanWidth: CGFloat = 750 {
        didSet {
            UserDefaults.standard.set(Double(scanWidth), forKey: "scanWidth")
        }
    }
    public var scanHeight: CGFloat = 70 {
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
                stopMousePolling()
            } else {
                startMousePolling()
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
        
        startMousePolling()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMousePolling()
        retractTimer?.invalidate()
    }
    
    @objc private func screenParametersChanged() {
        if isDroppedDown {
            repositionPanel()
        }
    }
    
    private func startMousePolling() {
        stopMousePolling()
        guard isEnabled else { return }
        
        // Poll global mouse cursor position 12 times a second (0.08s interval)
        // Uses ~0.002% CPU and reliably bypasses all macOS transparency & TCC restrictions
        mousePollingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }
    
    private func stopMousePolling() {
        mousePollingTimer?.invalidate()
        mousePollingTimer = nil
    }
    
    private func checkMousePosition() {
        guard isEnabled && hoverDropOnly else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        
        let mouse = NSEvent.mouseLocation
        let midX = screen.frame.midX
        let maxY = screen.frame.maxY
        
        // Generous top center scan area (750px wide, top 70px of screen)
        let effectiveWidth = min(scanWidth, screen.frame.width * 0.75)
        let triggerRect = NSRect(
            x: midX - (effectiveWidth / 2),
            y: maxY - scanHeight,
            width: effectiveWidth,
            height: scanHeight
        )
        
        // Pill area when dropped down (includes extra 30px breathing room around edges)
        let pillRect: NSRect
        if let panel = pillPanel, isDroppedDown {
            pillRect = panel.frame.insetBy(dx: -30, dy: -25)
        } else {
            pillRect = .zero
        }
        
        let inTrigger = NSPointInRect(mouse, triggerRect)
        let inPill = NSPointInRect(mouse, pillRect)
        let isInside = inTrigger || inPill
        
        if isInside {
            retractTimer?.invalidate()
            retractTimer = nil
            isHoveringActive = true
            
            if !isDroppedDown {
                dropDown()
            }
        } else {
            if isHoveringActive || isDroppedDown {
                isHoveringActive = false
                if retractTimer == nil {
                    // 0.5s grace period before sliding back up
                    retractTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                        self?.retract()
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
        // High floating level so it displays smoothly above browser windows and menu bar
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
        
        let screenFrame = screen.visibleFrame
        let targetX = screenFrame.midX - (fittingSize.width / 2)
        let targetY = screenFrame.maxY - fittingSize.height - 6
        
        if !isDroppedDown || !panel.isVisible {
            panel.setFrameOrigin(NSPoint(x: targetX, y: screen.frame.maxY + 10))
            panel.alphaValue = 0.0
            panel.orderFront(nil)
        }
        
        isDroppedDown = true
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(NSPoint(x: targetX, y: targetY))
            panel.animator().alphaValue = 1.0
        }
    }
    
    public func retract(immediately: Bool = false) {
        guard let panel = pillPanel, isDroppedDown || panel.isVisible else { return }
        isDroppedDown = false
        retractTimer?.invalidate()
        retractTimer = nil
        
        guard let screen = NSScreen.main else {
            panel.orderOut(nil)
            return
        }
        
        let targetX = panel.frame.origin.x
        let targetY = screen.frame.maxY + 10
        
        if immediately {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: targetX, y: targetY))
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
        let targetX = screen.visibleFrame.midX - (fittingSize.width / 2)
        let targetY = screen.visibleFrame.maxY - fittingSize.height - 6
        panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
    }
}
