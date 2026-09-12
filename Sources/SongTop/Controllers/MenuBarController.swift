import AppKit
import Foundation

public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var detector: YouTubeDetector
    private var pillController: FloatingPillWindowController
    
    private var showTitleInMenuBar: Bool = true {
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
        
        // Settings / Preferences
        let dropDownItem = NSMenuItem(
            title: "Drop Down on Top Hover",
            action: #selector(setHoverDropDownMode),
            keyEquivalent: ""
        )
        dropDownItem.target = self
        dropDownItem.state = (pillController.isEnabled && pillController.hoverDropOnly) ? .on : .off
        menu.addItem(dropDownItem)
        
        let alwaysVisibleItem = NSMenuItem(
            title: "Always Keep Top Banner Visible",
            action: #selector(setAlwaysVisibleMode),
            keyEquivalent: ""
        )
        alwaysVisibleItem.target = self
        alwaysVisibleItem.state = (pillController.isEnabled && !pillController.hoverDropOnly) ? .on : .off
        menu.addItem(alwaysVisibleItem)
        
        let disablePillItem = NSMenuItem(
            title: "Hide Top Banner (Menu Bar Only)",
            action: #selector(setDisabledMode),
            keyEquivalent: ""
        )
        disablePillItem.target = self
        disablePillItem.state = (!pillController.isEnabled) ? .on : .off
        menu.addItem(disablePillItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleTitleItem = NSMenuItem(
            title: "Show Song Name in Menu Bar",
            action: #selector(toggleShowTitle),
            keyEquivalent: ""
        )
        toggleTitleItem.target = self
        toggleTitleItem.state = showTitleInMenuBar ? .on : .off
        menu.addItem(toggleTitleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Trigger Drop Down Preview
        let testItem = NSMenuItem(title: "Trigger Drop Down Preview", action: #selector(testDropDownClicked), keyEquivalent: "t")
        testItem.target = self
        testItem.image = NSImage(systemSymbolName: "arrow.down.to.line.compact", accessibilityDescription: nil)
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
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func openTabClicked() {
        if let track = detector.currentTrack {
            detector.focusTab(track: track)
        }
    }
    
    @objc private func playPauseClicked() {
        if let track = detector.currentTrack {
            detector.togglePlayPause(track: track)
        }
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
        pillController.isEnabled = true
        pillController.hoverDropOnly = true
        buildMenu(track: detector.currentTrack)
    }
    
    @objc private func setAlwaysVisibleMode() {
        pillController.isEnabled = true
        pillController.hoverDropOnly = false
        buildMenu(track: detector.currentTrack)
    }
    
    @objc private func setDisabledMode() {
        pillController.isEnabled = false
        buildMenu(track: detector.currentTrack)
    }
    
    @objc private func toggleShowTitle() {
        showTitleInMenuBar.toggle()
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
    
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}
