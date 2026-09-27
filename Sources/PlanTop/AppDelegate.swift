import AppKit
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pillController: FloatingPillWindowController!
    private var menuBarController: MenuBarController!
    private var settingsController: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()
    private var isLaunching = true
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        pillController = FloatingPillWindowController()
        menuBarController = MenuBarController(pillController: pillController)
        settingsController = SettingsWindowController(pillController: pillController, menuBarController: menuBarController)
        
        pillController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        
        menuBarController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        
        settingsController.onWindowClosed = { [weak self] in
            self?.handleSettingsClosed()
        }
        
        // Initial calendar sync
        GoogleCalendarService.shared.syncNow()
        print("PlanTop started successfully in background.")
        
        // Ensure launch-at-login is enabled so PlanTop starts upon computer startup
        let launchAtStartup = UserDefaults.standard.object(forKey: "plantop_launch_at_login") as? Bool ?? true
        LaunchAtLoginHelper.setEnabled(launchAtStartup)
        
        // Strictly maintain accessory mode so PlanTop NEVER appears in the macOS Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Only show settings on first manual launch or when --settings argument is passed
        let isBackground = CommandLine.arguments.contains("--background") || CommandLine.arguments.contains("--silent")
        let shouldOpenSettings = CommandLine.arguments.contains("--settings") || (!isBackground && !UserDefaults.standard.bool(forKey: "plantop_has_launched_before"))
        if shouldOpenSettings {
            UserDefaults.standard.set(true, forKey: "plantop_has_launched_before")
            openSettings()
        }
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenSettingsNotification),
            name: NSNotification.Name("com.plantop.openSettings"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenSettingsNotification),
            name: NSNotification.Name("com.songtop.openSettings"),
            object: nil
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isLaunching = false
        }
    }
    
    @objc private func handleOpenSettingsNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }
    public func applicationDidBecomeActive(_ notification: Notification) {
        // App became active (e.g. user hovered over panel to type, or clicked menu bar icon).
        // Settings should only be displayed when explicitly opened by user request.
    }
    
    public func openSettings() {
        NSApp.setActivationPolicy(.accessory)
        settingsController.show()
    }
    
    public func handleSettingsClosed() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown
    }
}
