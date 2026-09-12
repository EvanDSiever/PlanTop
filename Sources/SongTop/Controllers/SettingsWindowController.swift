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
    private let modeSegmentedControl = NSSegmentedControl(labels: ["Hover Dropdown", "Always Floating", "Menu Bar Only"], trackingMode: .selectOne, target: nil, action: nil)
    
    // Hover Controls
    private let widthSlider = NSSlider(value: 750, minValue: 300, maxValue: 1400, target: nil, action: nil)
    private let widthValueLabel = NSTextField(labelWithString: "750 px")
    private let heightSlider = NSSlider(value: 70, minValue: 30, maxValue: 120, target: nil, action: nil)
    private let heightValueLabel = NSTextField(labelWithString: "70 px")
    
    // Auto Peek Controls
    private let autoPeekCheckbox = NSButton(checkboxWithTitle: "Automatically drop down when a new song starts", target: nil, action: nil)
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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        loadInitialValues()
        updateLiveStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
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
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 680))
        scrollView.documentView = container
        
        var currentY: CGFloat = 660
        
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
        
        let appSubtitle = NSTextField(labelWithString: "YouTube Now Playing for macOS • Settings & Customizer")
        appSubtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        appSubtitle.textColor = .secondaryLabelColor
        appSubtitle.frame = NSRect(x: 82, y: currentY - 48, width: 380, height: 16)
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
        
        let testBtn = NSButton(title: "Test Dropdown", target: self, action: #selector(testDropdownClicked))
        testBtn.bezelStyle = .rounded
        testBtn.frame = NSRect(x: 350, y: 22, width: 116, height: 28)
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
        
        // 4. Hover Sensitivity Card
        let hoverCard = createCardView(frame: NSRect(x: 20, y: currentY - 145, width: 480, height: 138))
        container.addSubview(hoverCard)
        
        let hoverTitle = NSTextField(labelWithString: "Top-Screen Hover Sensitivity & Area")
        hoverTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        hoverTitle.frame = NSRect(x: 14, y: 112, width: 300, height: 16)
        hoverCard.addSubview(hoverTitle)
        
        // Width Slider
        let wLabel = NSTextField(labelWithString: "Scan Width:")
        wLabel.font = NSFont.systemFont(ofSize: 11)
        wLabel.frame = NSRect(x: 14, y: 80, width: 80, height: 16)
        hoverCard.addSubview(wLabel)
        
        widthSlider.frame = NSRect(x: 95, y: 78, width: 300, height: 20)
        widthSlider.target = self
        widthSlider.action = #selector(widthSliderChanged)
        hoverCard.addSubview(widthSlider)
        
        widthValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        widthValueLabel.alignment = .right
        widthValueLabel.frame = NSRect(x: 400, y: 80, width: 65, height: 16)
        hoverCard.addSubview(widthValueLabel)
        
        // Height Slider
        let hLabel = NSTextField(labelWithString: "Scan Height:")
        hLabel.font = NSFont.systemFont(ofSize: 11)
        hLabel.frame = NSRect(x: 14, y: 44, width: 80, height: 16)
        hoverCard.addSubview(hLabel)
        
        heightSlider.frame = NSRect(x: 95, y: 42, width: 300, height: 20)
        heightSlider.target = self
        heightSlider.action = #selector(heightSliderChanged)
        hoverCard.addSubview(heightSlider)
        
        heightValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        heightValueLabel.alignment = .right
        heightValueLabel.frame = NSRect(x: 400, y: 44, width: 65, height: 16)
        hoverCard.addSubview(heightValueLabel)
        
        let hoverDesc = NSTextField(labelWithString: "Move your mouse to the top center of your display to trigger the dropdown.")
        hoverDesc.font = NSFont.systemFont(ofSize: 10)
        hoverDesc.textColor = .secondaryLabelColor
        hoverDesc.frame = NSRect(x: 14, y: 14, width: 450, height: 16)
        hoverCard.addSubview(hoverDesc)
        
        currentY -= 160
        
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
        
        peekDurationSlider.frame = NSRect(x: 105, y: 12, width: 290, height: 20)
        peekDurationSlider.target = self
        peekDurationSlider.action = #selector(peekDurationChanged)
        peekCard.addSubview(peekDurationSlider)
        
        peekDurationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        peekDurationLabel.alignment = .right
        peekDurationLabel.frame = NSRect(x: 400, y: 14, width: 65, height: 16)
        peekCard.addSubview(peekDurationLabel)
        
        currentY -= 115
        
        // 6. Menu Bar Options Card
        let menuCard = createCardView(frame: NSRect(x: 20, y: currentY - 60, width: 480, height: 54))
        container.addSubview(menuCard)
        
        menuBarTitleCheckbox.frame = NSRect(x: 14, y: 18, width: 450, height: 18)
        menuBarTitleCheckbox.target = self
        menuBarTitleCheckbox.action = #selector(menuBarTitleToggled)
        menuCard.addSubview(menuBarTitleCheckbox)
        
        currentY -= 75
        
        // 7. Browser Status Card
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
    
    private func updateBrowserBadges() {
        browsersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let runningNames = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName })
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
        if !pillController.isEnabled {
            modeSegmentedControl.selectedSegment = 2
        } else if !pillController.hoverDropOnly {
            modeSegmentedControl.selectedSegment = 1
        } else {
            modeSegmentedControl.selectedSegment = 0
        }
        
        widthSlider.doubleValue = Double(pillController.scanWidth)
        widthValueLabel.stringValue = "\(Int(pillController.scanWidth)) px"
        
        heightSlider.doubleValue = Double(pillController.scanHeight)
        heightValueLabel.stringValue = "\(Int(pillController.scanHeight)) px"
        
        autoPeekCheckbox.state = pillController.autoPeekEnabled ? .on : .off
        peekDurationSlider.doubleValue = pillController.peekDuration
        peekDurationLabel.stringValue = String(format: "%.1f s", pillController.peekDuration)
        
        menuBarTitleCheckbox.state = UserDefaults.standard.bool(forKey: "showTitleInMenuBar") ? .on : .off
    }
    
    @objc private func testDropdownClicked() {
        pillController.peek(duration: pillController.peekDuration)
    }
    
    @objc private func modeChanged() {
        switch modeSegmentedControl.selectedSegment {
        case 0:
            pillController.isEnabled = true
            pillController.hoverDropOnly = true
        case 1:
            pillController.isEnabled = true
            pillController.hoverDropOnly = false
        case 2:
            pillController.isEnabled = false
        default:
            break
        }
        menuBarController.update(track: detector.currentTrack)
    }
    
    @objc private func widthSliderChanged() {
        let val = widthSlider.doubleValue
        pillController.scanWidth = CGFloat(val)
        widthValueLabel.stringValue = "\(Int(val)) px"
    }
    
    @objc private func heightSliderChanged() {
        let val = heightSlider.doubleValue
        pillController.scanHeight = CGFloat(val)
        heightValueLabel.stringValue = "\(Int(val)) px"
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
        let show = (menuBarTitleCheckbox.state == .on)
        UserDefaults.standard.set(show, forKey: "showTitleInMenuBar")
        menuBarController.update(track: detector.currentTrack)
    }
}
