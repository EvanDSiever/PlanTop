import AppKit

final class FlippedSettingsContainer: NSView {
    override var isFlipped: Bool { return true }
}

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var detector: YouTubeDetector
    private var pillController: FloatingPillWindowController
    private var menuBarController: MenuBarController
    private var settingsScrollView: NSScrollView?
    
    // Live Status UI
    private let statusLabel = NSTextField(labelWithString: "No YouTube Audio Playing")
    private let trackSubtitleLabel = NSTextField(labelWithString: "Play music in Chrome, Safari, Brave, or Arc")
    private let browserBadge = NSTextField(labelWithString: "Chrome")
    
    // Mode Control
    private let modeSegmentedControl = NSSegmentedControl(labels: ["Right Hover Slide", "Always Visible Panel", "Menu Bar Only"], trackingMode: .selectOne, target: nil, action: nil)
    
    // Appearance & Color Scheme Controls
    private let colorPresetOrange = NSButton(title: "Orange", target: nil, action: nil)
    private let colorPresetCoral = NSButton(title: "Coral", target: nil, action: nil)
    private let colorPresetBlue = NSButton(title: "Blue", target: nil, action: nil)
    private let colorPresetGreen = NSButton(title: "Green", target: nil, action: nil)
    private let colorPresetPurple = NSButton(title: "Purple", target: nil, action: nil)
    private let customColorWell = NSColorWell()
    
    // Typography & Font Selectors
    private let timeFontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appFontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    
    // Hover Controls (Right-Edge)
    private let widthSlider = NSSlider(value: 65, minValue: 25, maxValue: 150, target: nil, action: nil)
    private let widthValueLabel = NSTextField(labelWithString: "65 px")
    private let heightSlider = NSSlider(value: 550, minValue: 200, maxValue: 1100, target: nil, action: nil)
    private let heightValueLabel = NSTextField(labelWithString: "550 px")
    private let sensitivitySlider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 0.35, target: nil, action: nil)
    private let sensitivityValueLabel = NSTextField(labelWithString: "Instant (0.0s)")
    private let guideButton = NSButton(title: "Highlight Right Zone", target: nil, action: nil)
    
    // Video Preview & Sizing Controls
    private let videoPreviewCheckbox = NSButton(checkboxWithTitle: "Show video playing in side panel when active", target: nil, action: nil)
    private let pipCheckbox = NSButton(checkboxWithTitle: "Enable Picture-in-Picture mode (video player in side panel)", target: nil, action: nil)
    private let pipAudioCheckbox = NSButton(checkboxWithTitle: "Transfer sound to side panel in Picture-in-Picture mode", target: nil, action: nil)
    private let pipSyncBackCheckbox = NSButton(checkboxWithTitle: "Sync watching progress back to webpage when returning to tab", target: nil, action: nil)
    private let nativePiPCompanionCheckbox = NSButton(checkboxWithTitle: "Auto-dock companion controls when browser PiP is active", target: nil, action: nil)
    private let pinCheckbox = NSButton(checkboxWithTitle: "Pin side panel on screen permanently", target: nil, action: nil)
    private let panelWidthSlider = NSSlider(value: 340, minValue: 260, maxValue: 650, target: nil, action: nil)
    private let panelWidthValueLabel = NSTextField(labelWithString: "340 px")
    
    // Google Calendar Panel Controls
    private let calendarEnabledCheckbox = NSButton(checkboxWithTitle: "Show Google Calendar panel underneath video panel", target: nil, action: nil)
    private let calendarEmailField = NSTextField()
    private let classIdentifiersField = NSTextField()
    private let calendarStatusLabel = NSTextField(labelWithString: "Status: Checking...")
    private let calendarRefreshButton = NSButton(title: "Sync Now", target: nil, action: nil)
    private let calendarAccountsButton = NSButton(title: "Google Accounts", target: nil, action: nil)
    private let calendarICalField = NSTextField()
    
    // A/V Lip-Sync Calibration Controls
    private let syncDelaySlider = NSSlider(value: 0, minValue: -400, maxValue: 400, target: nil, action: nil)
    private let syncDelayValueLabel = NSTextField(labelWithString: "0 ms")
    private let presetMinus250Button = NSButton()
    private let presetZeroButton = NSButton()
    private let presetAdvanceButton = NSButton()
    private let presetDelayButton = NSButton()
    private let presetBluetoothButton = NSButton()
    
    // Auto Peek Controls
    private let autoPeekCheckbox = NSButton(checkboxWithTitle: "Automatically stretch out when a new song starts", target: nil, action: nil)
    private let peekDurationSlider = NSSlider(value: 5.0, minValue: 2.0, maxValue: 10.0, target: nil, action: nil)
    private let peekDurationLabel = NSTextField(labelWithString: "5.0 s")
    
    // Menu Bar & Startup Control
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch SongTop automatically at login", target: nil, action: nil)
    private let menuBarTitleCheckbox = NSButton(checkboxWithTitle: "Display song name in the macOS Menu Bar", target: nil, action: nil)
    
    // Cards collection for responsive centering & borderless layout
    private var sectionCards: [NSView] = []
    private var headerIconView: NSView?
    private var headerTitleLabel: NSView?
    private var headerSubtitleLabel: NSView?
    private var settingsContainer: FlippedSettingsContainer?
    
    // Browser Status Container
    private let browsersStack = NSStackView()
    private let tabAutomationStatusLabel = NSTextField(labelWithString: "In-Tab JavaScript: Waiting for YouTube playback")
    private let testTabAutomationButton = NSButton(title: "Test Connection", target: nil, action: nil)
    
    public var onWindowClosed: (() -> Void)?
    
    public init(detector: YouTubeDetector, pillController: FloatingPillWindowController, menuBarController: MenuBarController) {
        self.detector = detector
        self.pillController = pillController
        self.menuBarController = menuBarController
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SongTop Settings & Customization"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(red: 0.965, green: 0.973, blue: 0.985, alpha: 1.0)
        window.minSize = NSSize(width: 520, height: 480)
        window.collectionBehavior = [.fullScreenPrimary]
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onCalendarStatusUpdated),
            name: .songTopCalendarUpdated,
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
        window?.appearance = NSAppearance(named: .aqua)
        loadInitialValues()
        updateLiveStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let clip = settingsScrollView?.contentView {
            clip.scroll(to: NSPoint(x: 0, y: 0))
            settingsScrollView?.reflectScrolledClipView(clip)
        }
    }
    
    public func windowWillClose(_ notification: Notification) {
        pillController.hideTriggerZoneGuide()
        onWindowClosed?()
    }
    
    public func windowDidResize(_ notification: Notification) {
        relayoutContainer()
    }
    
    public func windowDidEnterFullScreen(_ notification: Notification) {
        relayoutContainer()
    }
    
    public func windowDidExitFullScreen(_ notification: Notification) {
        relayoutContainer()
    }
    
    @objc private func handleScrollViewBoundsChanged() {
        relayoutContainer()
    }
    
    private func relayoutContainer() {
        guard let scrollView = settingsScrollView, let container = settingsContainer else { return }
        let viewportWidth = scrollView.contentView.bounds.width
        let targetWidth = max(520, viewportWidth)
        if container.frame.width != targetWidth {
            container.frame.size.width = targetWidth
        }
        
        let cardWidth: CGFloat = 480
        let cardX = max(20, round((targetWidth - cardWidth) / 2))
        
        headerIconView?.frame.origin.x = cardX + 4
        headerTitleLabel?.frame.origin.x = cardX + 62
        headerSubtitleLabel?.frame.origin.x = cardX + 62
        
        for card in sectionCards {
            card.frame.origin.x = cardX
        }
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        window?.appearance = NSAppearance(named: .aqua)
        window?.backgroundColor = NSColor(red: 0.965, green: 0.973, blue: 0.985, alpha: 1.0)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(red: 0.965, green: 0.973, blue: 0.985, alpha: 1.0).cgColor
        
        sectionCards.removeAll()
        
        let scrollView = NSScrollView(frame: contentView.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        contentView.addSubview(scrollView)
        self.settingsScrollView = scrollView
        
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollViewBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollViewBoundsChanged),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        
        let container = FlippedSettingsContainer(frame: NSRect(x: 0, y: 0, width: 520, height: 1350))
        scrollView.documentView = container
        self.settingsContainer = container
        
        var currentY: CGFloat = 20
        
        // 1. Header
        let iconView = NSImageView(frame: NSRect(x: 24, y: currentY, width: 48, height: 48))
        if let icon = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil) {
            iconView.image = icon
        }
        container.addSubview(iconView)
        self.headerIconView = iconView
        
        let appTitle = NSTextField(labelWithString: "SongTop")
        appTitle.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        appTitle.frame = NSRect(x: 82, y: currentY + 4, width: 300, height: 24)
        container.addSubview(appTitle)
        self.headerTitleLabel = appTitle
        
        let appSubtitle = NSTextField(labelWithString: "YouTube Now Playing for macOS • Right-Side Panel Settings")
        appSubtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        appSubtitle.textColor = .secondaryLabelColor
        appSubtitle.frame = NSRect(x: 82, y: currentY + 28, width: 390, height: 16)
        container.addSubview(appSubtitle)
        self.headerSubtitleLabel = appSubtitle
        
        currentY += 62
        
        // 2. Live Now Playing Card
        let liveCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 74))
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
        
        currentY += 74 + 14
        
        // 3. Appearance, Color Scheme & Typography Card
        let appearanceCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 186))
        container.addSubview(appearanceCard)
        
        let appearanceTitle = NSTextField(labelWithString: "Appearance, Color Scheme & Typography")
        appearanceTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        appearanceTitle.textColor = NeumorphicTheme.accentColor
        appearanceTitle.frame = NSRect(x: 14, y: 156, width: 350, height: 16)
        appearanceCard.addSubview(appearanceTitle)
        
        // Color Scheme row
        let colorLabel = NSTextField(labelWithString: "Accent Color:")
        colorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        colorLabel.textColor = NeumorphicTheme.textPrimary
        colorLabel.frame = NSRect(x: 14, y: 126, width: 90, height: 16)
        appearanceCard.addSubview(colorLabel)
        
        let presets = [
            (colorPresetOrange, "Orange", 1),
            (colorPresetCoral, "Coral", 2),
            (colorPresetBlue, "Blue", 3),
            (colorPresetGreen, "Green", 4),
            (colorPresetPurple, "Purple", 5)
        ]
        var pX: CGFloat = 105
        for (btn, title, tag) in presets {
            btn.title = title
            btn.tag = tag
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
            btn.target = self
            btn.action = #selector(colorPresetClicked(_:))
            btn.frame = NSRect(x: pX, y: 122, width: 52, height: 24)
            appearanceCard.addSubview(btn)
            pX += 54
        }
        
        customColorWell.frame = NSRect(x: pX + 4, y: 122, width: 66, height: 24)
        customColorWell.target = self
        customColorWell.action = #selector(customColorWellChanged(_:))
        appearanceCard.addSubview(customColorWell)
        
        // Time Font row
        let timeLabel = NSTextField(labelWithString: "Time Font:")
        timeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = NeumorphicTheme.textPrimary
        timeLabel.frame = NSRect(x: 14, y: 84, width: 90, height: 16)
        appearanceCard.addSubview(timeLabel)
        
        timeFontPopup.frame = NSRect(x: 105, y: 80, width: 230, height: 24)
        timeFontPopup.removeAllItems()
        timeFontPopup.addItems(withTitles: [
            "Alien League Condensed",
            "Alien League Regular",
            "Futura Condensed Light",
            "SF Pro Rounded Light",
            "Monospaced Digit",
            "System Ultra Light"
        ])
        timeFontPopup.target = self
        timeFontPopup.action = #selector(timeFontChanged(_:))
        appearanceCard.addSubview(timeFontPopup)
        
        let timeHint = NSTextField(labelWithString: "Selected font applies to event time badges in the right-side panel.")
        timeHint.font = NSFont.systemFont(ofSize: 9.5)
        timeHint.textColor = .secondaryLabelColor
        timeHint.frame = NSRect(x: 108, y: 64, width: 350, height: 14)
        appearanceCard.addSubview(timeHint)
        
        // App Typography row
        let appFontLabel = NSTextField(labelWithString: "App Font:")
        appFontLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        appFontLabel.textColor = NeumorphicTheme.textPrimary
        appFontLabel.frame = NSRect(x: 14, y: 32, width: 90, height: 16)
        appearanceCard.addSubview(appFontLabel)
        
        appFontPopup.frame = NSRect(x: 105, y: 28, width: 230, height: 24)
        appFontPopup.removeAllItems()
        appFontPopup.addItems(withTitles: [
            "SF Pro Rounded (Default)",
            "System Default",
            "Monospaced",
            "Serif"
        ])
        appFontPopup.target = self
        appFontPopup.action = #selector(appFontChanged(_:))
        appearanceCard.addSubview(appFontPopup)
        
        let appHint = NSTextField(labelWithString: "Applied across tabs, buttons, calendar cards, and titles.")
        appHint.font = NSFont.systemFont(ofSize: 9.5)
        appHint.textColor = .secondaryLabelColor
        appHint.frame = NSRect(x: 108, y: 12, width: 350, height: 14)
        appearanceCard.addSubview(appHint)
        
        currentY += 186 + 14
        
        // 4. Display Mode Card
        let modeCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 70))
        container.addSubview(modeCard)
        
        let modeTitle = NSTextField(labelWithString: "Display Mode")
        modeTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        modeTitle.frame = NSRect(x: 14, y: 44, width: 300, height: 16)
        modeCard.addSubview(modeTitle)
        
        modeSegmentedControl.frame = NSRect(x: 14, y: 12, width: 450, height: 26)
        modeSegmentedControl.target = self
        modeSegmentedControl.action = #selector(modeChanged)
        modeCard.addSubview(modeSegmentedControl)
        
        currentY += 70 + 14
        
        // 4. Right-Edge Hover Sensitivity & Area Card
        let hoverCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 174))
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
        
        let hoverDesc = NSTextField(labelWithString: "Tip: Hover near the right edge of your screen. The panel stretches out smoothly.")
        hoverDesc.font = NSFont.systemFont(ofSize: 10)
        hoverDesc.textColor = .secondaryLabelColor
        hoverDesc.frame = NSRect(x: 14, y: 12, width: 450, height: 16)
        hoverCard.addSubview(hoverDesc)
        
        currentY += 174 + 14
        
        // 5. Behavior / Auto-Peek Card
        let peekCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 94))
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
        
        currentY += 94 + 14
        
        // 6. Live Video Playback & Picture-in-Picture Card
        let videoCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 304))
        container.addSubview(videoCard)
        
        let videoTitle = NSTextField(labelWithString: "Live Video Playback & Picture-in-Picture (PiP)")
        videoTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        videoTitle.frame = NSRect(x: 14, y: 276, width: 380, height: 16)
        videoCard.addSubview(videoTitle)
        
        videoPreviewCheckbox.frame = NSRect(x: 14, y: 250, width: 450, height: 18)
        videoPreviewCheckbox.target = self
        videoPreviewCheckbox.action = #selector(videoPreviewToggled)
        videoCard.addSubview(videoPreviewCheckbox)
        
        pipCheckbox.frame = NSRect(x: 14, y: 226, width: 450, height: 18)
        pipCheckbox.target = self
        pipCheckbox.action = #selector(pipCheckboxToggled)
        videoCard.addSubview(pipCheckbox)
        
        pipAudioCheckbox.frame = NSRect(x: 14, y: 202, width: 450, height: 18)
        pipAudioCheckbox.target = self
        pipAudioCheckbox.action = #selector(pipAudioCheckboxToggled)
        videoCard.addSubview(pipAudioCheckbox)
        
        pipSyncBackCheckbox.frame = NSRect(x: 14, y: 178, width: 450, height: 18)
        pipSyncBackCheckbox.target = self
        pipSyncBackCheckbox.action = #selector(pipSyncBackCheckboxToggled)
        videoCard.addSubview(pipSyncBackCheckbox)
        
        nativePiPCompanionCheckbox.frame = NSRect(x: 14, y: 154, width: 450, height: 18)
        nativePiPCompanionCheckbox.target = self
        nativePiPCompanionCheckbox.action = #selector(nativePiPCompanionToggled)
        videoCard.addSubview(nativePiPCompanionCheckbox)
        
        pinCheckbox.frame = NSRect(x: 14, y: 128, width: 450, height: 18)
        pinCheckbox.target = self
        pinCheckbox.action = #selector(pinCheckboxToggled)
        videoCard.addSubview(pinCheckbox)
        
        let pwLabel = NSTextField(labelWithString: "Panel Width:")
        pwLabel.font = NSFont.systemFont(ofSize: 11)
        pwLabel.frame = NSRect(x: 14, y: 98, width: 85, height: 16)
        videoCard.addSubview(pwLabel)
        
        panelWidthSlider.isContinuous = true
        panelWidthSlider.frame = NSRect(x: 105, y: 96, width: 290, height: 20)
        panelWidthSlider.target = self
        panelWidthSlider.action = #selector(panelWidthSliderChanged)
        videoCard.addSubview(panelWidthSlider)
        
        panelWidthValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        panelWidthValueLabel.alignment = .right
        panelWidthValueLabel.frame = NSRect(x: 400, y: 98, width: 65, height: 16)
        videoCard.addSubview(panelWidthValueLabel)
        
        // Option 2: Direct Tab Automation Controls
        tabAutomationStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        tabAutomationStatusLabel.frame = NSRect(x: 14, y: 64, width: 330, height: 20)
        tabAutomationStatusLabel.lineBreakMode = .byTruncatingTail
        videoCard.addSubview(tabAutomationStatusLabel)
        
        testTabAutomationButton.bezelStyle = .rounded
        testTabAutomationButton.frame = NSRect(x: 350, y: 60, width: 116, height: 26)
        testTabAutomationButton.target = self
        testTabAutomationButton.action = #selector(testTabAutomationClicked)
        videoCard.addSubview(testTabAutomationButton)
        
        let tabTipChrome = NSTextField(labelWithString: "Chrome / Brave / Arc: View > Developer > Allow JavaScript from Apple Events")
        tabTipChrome.font = NSFont.systemFont(ofSize: 10)
        tabTipChrome.textColor = .secondaryLabelColor
        tabTipChrome.frame = NSRect(x: 14, y: 44, width: 450, height: 14)
        videoCard.addSubview(tabTipChrome)
        
        let tabTipSafari = NSTextField(labelWithString: "Safari: Develop > Allow JavaScript from Apple Events")
        tabTipSafari.font = NSFont.systemFont(ofSize: 10)
        tabTipSafari.textColor = .secondaryLabelColor
        tabTipSafari.frame = NSRect(x: 14, y: 26, width: 450, height: 14)
        videoCard.addSubview(tabTipSafari)
        
        let dragTip = NSTextField(labelWithString: "Tip: You can also drag the left edge of the side panel to resize it interactively!")
        dragTip.font = NSFont.systemFont(ofSize: 10)
        dragTip.textColor = .secondaryLabelColor
        dragTip.frame = NSRect(x: 14, y: 8, width: 450, height: 14)
        videoCard.addSubview(dragTip)
        
        currentY += 304 + 14
        
        // 7. Audio / Video Lip-Sync Calibration Card
        let syncCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 118))
        container.addSubview(syncCard)
        
        let syncTitle = NSTextField(labelWithString: "Audio / Video Lip-Sync Calibration")
        syncTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        syncTitle.frame = NSRect(x: 14, y: 90, width: 350, height: 16)
        syncCard.addSubview(syncTitle)
        
        let delayLabel = NSTextField(labelWithString: "Panel Offset:")
        delayLabel.font = NSFont.systemFont(ofSize: 11)
        delayLabel.frame = NSRect(x: 14, y: 64, width: 85, height: 16)
        syncCard.addSubview(delayLabel)
        
        syncDelaySlider.isContinuous = true
        syncDelaySlider.frame = NSRect(x: 105, y: 62, width: 290, height: 20)
        syncDelaySlider.target = self
        syncDelaySlider.action = #selector(syncDelaySliderChanged)
        syncCard.addSubview(syncDelaySlider)
        
        syncDelayValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        syncDelayValueLabel.alignment = .right
        syncDelayValueLabel.frame = NSRect(x: 400, y: 64, width: 65, height: 16)
        syncCard.addSubview(syncDelayValueLabel)
        
        // Presets Stack
        let presetsStack = NSStackView()
        presetsStack.orientation = .horizontal
        presetsStack.spacing = 6
        presetsStack.frame = NSRect(x: 14, y: 32, width: 452, height: 22)
        
        configurePresetButton(presetMinus250Button, title: "-250 ms (Ideal)", action: #selector(presetMinus250Clicked))
        configurePresetButton(presetAdvanceButton, title: "-80 ms", action: #selector(presetAdvanceClicked))
        configurePresetButton(presetZeroButton, title: "0 ms (Exact)", action: #selector(presetZeroClicked))
        configurePresetButton(presetDelayButton, title: "+80 ms", action: #selector(presetDelayClicked))
        configurePresetButton(presetBluetoothButton, title: "+180 ms (BT)", action: #selector(presetBluetoothClicked))
        
        presetsStack.addArrangedSubview(presetMinus250Button)
        presetsStack.addArrangedSubview(presetAdvanceButton)
        presetsStack.addArrangedSubview(presetZeroButton)
        presetsStack.addArrangedSubview(presetDelayButton)
        presetsStack.addArrangedSubview(presetBluetoothButton)
        syncCard.addSubview(presetsStack)
        
        let syncTip = NSTextField(labelWithString: "0 ms locks exact frames with YouTube. Negative pulls video forward; positive delays video.")
        syncTip.font = NSFont.systemFont(ofSize: 10)
        syncTip.textColor = .secondaryLabelColor
        syncTip.frame = NSRect(x: 14, y: 10, width: 450, height: 14)
        syncCard.addSubview(syncTip)
        
        currentY += 118 + 14
        
        // 8. Google Calendar Activity Panel Card
        let calendarCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 228))
        container.addSubview(calendarCard)
        
        let calTitle = NSTextField(labelWithString: "Google Calendar Activity Panel")
        calTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        calTitle.textColor = NeumorphicTheme.accentColor
        calTitle.frame = NSRect(x: 14, y: 200, width: 350, height: 16)
        calendarCard.addSubview(calTitle)
        
        calendarEnabledCheckbox.frame = NSRect(x: 14, y: 174, width: 450, height: 18)
        calendarEnabledCheckbox.target = self
        calendarEnabledCheckbox.action = #selector(calendarEnabledToggled)
        calendarCard.addSubview(calendarEnabledCheckbox)
        
        let emailLabel = NSTextField(labelWithString: "Account:")
        emailLabel.font = NSFont.systemFont(ofSize: 11)
        emailLabel.frame = NSRect(x: 14, y: 146, width: 60, height: 16)
        calendarCard.addSubview(emailLabel)
        
        calendarEmailField.frame = NSRect(x: 78, y: 144, width: 220, height: 21)
        calendarEmailField.font = NSFont.systemFont(ofSize: 11)
        calendarEmailField.placeholderString = "evandsiever@gmail.com"
        calendarEmailField.target = self
        calendarEmailField.action = #selector(calendarEmailChanged)
        calendarCard.addSubview(calendarEmailField)
        
        calendarRefreshButton.frame = NSRect(x: 304, y: 142, width: 75, height: 24)
        calendarRefreshButton.bezelStyle = .rounded
        calendarRefreshButton.target = self
        calendarRefreshButton.action = #selector(calendarRefreshClicked)
        calendarCard.addSubview(calendarRefreshButton)
        
        calendarAccountsButton.frame = NSRect(x: 382, y: 142, width: 88, height: 24)
        calendarAccountsButton.bezelStyle = .rounded
        calendarAccountsButton.target = self
        calendarAccountsButton.action = #selector(calendarAccountsClicked)
        calendarCard.addSubview(calendarAccountsButton)
        
        // Class Identifiers / Detectors row
        let classIdLabel = NSTextField(labelWithString: "Class Detectors:")
        classIdLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        classIdLabel.frame = NSRect(x: 14, y: 116, width: 100, height: 16)
        calendarCard.addSubview(classIdLabel)
        
        classIdentifiersField.frame = NSRect(x: 118, y: 113, width: 348, height: 22)
        classIdentifiersField.font = NSFont.systemFont(ofSize: 11)
        classIdentifiersField.placeholderString = "Class IEL, Alfatih, Lecture, Lab"
        classIdentifiersField.target = self
        classIdentifiersField.action = #selector(classIdentifiersChanged(_:))
        calendarCard.addSubview(classIdentifiersField)
        
        let classIdHint = NSTextField(labelWithString: "Keywords separated by commas. Matching events appear in the Classes tab.")
        classIdHint.font = NSFont.systemFont(ofSize: 9.5)
        classIdHint.textColor = .secondaryLabelColor
        classIdHint.frame = NSRect(x: 118, y: 95, width: 348, height: 14)
        calendarCard.addSubview(classIdHint)
        
        calendarStatusLabel.font = NSFont.systemFont(ofSize: 10.5)
        calendarStatusLabel.textColor = .secondaryLabelColor
        calendarStatusLabel.frame = NSRect(x: 14, y: 66, width: 450, height: 16)
        calendarCard.addSubview(calendarStatusLabel)
        
        let icalLabel = NSTextField(labelWithString: "Private iCal Feed URL (Optional Fallback):")
        icalLabel.font = NSFont.systemFont(ofSize: 10)
        icalLabel.textColor = .secondaryLabelColor
        icalLabel.frame = NSRect(x: 14, y: 38, width: 300, height: 14)
        calendarCard.addSubview(icalLabel)
        
        calendarICalField.frame = NSRect(x: 14, y: 12, width: 452, height: 20)
        calendarICalField.font = NSFont.systemFont(ofSize: 10)
        calendarICalField.placeholderString = "https://calendar.google.com/calendar/ical/.../basic.ics"
        calendarICalField.target = self
        calendarICalField.action = #selector(calendarICalChanged)
        calendarCard.addSubview(calendarICalField)
        
        currentY += 228 + 14
        
        // 9. Startup & Menu Bar Integration Card
        let menuCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 76))
        container.addSubview(menuCard)
        
        let menuTitle = NSTextField(labelWithString: "System & Menu Bar Integration")
        menuTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        menuTitle.frame = NSRect(x: 14, y: 52, width: 350, height: 16)
        menuCard.addSubview(menuTitle)
        
        launchAtLoginCheckbox.frame = NSRect(x: 14, y: 28, width: 450, height: 18)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled)
        menuCard.addSubview(launchAtLoginCheckbox)
        
        menuBarTitleCheckbox.frame = NSRect(x: 14, y: 6, width: 450, height: 18)
        menuBarTitleCheckbox.target = self
        menuBarTitleCheckbox.action = #selector(menuBarTitleToggled)
        menuCard.addSubview(menuBarTitleCheckbox)
        
        currentY += 76 + 14
        
        // 10. Browser Status Card
        let browserCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: 58))
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
        
        currentY += 58 + 24
        
        container.frame = NSRect(x: 0, y: 0, width: 520, height: currentY)
        relayoutContainer()
    }
    
    private func createCardView(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.borderWidth = 0
        card.layer?.borderColor = nil
        sectionCards.append(card)
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
        
        if detector.isTabAutomationActive {
            tabAutomationStatusLabel.stringValue = "In-Tab Automation: Active (Zero-Reload)"
            tabAutomationStatusLabel.textColor = .systemGreen
        } else if let track = detector.currentTrack {
            tabAutomationStatusLabel.stringValue = "In-Tab Automation: Ready (\(track.browser))"
            tabAutomationStatusLabel.textColor = NeumorphicTheme.accentColor
        } else {
            tabAutomationStatusLabel.stringValue = "In-Tab Automation: Waiting for playback"
            tabAutomationStatusLabel.textColor = .secondaryLabelColor
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
            let badge = NSTextField(labelWithString: isRunning ? "• \(name) (Active)" : "• \(name)")
            badge.font = NSFont.systemFont(ofSize: 10, weight: isRunning ? .semibold : .regular)
            badge.textColor = isRunning ? NeumorphicTheme.accentColor : .tertiaryLabelColor
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
        pipCheckbox.state = pillController.isPiPEnabled ? .on : .off
        pipAudioCheckbox.state = pillController.isPiPAudioTransferEnabled ? .on : .off
        pipSyncBackCheckbox.state = pillController.isPiPSyncProgressEnabled ? .on : .off
        nativePiPCompanionCheckbox.state = pillController.isNativePiPCompanionEnabled ? .on : .off
        pinCheckbox.state = pillController.isPinned ? .on : .off
        
        panelWidthSlider.doubleValue = Double(pillController.customPanelWidth)
        panelWidthValueLabel.stringValue = "\(Int(pillController.customPanelWidth)) px"
        
        var delayMs = UserDefaults.standard.object(forKey: "songtop_av_sync_delay_ms") != nil
            ? UserDefaults.standard.double(forKey: "songtop_av_sync_delay_ms")
            : 0.0
        if delayMs == 250.0 {
            delayMs = 0.0
            UserDefaults.standard.set(0.0, forKey: "songtop_av_sync_delay_ms")
        }
        syncDelaySlider.doubleValue = delayMs
        syncDelayValueLabel.stringValue = formatDelayMs(delayMs)
        
        autoPeekCheckbox.state = pillController.autoPeekEnabled ? .on : .off
        peekDurationSlider.doubleValue = pillController.peekDuration
        peekDurationLabel.stringValue = String(format: "%.1f s", pillController.peekDuration)
        
        menuBarTitleCheckbox.state = menuBarController.showTitleInMenuBar ? .on : .off
        launchAtLoginCheckbox.state = LaunchAtLoginHelper.isEnabled ? .on : .off
        guideButton.title = pillController.isGuidePinned ? "Hide Right Zone" : "Highlight Right Zone"
        
        let currentHex = UserDefaults.standard.string(forKey: "songtop_accent_color_hex") ?? "#FF700D"
        if let c = NeumorphicTheme.colorFromHex(currentHex) {
            customColorWell.color = c
        }
        
        let timeFont = UserDefaults.standard.string(forKey: "songtop_time_font_name") ?? "AlienLeagueCondensed"
        timeFontPopup.selectItem(withTitle: fontTitleForName(timeFont))
        
        let appFont = UserDefaults.standard.string(forKey: "songtop_app_font_family") ?? "Rounded"
        appFontPopup.selectItem(withTitle: appFontTitleForName(appFont))
        
        classIdentifiersField.stringValue = UserDefaults.standard.string(forKey: "songtop_class_identifiers") ?? "Class IEL, Alfatih"
        
        calendarEnabledCheckbox.state = GoogleCalendarService.shared.isCalendarEnabled ? .on : .off
        calendarEmailField.stringValue = GoogleCalendarService.shared.targetEmail
        calendarICalField.stringValue = GoogleCalendarService.shared.customICalURL
        updateCalendarStatusUI()
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
        guideButton.title = pillController.isGuidePinned ? "Hide Right Zone" : "Highlight Right Zone"
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
    }
    
    @objc private func heightSliderChanged() {
        let val = heightSlider.doubleValue
        pillController.scanHeight = CGFloat(val)
        heightValueLabel.stringValue = "\(Int(val)) px"
    }
    
    @objc private func sensitivitySliderChanged() {
        let val = sensitivitySlider.doubleValue
        pillController.hoverDelay = val
        updateSensitivityLabel(delay: val)
    }
    
    @objc private func videoPreviewToggled() {
        pillController.isVideoPreviewEnabled = (videoPreviewCheckbox.state == .on)
    }
    
    @objc private func pipCheckboxToggled() {
        pillController.isPiPEnabled = (pipCheckbox.state == .on)
    }
    
    @objc private func pipAudioCheckboxToggled() {
        pillController.isPiPAudioTransferEnabled = (pipAudioCheckbox.state == .on)
    }
    
    @objc private func pipSyncBackCheckboxToggled() {
        pillController.isPiPSyncProgressEnabled = (pipSyncBackCheckbox.state == .on)
    }
    
    @objc private func nativePiPCompanionToggled() {
        pillController.isNativePiPCompanionEnabled = (nativePiPCompanionCheckbox.state == .on)
    }
    
    @objc private func pinCheckboxToggled() {
        pillController.isPinned = (pinCheckbox.state == .on)
    }
    
    @objc private func panelWidthSliderChanged() {
        let val = panelWidthSlider.doubleValue
        pillController.customPanelWidth = CGFloat(val)
        panelWidthValueLabel.stringValue = "\(Int(val)) px"
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
    
    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        LaunchAtLoginHelper.setEnabled(enabled)
    }
    
    @objc private func testTabAutomationClicked() {
        testTabAutomationButton.isEnabled = false
        tabAutomationStatusLabel.stringValue = "Testing tab connection..."
        detector.testTabAutomationConnection { [weak self] isConnected, message in
            DispatchQueue.main.async {
                self?.testTabAutomationButton.isEnabled = true
                self?.tabAutomationStatusLabel.stringValue = isConnected
                    ? "In-Tab Automation: Connected!"
                    : "Check Browser Settings"
                self?.tabAutomationStatusLabel.textColor = isConnected ? .systemGreen : .systemRed
                
                let alert = NSAlert()
                alert.messageText = isConnected ? "Direct Tab Automation Active" : "Action Required in Browser"
                alert.informativeText = message
                alert.alertStyle = isConnected ? .informational : .warning
                alert.runModal()
            }
        }
    }
    
    private func configurePresetButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        button.target = self
        button.action = action
    }
    
    private func formatDelayMs(_ ms: Double) -> String {
        let rounded = Int(round(ms))
        if rounded > 0 {
            return "+\(rounded) ms"
        } else {
            return "\(rounded) ms"
        }
    }
    
    @objc private func syncDelaySliderChanged() {
        let val = round(syncDelaySlider.doubleValue / 10.0) * 10.0
        syncDelayValueLabel.stringValue = formatDelayMs(val)
        UserDefaults.standard.set(val, forKey: "songtop_av_sync_delay_ms")
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
    }
    
    @objc private func presetMinus250Clicked() {
        applySyncDelayPreset(-250)
    }
    
    @objc private func presetZeroClicked() {
        applySyncDelayPreset(0)
    }
    
    @objc private func presetAdvanceClicked() {
        applySyncDelayPreset(-80)
    }
    
    @objc private func presetDelayClicked() {
        applySyncDelayPreset(80)
    }
    
    @objc private func presetBluetoothClicked() {
        applySyncDelayPreset(180)
    }
    
    private func applySyncDelayPreset(_ ms: Double) {
        syncDelaySlider.doubleValue = ms
        syncDelayValueLabel.stringValue = formatDelayMs(ms)
        UserDefaults.standard.set(ms, forKey: "songtop_av_sync_delay_ms")
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
    }
    
    // MARK: - Appearance & Typography Handlers
    @objc private func colorPresetClicked(_ sender: NSButton) {
        let hex: String
        switch sender.tag {
        case 1: hex = "#FF700D" // Vibrant Orange
        case 2: hex = "#FF4D4F" // Coral Red
        case 3: hex = "#2563EB" // Electric Blue
        case 4: hex = "#059669" // Emerald Green
        case 5: hex = "#7C3AED" // Amethyst Purple
        default: hex = "#FF700D"
        }
        applyAccentColorHex(hex)
    }
    
    @objc private func customColorWellChanged(_ sender: NSColorWell) {
        let hex = NeumorphicTheme.hexString(from: sender.color)
        applyAccentColorHex(hex)
    }
    
    private func applyAccentColorHex(_ hex: String) {
        UserDefaults.standard.set(hex, forKey: "songtop_accent_color_hex")
        if let c = NeumorphicTheme.colorFromHex(hex) {
            customColorWell.color = c
        }
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
    }
    
    @objc private func timeFontChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let fontName: String
        switch title {
        case "Alien League Condensed": fontName = "AlienLeagueCondensed"
        case "Alien League Regular": fontName = "AlienLeague"
        case "Futura Condensed Light": fontName = "Futura-CondensedLight"
        case "SF Pro Rounded Light": fontName = "SFProRoundedLight"
        case "Monospaced Digit": fontName = "Monospaced"
        case "System Ultra Light": fontName = "System"
        default: fontName = "AlienLeagueCondensed"
        }
        UserDefaults.standard.set(fontName, forKey: "songtop_time_font_name")
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
    }
    
    @objc private func appFontChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let family: String
        switch title {
        case "SF Pro Rounded (Default)": family = "Rounded"
        case "System Default": family = "System"
        case "Monospaced": family = "Monospaced"
        case "Serif": family = "Serif"
        default: family = "Rounded"
        }
        UserDefaults.standard.set(family, forKey: "songtop_app_font_family")
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
    }
    
    @objc private func classIdentifiersChanged(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(text.isEmpty ? "Class IEL, Alfatih" : text, forKey: "songtop_class_identifiers")
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
    }
    
    private func fontTitleForName(_ name: String) -> String {
        switch name {
        case "AlienLeagueCondensed": return "Alien League Condensed"
        case "AlienLeague": return "Alien League Regular"
        case "Futura-CondensedLight": return "Futura Condensed Light"
        case "SFProRoundedLight": return "SF Pro Rounded Light"
        case "Monospaced": return "Monospaced Digit"
        case "System": return "System Ultra Light"
        default: return "Alien League Condensed"
        }
    }
    
    private func appFontTitleForName(_ family: String) -> String {
        switch family {
        case "Rounded": return "SF Pro Rounded (Default)"
        case "System": return "System Default"
        case "Monospaced": return "Monospaced"
        case "Serif": return "Serif"
        default: return "SF Pro Rounded (Default)"
        }
    }
    
    // MARK: - Google Calendar Handlers
    @objc private func calendarEnabledToggled() {
        GoogleCalendarService.shared.isCalendarEnabled = (calendarEnabledCheckbox.state == .on)
    }
    
    @objc private func calendarEmailChanged() {
        // Target account is fixed to evandsiever@gmail.com
    }
    
    @objc private func calendarICalChanged() {
        let text = calendarICalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        GoogleCalendarService.shared.customICalURL = text
    }
    
    @objc private func calendarRefreshClicked() {
        GoogleCalendarService.shared.refresh()
        updateCalendarStatusUI()
    }
    
    @objc private func calendarAccountsClicked() {
        GoogleCalendarService.shared.openSystemSettingsAccounts()
    }
    
    @objc private func onCalendarStatusUpdated() {
        DispatchQueue.main.async { [weak self] in
            self?.updateCalendarStatusUI()
        }
    }
    
    private func updateCalendarStatusUI() {
        let service = GoogleCalendarService.shared
        switch service.syncStatus {
        case .idle:
            calendarStatusLabel.stringValue = "Status: Ready • Target account: \(service.targetEmail)"
            calendarStatusLabel.textColor = .secondaryLabelColor
        case .syncing:
            calendarStatusLabel.stringValue = "Status: Syncing today's activity..."
            calendarStatusLabel.textColor = .systemBlue
        case .synced(let date, let todayCount, let tomorrowCount):
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm:ss a"
            let timeStr = formatter.string(from: date)
            calendarStatusLabel.stringValue = "Status: Synced at \(timeStr) • \(todayCount) today, \(tomorrowCount) tomorrow"
            calendarStatusLabel.textColor = .systemGreen
        case .needsPermission:
            calendarStatusLabel.stringValue = "Status: Calendar permission required. Click Sync Now to grant access."
            calendarStatusLabel.textColor = .systemOrange
        case .unauthorized:
            calendarStatusLabel.stringValue = "Status: Calendar permission denied in System Settings."
            calendarStatusLabel.textColor = .systemRed
        case .error(let msg):
            calendarStatusLabel.stringValue = "Status: \(msg)"
            calendarStatusLabel.textColor = .systemRed
        }
    }
}
