import Foundation
import AppKit

public final class YouTubeDetector: ObservableObject {
    @Published public private(set) var currentTrack: TrackInfo?
    @Published public private(set) var isDetecting: Bool = false
    
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.songtop.detector", qos: .background)
    
    public init() {}
    
    public func start(interval: TimeInterval = 1.5) {
        stop()
        isDetecting = true
        checkNow()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.queue.async {
                    self?.checkNow()
                }
            }
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
        isDetecting = false
    }
    
    public func checkNow() {
        let detected = detectFromRunningBrowsers()
        
        if Thread.isMainThread {
            if self.currentTrack != detected {
                self.currentTrack = detected
            }
        } else {
            DispatchQueue.main.async {
                if self.currentTrack != detected {
                    self.currentTrack = detected
                }
            }
        }
    }
    
    public func detectFromRunningBrowsers() -> TrackInfo? {
        let runningApps = NSWorkspace.shared.runningApplications
        let runningNames = Set(runningApps.compactMap { $0.localizedName })
        
        // Priority order for browsers
        let supportedBrowsers: [(name: String, scriptGenerator: (String) -> String)] = [
            ("Google Chrome", YouTubeDetector.buildChromiumScript),
            ("Brave Browser", YouTubeDetector.buildChromiumScript),
            ("Arc", YouTubeDetector.buildChromiumScript),
            ("Microsoft Edge", YouTubeDetector.buildChromiumScript),
            ("Safari", YouTubeDetector.buildSafariScript),
            ("Vivaldi", YouTubeDetector.buildChromiumScript),
            ("Opera", YouTubeDetector.buildChromiumScript)
        ]
        
        for browser in supportedBrowsers {
            if runningNames.contains(browser.name) {
                let scriptSource = browser.scriptGenerator(browser.name)
                if let script = NSAppleScript(source: scriptSource) {
                    var errorDict: NSDictionary?
                    let result = script.executeAndReturnError(&errorDict)
                    if let output = result.stringValue, output != "NONE" && !output.isEmpty {
                        let parts = output.components(separatedBy: "|||")
                        if parts.count >= 3 {
                            let rawTitle = parts[0]
                            let url = parts[1]
                            let bName = parts[2]
                            return TrackInfo(rawTitle: rawTitle, url: url, browser: bName, isPlaying: true)
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    public func isUserActiveOnYouTubeTab() -> Bool {
        guard let track = currentTrack else { return false }
        let frontApp = NSWorkspace.shared.frontmostApplication
        guard let frontName = frontApp?.localizedName, frontName == track.browser else {
            return false
        }
        
        let targetId = track.youtubeVideoId ?? "youtube.com"
        let scriptSource: String
        if track.browser == "Safari" {
            scriptSource = """
            tell application "Safari"
                try
                    set aURL to URL of current tab of front window
                    if aURL contains "\(targetId)" then
                        return "ACTIVE"
                    end if
                end try
                return "AWAY"
            end tell
            """
        } else {
            scriptSource = """
            tell application "\(track.browser)"
                try
                    set aURL to URL of active tab of front window
                    if aURL contains "\(targetId)" then
                        return "ACTIVE"
                    end if
                end try
                return "AWAY"
            end tell
            """
        }
        
        if let script = NSAppleScript(source: scriptSource) {
            var err: NSDictionary?
            let result = script.executeAndReturnError(&err)
            return result.stringValue == "ACTIVE"
        }
        return false
    }
    
    public func seekBrowser(track: TrackInfo, toSeconds: Double) {
        guard toSeconds >= 0 else { return }
        let targetSecs = Int(toSeconds)
        let targetId = track.youtubeVideoId ?? "youtube.com"
        
        var base = track.url
        if let range = base.range(of: "&t=\\d+s?", options: .regularExpression) {
            base.removeSubrange(range)
        } else if let range = base.range(of: "\\?t=\\d+s?", options: .regularExpression) {
            base.removeSubrange(range)
        }
        let separator = base.contains("?") ? "&" : "?"
        let finalURL = "\(base)\(separator)t=\(targetSecs)s"
        
        let scriptSource: String
        if track.browser == "Safari" {
            scriptSource = """
            tell application "Safari"
                try
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "\(targetId)" then
                                set URL of t to "\(finalURL)"
                                return true
                            end if
                        end repeat
                    end repeat
                end try
            end tell
            """
        } else {
            scriptSource = """
            tell application "\(track.browser)"
                try
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "\(targetId)" then
                                set URL of t to "\(finalURL)"
                                return true
                            end if
                        end repeat
                    end repeat
                end try
            end tell
            """
        }
        
        queue.async {
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
            }
        }
    }
    
    public func focusTab(track: TrackInfo, atSeconds: Double? = nil) {
        let targetId = track.youtubeVideoId ?? "youtube.com"
        var targetURL = track.url
        if let sec = atSeconds, sec > 1 {
            var base = track.url
            if let range = base.range(of: "&t=\\d+s?", options: .regularExpression) {
                base.removeSubrange(range)
            } else if let range = base.range(of: "\\?t=\\d+s?", options: .regularExpression) {
                base.removeSubrange(range)
            }
            let separator = base.contains("?") ? "&" : "?"
            targetURL = "\(base)\(separator)t=\(Int(sec))s"
        }
        
        let scriptSource: String
        if track.browser == "Safari" {
            scriptSource = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "\(targetId)" then
                            set current tab of w to t
                            if "\(targetURL)" is not "\(track.url)" then
                                set URL of t to "\(targetURL)"
                            end if
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            """
        } else {
            scriptSource = """
            tell application "\(track.browser)"
                repeat with w in windows
                    set idx to 1
                    repeat with t in tabs of w
                        if URL of t contains "\(targetId)" then
                            set active tab index of w to idx
                            if "\(targetURL)" is not "\(track.url)" then
                                set URL of t to "\(targetURL)"
                            end if
                            set index of w to 1
                            activate
                            return true
                        end if
                        set idx to idx + 1
                    end repeat
                end repeat
            end tell
            """
        }
        
        queue.async {
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
            }
        }
    }
    
    public func togglePlayPause(track: TrackInfo) {
        focusTab(track: track)
        queue.asyncAfter(deadline: .now() + 0.1) {
            let scriptSource = """
            tell application "System Events"
                keystroke "k"
            end tell
            """
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
            }
        }
    }
    
    public func nextTrack(track: TrackInfo) {
        focusTab(track: track)
        queue.asyncAfter(deadline: .now() + 0.1) {
            let scriptSource = """
            tell application "System Events"
                keystroke "N" using {shift down}
            end tell
            """
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
            }
        }
    }
    
    public static func buildChromiumScript(browserName: String) -> String {
        return """
        tell application "\(browserName)"
            try
                repeat with w in windows
                    set aTab to active tab of w
                    set aURL to URL of aTab
                    if aURL contains "youtube.com/watch" or aURL contains "music.youtube.com" then
                        return (title of aTab) & "|||" & aURL & "|||\(browserName)"
                    end if
                end repeat
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" then
                            return (title of t) & "|||" & u & "|||\(browserName)"
                        end if
                    end repeat
                end repeat
            end try
            return "NONE"
        end tell
        """
    }
    
    public static func buildSafariScript(browserName: String) -> String {
        return """
        tell application "Safari"
            try
                repeat with w in windows
                    set aTab to current tab of w
                    set aURL to URL of aTab
                    if aURL contains "youtube.com/watch" or aURL contains "music.youtube.com" then
                        return (name of aTab) & "|||" & aURL & "|||Safari"
                    end if
                end repeat
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" then
                            return (name of t) & "|||" & u & "|||Safari"
                        end if
                    end repeat
                end repeat
            end try
            return "NONE"
        end tell
        """
    }
}
