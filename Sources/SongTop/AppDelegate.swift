import AppKit
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var detector: YouTubeDetector!
    private var pillController: FloatingPillWindowController!
    private var menuBarController: MenuBarController!
    private var cancellables = Set<AnyCancellable>()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent app from showing in Dock
        NSApp.setActivationPolicy(.accessory)
        
        detector = YouTubeDetector()
        pillController = FloatingPillWindowController(detector: detector)
        menuBarController = MenuBarController(detector: detector, pillController: pillController)
        
        detector.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.pillController.update(track: track)
                self?.menuBarController.update(track: track)
            }
            .store(in: &cancellables)
        
        // Start monitoring
        detector.start(interval: 1.5)
        print("SongTop started successfully.")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        detector.stop()
    }
}
