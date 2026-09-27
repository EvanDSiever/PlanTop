import AppKit

final class FlippedSettingsContainer: NSView {
    override var isFlipped: Bool { return true }
}

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var pillController: FloatingPillWindowController
    private var menuBarController: MenuBarController
    private var settingsScrollView: NSScrollView?
    
    // Mode Control
    private let modeSegmentedControl = NSSegmentedControl(labels: ["Right Hover Slide", "Always Visible Panel", "Menu Bar Only"], trackingMode: .selectOne, target: nil, action: nil)
    
    // Appearance & Color Scheme Controls
    private let colorPresetBlue = NSButton(title: "Blue", target: nil, action: nil)
    private let colorPresetPurple = NSButton(title: "Purple", target: nil, action: nil)
    private let colorPresetGreen = NSButton(title: "Green", target: nil, action: nil)
    private let colorPresetOrange = NSButton(title: "Orange", target: nil, action: nil)
    private let colorPresetRed = NSButton(title: "Red", target: nil, action: nil)
    private let customColorWell = NSColorWell()
    private var isInternalColorChange = false
    private var calTitleLabel: NSTextField?
    private var panelTitleLabel: NSTextField?
    private var appearanceTitleLabel: NSTextField?
    private var sysTitleLabel: NSTextField?
    
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
    
    // Side Panel Sizing & Pinning Controls
    private let pinCheckbox = NSButton(checkboxWithTitle: "Pin side panel on screen permanently", target: nil, action: nil)
    private let panelWidthSlider = NSSlider(value: 340, minValue: 260, maxValue: 650, target: nil, action: nil)
    private let panelWidthValueLabel = NSTextField(labelWithString: "340 px")
    
    // Daily Planner & Google Calendar Controls
    private let calendarEnabledCheckbox = NSButton(checkboxWithTitle: "Enable Daily Planner side-panel", target: nil, action: nil)
    private let classIdentifiersField = NSTextField()
    private let calendarStatusLabel = NSTextField(labelWithString: "Status: Checking...")
    private let calendarRefreshButton = NSButton(title: "Sync Now", target: nil, action: nil)
    private let calendarAccountsButton = NSButton(title: "System Calendar Accounts", target: nil, action: nil)
    private let calendarICalField = NSTextField()
    
    // Auto Peek Controls for Upcoming Events
    private let autoPeekCheckbox = NSButton(checkboxWithTitle: "Auto-slide out side panel when an upcoming event is starting", target: nil, action: nil)
    private let peekDurationSlider = NSSlider(value: 5.0, minValue: 2.0, maxValue: 10.0, target: nil, action: nil)
    private let peekDurationLabel = NSTextField(labelWithString: "5.0 s")
    
    // Menu Bar & Startup Control
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch PlanTop automatically at login", target: nil, action: nil)
    private let menuBarTitleCheckbox = NSButton(checkboxWithTitle: "Display upcoming schedule in macOS Menu Bar", target: nil, action: nil)
    
    // Cards collection for responsive centering & borderless layout
    private var sectionCards: [NSView] = []
    private var headerIconView: NSImageView?
    private var headerTitleLabel: NSView?
    private var headerSubtitleLabel: NSView?
    private var settingsContainer: FlippedSettingsContainer?
    
    public var onWindowClosed: (() -> Void)?
    
    public init(pillController: FloatingPillWindowController, menuBarController: MenuBarController) {
        self.pillController = pillController
        self.menuBarController = menuBarController
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PlanTop Settings & Preferences"
        window.backgroundColor = .windowBackgroundColor
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
            name: .planTopSettingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onCalendarStatusUpdated),
            name: .planTopCalendarUpdated,
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
        guard !isInternalColorChange else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isInternalColorChange else { return }
            self.loadInitialValues()
        }
    }
    
    public func show() {
        loadInitialValues()
        updateCalendarStatusUI()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        onWindowClosed?()
    }
    
    public func windowDidResize(_ notification: Notification) {
        relayoutResponsiveCards()
    }
    
    private func relayoutResponsiveCards() {
        guard let _ = settingsContainer, let scrollView = settingsScrollView else { return }
        let contentWidth = scrollView.contentView.bounds.width
        let cardWidth = min(contentWidth - 40, max(460, contentWidth - 40))
        let cardX = max(20, (contentWidth - cardWidth) / 2)
        
        if let icon = headerIconView, let title = headerTitleLabel, let subtitle = headerSubtitleLabel {
            icon.frame.origin.x = cardX
            title.frame.origin.x = cardX + 58
            subtitle.frame.origin.x = cardX + 58
        }
        
        for card in sectionCards {
            card.frame.origin.x = cardX
            card.frame.size.width = cardWidth
            card.needsLayout = true
        }
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        self.settingsScrollView = scrollView
        
        let container = FlippedSettingsContainer(frame: NSRect(x: 0, y: 0, width: 540, height: 980))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.settingsContainer = container
        
        var currentY: CGFloat = 24
        
        // 1. Header Banner
        let iconView = NSImageView(frame: NSRect(x: 20, y: currentY, width: 44, height: 44))
        let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "PlanTop")?.withSymbolConfiguration(config)
        iconView.contentTintColor = AppleTheme.primary
        container.addSubview(iconView)
        self.headerIconView = iconView
        
        let appTitle = NSTextField(labelWithString: "PlanTop Daily Planner")
        appTitle.font = AppleTheme.title2Font
        appTitle.textColor = AppleTheme.label
        appTitle.frame = NSRect(x: 74, y: currentY + 2, width: 380, height: 26)
        container.addSubview(appTitle)
        self.headerTitleLabel = appTitle
        
        let appSubtitle = NSTextField(labelWithString: "Stealth macOS Side-Panel Companion & Calendar Activity Hub")
        appSubtitle.font = AppleTheme.footnoteFont
        appSubtitle.textColor = AppleTheme.secondaryLabel
        appSubtitle.frame = NSRect(x: 74, y: currentY + 28, width: 420, height: 16)
        container.addSubview(appSubtitle)
        self.headerSubtitleLabel = appSubtitle
        
        currentY += 60
        
        // CARD 1: Google Calendar & Daily Planner Integration
        let calCardH: CGFloat = 260
        let calCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: calCardH))
        container.addSubview(calCard)
        sectionCards.append(calCard)
        
        let calTitle = NSTextField(labelWithString: "Daily Planner & Google Calendar Integration")
        calTitle.font = AppleTheme.font(size: 13, weight: .semibold)
        calTitle.textColor = AppleTheme.primary
        calTitle.frame = NSRect(x: 14, y: calCardH - 30, width: 400, height: 16)
        calCard.addSubview(calTitle)
        self.calTitleLabel = calTitle
        
        calendarEnabledCheckbox.frame = NSRect(x: 14, y: calCardH - 58, width: 400, height: 18)
        calendarEnabledCheckbox.target = self
        calendarEnabledCheckbox.action = #selector(calendarEnabledChanged(_:))
        calCard.addSubview(calendarEnabledCheckbox)
        
        // Class Detectors
        let classLabel = NSTextField(labelWithString: "Class Detectors (Keywords separated by commas):")
        classLabel.font = AppleTheme.font(size: 12, weight: .medium)
        classLabel.textColor = AppleTheme.label
        classLabel.frame = NSRect(x: 14, y: calCardH - 90, width: 420, height: 16)
        calCard.addSubview(classLabel)
        
        classIdentifiersField.frame = NSRect(x: 14, y: calCardH - 116, width: 450, height: 22)
        classIdentifiersField.placeholderString = "Class IEL, Alfatih, Lecture, Lab, Seminar"
        classIdentifiersField.target = self
        classIdentifiersField.action = #selector(classIdentifiersChanged(_:))
        calCard.addSubview(classIdentifiersField)
        
        // iCal subscription URL
        let iCalLabel = NSTextField(labelWithString: "Custom Google Calendar iCal URL (Secret Address in iCal format):")
        iCalLabel.font = AppleTheme.font(size: 12, weight: .medium)
        iCalLabel.textColor = AppleTheme.label
        iCalLabel.frame = NSRect(x: 14, y: calCardH - 148, width: 450, height: 16)
        calCard.addSubview(iCalLabel)
        
        calendarICalField.frame = NSRect(x: 14, y: calCardH - 174, width: 450, height: 22)
        calendarICalField.placeholderString = "https://calendar.google.com/calendar/ical/.../basic.ics"
        calendarICalField.target = self
        calendarICalField.action = #selector(calendarICalChanged(_:))
        calCard.addSubview(calendarICalField)
        
        // Sync status and actions
        calendarStatusLabel.font = AppleTheme.footnoteFont
        calendarStatusLabel.textColor = AppleTheme.secondaryLabel
        calendarStatusLabel.frame = NSRect(x: 14, y: 18, width: 230, height: 26)
        calCard.addSubview(calendarStatusLabel)
        
        calendarRefreshButton.bezelStyle = .rounded
        calendarRefreshButton.target = self
        calendarRefreshButton.action = #selector(syncCalendarNowClicked)
        calendarRefreshButton.frame = NSRect(x: 250, y: 16, width: 90, height: 28)
        calCard.addSubview(calendarRefreshButton)
        
        calendarAccountsButton.bezelStyle = .rounded
        calendarAccountsButton.target = self
        calendarAccountsButton.action = #selector(openCalendarAccountsClicked)
        calendarAccountsButton.frame = NSRect(x: 345, y: 16, width: 122, height: 28)
        calCard.addSubview(calendarAccountsButton)
        
        currentY += calCardH + 14
        
        // CARD 2: Right-Edge Slide Panel & Display Mode
        let panelCardH: CGFloat = 370
        let panelCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: panelCardH))
        container.addSubview(panelCard)
        sectionCards.append(panelCard)
        
        let panelTitle = NSTextField(labelWithString: "Right-Edge Slide Panel & Display Mode")
        panelTitle.font = AppleTheme.font(size: 13, weight: .semibold)
        panelTitle.textColor = AppleTheme.primary
        panelTitle.frame = NSRect(x: 14, y: panelCardH - 30, width: 400, height: 16)
        panelCard.addSubview(panelTitle)
        self.panelTitleLabel = panelTitle
        
        modeSegmentedControl.frame = NSRect(x: 14, y: panelCardH - 62, width: 450, height: 24)
        modeSegmentedControl.target = self
        modeSegmentedControl.action = #selector(modeSegmentChanged(_:))
        panelCard.addSubview(modeSegmentedControl)
        
        // 1. Hover Scan Reach slider
        let reachLabel = NSTextField(labelWithString: "Hover Scan Reach (px from right bezel):")
        reachLabel.font = AppleTheme.font(size: 12, weight: .medium)
        reachLabel.textColor = AppleTheme.label
        reachLabel.frame = NSRect(x: 14, y: panelCardH - 96, width: 280, height: 16)
        panelCard.addSubview(reachLabel)
        
        widthSlider.frame = NSRect(x: 14, y: panelCardH - 120, width: 380, height: 20)
        widthSlider.target = self
        widthSlider.action = #selector(widthSliderChanged(_:))
        panelCard.addSubview(widthSlider)
        
        widthValueLabel.font = AppleTheme.font(size: 12, weight: .semibold)
        widthValueLabel.textColor = AppleTheme.secondaryLabel
        widthValueLabel.alignment = .right
        widthValueLabel.frame = NSRect(x: 400, y: panelCardH - 120, width: 64, height: 20)
        panelCard.addSubview(widthValueLabel)
        
        // 2. Hover Trigger Height slider
        let heightLabel = NSTextField(labelWithString: "Hover Trigger Zone Height (200px - 1100px):")
        heightLabel.font = AppleTheme.font(size: 12, weight: .medium)
        heightLabel.textColor = AppleTheme.label
        heightLabel.frame = NSRect(x: 14, y: panelCardH - 150, width: 320, height: 16)
        panelCard.addSubview(heightLabel)
        
        heightSlider.frame = NSRect(x: 14, y: panelCardH - 174, width: 380, height: 20)
        heightSlider.target = self
        heightSlider.action = #selector(heightSliderChanged(_:))
        panelCard.addSubview(heightSlider)
        
        heightValueLabel.font = AppleTheme.font(size: 12, weight: .semibold)
        heightValueLabel.textColor = AppleTheme.secondaryLabel
        heightValueLabel.alignment = .right
        heightValueLabel.frame = NSRect(x: 400, y: panelCardH - 174, width: 64, height: 20)
        panelCard.addSubview(heightValueLabel)
        
        // 3. Hover Sensitivity / Delay slider
        let sensitivityLabel = NSTextField(labelWithString: "Hover Activation Delay (Sensitivity):")
        sensitivityLabel.font = AppleTheme.font(size: 12, weight: .medium)
        sensitivityLabel.textColor = AppleTheme.label
        sensitivityLabel.frame = NSRect(x: 14, y: panelCardH - 204, width: 320, height: 16)
        panelCard.addSubview(sensitivityLabel)
        
        sensitivitySlider.frame = NSRect(x: 14, y: panelCardH - 228, width: 380, height: 20)
        sensitivitySlider.target = self
        sensitivitySlider.action = #selector(sensitivitySliderChanged(_:))
        panelCard.addSubview(sensitivitySlider)
        
        sensitivityValueLabel.font = AppleTheme.font(size: 12, weight: .semibold)
        sensitivityValueLabel.textColor = AppleTheme.secondaryLabel
        sensitivityValueLabel.alignment = .right
        sensitivityValueLabel.frame = NSRect(x: 400, y: panelCardH - 228, width: 64, height: 20)
        panelCard.addSubview(sensitivityValueLabel)
        
        // 4. Panel Width slider
        let pWidthLabel = NSTextField(labelWithString: "Slide Panel Width (260px - 650px):")
        pWidthLabel.font = AppleTheme.font(size: 12, weight: .medium)
        pWidthLabel.textColor = AppleTheme.label
        pWidthLabel.frame = NSRect(x: 14, y: panelCardH - 258, width: 280, height: 16)
        panelCard.addSubview(pWidthLabel)
        
        panelWidthSlider.frame = NSRect(x: 14, y: panelCardH - 282, width: 380, height: 20)
        panelWidthSlider.target = self
        panelWidthSlider.action = #selector(panelWidthSliderChanged(_:))
        panelCard.addSubview(panelWidthSlider)
        
        panelWidthValueLabel.font = AppleTheme.font(size: 12, weight: .semibold)
        panelWidthValueLabel.textColor = AppleTheme.secondaryLabel
        panelWidthValueLabel.alignment = .right
        panelWidthValueLabel.frame = NSRect(x: 400, y: panelCardH - 282, width: 64, height: 20)
        panelCard.addSubview(panelWidthValueLabel)
        
        // Pin & Test Guide buttons
        pinCheckbox.frame = NSRect(x: 14, y: 18, width: 270, height: 22)
        pinCheckbox.target = self
        pinCheckbox.action = #selector(pinCheckboxChanged(_:))
        panelCard.addSubview(pinCheckbox)
        
        guideButton.bezelStyle = .rounded
        guideButton.target = self
        guideButton.action = #selector(guideButtonClicked)
        guideButton.frame = NSRect(x: 310, y: 16, width: 155, height: 28)
        panelCard.addSubview(guideButton)
        
        currentY += panelCardH + 14
        
        // CARD 3: Appearance, Color Scheme & Typography
        let appCardH: CGFloat = 186
        let appearanceCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: appCardH))
        container.addSubview(appearanceCard)
        sectionCards.append(appearanceCard)
        
        let appearanceTitle = NSTextField(labelWithString: "Appearance, Color Scheme & Typography")
        appearanceTitle.font = AppleTheme.font(size: 13, weight: .semibold)
        appearanceTitle.textColor = AppleTheme.primary
        appearanceTitle.frame = NSRect(x: 14, y: appCardH - 30, width: 350, height: 16)
        appearanceCard.addSubview(appearanceTitle)
        self.appearanceTitleLabel = appearanceTitle
        
        // Color row
        let colorLabel = NSTextField(labelWithString: "Accent Color:")
        colorLabel.font = AppleTheme.font(size: 12, weight: .medium)
        colorLabel.textColor = AppleTheme.label
        colorLabel.frame = NSRect(x: 14, y: appCardH - 60, width: 90, height: 16)
        appearanceCard.addSubview(colorLabel)
        
        let presets = [
            (colorPresetBlue, "Blue", 1),
            (colorPresetPurple, "Purple", 2),
            (colorPresetGreen, "Green", 3),
            (colorPresetOrange, "Orange", 4),
            (colorPresetRed, "Red", 5)
        ]
        var pX: CGFloat = 105
        for (btn, title, tag) in presets {
            btn.title = title
            btn.tag = tag
            btn.bezelStyle = .rounded
            btn.font = AppleTheme.font(size: 11, weight: .medium)
            btn.target = self
            btn.action = #selector(colorPresetClicked(_:))
            btn.frame = NSRect(x: pX, y: appCardH - 64, width: 52, height: 24)
            appearanceCard.addSubview(btn)
            pX += 54
        }
        
        customColorWell.frame = NSRect(x: pX + 4, y: appCardH - 64, width: 66, height: 24)
        customColorWell.target = self
        customColorWell.action = #selector(customColorWellChanged(_:))
        customColorWell.isContinuous = true
        if #available(macOS 13.0, *) {
            customColorWell.colorWellStyle = .expanded
        }
        customColorWell.color = AppleTheme.primary
        appearanceCard.addSubview(customColorWell)
        
        // Time Font row
        let timeLabel = NSTextField(labelWithString: "Time Font:")
        timeLabel.font = AppleTheme.font(size: 12, weight: .medium)
        timeLabel.textColor = AppleTheme.label
        timeLabel.frame = NSRect(x: 14, y: appCardH - 102, width: 90, height: 16)
        appearanceCard.addSubview(timeLabel)
        
        timeFontPopup.frame = NSRect(x: 105, y: appCardH - 106, width: 230, height: 24)
        timeFontPopup.removeAllItems()
        timeFontPopup.addItems(withTitles: [
            "SF Pro Monospaced Digits (Default)",
            "SF Pro Rounded",
            "SF Pro Regular",
            "SF Mono",
            "Futura Condensed Light",
            "Alien League"
        ])
        timeFontPopup.target = self
        timeFontPopup.action = #selector(timeFontChanged(_:))
        appearanceCard.addSubview(timeFontPopup)
        
        // App Font row
        let appFontLabel = NSTextField(labelWithString: "App Font:")
        appFontLabel.font = AppleTheme.font(size: 12, weight: .medium)
        appFontLabel.textColor = AppleTheme.label
        appFontLabel.frame = NSRect(x: 14, y: appCardH - 144, width: 90, height: 16)
        appearanceCard.addSubview(appFontLabel)
        
        appFontPopup.frame = NSRect(x: 105, y: appCardH - 148, width: 230, height: 24)
        appFontPopup.removeAllItems()
        appFontPopup.addItems(withTitles: [
            "SF Pro (System Default)",
            "SF Pro Rounded",
            "SF Mono",
            "Avenir",
            "System Serif"
        ])
        appFontPopup.target = self
        appFontPopup.action = #selector(appFontChanged(_:))
        appearanceCard.addSubview(appFontPopup)
        
        currentY += appCardH + 14
        
        // CARD 4: System & Menu Bar Integration
        let sysCardH: CGFloat = 205
        let sysCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: sysCardH))
        container.addSubview(sysCard)
        sectionCards.append(sysCard)
        
        let sysTitle = NSTextField(labelWithString: "System & Menu Bar Integration")
        sysTitle.font = AppleTheme.font(size: 13, weight: .semibold)
        sysTitle.textColor = AppleTheme.primary
        sysTitle.frame = NSRect(x: 14, y: sysCardH - 30, width: 350, height: 16)
        sysCard.addSubview(sysTitle)
        self.sysTitleLabel = sysTitle
        
        menuBarTitleCheckbox.frame = NSRect(x: 14, y: sysCardH - 58, width: 420, height: 18)
        menuBarTitleCheckbox.target = self
        menuBarTitleCheckbox.action = #selector(menuBarTitleCheckboxChanged(_:))
        sysCard.addSubview(menuBarTitleCheckbox)
        
        autoPeekCheckbox.frame = NSRect(x: 14, y: sysCardH - 86, width: 440, height: 18)
        autoPeekCheckbox.target = self
        autoPeekCheckbox.action = #selector(autoPeekCheckboxChanged(_:))
        sysCard.addSubview(autoPeekCheckbox)
        
        let peekLabel = NSTextField(labelWithString: "Auto-Peek Duration:")
        peekLabel.font = AppleTheme.font(size: 12, weight: .medium)
        peekLabel.textColor = AppleTheme.secondaryLabel
        peekLabel.frame = NSRect(x: 34, y: sysCardH - 114, width: 130, height: 16)
        sysCard.addSubview(peekLabel)
        
        peekDurationSlider.frame = NSRect(x: 168, y: sysCardH - 116, width: 226, height: 20)
        peekDurationSlider.target = self
        peekDurationSlider.action = #selector(peekDurationSliderChanged(_:))
        sysCard.addSubview(peekDurationSlider)
        
        peekDurationLabel.font = AppleTheme.font(size: 12, weight: .semibold)
        peekDurationLabel.textColor = AppleTheme.secondaryLabel
        peekDurationLabel.alignment = .right
        peekDurationLabel.frame = NSRect(x: 400, y: sysCardH - 116, width: 64, height: 20)
        sysCard.addSubview(peekDurationLabel)
        
        launchAtLoginCheckbox.frame = NSRect(x: 14, y: sysCardH - 152, width: 420, height: 18)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginCheckboxChanged(_:))
        sysCard.addSubview(launchAtLoginCheckbox)
        
        currentY += sysCardH + 30
        
        container.frame.size.height = currentY
        scrollView.documentView = container
        window.contentView = scrollView
    }
    
    private func createCardView(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.backgroundColor = AppleTheme.cardBackground.cgColor
        card.layer?.cornerRadius = AppleTheme.cornerRadius
        card.layer?.borderColor = AppleTheme.cardBorder.cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.masksToBounds = true
        return card
    }
    
    private func loadInitialValues() {
        modeSegmentedControl.selectedSegment = pillController.displayMode.rawValue
        
        let reach = pillController.scanReach
        widthSlider.doubleValue = Double(reach)
        widthValueLabel.stringValue = "\(Int(reach)) px"
        
        let hVal = pillController.scanHeight
        heightSlider.doubleValue = Double(hVal)
        heightValueLabel.stringValue = "\(Int(hVal)) px"
        
        let delay = pillController.hoverDelay
        sensitivitySlider.doubleValue = delay
        sensitivityValueLabel.stringValue = delay <= 0.02 ? "Instant (0.0s)" : String(format: "%.2fs", delay)
        
        let pWidth = pillController.customPanelWidth
        panelWidthSlider.doubleValue = Double(pWidth)
        panelWidthValueLabel.stringValue = "\(Int(pWidth)) px"
        
        pinCheckbox.state = pillController.isPinned ? .on : .off
        
        calendarEnabledCheckbox.state = GoogleCalendarService.shared.isCalendarEnabled ? .on : .off
        classIdentifiersField.stringValue = UserDefaults.standard.string(forKey: "calendarClassIdentifiers") ?? "Class IEL, Alfatih, Lecture, Lab"
        calendarICalField.stringValue = GoogleCalendarService.shared.customICalURL
        
        menuBarTitleCheckbox.state = menuBarController.showUpcomingInMenuBar ? .on : .off
        autoPeekCheckbox.state = pillController.autoPeekEnabled ? .on : .off
        
        let dur = pillController.peekDuration
        peekDurationSlider.doubleValue = dur
        peekDurationLabel.stringValue = String(format: "%.1f s", dur)
        
        launchAtLoginCheckbox.state = LaunchAtLoginHelper.isEnabled ? .on : .off
        
        if !isInternalColorChange {
            customColorWell.color = AppleTheme.primary
        }
        updateAccentColors()
        
        let fontName = UserDefaults.standard.string(forKey: "plantop_time_font_name") ?? UserDefaults.standard.string(forKey: "songtop_time_font_name") ?? "SFPro"
        if fontName == "SFPro" || fontName == "MonospacedDigit" {
            timeFontPopup.selectItem(withTitle: "SF Pro Monospaced Digits (Default)")
        } else if fontName.contains("Rounded") {
            timeFontPopup.selectItem(withTitle: "SF Pro Rounded")
        } else if fontName.contains("Mono") {
            timeFontPopup.selectItem(withTitle: "SF Mono")
        } else if fontName.contains("Futura") {
            timeFontPopup.selectItem(withTitle: "Futura Condensed Light")
        } else if fontName.contains("Alien") {
            timeFontPopup.selectItem(withTitle: "Alien League")
        } else {
            timeFontPopup.selectItem(withTitle: "SF Pro Monospaced Digits (Default)")
        }
        
        let family = UserDefaults.standard.string(forKey: "plantop_app_font_family") ?? UserDefaults.standard.string(forKey: "songtop_app_font_family") ?? "System"
        if family == "System" || family == "SFPro" {
            appFontPopup.selectItem(withTitle: "SF Pro (System Default)")
        } else if family == "Rounded" {
            appFontPopup.selectItem(withTitle: "SF Pro Rounded")
        } else if family == "Monospaced" || family == "Mono" {
            appFontPopup.selectItem(withTitle: "SF Mono")
        } else if family == "Avenir" {
            appFontPopup.selectItem(withTitle: "Avenir")
        } else if family == "Serif" {
            appFontPopup.selectItem(withTitle: "System Serif")
        } else {
            appFontPopup.selectItem(withTitle: "SF Pro (System Default)")
        }
        
        updateCalendarStatusUI()
    }
    
    @objc private func onCalendarStatusUpdated() {
        DispatchQueue.main.async { [weak self] in
            self?.updateCalendarStatusUI()
        }
    }
    
    private func updateCalendarStatusUI() {
        switch GoogleCalendarService.shared.syncStatus {
        case .idle:
            if let last = GoogleCalendarService.shared.lastSyncDate {
                let df = DateFormatter()
                df.timeStyle = .short
                calendarStatusLabel.stringValue = "Last synced: \(df.string(from: last))"
            } else {
                calendarStatusLabel.stringValue = "Status: Ready"
            }
        case .syncing:
            calendarStatusLabel.stringValue = "Status: Syncing events..."
        case .synced(_, let todayCount, let tomorrowCount):
            calendarStatusLabel.stringValue = "Synced: \(todayCount) today, \(tomorrowCount) tomorrow"
        case .needsPermission:
            calendarStatusLabel.stringValue = "Status: Calendar access required"
        case .unauthorized:
            calendarStatusLabel.stringValue = "Status: Calendar access denied"
        case .error(let msg):
            calendarStatusLabel.stringValue = "Status: \(msg)"
        }
    }
    
    @objc private func modeSegmentChanged(_ sender: NSSegmentedControl) {
        if let mode = DisplayMode(rawValue: sender.selectedSegment) {
            pillController.displayMode = mode
        }
    }
    
    @objc private func widthSliderChanged(_ sender: NSSlider) {
        pillController.scanReach = CGFloat(sender.doubleValue)
        widthValueLabel.stringValue = "\(Int(sender.doubleValue)) px"
        if pillController.isGuidePinned {
            pillController.updateGuidePosition()
        }
    }
    
    @objc private func heightSliderChanged(_ sender: NSSlider) {
        pillController.scanHeight = CGFloat(sender.doubleValue)
        heightValueLabel.stringValue = "\(Int(sender.doubleValue)) px"
        if pillController.isGuidePinned {
            pillController.updateGuidePosition()
        }
    }
    
    @objc private func sensitivitySliderChanged(_ sender: NSSlider) {
        let delay = sender.doubleValue
        pillController.hoverDelay = delay
        if delay <= 0.02 {
            sensitivityValueLabel.stringValue = "Instant (0.0s)"
        } else {
            sensitivityValueLabel.stringValue = String(format: "%.2fs", delay)
        }
    }
    
    @objc private func panelWidthSliderChanged(_ sender: NSSlider) {
        pillController.customPanelWidth = CGFloat(sender.doubleValue)
        panelWidthValueLabel.stringValue = "\(Int(sender.doubleValue)) px"
    }
    
    @objc private func pinCheckboxChanged(_ sender: NSButton) {
        pillController.isPinned = (sender.state == .on)
    }
    
    @objc private func guideButtonClicked() {
        if pillController.isGuidePinned {
            pillController.hideGuide()
            guideButton.title = "Highlight Right Zone"
        } else {
            pillController.showGuide(pinned: true)
            guideButton.title = "Hide Highlight"
        }
    }
    
    @objc private func calendarEnabledChanged(_ sender: NSButton) {
        GoogleCalendarService.shared.isCalendarEnabled = (sender.state == .on)
    }
    
    @objc private func classIdentifiersChanged(_ sender: NSTextField) {
        UserDefaults.standard.set(sender.stringValue, forKey: "calendarClassIdentifiers")
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
        GoogleCalendarService.shared.syncNow()
    }
    
    @objc private func calendarICalChanged(_ sender: NSTextField) {
        GoogleCalendarService.shared.customICalURL = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @objc private func syncCalendarNowClicked() {
        GoogleCalendarService.shared.syncNow()
    }
    
    @objc private func openCalendarAccountsClicked() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func updateAccentColors() {
        let p = AppleTheme.primary
        headerIconView?.contentTintColor = p
        calTitleLabel?.textColor = p
        panelTitleLabel?.textColor = p
        appearanceTitleLabel?.textColor = p
        sysTitleLabel?.textColor = p
    }
    
    @objc private func colorPresetClicked(_ sender: NSButton) {
        let hex: String
        switch sender.tag {
        case 1: hex = "#007AFF" // System Blue
        case 2: hex = "#AF52DE" // System Purple
        case 3: hex = "#34C759" // System Green
        case 4: hex = "#FF9500" // System Orange
        case 5: hex = "#FF3B30" // System Red
        default: hex = "#007AFF"
        }
        UserDefaults.standard.set(hex, forKey: "plantop_accent_color_hex")
        UserDefaults.standard.set(hex, forKey: "songtop_accent_color_hex")
        UserDefaults.standard.synchronize()
        isInternalColorChange = true
        customColorWell.color = AppleTheme.primary
        NSColorPanel.shared.color = AppleTheme.primary
        updateAccentColors()
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
        isInternalColorChange = false
    }
    
    @objc private func customColorWellChanged(_ sender: NSColorWell) {
        guard !isInternalColorChange else { return }
        let selectedColor = sender.color
        let hex = AppleTheme.hexString(from: selectedColor)
        UserDefaults.standard.set(hex, forKey: "plantop_accent_color_hex")
        UserDefaults.standard.set(hex, forKey: "songtop_accent_color_hex")
        UserDefaults.standard.synchronize()
        isInternalColorChange = true
        NSColorPanel.shared.color = selectedColor
        updateAccentColors()
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
        isInternalColorChange = false
    }
    
    @objc private func timeFontChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let fontName: String
        switch title {
        case "SF Pro Monospaced Digits (Default)": fontName = "SFPro"
        case "SF Pro Rounded": fontName = "SFProRounded"
        case "SF Pro Regular": fontName = "SFProRegular"
        case "SF Mono": fontName = "SFMono"
        case "Futura Condensed Light": fontName = "Futura-CondensedLight"
        case "Alien League": fontName = "AlienLeagueCondensed"
        default: fontName = "SFPro"
        }
        UserDefaults.standard.set(fontName, forKey: "plantop_time_font_name")
        UserDefaults.standard.set(fontName, forKey: "songtop_time_font_name")
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
    }
    
    @objc private func appFontChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let family: String
        switch title {
        case "SF Pro (System Default)": family = "System"
        case "SF Pro Rounded": family = "Rounded"
        case "SF Mono": family = "Monospaced"
        case "Avenir": family = "Avenir"
        case "System Serif": family = "Serif"
        default: family = "System"
        }
        UserDefaults.standard.set(family, forKey: "plantop_app_font_family")
        UserDefaults.standard.set(family, forKey: "songtop_app_font_family")
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
    }
    
    @objc private func menuBarTitleCheckboxChanged(_ sender: NSButton) {
        menuBarController.showUpcomingInMenuBar = (sender.state == .on)
    }
    
    @objc private func autoPeekCheckboxChanged(_ sender: NSButton) {
        pillController.autoPeekEnabled = (sender.state == .on)
    }
    
    @objc private func peekDurationSliderChanged(_ sender: NSSlider) {
        let val = sender.doubleValue
        pillController.peekDuration = val
        peekDurationLabel.stringValue = String(format: "%.1f s", val)
    }
    
    @objc private func launchAtLoginCheckboxChanged(_ sender: NSButton) {
        LaunchAtLoginHelper.setEnabled(sender.state == .on)
    }
}
