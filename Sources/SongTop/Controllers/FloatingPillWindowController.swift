import AppKit

final class HoverTriggerView: NSView {
    var onHoverStateChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverStateChanged?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverStateChanged?(false)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Subtle top notch accent (tiny 40x3px pill) to show where hover zone is
        let accentWidth: CGFloat = 48
        let accentHeight: CGFloat = 3
        let accentRect = NSRect(
            x: (bounds.width - accentWidth) / 2,
            y: bounds.height - accentHeight,
            width: accentWidth,
            height: accentHeight
        )
        let path = NSBezierPath(roundedRect: accentRect, xRadius: 1.5, yRadius: 1.5)
        NSColor(white: 1.0, alpha: 0.18).setFill()
        path.fill()
    }
}

public final class FloatingPillWindowController: NSObject {
    private var triggerPanel: NSPanel?
    private var triggerView: HoverTriggerView?
    
    private var pillPanel: NSPanel?
    private var pillView: FloatingPillView?
    
    private var detector: YouTubeDetector
    
    private var isInsideTrigger: Bool = false
    private var isInsidePill: Bool = false
    private var isDroppedDown: Bool = false
    private var retractTimer: Timer?
    private var lastTrackId: String = ""
    
    public var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isPillEnabled")
            if !isEnabled {
                triggerPanel?.orderOut(nil)
                retract(immediately: true)
            } else {
                setupTriggerPanel()
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
        
        setupTriggerPanel()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        retractTimer?.invalidate()
    }
    
    @objc private func screenParametersChanged() {
        repositionPanels()
    }
    
    private func setupTriggerPanel() {
        guard isEnabled else { return }
        guard let screen = NSScreen.main else { return }
        
        let width: CGFloat = 380
        let height: CGFloat = 32
        let midX = screen.frame.midX
        let maxY = screen.frame.maxY
        
        if triggerPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: midX - (width / 2), y: maxY - height, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            
            let tv = HoverTriggerView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            tv.onHoverStateChanged = { [weak self] hovering in
                self?.isInsideTrigger = hovering
                self?.evaluateHoverState()
            }
            
            panel.contentView = tv
            self.triggerView = tv
            self.triggerPanel = panel
        }
        
        triggerPanel?.setFrame(NSRect(x: midX - (width / 2), y: maxY - height, width: width, height: height), display: true)
        triggerPanel?.orderFront(nil)
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
        pv.onHoverStateChanged = { [weak self] hovering in
            self?.isInsidePill = hovering
            self?.evaluateHoverState()
        }
        
        panel.contentView = pv
        self.pillView = pv
        self.pillPanel = panel
        
        return (panel, pv)
    }
    
    private func evaluateHoverState() {
        guard isEnabled && hoverDropOnly else { return }
        
        let shouldBeOpen = isInsideTrigger || isInsidePill
        if shouldBeOpen {
            retractTimer?.invalidate()
            retractTimer = nil
            if !isDroppedDown {
                dropDown()
            }
        } else {
            if isDroppedDown && retractTimer == nil {
                retractTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                    self?.retract()
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
        let isNewTrack = (trackUrl != lastTrackId)
        lastTrackId = trackUrl
        
        if isDroppedDown || !hoverDropOnly {
            updateContent(track: track)
        }
        
        if !hoverDropOnly {
            dropDown()
        } else if isNewTrack && track != nil {
            peek(duration: 4.5)
        }
    }
    
    public func peek(duration: TimeInterval = 4.5) {
        guard isEnabled else { return }
        dropDown()
        
        retractTimer?.invalidate()
        retractTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isInsideTrigger && !self.isInsidePill {
                self.retract()
            }
        }
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
    
    private func repositionPanels() {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 380
        let height: CGFloat = 32
        let midX = screen.frame.midX
        let maxY = screen.frame.maxY
        
        triggerPanel?.setFrame(NSRect(x: midX - (width / 2), y: maxY - height, width: width, height: height), display: true)
        
        if let panel = pillPanel, let pv = pillView, isDroppedDown {
            let fittingSize = pv.calculateFittingSize()
            let targetX = screen.visibleFrame.midX - (fittingSize.width / 2)
            let targetY = screen.visibleFrame.maxY - fittingSize.height - 6
            panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        }
    }
}
