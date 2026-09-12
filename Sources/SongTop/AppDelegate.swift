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
        print("SongTop started successfully.")
        
        // Welcome the user with the Settings & Customization window on launch
        openSettings()
    }
    
    public func openSettings() {
        // Show in Dock while settings window is open
        NSApp.setActivationPolicy(.regular)
        settingsController.show()
    }
    
    public func handleSettingsClosed() {
        // Return to stealth accessory mode in menu bar when closed
        NSApp.setActivationPolicy(.accessory)
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        detector.stop()
    }
}
