import AppKit
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var detector: YouTubeDetector!
    private var pillController: FloatingPillWindowController!
    private var menuBarController: MenuBarController!
    private var settingsController: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        detector = YouTubeDetector()
        pillController = FloatingPillWindowController(detector: detector)
        menuBarController = MenuBarController(detector: detector, pillController: pillController)
        settingsController = SettingsWindowController(detector: detector, pillController: pillController, menuBarController: menuBarController)
        
        menuBarController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        
        settingsController.onWindowClosed = { [weak self] in
            self?.handleSettingsClosed()
        }
        
        detector.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.pillController.update(track: track)
                self?.menuBarController.update(track: track)
                self?.settingsController.updateLiveStatus()
            }
            .store(in: &cancellables)
        
        // Start monitoring
        detector.start(interval: 1.5)
        print("SongTop started successfully in background.")
        
        // Strictly maintain accessory mode so SongTop NEVER appears in the macOS Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Only show settings on first manual launch or when --settings argument is passed
        let isBackground = CommandLine.arguments.contains("--background") || CommandLine.arguments.contains("--silent")
        let shouldOpenSettings = CommandLine.arguments.contains("--settings") || (!isBackground && !UserDefaults.standard.bool(forKey: "songtop_has_launched_before"))
        if shouldOpenSettings {
            UserDefaults.standard.set(true, forKey: "songtop_has_launched_before")
            openSettings()
        }
        
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
    
    private var isLaunching = true
    
    @objc private func handleOpenSettingsNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }
    
    public func applicationDidBecomeActive(_ notification: Notification) {
        if !isLaunching && !(settingsController.window?.isVisible ?? false) {
            openSettings()
        }
    }
    
    public func openSettings() {
        // Keep accessory mode: show settings window without appearing in Dock
        NSApp.setActivationPolicy(.accessory)
        settingsController.show()
    }
    
    public func handleSettingsClosed() {
        // Retain stealth accessory mode in menu bar
        NSApp.setActivationPolicy(.accessory)
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Manual activation from Spotlight, Finder, or Terminal brings up Settings
        openSettings()
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        detector.stop()
    }
}
