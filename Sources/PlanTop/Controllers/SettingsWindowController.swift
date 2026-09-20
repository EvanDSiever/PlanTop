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
    private var headerIconView: NSView?
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
        DispatchQueue.main.async { [weak self] in
            self?.loadInitialValues()
        }
    }
    
    public func show() {
        window?.appearance = NSAppearance(named: .aqua)
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
        container.layer?.backgroundColor = NSColor(red: 0.965, green: 0.973, blue: 0.985, alpha: 1.0).cgColor
        self.settingsContainer = container
        
        var currentY: CGFloat = 24
        
        // 1. Header Banner
        let iconView = NSImageView(frame: NSRect(x: 20, y: currentY, width: 46, height: 46))
        let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        iconView.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "PlanTop")?.withSymbolConfiguration(config)
        iconView.contentTintColor = NeumorphicTheme.accentColor
        container.addSubview(iconView)
        self.headerIconView = iconView
        
        let appTitle = NSTextField(labelWithString: "PlanTop Daily Planner")
        appTitle.font = NSFont.systemFont(ofSize: 19, weight: .bold)
        appTitle.textColor = .labelColor
        appTitle.frame = NSRect(x: 78, y: currentY + 2, width: 380, height: 24)
        container.addSubview(appTitle)
        self.headerTitleLabel = appTitle
        
        let appSubtitle = NSTextField(labelWithString: "Stealth macOS Side-Panel Companion & Calendar Activity Hub")
        appSubtitle.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        appSubtitle.textColor = .secondaryLabelColor
        appSubtitle.frame = NSRect(x: 78, y: currentY + 26, width: 420, height: 16)
        container.addSubview(appSubtitle)
        self.headerSubtitleLabel = appSubtitle
        
        currentY += 60
        
        // CARD 1: Google Calendar & Daily Planner Integration
        let calCardH: CGFloat = 260
        let calCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: calCardH))
        container.addSubview(calCard)
        sectionCards.append(calCard)
        
        let calTitle = NSTextField(labelWithString: "Daily Planner & Google Calendar Integration")
        calTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        calTitle.textColor = NeumorphicTheme.accentColor
        calTitle.frame = NSRect(x: 14, y: calCardH - 30, width: 400, height: 16)
        calCard.addSubview(calTitle)
        
        calendarEnabledCheckbox.frame = NSRect(x: 14, y: calCardH - 58, width: 400, height: 18)
        calendarEnabledCheckbox.target = self
        calendarEnabledCheckbox.action = #selector(calendarEnabledChanged(_:))
        calCard.addSubview(calendarEnabledCheckbox)
        
        // Class Detectors
        let classLabel = NSTextField(labelWithString: "Class Detectors (Keywords separated by commas):")
        classLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        classLabel.textColor = NeumorphicTheme.textPrimary
        classLabel.frame = NSRect(x: 14, y: calCardH - 90, width: 420, height: 16)
        calCard.addSubview(classLabel)
        
        classIdentifiersField.frame = NSRect(x: 14, y: calCardH - 116, width: 450, height: 22)
        classIdentifiersField.placeholderString = "Class IEL, Alfatih, Lecture, Lab, Seminar"
        classIdentifiersField.target = self
        classIdentifiersField.action = #selector(classIdentifiersChanged(_:))
        calCard.addSubview(classIdentifiersField)
        
        // iCal subscription URL
        let iCalLabel = NSTextField(labelWithString: "Custom Google Calendar iCal URL (Secret Address in iCal format):")
        iCalLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        iCalLabel.textColor = NeumorphicTheme.textPrimary
        iCalLabel.frame = NSRect(x: 14, y: calCardH - 148, width: 450, height: 16)
        calCard.addSubview(iCalLabel)
        
        calendarICalField.frame = NSRect(x: 14, y: calCardH - 174, width: 450, height: 22)
        calendarICalField.placeholderString = "https://calendar.google.com/calendar/ical/.../basic.ics"
        calendarICalField.target = self
        calendarICalField.action = #selector(calendarICalChanged(_:))
        calCard.addSubview(calendarICalField)
        
        // Sync status and actions
        calendarStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        calendarStatusLabel.textColor = .secondaryLabelColor
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
        let panelCardH: CGFloat = 260
        let panelCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: panelCardH))
        container.addSubview(panelCard)
        sectionCards.append(panelCard)
        
        let panelTitle = NSTextField(labelWithString: "Right-Edge Slide Panel & Display Mode")
        panelTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        panelTitle.textColor = NeumorphicTheme.accentColor
        panelTitle.frame = NSRect(x: 14, y: panelCardH - 30, width: 400, height: 16)
        panelCard.addSubview(panelTitle)
        
        modeSegmentedControl.frame = NSRect(x: 14, y: panelCardH - 62, width: 450, height: 24)
        modeSegmentedControl.target = self
        modeSegmentedControl.action = #selector(modeSegmentChanged(_:))
        panelCard.addSubview(modeSegmentedControl)
        
        // Reach slider
        let reachLabel = NSTextField(labelWithString: "Hover Scan Reach (px from right bezel):")
        reachLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        reachLabel.textColor = NeumorphicTheme.textPrimary
        reachLabel.frame = NSRect(x: 14, y: panelCardH - 96, width: 280, height: 16)
        panelCard.addSubview(reachLabel)
        
        widthSlider.frame = NSRect(x: 14, y: panelCardH - 120, width: 380, height: 20)
        widthSlider.target = self
        widthSlider.action = #selector(widthSliderChanged(_:))
        panelCard.addSubview(widthSlider)
        
        widthValueLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        widthValueLabel.alignment = .right
        widthValueLabel.frame = NSRect(x: 400, y: panelCardH - 120, width: 64, height: 20)
        panelCard.addSubview(widthValueLabel)
        
        // Panel Width slider
        let pWidthLabel = NSTextField(labelWithString: "Slide Panel Width (260px - 650px):")
        pWidthLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        pWidthLabel.textColor = NeumorphicTheme.textPrimary
        pWidthLabel.frame = NSRect(x: 14, y: panelCardH - 150, width: 280, height: 16)
        panelCard.addSubview(pWidthLabel)
        
        panelWidthSlider.frame = NSRect(x: 14, y: panelCardH - 174, width: 380, height: 20)
        panelWidthSlider.target = self
        panelWidthSlider.action = #selector(panelWidthSliderChanged(_:))
        panelCard.addSubview(panelWidthSlider)
        
        panelWidthValueLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        panelWidthValueLabel.alignment = .right
        panelWidthValueLabel.frame = NSRect(x: 400, y: panelCardH - 174, width: 64, height: 20)
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
        appearanceTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        appearanceTitle.textColor = NeumorphicTheme.accentColor
        appearanceTitle.frame = NSRect(x: 14, y: appCardH - 30, width: 350, height: 16)
        appearanceCard.addSubview(appearanceTitle)
        
        // Color row
        let colorLabel = NSTextField(labelWithString: "Accent Color:")
        colorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        colorLabel.textColor = NeumorphicTheme.textPrimary
        colorLabel.frame = NSRect(x: 14, y: appCardH - 60, width: 90, height: 16)
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
            btn.frame = NSRect(x: pX, y: appCardH - 64, width: 52, height: 24)
            appearanceCard.addSubview(btn)
            pX += 54
        }
        
        customColorWell.frame = NSRect(x: pX + 4, y: appCardH - 64, width: 66, height: 24)
        customColorWell.target = self
        customColorWell.action = #selector(customColorWellChanged(_:))
        appearanceCard.addSubview(customColorWell)
        
        // Time Font row
        let timeLabel = NSTextField(labelWithString: "Time Font:")
        timeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = NeumorphicTheme.textPrimary
        timeLabel.frame = NSRect(x: 14, y: appCardH - 102, width: 90, height: 16)
        appearanceCard.addSubview(timeLabel)
        
        timeFontPopup.frame = NSRect(x: 105, y: appCardH - 106, width: 230, height: 24)
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
        
        // App Font row
        let appFontLabel = NSTextField(labelWithString: "App Font:")
        appFontLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        appFontLabel.textColor = NeumorphicTheme.textPrimary
        appFontLabel.frame = NSRect(x: 14, y: appCardH - 144, width: 90, height: 16)
        appearanceCard.addSubview(appFontLabel)
        
        appFontPopup.frame = NSRect(x: 105, y: appCardH - 148, width: 230, height: 24)
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
        
        currentY += appCardH + 14
        
        // CARD 4: System & Menu Bar Integration
        let sysCardH: CGFloat = 160
        let sysCard = createCardView(frame: NSRect(x: 20, y: currentY, width: 480, height: sysCardH))
        container.addSubview(sysCard)
        sectionCards.append(sysCard)
        
        let sysTitle = NSTextField(labelWithString: "System & Menu Bar Integration")
        sysTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        sysTitle.textColor = NeumorphicTheme.accentColor
        sysTitle.frame = NSRect(x: 14, y: sysCardH - 30, width: 350, height: 16)
        sysCard.addSubview(sysTitle)
        
        menuBarTitleCheckbox.frame = NSRect(x: 14, y: sysCardH - 60, width: 420, height: 18)
        menuBarTitleCheckbox.target = self
        menuBarTitleCheckbox.action = #selector(menuBarTitleCheckboxChanged(_:))
        sysCard.addSubview(menuBarTitleCheckbox)
        
        autoPeekCheckbox.frame = NSRect(x: 14, y: sysCardH - 90, width: 440, height: 18)
        autoPeekCheckbox.target = self
        autoPeekCheckbox.action = #selector(autoPeekCheckboxChanged(_:))
        sysCard.addSubview(autoPeekCheckbox)
        
        launchAtLoginCheckbox.frame = NSRect(x: 14, y: sysCardH - 120, width: 420, height: 18)
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
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 14
        card.layer?.borderColor = NeumorphicTheme.panelBorderOutline.cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.masksToBounds = true
        return card
    }
    
    private func loadInitialValues() {
        modeSegmentedControl.selectedSegment = pillController.displayMode.rawValue
        
        let reach = pillController.scanReach
        widthSlider.doubleValue = Double(reach)
        widthValueLabel.stringValue = "\(Int(reach)) px"
        
        let pWidth = pillController.customPanelWidth
        panelWidthSlider.doubleValue = Double(pWidth)
        panelWidthValueLabel.stringValue = "\(Int(pWidth)) px"
        
        pinCheckbox.state = pillController.isPinned ? .on : .off
        
        calendarEnabledCheckbox.state = GoogleCalendarService.shared.isCalendarEnabled ? .on : .off
        classIdentifiersField.stringValue = UserDefaults.standard.string(forKey: "calendarClassIdentifiers") ?? "Class IEL, Alfatih, Lecture, Lab"
        calendarICalField.stringValue = GoogleCalendarService.shared.customICalURL
        
        menuBarTitleCheckbox.state = menuBarController.showUpcomingInMenuBar ? .on : .off
        autoPeekCheckbox.state = pillController.autoPeekEnabled ? .on : .off
        launchAtLoginCheckbox.state = LaunchAtLoginHelper.isEnabled ? .on : .off
        
        customColorWell.color = NeumorphicTheme.accentColor
        
        let fontName = UserDefaults.standard.string(forKey: "plantop_time_font_name") ?? UserDefaults.standard.string(forKey: "songtop_time_font_name") ?? "AlienLeagueCondensed"
        if fontName == "AlienLeagueCondensed" {
            timeFontPopup.selectItem(withTitle: "Alien League Condensed")
        } else if fontName == "AlienLeague" {
            timeFontPopup.selectItem(withTitle: "Alien League Regular")
        } else if fontName == "Futura-CondensedLight" {
            timeFontPopup.selectItem(withTitle: "Futura Condensed Light")
        } else if fontName.contains("SFPro") {
            timeFontPopup.selectItem(withTitle: "SF Pro Rounded Light")
        } else {
            timeFontPopup.selectItem(withTitle: "Alien League Condensed")
        }
        
        let family = UserDefaults.standard.string(forKey: "plantop_app_font_family") ?? UserDefaults.standard.string(forKey: "songtop_app_font_family") ?? "Rounded"
        if family == "System" {
            appFontPopup.selectItem(withTitle: "System Default")
        } else if family == "Monospaced" {
            appFontPopup.selectItem(withTitle: "Monospaced")
        } else if family == "Serif" {
            appFontPopup.selectItem(withTitle: "Serif")
        } else {
            appFontPopup.selectItem(withTitle: "SF Pro Rounded (Default)")
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
    
    @objc private func colorPresetClicked(_ sender: NSButton) {
        let hex: String
        switch sender.tag {
        case 1: hex = "#FF700D" // Vibrant Orange
        case 2: hex = "#FF6B6B" // Coral
        case 3: hex = "#2563EB" // Blue
        case 4: hex = "#059669" // Green
        case 5: hex = "#7C3AED" // Purple
        default: hex = "#FF700D"
        }
        UserDefaults.standard.set(hex, forKey: "plantop_accent_color_hex")
        UserDefaults.standard.set(hex, forKey: "songtop_accent_color_hex")
        customColorWell.color = NeumorphicTheme.accentColor
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
    }
    
    @objc private func customColorWellChanged(_ sender: NSColorWell) {
        let hex = NeumorphicTheme.hexString(from: sender.color)
        UserDefaults.standard.set(hex, forKey: "plantop_accent_color_hex")
        UserDefaults.standard.set(hex, forKey: "songtop_accent_color_hex")
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
    }
    
    @objc private func timeFontChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let fontName: String
        switch title {
        case "Alien League Condensed": fontName = "AlienLeagueCondensed"
        case "Alien League Regular": fontName = "AlienLeague"
        case "Futura Condensed Light": fontName = "Futura-CondensedLight"
        case "SF Pro Rounded Light": fontName = "SFProRounded-Light"
        default: fontName = "AlienLeagueCondensed"
        }
        UserDefaults.standard.set(fontName, forKey: "plantop_time_font_name")
        UserDefaults.standard.set(fontName, forKey: "songtop_time_font_name")
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
    }
    
    @objc private func appFontChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let family: String
        switch title {
        case "System Default": family = "System"
        case "Monospaced": family = "Monospaced"
        case "Serif": family = "Serif"
        default: family = "Rounded"
        }
        UserDefaults.standard.set(family, forKey: "plantop_app_font_family")
        UserDefaults.standard.set(family, forKey: "songtop_app_font_family")
        NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
    }
    
    @objc private func menuBarTitleCheckboxChanged(_ sender: NSButton) {
        menuBarController.showUpcomingInMenuBar = (sender.state == .on)
    }
    
    @objc private func autoPeekCheckboxChanged(_ sender: NSButton) {
        pillController.autoPeekEnabled = (sender.state == .on)
    }
    
    @objc private func launchAtLoginCheckboxChanged(_ sender: NSButton) {
        LaunchAtLoginHelper.setEnabled(sender.state == .on)
    }
}
