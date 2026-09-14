import AppKit
import ServiceManagement

public final class LaunchAtLoginHelper {
    public static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled { return true }
        }
        return isLaunchAgentInstalled
    }
    
    public static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("[LaunchAtLogin] SMAppService failed (\(error)), falling back to LaunchAgent")
                configureLaunchAgent(enabled: enabled)
            }
        } else {
            configureLaunchAgent(enabled: enabled)
        }
        
        UserDefaults.standard.set(enabled, forKey: "songtop_launch_at_login")
    }
    
    private static var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.songtop.mac.plist")
    }
    
    private static var isLaunchAgentInstalled: Bool {
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }
    
    private static func configureLaunchAgent(enabled: Bool) {
        let fileManager = FileManager.default
        let plistURL = launchAgentPlistURL
        
        if enabled {
            let dir = plistURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            
            let execPath = Bundle.main.executablePath ?? "/Applications/SongTop.app/Contents/MacOS/SongTop"
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.songtop.mac</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                    <string>--background</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? fileManager.removeItem(at: plistURL)
        }
    }
}
