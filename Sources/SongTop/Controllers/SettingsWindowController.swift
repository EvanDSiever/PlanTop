import AppKit

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var detector: YouTubeDetector
    private var pillController: FloatingPillWindowController
    private var menuBarController: MenuBarController
    
    // Live Status UI
    private let statusLabel = NSTextField(labelWithString: "No YouTube Audio Playing")
    private let trackSubtitleLabel = NSTextField(labelWithString: "Play music in Chrome, Safari, Brave, or Arc")
    private let browserBadge = NSTextField(labelWithString: "Chrome")
    
    // Mode Control
    private let modeSegmentedControl = NSSegmentedControl(labels: ["Right Hover Slide", "Always Visible Panel", "Menu Bar Only"], trackingMode: .selectOne, target: nil, action: nil)
    
    // Hover Controls (Right-Edge)
    private let widthSlider = NSSlider(value: 65, minValue: 25, maxValue: 150, target: nil, action: nil)
    private let widthValueLabel = NSTextField(labelWithString: "65 px")
    private let heightSlider = NSSlider(value: 550, minValue: 200, maxValue: 1100, target: nil, action: nil)
    private let heightValueLabel = NSTextField(labelWithString: "550 px")
    private let sensitivitySlider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 0.35, target: nil, action: nil)
    private let sensitivityValueLabel = NSTextField(labelWithString: "Instant (0.0s)")
    private let guideButton = NSButton(title: "🎯 Highlight Right Zone", target: nil, action: nil)
    
    // Video Preview Control
    private let videoPreviewCheckbox = NSButton(checkboxWithTitle: "Show video playing in side panel when active (Muted by default)", target: nil, action: nil)
    
    // Auto Peek Controls
    private let autoPeekCheckbox = NSButton(checkboxWithTitle: "Automatically stretch out when a new song starts", target: nil, action: nil)
    private let peekDurationSlider = NSSlider(value: 5.0, minValue: 2.0, maxValue: 10.0, target: nil, action: nil)
    private let peekDurationLabel = NSTextField(labelWithString: "5.0 s")
    
    // Menu Bar Control
    private let menuBarTitleCheckbox = NSButton(checkboxWithTitle: "Display song name in the macOS Menu Bar", target: nil, action: nil)
    
    // Browser Status Container
    private let browsersStack = NSStackView()
    
    public var onWindowClosed: (() -> Void)?
    
    public init(detector: YouTubeDetector, pillController: FloatingPillWindowController, menuBarController: MenuBarController) {
        self.detector = detector
        self.pillController = pillController
        self.menuBarController = menuBarController
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SongTop Settings & Customization"
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        
        setupUI()
        loadInitialValues()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSettingsChanged),
            name: .songTopSettingsChanged,
            object: nil
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func onSettingsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.loadInitialValues()
        }
    }
    
    public func show() {
        loadInitialValues()
        updateLiveStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        pillController.hideTriggerZoneGuide()
        onWindowClosed?()
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.material = .windowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        contentView.addSubview(visualEffect)
        
        let scrollView = NSScrollView(frame: contentView.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(scrollView)
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 730))
        scrollView.documentView = container
        
        var currentY: CGFloat = 710
        
        // 1. Header
        let iconView = NSImageView(frame: NSRect(x: 24, y: currentY - 50, width: 48, height: 48))
        if let icon = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil) {
            iconView.image = icon
        }
        container.addSubview(iconView)
        
        let appTitle = NSTextField(labelWithString: "SongTop")
        appTitle.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        appTitle.frame = NSRect(x: 82, y: currentY - 32, width: 300, height: 24)
        container.addSubview(appTitle)
        
        let appSubtitle = NSTextField(labelWithString: "YouTube Now Playing for macOS • Right-Side Panel Settings")
        appSubtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        appSubtitle.textColor = .secondaryLabelColor
        appSubtitle.frame = NSRect(x: 82, y: currentY - 48, width: 390, height: 16)
        container.addSubview(appSubtitle)
        
        currentY -= 70
        
        // 2. Live Now Playing Card
        let liveCard = createCardView(frame: NSRect(x: 20, y: currentY - 80, width: 480, height: 74))
        container.addSubview(liveCard)
        
        let liveBadge = NSTextField(labelWithString: "LIVE DETECTED TRACK")
        liveBadge.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        liveBadge.textColor = .systemRed
        liveBadge.frame = NSRect(x: 14, y: 52, width: 200, height: 14)
        liveCard.addSubview(liveBadge)
        
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.frame = NSRect(x: 14, y: 30, width: 320, height: 18)
        statusLabel.lineBreakMode = .byTruncatingTail
        liveCard.addSubview(statusLabel)
        
        trackSubtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        trackSubtitleLabel.textColor = .secondaryLabelColor
        trackSubtitleLabel.frame = NSRect(x: 14, y: 12, width: 320, height: 16)
        trackSubtitleLabel.lineBreakMode = .byTruncatingTail
        liveCard.addSubview(trackSubtitleLabel)
        
        let testBtn = NSButton(title: "Test Side Panel", target: self, action: #selector(testDropdownClicked))
        testBtn.bezelStyle = .rounded
        testBtn.frame = NSRect(x: 345, y: 22, width: 122, height: 28)
        liveCard.addSubview(testBtn)
        
        currentY -= 95
        
        // 3. Display Mode Card
        let modeCard = createCardView(frame: NSRect(x: 20, y: currentY - 76, width: 480, height: 70))
        container.addSubview(modeCard)
        
        let modeTitle = NSTextField(labelWithString: "Display Mode")
        modeTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        modeTitle.frame = NSRect(x: 14, y: 44, width: 300, height: 16)
        modeCard.addSubview(modeTitle)
        
        modeSegmentedControl.frame = NSRect(x: 14, y: 12, width: 450, height: 26)
        modeSegmentedControl.target = self
        modeSegmentedControl.action = #selector(modeChanged)
        modeCard.addSubview(modeSegmentedControl)
        
        currentY -= 90
        
        // 4. Right-Edge Hover Sensitivity & Area Card
        let hoverCard = createCardView(frame: NSRect(x: 20, y: currentY - 180, width: 480, height: 174))
        container.addSubview(hoverCard)
        
        let hoverTitle = NSTextField(labelWithString: "Right-Edge Hover Sensitivity & Area")
        hoverTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        hoverTitle.frame = NSRect(x: 14, y: 146, width: 270, height: 16)
        hoverCard.addSubview(hoverTitle)
        
        guideButton.frame = NSRect(x: 295, y: 142, width: 172, height: 24)
        guideButton.bezelStyle = .rounded
        guideButton.target = self
        guideButton.action = #selector(toggleGuideClicked)
        hoverCard.addSubview(guideButton)
        
        // Edge Reach Slider (Continuous)
        let wLabel = NSTextField(labelWithString: "Edge Reach:")
        wLabel.font = NSFont.systemFont(ofSize: 11)
        wLabel.frame = NSRect(x: 14, y: 114, width: 85, height: 16)
        hoverCard.addSubview(wLabel)
        
        widthSlider.isContinuous = true
        widthSlider.frame = NSRect(x: 100, y: 112, width: 295, height: 20)
        widthSlider.target = self
        widthSlider.action = #selector(widthSliderChanged)
        hoverCard.addSubview(widthSlider)
        
        widthValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        widthValueLabel.alignment = .right
        widthValueLabel.frame = NSRect(x: 400, y: 114, width: 65, height: 16)
        hoverCard.addSubview(widthValueLabel)
        
        // Vertical Span Slider (Continuous)
        let hLabel = NSTextField(labelWithString: "Vertical Span:")
        hLabel.font = NSFont.systemFont(ofSize: 11)
        hLabel.frame = NSRect(x: 14, y: 78, width: 85, height: 16)
        hoverCard.addSubview(hLabel)
        
        heightSlider.isContinuous = true
        heightSlider.frame = NSRect(x: 100, y: 76, width: 295, height: 20)
        heightSlider.target = self
        heightSlider.action = #selector(heightSliderChanged)
        hoverCard.addSubview(heightSlider)
        
        heightValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        heightValueLabel.alignment = .right
        heightValueLabel.frame = NSRect(x: 400, y: 78, width: 65, height: 16)
        hoverCard.addSubview(heightValueLabel)
        
        // Trigger Delay Slider (Continuous)
        let sLabel = NSTextField(labelWithString: "Trigger Delay:")
        sLabel.font = NSFont.systemFont(ofSize: 11)
        sLabel.frame = NSRect(x: 14, y: 42, width: 85, height: 16)
        hoverCard.addSubview(sLabel)
        
        sensitivitySlider.isContinuous = true
        sensitivitySlider.frame = NSRect(x: 100, y: 40, width: 295, height: 20)
        sensitivitySlider.target = self
        sensitivitySlider.action = #selector(sensitivitySliderChanged)
        hoverCard.addSubview(sensitivitySlider)
        
        sensitivityValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sensitivityValueLabel.alignment = .right
        sensitivityValueLabel.frame = NSRect(x: 395, y: 42, width: 75, height: 16)
        hoverCard.addSubview(sensitivityValueLabel)
        
        let hoverDesc = NSTextField(labelWithString: "💡 Tip: Hover near the right edge of your screen. The panel stretches out smoothly.")
        hoverDesc.font = NSFont.systemFont(ofSize: 10)
        hoverDesc.textColor = .secondaryLabelColor
        hoverDesc.frame = NSRect(x: 14, y: 12, width: 450, height: 16)
        hoverCard.addSubview(hoverDesc)
        
        currentY -= 195
        
        // 5. Behavior / Auto-Peek Card
        let peekCard = createCardView(frame: NSRect(x: 20, y: currentY - 100, width: 480, height: 94))
        container.addSubview(peekCard)
        
        let peekTitle = NSTextField(labelWithString: "Track Change Behavior")
        peekTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        peekTitle.frame = NSRect(x: 14, y: 68, width: 300, height: 16)
        peekCard.addSubview(peekTitle)
        
        autoPeekCheckbox.frame = NSRect(x: 14, y: 42, width: 400, height: 18)
        autoPeekCheckbox.target = self
        autoPeekCheckbox.action = #selector(autoPeekToggled)
        peekCard.addSubview(autoPeekCheckbox)
        
        let pLabel = NSTextField(labelWithString: "Peek Duration:")
        pLabel.font = NSFont.systemFont(ofSize: 11)
        pLabel.frame = NSRect(x: 14, y: 14, width: 90, height: 16)
        peekCard.addSubview(pLabel)
        
        peekDurationSlider.isContinuous = true
        peekDurationSlider.frame = NSRect(x: 105, y: 12, width: 290, height: 20)
        peekDurationSlider.target = self
        peekDurationSlider.action = #selector(peekDurationChanged)
        peekCard.addSubview(peekDurationSlider)
        
        peekDurationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        peekDurationLabel.alignment = .right
        peekDurationLabel.frame = NSRect(x: 400, y: 14, width: 65, height: 16)
        peekCard.addSubview(peekDurationLabel)
        
        currentY -= 115
        
        // 6. Live Video Playback Card
        let videoCard = createCardView(frame: NSRect(x: 20, y: currentY - 74, width: 480, height: 68))
        container.addSubview(videoCard)
        
        let videoTitle = NSTextField(labelWithString: "Live Video Playback")
        videoTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        videoTitle.frame = NSRect(x: 14, y: 44, width: 300, height: 16)
        videoCard.addSubview(videoTitle)
        
        videoPreviewCheckbox.frame = NSRect(x: 14, y: 16, width: 450, height: 18)
        videoPreviewCheckbox.target = self
        videoPreviewCheckbox.action = #selector(videoPreviewToggled)
        videoCard.addSubview(videoPreviewCheckbox)
        
        currentY -= 88
        
        // 7. Menu Bar Options Card
        let menuCard = createCardView(frame: NSRect(x: 20, y: currentY - 60, width: 480, height: 54))
        container.addSubview(menuCard)
        
        menuBarTitleCheckbox.frame = NSRect(x: 14, y: 18, width: 450, height: 18)
        menuBarTitleCheckbox.target = self
        menuBarTitleCheckbox.action = #selector(menuBarTitleToggled)
        menuCard.addSubview(menuBarTitleCheckbox)
        
        currentY -= 75
        
        // 8. Browser Status Card
        let browserCard = createCardView(frame: NSRect(x: 20, y: currentY - 65, width: 480, height: 58))
        container.addSubview(browserCard)
        
        let browserCardTitle = NSTextField(labelWithString: "Supported Browsers Detected")
        browserCardTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        browserCardTitle.textColor = .secondaryLabelColor
        browserCardTitle.frame = NSRect(x: 14, y: 34, width: 300, height: 16)
        browserCard.addSubview(browserCardTitle)
        
        browsersStack.orientation = .horizontal
        browsersStack.spacing = 8
        browsersStack.frame = NSRect(x: 14, y: 10, width: 450, height: 18)
        browserCard.addSubview(browsersStack)
        updateBrowserBadges()
    }
    
    private func createCardView(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.08).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(white: 0.5, alpha: 0.12).cgColor
        return card
    }
    
    public func updateLiveStatus() {
        if let track = detector.currentTrack {
            statusLabel.stringValue = track.title
            trackSubtitleLabel.stringValue = track.artist.isEmpty
                ? "\(track.browser) • YouTube"
                : "\(track.artist) • \(track.browser)"
        } else {
            statusLabel.stringValue = "No YouTube Audio Playing"
            trackSubtitleLabel.stringValue = "Play music in Chrome, Safari, Brave, or Arc"
        }
        updateBrowserBadges()
    }
    
    public func updateBrowserBadges() {
        browsersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let runningApps = NSWorkspace.shared.runningApplications
        let runningNames = Set(runningApps.compactMap { $0.localizedName })
        let browsers = ["Google Chrome", "Safari", "Brave Browser", "Arc", "Microsoft Edge"]
        
        for name in browsers {
            let isRunning = runningNames.contains(name)
            let badge = NSTextField(labelWithString: "\(isRunning ? "🟢" : "⚪") \(name)")
            badge.font = NSFont.systemFont(ofSize: 10, weight: isRunning ? .semibold : .regular)
            badge.textColor = isRunning ? .labelColor : .tertiaryLabelColor
            browsersStack.addArrangedSubview(badge)
        }
    }
    
    private func loadInitialValues() {
        modeSegmentedControl.selectedSegment = pillController.displayMode.rawValue
        
        widthSlider.doubleValue = Double(pillController.scanReach)
        widthValueLabel.stringValue = "\(Int(pillController.scanReach)) px"
        
        heightSlider.doubleValue = Double(pillController.scanHeight)
        heightValueLabel.stringValue = "\(Int(pillController.scanHeight)) px"
        
        sensitivitySlider.doubleValue = pillController.hoverDelay
        updateSensitivityLabel(delay: pillController.hoverDelay)
        
        videoPreviewCheckbox.state = pillController.isVideoPreviewEnabled ? .on : .off
        
        autoPeekCheckbox.state = pillController.autoPeekEnabled ? .on : .off
        peekDurationSlider.doubleValue = pillController.peekDuration
        peekDurationLabel.stringValue = String(format: "%.1f s", pillController.peekDuration)
        
        menuBarTitleCheckbox.state = menuBarController.showTitleInMenuBar ? .on : .off
        guideButton.title = pillController.isGuidePinned ? "Hide Right Zone" : "🎯 Highlight Right Zone"
    }
    
    private func updateSensitivityLabel(delay: Double) {
        if delay <= 0.02 {
            sensitivityValueLabel.stringValue = "Instant (0.0s)"
        } else {
            sensitivityValueLabel.stringValue = String(format: "%.2f s", delay)
        }
    }
    
    @objc private func toggleGuideClicked() {
        pillController.toggleGuide()
        guideButton.title = pillController.isGuidePinned ? "Hide Right Zone" : "🎯 Highlight Right Zone"
    }
    
    @objc private func testDropdownClicked() {
        pillController.peek(duration: pillController.peekDuration)
    }
    
    @objc private func modeChanged() {
        if let mode = DisplayMode(rawValue: modeSegmentedControl.selectedSegment) {
            pillController.displayMode = mode
        }
    }
    
    @objc private func widthSliderChanged() {
        let val = widthSlider.doubleValue
        pillController.scanReach = CGFloat(val)
        widthValueLabel.stringValue = "\(Int(val)) px"
        pillController.showTriggerZoneGuide(temporarily: true)
    }
    
    @objc private func heightSliderChanged() {
        let val = heightSlider.doubleValue
        pillController.scanHeight = CGFloat(val)
        heightValueLabel.stringValue = "\(Int(val)) px"
        pillController.showTriggerZoneGuide(temporarily: true)
    }
    
    @objc private func sensitivitySliderChanged() {
        let val = sensitivitySlider.doubleValue
        pillController.hoverDelay = val
        updateSensitivityLabel(delay: val)
        pillController.showTriggerZoneGuide(temporarily: true)
    }
    
    @objc private func videoPreviewToggled() {
        pillController.isVideoPreviewEnabled = (videoPreviewCheckbox.state == .on)
    }
    
    @objc private func autoPeekToggled() {
        pillController.autoPeekEnabled = (autoPeekCheckbox.state == .on)
    }
    
    @objc private func peekDurationChanged() {
        let val = peekDurationSlider.doubleValue
        pillController.peekDuration = val
        peekDurationLabel.stringValue = String(format: "%.1f s", val)
    }
    
    @objc private func menuBarTitleToggled() {
        menuBarController.showTitleInMenuBar = (menuBarTitleCheckbox.state == .on)
    }
}
