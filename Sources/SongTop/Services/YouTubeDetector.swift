import Foundation
import AppKit

extension Notification.Name {
    public static let songTopNativePiPChanged = Notification.Name("com.songtop.nativePiPChanged")
    public static let songTopTabTelemetryUpdated = Notification.Name("com.songtop.tabTelemetryUpdated")
    public static let songTopTabAutomationChanged = Notification.Name("com.songtop.tabAutomationChanged")
}

public final class YouTubeDetector: ObservableObject {
    @Published public private(set) var currentTrack: TrackInfo?
    @Published public private(set) var isDetecting: Bool = false
    @Published public private(set) var isNativePiPActive: Bool = false
    @Published public private(set) var nativePiPBounds: CGRect?
    @Published public private(set) var isTabAutomationActive: Bool = false
    
    // Live in-tab telemetry from Option 2
    @Published public private(set) var tabCurrentTime: Double = 0.0
    @Published public private(set) var tabDuration: Double = 0.0
    @Published public private(set) var tabIsPaused: Bool = false
    @Published public private(set) var tabVolume: Int = 100
    @Published public private(set) var tabIsMuted: Bool = false
    
    private var timer: Timer?
    private var telemetryTimer: Timer?
    private let queue = DispatchQueue(label: "com.songtop.detector", qos: .userInitiated)
    
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
            // Fast telemetry timer (every 400ms) to keep playhead scrubber and time labels smoothly animated
            self.telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                self?.pollActiveTelemetry()
            }
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        isDetecting = false
    }
    
    public static func checkNativePiPWindow() -> (isActive: Bool, bounds: CGRect?) {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return (false, nil)
        }
        for w in list {
            let name = w[kCGWindowName as String] as? String ?? ""
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            if (name == "Picture in Picture" || name == "Picture-in-Picture") && layer >= 3 {
                if let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                   let x = boundsDict["X"] as? Double,
                   let y = boundsDict["Y"] as? Double,
                   let width = boundsDict["Width"] as? Double,
                   let height = boundsDict["Height"] as? Double {
                    return (true, CGRect(x: x, y: y, width: width, height: height))
                }
                return (true, nil)
            }
        }
        return (false, nil)
    }
    
    public func checkNow() {
        let pipInfo = YouTubeDetector.checkNativePiPWindow()
        let detected = detectFromRunningBrowsers()
        
        let updateBlock = {
            if self.isNativePiPActive != pipInfo.isActive {
                self.isNativePiPActive = pipInfo.isActive
                self.nativePiPBounds = pipInfo.bounds
                NotificationCenter.default.post(name: .songTopNativePiPChanged, object: nil)
            }
            if self.currentTrack != detected {
                self.currentTrack = detected
                if let t = detected {
                    self.pollTabPlaybackState(track: t, completion: nil)
                }
            }
        }
        
        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }
    
    private func pollActiveTelemetry() {
        guard let track = currentTrack else { return }
        pollTabPlaybackState(track: track, completion: nil)
    }
    
    public func detectFromRunningBrowsers() -> TrackInfo? {
        let runningApps = NSWorkspace.shared.runningApplications
        let runningNames = Set(runningApps.compactMap { $0.localizedName })
        
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
    
    // MARK: - Option 2: Direct Tab Automation Engine (In-Tab JavaScript via Apple Events)
    
    public func executeInTabJS(track: TrackInfo, script: String, completion: ((Result<String, Error>) -> Void)? = nil) {
        let browser = track.browser
        let targetId = track.youtubeVideoId ?? "youtube.com"
        let escapedScript = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource: String
        if browser == "Safari" {
            scriptSource = """
            tell application "Safari"
                try
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "\(targetId)" then
                                set res to (do JavaScript "\(escapedScript)" in t)
                                return (res as string)
                            end if
                        end repeat
                    end repeat
                on error errMsg number errNum
                    return "ERROR:" & errNum & ":" & errMsg
                end try
                return "TAB_NOT_FOUND"
            end tell
            """
        } else {
            scriptSource = """
            tell application "\(browser)"
                try
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "\(targetId)" then
                                tell t
                                    set res to (execute javascript "\(escapedScript)")
                                    return (res as string)
                                end tell
                            end if
                        end repeat
                    end repeat
                on error errMsg number errNum
                    return "ERROR:" & errNum & ":" & errMsg
                end try
                return "TAB_NOT_FOUND"
            end tell
            """
        }
        
        queue.async {
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: scriptSource) {
                let result = appleScript.executeAndReturnError(&errorDict)
                if let err = errorDict {
                    let nsErr = NSError(domain: "com.songtop.applescript", code: -1, userInfo: err as? [String: Any])
                    DispatchQueue.main.async {
                        self.setAutomationActive(false)
                        completion?(.failure(nsErr))
                    }
                    return
                }
                
                let output = result.stringValue ?? ""
                if output.hasPrefix("ERROR:") {
                    let nsErr = NSError(domain: "com.songtop.tabjs", code: -2, userInfo: [NSLocalizedDescriptionKey: output])
                    DispatchQueue.main.async {
                        self.setAutomationActive(false)
                        completion?(.failure(nsErr))
                    }
                } else if output == "TAB_NOT_FOUND" {
                    let nsErr = NSError(domain: "com.songtop.tabjs", code: -3, userInfo: [NSLocalizedDescriptionKey: "YouTube tab not found in \(browser)"])
                    DispatchQueue.main.async {
                        completion?(.failure(nsErr))
                    }
                } else {
                    DispatchQueue.main.async {
                        self.setAutomationActive(true)
                        completion?(.success(output))
                    }
                }
            } else {
                let nsErr = NSError(domain: "com.songtop.applescript", code: -4, userInfo: [NSLocalizedDescriptionKey: "Could not compile script"])
                DispatchQueue.main.async {
                    self.setAutomationActive(false)
                    completion?(.failure(nsErr))
                }
            }
        }
    }
    
    private func setAutomationActive(_ active: Bool) {
        guard isTabAutomationActive != active else { return }
        isTabAutomationActive = active
        NotificationCenter.default.post(name: .songTopTabAutomationChanged, object: nil)
    }
    
    // Instant In-Tab Seeking (Zero Page Reload!)
    public func seekBrowser(track: TrackInfo, toSeconds: Double) {
        guard toSeconds >= 0 else { return }
        let js = """
        (function() {
            var v = document.querySelector('video');
            if (v) {
                v.currentTime = \(toSeconds);
                return 'OK';
            }
            return 'NO_VIDEO';
        })()
        """
        
        executeInTabJS(track: track, script: js) { [weak self] result in
            switch result {
            case .success:
                self?.tabCurrentTime = toSeconds
            case .failure:
                // Fallback to URL-based seek if in-tab JS is disabled
                self?.fallbackURLSeek(track: track, toSeconds: toSeconds)
            }
        }
    }
    
    // In-Background Play / Pause (No focus stealing!)
    public func togglePlayPause(track: TrackInfo) {
        let js = """
        (function() {
            var v = document.querySelector('video');
            if (v) {
                if (v.paused) {
                    v.play();
                    return 'PLAYING';
                } else {
                    v.pause();
                    return 'PAUSED';
                }
            }
            return 'NO_VIDEO';
        })()
        """
        
        executeInTabJS(track: track, script: js) { [weak self] result in
            switch result {
            case .success(let state):
                self?.tabIsPaused = (state == "PAUSED")
                NotificationCenter.default.post(name: .songTopTabTelemetryUpdated, object: nil)
            case .failure:
                // Fallback to focus tab + key "k"
                self?.fallbackTogglePlayPause(track: track)
            }
        }
    }
    
    // In-Background Volume
    public func setVolume(track: TrackInfo, volume: Int) {
        let fraction = max(0.0, min(1.0, Double(volume) / 100.0))
        let js = """
        (function() {
            var v = document.querySelector('video');
            if (v) {
                v.volume = \(fraction);
                return 'OK';
            }
            return 'NO_VIDEO';
        })()
        """
        executeInTabJS(track: track, script: js) { [weak self] _ in
            self?.tabVolume = volume
        }
    }
    
    // In-Background Mute
    public func setMuted(track: TrackInfo, muted: Bool) {
        let js = """
        (function() {
            var v = document.querySelector('video');
            if (v) {
                v.muted = \(muted);
                return 'OK';
            }
            return 'NO_VIDEO';
        })()
        """
        executeInTabJS(track: track, script: js) { [weak self] _ in
            self?.tabIsMuted = muted
        }
    }
    
    // In-Background Next Track
    public func nextTrack(track: TrackInfo) {
        let js = """
        (function() {
            var btn = document.querySelector('.ytp-next-button');
            if (btn) {
                btn.click();
                return 'OK';
            }
            return 'NO_BTN';
        })()
        """
        executeInTabJS(track: track, script: js) { [weak self] result in
            switch result {
            case .success:
                break
            case .failure:
                self?.fallbackNextTrack(track: track)
            }
        }
    }
    
    // Real-Time Playback Telemetry Query
    public func pollTabPlaybackState(track: TrackInfo, completion: (((cur: Double, dur: Double, paused: Bool, vol: Int, muted: Bool)?) -> Void)? = nil) {
        let startTime = Date()
        let js = """
        (function() {
            var v = document.querySelector('video');
            if (!v) return JSON.stringify({ error: 'no_video' });
            return JSON.stringify({
                cur: v.currentTime || 0,
                dur: v.duration || 0,
                paused: v.paused,
                vol: Math.round((v.volume || 0) * 100),
                muted: v.muted
            });
        })()
        """
        
        executeInTabJS(track: track, script: js) { [weak self] result in
            guard let self = self else { return }
            let latency = Date().timeIntervalSince(startTime)
            switch result {
            case .success(let jsonString):
                if let data = jsonString.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   dict["error"] == nil {
                    var cur = dict["cur"] as? Double ?? 0
                    let dur = dict["dur"] as? Double ?? 0
                    let paused = dict["paused"] as? Bool ?? false
                    let vol = dict["vol"] as? Int ?? 100
                    let muted = dict["muted"] as? Bool ?? false
                    
                    // Compensate for full round-trip AppleScript and WebKit dispatch latency
                    if !paused && latency > 0 && latency < 0.8 {
                        cur += (latency + 0.05)
                    }
                    
                    self.tabCurrentTime = cur
                    if dur > 0 { self.tabDuration = dur }
                    self.tabIsPaused = paused
                    self.tabVolume = vol
                    self.tabIsMuted = muted
                    NotificationCenter.default.post(name: .songTopTabTelemetryUpdated, object: nil)
                    completion?((cur, dur, paused, vol, muted))
                    return
                }
            case .failure:
                break
            }
            completion?(nil)
        }
    }
    
    // Connection Tester for Settings Window
    public func testTabAutomationConnection(completion: @escaping (Bool, String) -> Void) {
        guard let track = currentTrack else {
            completion(false, "No active YouTube tab found to test. Play audio in Chrome, Safari, Brave, or Arc first.")
            return
        }
        
        executeInTabJS(track: track, script: "'SONGTOP_OK'") { result in
            switch result {
            case .success:
                completion(true, "🟢 Connected! Real-time in-tab seeking & background controls are active in \(track.browser).")
            case .failure:
                let browser = track.browser
                let msg: String
                if browser == "Safari" {
                    msg = "⚠️ Safari blocked JavaScript events. To enable: in Safari top menu bar, click Develop > Allow JavaScript from Apple Events."
                } else {
                    msg = "⚠️ \(browser) blocked JavaScript events. To enable: in \(browser) top menu bar, click View > Developer > Allow JavaScript from Apple Events."
                }
                completion(false, msg)
            }
        }
    }
    
    // MARK: - Safe Fallbacks
    
    private func fallbackURLSeek(track: TrackInfo, toSeconds: Double) {
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
    
    private func fallbackTogglePlayPause(track: TrackInfo) {
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
    
    private func fallbackNextTrack(track: TrackInfo) {
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
