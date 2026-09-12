import AppKit
import Foundation

public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var detector: YouTubeDetector
    private var pillController: FloatingPillWindowController
    
    public var showTitleInMenuBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showTitleInMenuBar, forKey: "showTitleInMenuBar")
            updateDisplay()
        }
    }
    
    public var onOpenSettings: (() -> Void)?
    
    public init(detector: YouTubeDetector, pillController: FloatingPillWindowController) {
        self.detector = detector
        self.pillController = pillController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        
        if UserDefaults.standard.object(forKey: "showTitleInMenuBar") != nil {
            self.showTitleInMenuBar = UserDefaults.standard.bool(forKey: "showTitleInMenuBar")
        }
        
        setupMenu()
        updateDisplay()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSettingsChanged),
            name: .songTopSettingsChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func onSettingsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if UserDefaults.standard.object(forKey: "showTitleInMenuBar") != nil {
                let saved = UserDefaults.standard.bool(forKey: "showTitleInMenuBar")
                if self.showTitleInMenuBar != saved {
                    self.showTitleInMenuBar = saved
                }
            }
            self.updateDisplay()
            self.buildMenu(track: self.detector.currentTrack)
        }
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        buildMenu(track: detector.currentTrack)
    }
    
    public func update(track: TrackInfo?) {
        updateDisplay()
        buildMenu(track: track)
    }
    
    private func updateDisplay() {
        guard let button = statusItem.button else { return }
        
        if let track = detector.currentTrack {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let icon = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "YouTube Playing")?
                .withSymbolConfiguration(symbolConfig)
            button.image = icon
            button.imagePosition = .imageLeft
            
            if showTitleInMenuBar {
                let display = track.title
                let truncated = display.count > 28 ? String(display.prefix(28)) + "…" : display
                button.title = " \(truncated)"
            } else {
                button.title = ""
            }
        } else {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let icon = NSImage(systemSymbolName: "music.note", accessibilityDescription: "SongTop Idle")?
                .withSymbolConfiguration(symbolConfig)
            button.image = icon
            button.imagePosition = .imageLeft
            button.title = ""
        }
    }
    
    private func setupMenu() {
        buildMenu(track: detector.currentTrack)
    }
    
    private func buildMenu(track: TrackInfo?) {
        let menu = NSMenu()
        menu.delegate = self
        
        if let track = track {
            // Track Title
            let titleItem = NSMenuItem(title: track.title, action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(
                string: track.title,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 13)
                ]
            )
            menu.addItem(titleItem)
            
            // Artist / Source
            let sourceDesc = track.artist.isEmpty
                ? "\(track.browser) • YouTube"
                : "\(track.artist)  (\(track.browser))"
            let artistItem = NSMenuItem(title: sourceDesc, action: nil, keyEquivalent: "")
            artistItem.attributedTitle = NSAttributedString(
                string: sourceDesc,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(artistItem)
            menu.addItem(NSMenuItem.separator())
            
            // Open Tab
            let openItem = NSMenuItem(title: "Open in \(track.browser)", action: #selector(openTabClicked), keyEquivalent: "o")
            openItem.target = self
            openItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            menu.addItem(openItem)
            
            // Play / Pause
            let playPauseItem = NSMenuItem(title: "Play / Pause", action: #selector(playPauseClicked), keyEquivalent: "p")
            playPauseItem.target = self
            playPauseItem.image = NSImage(systemSymbolName: "playpause.fill", accessibilityDescription: nil)
            menu.addItem(playPauseItem)
            
            // Next Track
            let nextItem = NSMenuItem(title: "Next Track", action: #selector(nextTrackClicked), keyEquivalent: "n")
            nextItem.target = self
            nextItem.image = NSImage(systemSymbolName: "forward.end.fill", accessibilityDescription: nil)
            menu.addItem(nextItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // Copy Title
            let copyTitleItem = NSMenuItem(title: "Copy Song Title", action: #selector(copyTitleClicked), keyEquivalent: "c")
            copyTitleItem.target = self
            copyTitleItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copyTitleItem)
            
            // Copy URL
            let copyUrlItem = NSMenuItem(title: "Copy YouTube Link", action: #selector(copyUrlClicked), keyEquivalent: "l")
            copyUrlItem.target = self
            copyUrlItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
            menu.addItem(copyUrlItem)
        } else {
            let noMusicItem = NSMenuItem(title: "No YouTube Audio Playing", action: nil, keyEquivalent: "")
            noMusicItem.attributedTitle = NSAttributedString(
                string: "No YouTube Audio Playing",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(noMusicItem)
            
            let tipItem = NSMenuItem(title: "Play a song in Chrome, Safari, Brave, or Arc", action: nil, keyEquivalent: "")
            tipItem.attributedTitle = NSAttributedString(
                string: "Play a song in Chrome, Safari, Brave, Arc, or Edge",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            )
            menu.addItem(tipItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Audio / Video Lip-Sync Calibration Submenu
        let syncSubmenu = NSMenu()
        var currentMs = UserDefaults.standard.object(forKey: "songtop_av_sync_delay_ms") != nil
            ? UserDefaults.standard.double(forKey: "songtop_av_sync_delay_ms")
            : 0.0
        if currentMs == 250.0 {
            currentMs = 0.0
            UserDefaults.standard.set(0.0, forKey: "songtop_av_sync_delay_ms")
        }
        let formattedCur = currentMs > 0 ? "+\(Int(currentMs)) ms" : "\(Int(currentMs)) ms"
        
        let currentItem = NSMenuItem(title: "Active Calibration: \(formattedCur)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        syncSubmenu.addItem(currentItem)
        syncSubmenu.addItem(NSMenuItem.separator())
        
        let presets: [(label: String, value: Double)] = [
            ("-250 ms (Ideal / Advance Video)", -250),
            ("-120 ms (Fast Audio)", -120),
            ("-80 ms (Video Lags)", -80),
            ("0 ms (Exact Match)", 0),
            ("+80 ms (Video Leads)", 80),
            ("+180 ms (Bluetooth Audio)", 180)
        ]
        
        for p in presets {
            let item = NSMenuItem(title: p.label, action: #selector(menuBarSyncPresetSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.value
            if abs(currentMs - p.value) < 5 {
                item.state = .on
            }
            syncSubmenu.addItem(item)
        }
        
        syncSubmenu.addItem(NSMenuItem.separator())
        let calibrateItem = NSMenuItem(title: "Fine-Tune in Settings...", action: #selector(openSettingsClicked), keyEquivalent: "")
        calibrateItem.target = self
        syncSubmenu.addItem(calibrateItem)
        
        let syncMenuItem = NSMenuItem(title: "Lip-Sync Calibration (\(formattedCur))", action: nil, keyEquivalent: "")
        syncMenuItem.submenu = syncSubmenu
        syncMenuItem.image = NSImage(systemSymbolName: "slider.horizontal.below.rectangle", accessibilityDescription: nil)
        menu.addItem(syncMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings / Preferences
        let dropDownItem = NSMenuItem(
            title: "Slide Out on Right Edge Hover",
            action: #selector(setHoverDropDownMode),
            keyEquivalent: ""
        )
        dropDownItem.target = self
        dropDownItem.state = (pillController.displayMode == .hoverDropdown) ? .on : .off
        menu.addItem(dropDownItem)
        
        let alwaysVisibleItem = NSMenuItem(
            title: "Always Keep Side Panel Visible",
            action: #selector(setAlwaysVisibleMode),
            keyEquivalent: ""
        )
        alwaysVisibleItem.target = self
        alwaysVisibleItem.state = (pillController.displayMode == .alwaysFloating) ? .on : .off
        menu.addItem(alwaysVisibleItem)
        
        let disablePillItem = NSMenuItem(
            title: "Hide Side Panel (Menu Bar Only)",
            action: #selector(setDisabledMode),
            keyEquivalent: ""
        )
        disablePillItem.target = self
        disablePillItem.state = (pillController.displayMode == .menuBarOnly) ? .on : .off
        menu.addItem(disablePillItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Pin Side Panel
        let pinItem = NSMenuItem(
            title: "Pin Side Panel on Screen",
            action: #selector(togglePinClicked),
            keyEquivalent: "k"
        )
        pinItem.target = self
        pinItem.image = NSImage(systemSymbolName: pillController.isPinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinItem.state = pillController.isPinned ? .on : .off
        menu.addItem(pinItem)
        
        let toggleTitleItem = NSMenuItem(
            title: "Show Song Name in Menu Bar",
            action: #selector(toggleShowTitle),
            keyEquivalent: ""
        )
        toggleTitleItem.target = self
        toggleTitleItem.state = showTitleInMenuBar ? .on : .off
        menu.addItem(toggleTitleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Trigger Slide Out Preview
        let testItem = NSMenuItem(title: "Trigger Side Panel Preview", action: #selector(testDropDownClicked), keyEquivalent: "t")
        testItem.target = self
        testItem.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
        menu.addItem(testItem)
        
        // Refresh Now
        let refreshItem = NSMenuItem(title: "Check Now", action: #selector(checkNowClicked), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refreshItem)
        
        // Settings & Customization
        let settingsItem = NSMenuItem(title: "Settings & Customization...", action: #selector(openSettingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit SongTop", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func togglePinClicked() {
        pillController.togglePin()
        buildMenu(track: detector.currentTrack)
    }
    
    @objc private func openTabClicked() {
        if let track = detector.currentTrack {
            detector.focusTab(track: track)
        }
    }
    
    @objc private func playPauseClicked() {
        pillController.togglePlayPause()
    }
    
    @objc private func nextTrackClicked() {
        if let track = detector.currentTrack {
            detector.nextTrack(track: track)
        }
    }
    
    @objc private func copyTitleClicked() {
        if let track = detector.currentTrack {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(track.displayTitle, forType: .string)
        }
    }
    
    @objc private func copyUrlClicked() {
        if let track = detector.currentTrack {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(track.url, forType: .string)
        }
    }
    
    @objc private func setHoverDropDownMode() {
        pillController.displayMode = .hoverDropdown
        buildMenu(track: detector.currentTrack)
    }
    
    @objc private func setAlwaysVisibleMode() {
        pillController.displayMode = .alwaysFloating
        buildMenu(track: detector.currentTrack)
    }
    
    @objc private func setDisabledMode() {
        pillController.displayMode = .menuBarOnly
        buildMenu(track: detector.currentTrack)
    }
    
    
    @objc private func toggleShowTitle() {
        showTitleInMenuBar.toggle()
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
        buildMenu(track: detector.currentTrack)
    }
    
    @objc private func testDropDownClicked() {
        pillController.peek(duration: 5.0)
    }
    
    @objc private func checkNowClicked() {
        detector.checkNow()
    }
    
    @objc private func openSettingsClicked() {
        onOpenSettings?()
    }
    
    @objc private func menuBarSyncPresetSelected(_ sender: NSMenuItem) {
        guard let ms = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(ms, forKey: "songtop_av_sync_delay_ms")
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
    }
    
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}
