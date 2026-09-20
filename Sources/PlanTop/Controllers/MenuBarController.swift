import AppKit
import Foundation

public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var pillController: FloatingPillWindowController
    
    public var showUpcomingInMenuBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showUpcomingInMenuBar, forKey: "plantop_show_upcoming_menu_bar")
            updateDisplay()
        }
    }
    
    public var onOpenSettings: (() -> Void)?
    
    public init(pillController: FloatingPillWindowController) {
        self.pillController = pillController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        
        if UserDefaults.standard.object(forKey: "plantop_show_upcoming_menu_bar") != nil {
            self.showUpcomingInMenuBar = UserDefaults.standard.bool(forKey: "plantop_show_upcoming_menu_bar")
        } else if UserDefaults.standard.object(forKey: "showTitleInMenuBar") != nil {
            self.showUpcomingInMenuBar = UserDefaults.standard.bool(forKey: "showTitleInMenuBar")
        }
        
        setupMenu()
        updateDisplay()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSettingsChanged),
            name: .planTopSettingsChanged,
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
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func onSettingsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if UserDefaults.standard.object(forKey: "plantop_show_upcoming_menu_bar") != nil {
                let saved = UserDefaults.standard.bool(forKey: "plantop_show_upcoming_menu_bar")
                if self.showUpcomingInMenuBar != saved {
                    self.showUpcomingInMenuBar = saved
                }
            }
            self.updateDisplay()
        }
    }
    
    @objc private func onCalendarUpdated() {
        DispatchQueue.main.async { [weak self] in
            self?.updateDisplay()
        }
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }
    
    public func updateDisplay() {
        guard let button = statusItem.button else { return }
        
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let icon = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "PlanTop")?.withSymbolConfiguration(config)
        button.image = icon
        button.imagePosition = .imageLeft
        
        if showUpcomingInMenuBar {
            let active = GoogleCalendarService.shared.todaysEvents.first(where: { $0.isHappeningNow })
            let nextUpcoming = GoogleCalendarService.shared.todaysEvents.first(where: { !$0.isPast && !$0.isHappeningNow })
            
            if let activeEvent = active {
                let display = activeEvent.title
                let truncated = display.count > 20 ? String(display.prefix(18)) + "…" : display
                button.title = " [NOW] \(truncated)"
            } else if let nextEvent = nextUpcoming {
                let display = nextEvent.title
                let truncated = display.count > 20 ? String(display.prefix(18)) + "…" : display
                let timeStr = nextEvent.formattedStartTime.isEmpty ? nextEvent.formattedTime : nextEvent.formattedStartTime
                button.title = " [\(timeStr)] \(truncated)"
            } else {
                button.title = ""
            }
        } else {
            button.title = ""
        }
    }
    
    private func setupMenu() {
        buildMenu()
    }
    
    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        
        // Header
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        let headerItem = NSMenuItem(title: "PlanTop • \(df.string(from: now))", action: nil, keyEquivalent: "")
        headerItem.attributedTitle = NSAttributedString(
            string: "PlanTop • \(df.string(from: now))",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        // Today's Events
        let todayEvents = GoogleCalendarService.shared.todaysEvents
        let todayHeader = NSMenuItem(title: "── Today (\(todayEvents.count)) ──", action: nil, keyEquivalent: "")
        todayHeader.isEnabled = false
        menu.addItem(todayHeader)
        
        if todayEvents.isEmpty {
            let empty = NSMenuItem(title: "No more events scheduled today", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for event in todayEvents.prefix(6) {
                let prefix: String
                if event.isHappeningNow {
                    prefix = "🔴 [NOW] "
                } else if event.isPast {
                    prefix = "✓ "
                } else {
                    prefix = "[\(event.formattedTime)] "
                }
                let item = NSMenuItem(title: "\(prefix)\(event.title)", action: #selector(eventItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = event
                menu.addItem(item)
            }
        }
        
        // Tomorrow's Events preview
        let tomorrowEvents = GoogleCalendarService.shared.tomorrowsEvents
        if !tomorrowEvents.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let tomorrowHeader = NSMenuItem(title: "── Tomorrow (\(tomorrowEvents.count)) ──", action: nil, keyEquivalent: "")
            tomorrowHeader.isEnabled = false
            menu.addItem(tomorrowHeader)
            
            for event in tomorrowEvents.prefix(4) {
                let item = NSMenuItem(title: "[\(event.formattedTime)] \(event.title)", action: #selector(eventItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = event
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick Actions
        let openCalItem = NSMenuItem(title: "Open Calendar App", action: #selector(openCalendarAppClicked), keyEquivalent: "c")
        openCalItem.target = self
        openCalItem.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        menu.addItem(openCalItem)
        
        let syncItem = NSMenuItem(title: "Sync Calendar Now", action: #selector(syncNowClicked), keyEquivalent: "r")
        syncItem.target = self
        syncItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(syncItem)
        
        let slidePanelItem = NSMenuItem(title: "Toggle Side Panel", action: #selector(toggleSidePanelClicked), keyEquivalent: "p")
        slidePanelItem.target = self
        slidePanelItem.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
        menu.addItem(slidePanelItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Display Mode controls
        let hoverModeItem = NSMenuItem(title: "Slide Out on Right Edge Hover", action: #selector(setHoverMode), keyEquivalent: "")
        hoverModeItem.target = self
        hoverModeItem.state = (pillController.displayMode == .hoverDropdown) ? .on : .off
        menu.addItem(hoverModeItem)
        
        let alwaysVisibleItem = NSMenuItem(title: "Always Keep Side Panel Visible", action: #selector(setAlwaysVisibleMode), keyEquivalent: "")
        alwaysVisibleItem.target = self
        alwaysVisibleItem.state = (pillController.displayMode == .alwaysFloating) ? .on : .off
        menu.addItem(alwaysVisibleItem)
        
        let pinItem = NSMenuItem(title: "Pin Side Panel on Screen", action: #selector(togglePinMode), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = pillController.isPinned ? .on : .off
        menu.addItem(pinItem)
        
        let toggleMenuBarTitle = NSMenuItem(title: "Show Upcoming Event in Menu Bar", action: #selector(toggleShowUpcomingInMenuBar), keyEquivalent: "")
        toggleMenuBarTitle.target = self
        toggleMenuBarTitle.state = showUpcomingInMenuBar ? .on : .off
        menu.addItem(toggleMenuBarTitle)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings & Quit
        let settingsItem = NSMenuItem(title: "PlanTop Settings & Preferences...", action: #selector(openSettingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        let quitItem = NSMenuItem(title: "Quit PlanTop", action: #selector(quitAppClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func eventItemClicked(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }
        if let meetURL = event.videoMeetingURL {
            NSWorkspace.shared.open(meetURL)
        } else if let calURL = event.webCalendarURL {
            NSWorkspace.shared.open(calURL)
        } else {
            openCalendarAppClicked()
        }
    }
    
    @objc private func openCalendarAppClicked() {
        if let url = URL(string: "ical://") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func syncNowClicked() {
        GoogleCalendarService.shared.syncNow()
        updateDisplay()
    }
    
    @objc private func toggleSidePanelClicked() {
        if pillController.isDroppedDown {
            pillController.retract()
        } else {
            pillController.dropDown()
        }
    }
    
    @objc private func setHoverMode() {
        pillController.displayMode = .hoverDropdown
    }
    
    @objc private func setAlwaysVisibleMode() {
        pillController.displayMode = .alwaysFloating
    }
    
    @objc private func togglePinMode() {
        pillController.togglePin()
    }
    
    @objc private func toggleShowUpcomingInMenuBar() {
        showUpcomingInMenuBar.toggle()
    }
    
    @objc private func openSettingsClicked() {
        onOpenSettings?()
    }
    
    @objc private func quitAppClicked() {
        NSApplication.shared.terminate(nil)
    }
}
