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
    
    public var isVideoPreviewEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isVideoPreviewEnabled, forKey: "isVideoPreviewEnabled")
            pillView?.isVideoPreviewEnabled = isVideoPreviewEnabled
            if isDroppedDown {
                repositionPanel()
            }
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
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
                NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
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
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        }
    }
    
    // YouTube Picture-in-Picture (PiP) Mode
    public var isPiPEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isPiPEnabled, forKey: "isPiPEnabled")
            if !isPiPEnabled && isPiPActive {
                exitPiPMode()
            }
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        }
    }
    public var isPiPAudioTransferEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isPiPAudioTransferEnabled, forKey: "isPiPAudioTransferEnabled")
            if isPiPActive {
                pillView?.setPiPAudio(enabled: isPiPAudioTransferEnabled)
            }
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        }
    }
    public var isPiPSyncProgressEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isPiPSyncProgressEnabled, forKey: "isPiPSyncProgressEnabled")
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        }
    }
    public private(set) var isPiPActive: Bool = false
    private var pipTimer: Timer?
    
    // Native PiP Companion Dock
    public var isNativePiPCompanionEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isNativePiPCompanionEnabled, forKey: "isNativePiPCompanionEnabled")
            handleNativePiPStateChanged()
            NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
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
    
    public func togglePlayPause() {
        if let pv = pillView {
            pv.togglePlayPause()
        } else if let track = detector.currentTrack {
            detector.togglePlayPause(track: track)
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
        
        if UserDefaults.standard.object(forKey: "customPanelWidth") != nil {
            let savedW = CGFloat(UserDefaults.standard.double(forKey: "customPanelWidth"))
            self.customPanelWidth = max(260, min(650, savedW))
        }
        if UserDefaults.standard.object(forKey: "isSidePanelPinned") != nil {
            self.isPinned = UserDefaults.standard.bool(forKey: "isSidePanelPinned")
        }
        if UserDefaults.standard.object(forKey: "isVideoPreviewEnabled") != nil {
            self.isVideoPreviewEnabled = UserDefaults.standard.bool(forKey: "isVideoPreviewEnabled")
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
        if UserDefaults.standard.object(forKey: "isPiPEnabled") != nil {
            self.isPiPEnabled = UserDefaults.standard.bool(forKey: "isPiPEnabled")
        }
        if UserDefaults.standard.object(forKey: "isPiPAudioTransferEnabled") != nil {
            self.isPiPAudioTransferEnabled = UserDefaults.standard.bool(forKey: "isPiPAudioTransferEnabled")
        }
        if UserDefaults.standard.object(forKey: "isPiPSyncProgressEnabled") != nil {
            self.isPiPSyncProgressEnabled = UserDefaults.standard.bool(forKey: "isPiPSyncProgressEnabled")
        }
        if UserDefaults.standard.object(forKey: "isNativePiPCompanionEnabled") != nil {
            self.isNativePiPCompanionEnabled = UserDefaults.standard.bool(forKey: "isNativePiPCompanionEnabled")
        }
        
        startMouseTracking()
        startPiPTimer()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onNativePiPChanged),
            name: .songTopNativePiPChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onTabTelemetryUpdated),
            name: .songTopTabTelemetryUpdated,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAvailableTracksChanged),
            name: .songTopAvailableTracksChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMouseTracking()
        retractTimer?.invalidate()
        guideHideTimer?.invalidate()
        pipTimer?.invalidate()
    }
    
    @objc private func onNativePiPChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.handleNativePiPStateChanged()
        }
    }
    
    @objc private func onTabTelemetryUpdated() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pillView?.updateTelemetry(
                cur: self.detector.tabCurrentTime,
                dur: self.detector.tabDuration,
                paused: self.detector.tabIsPaused,
                vol: self.detector.tabVolume,
                muted: self.detector.tabIsMuted
            )
        }
    }
    
    @objc private func onAvailableTracksChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pillView?.updateAvailableTracks(
                self.detector.availableTracks,
                selectedTrack: self.detector.currentTrack,
                isAuto: self.detector.isAutoTracking
            )
        }
    }
    
    private func handleNativePiPStateChanged() {
        let isPiP = detector.isNativePiPActive
        pillView?.isNativePiPActive = (isPiP && isNativePiPCompanionEnabled)
        if isDroppedDown {
            repositionPanel()
        }
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
    
    private func startPiPTimer() {
        pipTimer?.invalidate()
        pipTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.checkPiPStatus()
        }
    }
    
    private func checkPiPStatus() {
        guard isPiPEnabled, isVideoPreviewEnabled, let track = detector.currentTrack, track.isPlaying else {
            if isPiPActive {
                exitPiPMode()
            }
            return
        }
        
        let isTabActive = detector.isUserActiveOnYouTubeTab()
        if !isTabActive && !isPiPActive {
            enterPiPMode()
        } else if isTabActive && isPiPActive {
            exitPiPMode()
        }
    }
    
    private func enterPiPMode() {
        guard !isPiPActive else { return }
        isPiPActive = true
        
        // Transfer audio to side panel if enabled
        if isPiPAudioTransferEnabled {
            pillView?.setPiPAudio(enabled: true)
        }
    }
    
    private func exitPiPMode() {
        guard isPiPActive else { return }
        isPiPActive = false
        
        // Mute side panel preview audio
        pillView?.setPiPAudio(enabled: false)
        
        // Sync watching progress back to browser if enabled
        if isPiPSyncProgressEnabled, let pv = pillView, let track = detector.currentTrack {
            // Guard: Only sync progress if pillView is currently displaying THIS exact track!
            if pv.currentTrackUrl == track.url {
                let panelTime = pv.currentTime
                if panelTime > 1.0 && (pv.duration <= 0 || panelTime < pv.duration - 1.0) {
                    detector.seekBrowser(track: track, toSeconds: panelTime)
                }
            }
        }
        
        // If not pinned and mouse is not hovering, retract after a brief grace period
        if !isPinned && !isHoveringActive && isDroppedDown {
            retractTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if !self.isPinned && !self.isHoveringActive {
                    self.retract()
                }
            }
        }
    }
    
    private func checkMousePositionBackground() {
        guard isEnabled && hoverDropOnly else { return }
        if isPinned { return }
        
        let mouse = NSEvent.mouseLocation
        
        // Find the screen under the mouse, or fallback to main
        let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let screen = activeScreen else { return }
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        // Panel vertical center (upper-middle right, cleanly away from dock and corners)
        let panelHeight: CGFloat = 56
        let targetY = visibleFrame.midY - (panelHeight / 2) + 20
        let effectiveReach = min(scanReach, screenFrame.width * 0.3)
        let effectiveHeight = min(scanHeight, visibleFrame.height)
        let triggerY = max(visibleFrame.minY, targetY - ((effectiveHeight - panelHeight) / 2))
        
        // Comprehensive right-edge trigger zone:
        // Spans flush from the right edge of the screen inward by scanReach
        let triggerRect = NSRect(
            x: screenFrame.maxX - effectiveReach,
            y: triggerY,
            width: effectiveReach,
            height: effectiveHeight
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
        
        let panelHeight: CGFloat = 56
        let targetY = visibleFrame.midY - (panelHeight / 2) + 20
        let effectiveReach = min(scanReach, screenFrame.width * 0.3)
        let effectiveHeight = min(scanHeight, visibleFrame.height)
        let triggerY = max(visibleFrame.minY, targetY - ((effectiveHeight - panelHeight) / 2))
        
        let targetRect = NSRect(
            x: screenFrame.maxX - effectiveReach,
            y: triggerY,
            width: effectiveReach,
            height: effectiveHeight
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
            view.layer?.cornerRadius = 14
            view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            
            let lbl = NSTextField(labelWithString: "")
            lbl.font = NSFont.systemFont(ofSize: 11, weight: .bold)
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
        label.frame = NSRect(x: 4, y: max(4, (targetRect.height - 30) / 2), width: max(30, targetRect.width - 8), height: 30)
        
        if isInside {
            view.layer?.backgroundColor = NSColor(red: 0.15, green: 0.8, blue: 0.4, alpha: 0.35).cgColor
            view.layer?.borderWidth = 2.0
            view.layer?.borderColor = NSColor(red: 0.2, green: 0.95, blue: 0.45, alpha: 0.95).cgColor
            label.stringValue = targetRect.width > 70 ? "🎯 Active Hover Zone!\n(\(Int(scanReach))px reach)" : "🎯 Active"
        } else {
            view.layer?.backgroundColor = NSColor(red: 0.1, green: 0.55, blue: 1.0, alpha: 0.22).cgColor
            view.layer?.borderWidth = 1.5
            view.layer?.borderColor = NSColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.85).cgColor
            label.stringValue = targetRect.width > 70 ? "🎯 Right Edge Zone\n(\(Int(scanReach))px reach)" : "🎯 Zone"
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 56),
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
        
        let pv = FloatingPillView(frame: NSRect(x: 0, y: 0, width: customPanelWidth, height: 56))
        pv.preferredPanelWidth = customPanelWidth
        pv.isPinned = isPinned
        pv.isNativePiPActive = (detector.isNativePiPActive && isNativePiPCompanionEnabled)
        pv.isVideoPreviewEnabled = isVideoPreviewEnabled
        pv.onSelectTrack = { [weak detector] track in
            detector?.selectTrack(track)
        }
        pv.onOpenTab = { [weak self, weak detector, weak pv] in
            guard let self = self else { return }
            if let t = detector?.currentTrack {
                let seekTime = (self.isPiPSyncProgressEnabled && pv != nil) ? pv!.currentTime : nil
                detector?.focusTab(track: t, atSeconds: seekTime)
            }
        }
        pv.onSeekRequested = { [weak self, weak detector] seconds in
            guard self != nil else { return }
            if let t = detector?.currentTrack {
                detector?.seekBrowser(track: t, toSeconds: seconds)
            }
        }
        pv.onTogglePlayPause = { [weak detector] in
            if let t = detector?.currentTrack {
                detector?.togglePlayPause(track: t)
            }
        }
        pv.onVolumeRequested = { [weak detector] vol in
            if let t = detector?.currentTrack {
                detector?.setVolume(track: t, volume: vol)
            }
        }
        pv.onMuteRequested = { [weak detector] muted in
            if let t = detector?.currentTrack {
                detector?.setMuted(track: t, muted: muted)
            }
        }
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
        pv.onCopyTitle = { [weak detector] in
            if let t = detector?.currentTrack {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(t.displayTitle, forType: .string)
            }
        }
        pv.onDismiss = { [weak self] in
            guard let self = self else { return }
            if self.isPinned {
                self.isPinned = false
            }
            if self.isPiPActive {
                self.exitPiPMode()
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
                self.isHoveringActive = false
                if self.retractTimer == nil && self.isDroppedDown && self.hoverDropOnly {
                    self.retractTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                        self?.retract()
                    }
                }
            }
        }
        
        panel.contentView = pv
        self.pillView = pv
        self.pillPanel = panel
        
        return (panel, pv)
    }
    
    private func updateContent(track: TrackInfo?) {
        let (panel, pv) = setupPillPanel()
        pv.isNativePiPActive = (detector.isNativePiPActive && isNativePiPCompanionEnabled)
        let currentSec: Double?
        if let t = track, detector.currentTrack?.url == t.url, detector.tabCurrentTime > 0 {
            currentSec = detector.tabCurrentTime
        } else if let t = track, let cached = detector.cachedPosition(for: t.url), cached > 0 {
            currentSec = cached
        } else {
            currentSec = nil
        }
        pv.update(with: track, initialSeconds: currentSec)
        pv.updateAvailableTracks(detector.availableTracks, selectedTrack: track, isAuto: detector.isAutoTracking)
        if isPiPActive && isPiPAudioTransferEnabled {
            pv.setPiPAudio(enabled: true)
        }
        let fittingSize = pv.calculateFittingSize()
        panel.setContentSize(fittingSize)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
        if isDroppedDown {
            repositionPanel()
        }
    }
    
    public func dropDown() {
        guard let screen = NSScreen.main else { return }
        let (panel, pv) = setupPillPanel()
        
        pv.preferredPanelWidth = customPanelWidth
        pv.isNativePiPActive = (detector.isNativePiPActive && isNativePiPCompanionEnabled)
        let currentSec: Double?
        if detector.currentTrack != nil, detector.tabCurrentTime > 0 {
            currentSec = detector.tabCurrentTime
        } else if let t = detector.currentTrack, let cached = detector.cachedPosition(for: t.url), cached > 0 {
            currentSec = cached
        } else {
            currentSec = nil
        }
        pv.update(with: detector.currentTrack, initialSeconds: currentSec)
        pv.updateAvailableTracks(detector.availableTracks, selectedTrack: detector.currentTrack, isAuto: detector.isAutoTracking)
        if isPiPActive && isPiPAudioTransferEnabled {
            pv.setPiPAudio(enabled: true)
        }
        let fittingSize = pv.calculateFittingSize()
        panel.setContentSize(fittingSize)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        // Anchored flush to the right edge of the display
        let targetX = screenFrame.maxX - fittingSize.width
        let targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        
        let wasDropped = isDroppedDown
        isDroppedDown = true
        isPillVisibleInternal = true
        cachedPillRect = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height).insetBy(dx: -40, dy: -30)
        
        // Window itself is always kept in-bounds right on the screen edge
        panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        panel.alphaValue = 1.0
        panel.orderFront(nil)
        
        // Trigger smooth stretch-out animation from the right bezel
        if !wasDropped || !pv.isStretchedOut {
            pv.stretchOut(animated: true)
        }
    }
    
    public func retract(immediately: Bool = false) {
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
        
        // Slide smoothly back into the right bezel
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
        let targetX = screenFrame.maxX - fittingSize.width
        let targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        
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
        let fittingSize = pv.calculateFittingSize()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let targetX = screenFrame.maxX - fittingSize.width
        let targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        let targetFrame = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height)
        
        cachedPillRect = targetFrame.insetBy(dx: -40, dy: -30)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
        pv.frame = NSRect(origin: .zero, size: fittingSize)
        pv.needsLayout = true
    }
    
    private func repositionPanel() {
        guard let screen = NSScreen.main, let panel = pillPanel, let pv = pillView else { return }
        pv.preferredPanelWidth = customPanelWidth
        let fittingSize = pv.calculateFittingSize()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let targetX = screenFrame.maxX - fittingSize.width
        let targetY = visibleFrame.midY - (fittingSize.height / 2) + 20
        cachedPillRect = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height).insetBy(dx: -40, dy: -30)
        panel.setFrame(NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height), display: true)
        pv.frame = NSRect(origin: .zero, size: fittingSize)
    }
}
