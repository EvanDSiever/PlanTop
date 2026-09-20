import AppKit

public enum DisplayMode: Int {
    case hoverDropdown = 0
    case alwaysFloating = 1
    case menuBarOnly = 2
}

public final class FloatingPillWindowController: NSObject {
    private var pillPanel: NSPanel?
    private var pillView: FloatingPillView?
    
    // Dedicated background timer for cursor tracking (immune to main runloop freezes)
    private var mouseTrackerTimer: DispatchSourceTimer?
    private let mouseQueue = DispatchQueue(label: "com.plantop.mousetracker", qos: .userInteractive)
    
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
    public private(set) var isManuallyOpened: Bool = false
    private var isHoveringActive: Bool = false
    
    public var onOpenSettings: (() -> Void)?
    
    // Customizable scan dimensions for Right-Edge Hover
    public var scanReach: CGFloat = 65 {
        didSet {
            UserDefaults.standard.set(Double(scanReach), forKey: "scanReach")
        }
    }
    public var scanWidth: CGFloat {
        get { return scanReach }
        set { scanReach = newValue }
    }
    public var scanHeight: CGFloat = 550 {
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
    
    private var isLiveResizing: Bool = false
    
    // Dynamic Drag-Scaling width (260px - 650px)
    public var customPanelWidth: CGFloat = 340 {
        didSet {
            let clamped = max(260, min(650, customPanelWidth))
            if customPanelWidth != clamped {
                customPanelWidth = clamped
                return
            }
            UserDefaults.standard.set(Double(customPanelWidth), forKey: "customPanelWidth")
            pillView?.preferredPanelWidth = customPanelWidth
            if isDroppedDown && !isLiveResizing {
                repositionPanel()
            }
            if !isLiveResizing {
                NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
            }
        }
    }
    
    // Permanent Pinning
    public var isPinned: Bool = false {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "isSidePanelPinned")
            pillView?.isPinned = isPinned
            if isPinned {
                retractTimer?.invalidate()
                retractTimer = nil
                if !isDroppedDown {
                    dropDown()
                }
            }
            NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
        }
    }
    
    public func togglePin() {
        isPinned.toggle()
        if !isPinned && !isHoveringActive {
            retractTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.retract()
            }
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
            NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
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
            NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
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
            NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
        }
    }
    
    public override init() {
        super.init()
        
        if UserDefaults.standard.object(forKey: "customPanelWidth") != nil {
            let savedW = CGFloat(UserDefaults.standard.double(forKey: "customPanelWidth"))
            self.customPanelWidth = max(260, min(650, savedW))
        }
        if UserDefaults.standard.object(forKey: "isSidePanelPinned") != nil {
            self.isPinned = UserDefaults.standard.bool(forKey: "isSidePanelPinned")
        }
        if UserDefaults.standard.object(forKey: "isPillEnabled") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "isPillEnabled")
        }
        if UserDefaults.standard.object(forKey: "hoverDropOnly") != nil {
            self.hoverDropOnly = UserDefaults.standard.bool(forKey: "hoverDropOnly")
        }
        if UserDefaults.standard.object(forKey: "scanReach") != nil {
            self.scanReach = CGFloat(UserDefaults.standard.double(forKey: "scanReach"))
        } else if UserDefaults.standard.object(forKey: "scanWidth") != nil {
            let old = CGFloat(UserDefaults.standard.double(forKey: "scanWidth"))
            self.scanReach = old > 200 ? 65 : old
        }
        if UserDefaults.standard.object(forKey: "scanHeight") != nil {
            let val = CGFloat(UserDefaults.standard.double(forKey: "scanHeight"))
            self.scanHeight = val < 150 ? 550 : val
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onCalendarUpdated),
            name: .planTopCalendarUpdated,
            object: nil
        )
    }
    
    deinit {
        stopMouseTracking()
        retractTimer?.invalidate()
        guideHideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func screenParametersChanged() {
        if isDroppedDown {
            repositionPanel()
        }
    }
    
    @objc private func onCalendarUpdated() {
        DispatchQueue.main.async { [weak self] in
            self?.pillView?.reloadCalendar()
            if self?.isDroppedDown == true {
                self?.repositionPanel()
            }
        }
    }
    
    // MARK: - Cursor Tracking on Right Display Edge
    private func startMouseTracking() {
        stopMouseTracking()
        
        let timer = DispatchSource.makeTimerSource(queue: mouseQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.checkMousePosition()
        }
        timer.resume()
        self.mouseTrackerTimer = timer
    }
    
    private func stopMouseTracking() {
        mouseTrackerTimer?.cancel()
        mouseTrackerTimer = nil
    }
    
    public func notifyUserInteraction() {
        retractTimer?.invalidate()
        retractTimer = nil
        isHoveringActive = true
    }
    
    private func checkMousePosition() {
        guard isEnabled else { return }
        if isPinned || isManuallyOpened { return }
        
        let mouseLoc = NSEvent.mouseLocation
        
        if isPillVisibleInternal {
            var isInsidePanel = false
            if let panel = pillPanel, panel.isVisible {
                let panelFrame = panel.frame.insetBy(dx: -40, dy: -30)
                let cached = cachedPillRect.insetBy(dx: -40, dy: -30)
                if panelFrame.contains(mouseLoc) || cached.contains(mouseLoc) {
                    isInsidePanel = true
                }
            } else {
                isInsidePanel = cachedPillRect.contains(mouseLoc)
            }
            
            if isInsidePanel {
                hoverStartTime = nil
                retractTimer?.invalidate()
                retractTimer = nil
                isHoveringActive = true
                return
            }
        }
        
        // Target Primary Screen
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main
        guard let targetScreen = screen else { return }
        
        let screenFrame = targetScreen.frame
        let visibleFrame = targetScreen.visibleFrame
        
        let triggerReach = scanReach
        let triggerHeight = scanHeight
        let triggerY = visibleFrame.midY - (triggerHeight / 2) + 20
        
        let triggerZone = NSRect(
            x: screenFrame.maxX - triggerReach,
            y: triggerY,
            width: triggerReach,
            height: triggerHeight
        )
        
        let isInZone = triggerZone.contains(mouseLoc)
        
        if isInZone {
            if hoverDelay <= 0.001 {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if !self.isDroppedDown {
                        self.dropDown()
                    }
                }
            } else {
                if let start = hoverStartTime {
                    if Date().timeIntervalSince(start) >= hoverDelay {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            if !self.isDroppedDown {
                                self.dropDown()
                            }
                        }
                    }
                } else {
                    hoverStartTime = Date()
                }
            }
        } else {
            hoverStartTime = nil
            if isPillVisibleInternal && hoverDropOnly && !isHoveringActive && !isPinned {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let currentLoc = NSEvent.mouseLocation
                    if let panel = self.pillPanel, panel.isVisible {
                        let panelFrame = panel.frame.insetBy(dx: -40, dy: -30)
                        let cached = self.cachedPillRect.insetBy(dx: -40, dy: -30)
                        if panelFrame.contains(currentLoc) || cached.contains(currentLoc) {
                            self.retractTimer?.invalidate()
                            self.retractTimer = nil
                            self.isHoveringActive = true
                            return
                        }
                    }
                    if self.retractTimer == nil && self.isDroppedDown && !self.isHoveringActive {
                        self.retractTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                            guard let self = self else { return }
                            let finalLoc = NSEvent.mouseLocation
                            if let panel = self.pillPanel, panel.isVisible {
                                let panelFrame = panel.frame.insetBy(dx: -40, dy: -30)
                                let cached = self.cachedPillRect.insetBy(dx: -40, dy: -30)
                                if panelFrame.contains(finalLoc) || cached.contains(finalLoc) {
                                    self.isHoveringActive = true
                                    return
                                }
                            }
                            self.retract()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Guide Panel
    public func showGuide(pinned: Bool = false) {
        isGuidePinned = pinned
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        let triggerReach = scanReach
        let triggerHeight = scanHeight
        let triggerY = visibleFrame.midY - (triggerHeight / 2) + 20
        let triggerZone = NSRect(
            x: screenFrame.maxX - triggerReach,
            y: triggerY,
            width: triggerReach,
            height: triggerHeight
        )
        
        if guidePanel == nil {
            let panel = NSPanel(
                contentRect: triggerZone,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let bgView = NSView(frame: NSRect(origin: .zero, size: triggerZone.size))
            bgView.wantsLayer = true
            bgView.layer?.backgroundColor = NeumorphicTheme.accentColor.withAlphaComponent(0.18).cgColor
            bgView.layer?.borderColor = NeumorphicTheme.accentColor.withAlphaComponent(0.65).cgColor
            bgView.layer?.borderWidth = 1.5
            bgView.layer?.cornerRadius = 12
            
            let label = NSTextField(labelWithString: "Hover Zone")
            label.alignment = .center
            label.font = NeumorphicTheme.roundedFont(ofSize: 11, weight: .bold)
            label.textColor = NeumorphicTheme.accentColor
            label.frame = NSRect(x: 0, y: (triggerZone.height - 20) / 2, width: triggerZone.width, height: 20)
            label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            bgView.addSubview(label)
            
            panel.contentView = bgView
            self.guidePanel = panel
            self.guideLabel = label
        } else {
            guidePanel?.setFrame(triggerZone, display: true)
        }
        
        guidePanel?.alphaValue = 1.0
        guidePanel?.orderFrontRegardless()
        
        guideHideTimer?.invalidate()
        if !pinned {
            guideHideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
                self?.hideGuide()
            }
        }
    }
    
    public func hideGuide() {
        isGuidePinned = false
        guideHideTimer?.invalidate()
        guideHideTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            guidePanel?.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.guidePanel?.orderOut(nil)
        })
    }
    
    public func updateGuidePosition() {
        guard let screen = NSScreen.main, let panel = guidePanel else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let triggerReach = scanReach
        let triggerHeight = scanHeight
        let triggerY = visibleFrame.midY - (triggerHeight / 2) + 20
        let triggerZone = NSRect(
            x: screenFrame.maxX - triggerReach,
            y: triggerY,
            width: triggerReach,
            height: triggerHeight
        )
        panel.setFrame(triggerZone, display: true)
    }
    
    // MARK: - Auto-Peek for Upcoming Events
    public func autoPeek(duration: Double = 5.0) {
        guard autoPeekEnabled && !isDroppedDown && !isPinned else { return }
        dropDown()
        
        retractTimer?.invalidate()
        retractTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isHoveringActive && !self.isPinned {
                self.retract()
            }
        }
    }
    
    private func setupPillPanel() -> (NSPanel, FloatingPillView) {
        if let panel = pillPanel, let pv = pillView {
            return (panel, pv)
        }
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: customPanelWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        let pv = FloatingPillView(frame: NSRect(x: 0, y: 0, width: customPanelWidth, height: 400))
        pv.preferredPanelWidth = customPanelWidth
        pv.isPinned = isPinned
        
        pv.onTogglePin = { [weak self] in
            self?.togglePin()
        }
        pv.onResizeWidthChanged = { [weak self] width in
            self?.handleLiveResize(width: width)
        }
        pv.onResizeCompleted = { [weak self] in
            self?.handleResizeCompleted()
        }
        pv.onHeightChanged = { [weak self] in
            self?.handlePanelHeightChanged()
        }
        pv.onUserInteraction = { [weak self] in
            self?.notifyUserInteraction()
        }
        pv.onOpenSettings = { [weak self] in
            self?.onOpenSettings?()
        }
        pv.onDismiss = { [weak self] in
            guard let self = self else { return }
            if self.isPinned {
                self.isPinned = false
            }
            self.retract(immediately: false)
        }
        pv.onHoverStateChanged = { [weak self] isHovered in
            guard let self = self else { return }
            if self.isPinned { return }
            if isHovered {
                self.retractTimer?.invalidate()
                self.retractTimer = nil
                self.isHoveringActive = true
            } else {
                // Before scheduling retract, check if the mouse is actually still inside the panel
                let mouseLoc = NSEvent.mouseLocation
                if let panel = self.pillPanel, panel.isVisible {
                    let panelFrame = panel.frame.insetBy(dx: -40, dy: -30)
                    let cached = self.cachedPillRect.insetBy(dx: -40, dy: -30)
                    if panelFrame.contains(mouseLoc) || cached.contains(mouseLoc) {
                        self.isHoveringActive = true
                        return
                    }
                }
                
                self.isHoveringActive = false
                if self.retractTimer == nil && self.isDroppedDown && self.hoverDropOnly {
                    self.retractTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        let finalLoc = NSEvent.mouseLocation
                        if let panel = self.pillPanel, panel.isVisible {
                            let panelFrame = panel.frame.insetBy(dx: -40, dy: -30)
                            let cached = self.cachedPillRect.insetBy(dx: -40, dy: -30)
                            if panelFrame.contains(finalLoc) || cached.contains(finalLoc) {
                                self.isHoveringActive = true
                                return
                            }
                        }
                        self.retract()
                    }
                }
            }
        }
        
        panel.contentView = pv
        self.pillPanel = panel
        self.pillView = pv
        return (panel, pv)
    }
    
    public func dropDown(manually: Bool = false) {
        if manually {
            isManuallyOpened = true
        }
        guard let screen = NSScreen.main else { return }
        let (panel, pv) = setupPillPanel()
        
        pv.preferredPanelWidth = customPanelWidth
        pv.reloadCalendar()
        
        let fittingSize = pv.calculateFittingSize()
        panel.setContentSize(fittingSize)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let rightMargin: CGFloat = 16
        let targetX = screenFrame.maxX - fittingSize.width - rightMargin
        let targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        
        let wasDropped = isDroppedDown
        isDroppedDown = true
        isPillVisibleInternal = true
        cachedPillRect = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height).insetBy(dx: -40, dy: -30)
        
        panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
        
        if !wasDropped || !pv.isStretchedOut {
            pv.stretchOut(animated: true)
        }
    }
    
    public func retract(immediately: Bool = false) {
        isManuallyOpened = false
        if isPinned && !immediately {
            return
        }
        guard let panel = pillPanel, let pv = pillView, isDroppedDown || panel.isVisible else { return }
        isDroppedDown = false
        isPillVisibleInternal = false
        cachedPillRect = .zero
        retractTimer?.invalidate()
        retractTimer = nil
        
        if immediately {
            pv.slideIn(animated: false) {
                panel.orderOut(nil)
            }
            return
        }
        
        pv.slideIn(animated: true) { [weak self, weak panel] in
            guard let self = self, let panel = panel else { return }
            if !self.isDroppedDown {
                panel.orderOut(nil)
            }
        }
    }
    
    public func handleLiveResize(width: CGFloat) {
        isLiveResizing = true
        let clamped = max(260, min(650, width))
        guard let panel = pillPanel, let pv = pillView, let screen = NSScreen.main else { return }
        pv.preferredPanelWidth = clamped
        let fittingSize = pv.calculateFittingSize()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let rightMargin: CGFloat = 16
        let targetX = screenFrame.maxX - fittingSize.width - rightMargin
        
        var targetY: CGFloat
        if panel.frame.height > 10 && panel.frame.maxY > visibleFrame.minY {
            targetY = panel.frame.maxY - fittingSize.height
        } else {
            targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        }
        if targetY < visibleFrame.minY + 16 { targetY = visibleFrame.minY + 16 }
        if targetY + fittingSize.height > visibleFrame.maxY - 16 { targetY = visibleFrame.maxY - 16 - fittingSize.height }
        
        cachedPillRect = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height).insetBy(dx: -40, dy: -30)
        panel.setFrame(NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height), display: true)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
    }
    
    public func handleResizeCompleted() {
        guard isLiveResizing else { return }
        isLiveResizing = false
        if let pv = pillView {
            customPanelWidth = pv.preferredPanelWidth
        }
    }
    
    private func handlePanelHeightChanged() {
        guard let panel = pillPanel, let pv = pillView, let screen = NSScreen.main else { return }
        notifyUserInteraction()
        
        let fittingSize = pv.calculateFittingSize()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let rightMargin: CGFloat = 16
        let targetX = screenFrame.maxX - fittingSize.width - rightMargin
        
        // Anchor the top of the panel so header, clock, and category tabs do NOT jump under cursor
        var targetY: CGFloat
        if panel.frame.height > 10 && panel.frame.maxY > visibleFrame.minY {
            targetY = panel.frame.maxY - fittingSize.height
        } else {
            targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        }
        
        // Clamp vertically so the panel stays comfortably within visible screen bounds
        if targetY < visibleFrame.minY + 16 {
            targetY = visibleFrame.minY + 16
        }
        if targetY + fittingSize.height > visibleFrame.maxY - 16 {
            targetY = visibleFrame.maxY - 16 - fittingSize.height
        }
        
        let targetFrame = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height)
        
        // Union with current frame so mouse detection never flags outside during animation
        cachedPillRect = panel.frame.union(targetFrame).insetBy(dx: -50, dy: -40)
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: false)
            pv.animator().frame = NSRect(origin: .zero, size: fittingSize)
        }, completionHandler: { [weak self] in
            guard let self = self, let panel = self.pillPanel else { return }
            self.cachedPillRect = panel.frame.insetBy(dx: -40, dy: -30)
        })
        pv.needsLayout = true
    }
    
    private func repositionPanel() {
        guard let screen = NSScreen.main, let panel = pillPanel, let pv = pillView else { return }
        pv.preferredPanelWidth = customPanelWidth
        let fittingSize = pv.calculateFittingSize()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let rightMargin: CGFloat = 16
        let targetX = screenFrame.maxX - fittingSize.width - rightMargin
        let targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        cachedPillRect = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height).insetBy(dx: -40, dy: -30)
        panel.setFrame(NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height), display: true)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
    }
}
