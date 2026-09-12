import AppKit
import WebKit

protocol YouTubeVideoPlayerDelegate: AnyObject {
    func handleBridgeMessage(_ body: Any)
}

private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var delegate: YouTubeVideoPlayerDelegate?
    
    init(delegate: YouTubeVideoPlayerDelegate) {
        self.delegate = delegate
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.handleBridgeMessage(message.body)
    }
}

private final class VideoClickOverlayView: NSView {
    var onClicked: (() -> Void)?
    var onSkipAdClicked: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var isAdActive: Bool = false
    private var trackingArea: NSTrackingArea?
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            // If an ad is active and user clicked in bottom-right skip button zone (within 110px of right and 46px of bottom):
            if isAdActive && (point.x > bounds.width - 110 && point.y < 46) {
                onSkipAdClicked?()
                return
            }
            onClicked?()
        }
    }
}

public final class YouTubeVideoPlayerView: NSView, YouTubeVideoPlayerDelegate, WKNavigationDelegate {
    private var webView: WKWebView!
    private let thumbnailImageView = NSImageView()
    private let clickOverlay = VideoClickOverlayView()
    private let playOverlay = NSImageView()
    private let loadingIndicator = NSProgressIndicator()
    private let skipAdButton = NSButton()
    
    public private(set) var currentVideoId: String?
    public private(set) var isMuted: Bool = true
    public private(set) var isPlaying: Bool = true
    public private(set) var isReady: Bool = false
    public private(set) var isAdActive: Bool = false
    public private(set) var browserCurrentTime: Double = 0.0
    public private(set) var panelCurrentTime: Double = 0.0
    public private(set) var duration: Double = 0.0
    public private(set) var volume: Int = 100
    private var shouldBePlaying: Bool = true
    
    /// Constant audio/video lip-sync delay (in seconds) to compensate for speaker/Bluetooth latency. Default 0.0s (exact frame match).
    public var syncDelay: Double = {
        if let stored = UserDefaults.standard.object(forKey: "songtop_av_sync_delay_ms") as? Double, stored == 250.0 {
            UserDefaults.standard.set(0.0, forKey: "songtop_av_sync_delay_ms")
            return 0.0
        }
        let ms = UserDefaults.standard.object(forKey: "songtop_av_sync_delay_ms") != nil
            ? UserDefaults.standard.double(forKey: "songtop_av_sync_delay_ms")
            : 0.0
        return ms / 1000.0
    }()
    
    public var currentTime: Double {
        return browserCurrentTime > 0 ? browserCurrentTime : panelCurrentTime
    }
    
    public var onVideoClicked: (() -> Void)?
    public var onPlaybackStateChanged: ((Bool) -> Void)?
    public var onProgressUpdated: ((Double, Double) -> Void)?
    public var onVolumeChanged: ((Int, Bool) -> Void)?
    
    private var isHovered: Bool = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "playerBridge")
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // 1. Crisp Video Artwork / Thumbnail (Immediate display while video stream buffers)
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.wantsLayer = true
        thumbnailImageView.layer?.cornerRadius = 12
        thumbnailImageView.layer?.masksToBounds = true
        addSubview(thumbnailImageView)
        
        // 2. WebKit Live Video Player
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        
        let ucc = WKUserContentController()
        let proxy = ScriptMessageProxy(delegate: self)
        ucc.add(proxy, name: "playerBridge")
        
        // Injected CSS: Isolates the video element to 100vw x 100vh and hides all mastheads/sidebars/comments and endscreen cards
        let injectedCSS = """
        html, body {
            margin: 0 !important;
            padding: 0 !important;
            overflow: hidden !important;
            width: 100vw !important;
            height: 100vh !important;
            background: #000 !important;
        }
        #masthead-container, #secondary, #below, #chat-container, ytd-miniplayer, #guide, tp-yt-app-drawer, #comments, ytd-watch-metadata, #related, ytd-merch-shelf-renderer, ytd-banner-promo-renderer, #clarify-box, #donation-shelf, #panels, #ticket-shelf, #actions, #meta, #info, ytd-engagement-panel-section-list-renderer, ytd-popup-container, #guide-wrapper, #voice-search-button, #search-form,
        .ytp-endscreen-content, .ytp-autonav-endscreen, .ytp-ce-element, .ytp-ce-covering-overlay, .ytp-ce-element-show, .ytp-upnext, .ytp-pause-overlay {
            display: none !important;
            visibility: hidden !important;
            pointer-events: none !important;
            opacity: 0 !important;
        }
        #movie_player, .html5-video-player, #player-theater-container, #player-container-outer, #player-container-inner, #player-container {
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            width: 100vw !important;
            height: 100vh !important;
            max-width: 100vw !important;
            max-height: 100vh !important;
            z-index: 99999 !important;
            background: #000 !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        video.html5-main-video {
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
            width: 100vw !important;
            height: 100vh !important;
            object-fit: contain !important;
        }
        .ytp-chrome-top, .ytp-title-text, .ytp-title-channel, .ytp-title, .ytp-gradient-top, .ytp-gradient-bottom, .ytp-chrome-bottom, .ytp-watermark, .ytp-bezel, .ytp-bezel-text, .ytp-paid-content-overlay {
            opacity: 0 !important;
            visibility: hidden !important;
            pointer-events: none !important;
        }
        .ytp-ad-module, .ytp-ad-player-overlay, .ytp-ad-player-overlay-layout, .ytp-ad-skip-button-container, .ytp-ad-skip-button-modern, .ytp-ad-skip-button, .videoAdUiSkipButton, .ytp-skip-ad-button {
            display: block !important;
            opacity: 1 !important;
            visibility: visible !important;
            pointer-events: auto !important;
            z-index: 100000 !important;
        }
        """
        let escapedCSS = injectedCSS.replacingOccurrences(of: "\n", with: " ")
        let styleInjectionJS = """
        (function() {
            function injectStyle() {
                if (!document.getElementById('songtop-player-style')) {
                    var s = document.createElement('style');
                    s.id = 'songtop-player-style';
                    s.textContent = `\(escapedCSS)`;
                    (document.head || document.documentElement).appendChild(s);
                }
            }
            injectStyle();
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', injectStyle);
            }
        })();
        """
        ucc.addUserScript(WKUserScript(source: styleInjectionJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        
        // Injected JS: Real-time video player control, accurate ad detection without false triggers, and playback reporting
        let injectedBridgeJS = """
        (function() {
            if (window._songTopInjected) return;
            window._songTopInjected = true;

            var lastAdState = false;
            var lastPlayState = null;
            var readyNotified = false;
            var lastSeekTimestamp = 0;
            window._songTopInitialSynced = false;

            // Closed-loop dynamic frame synchronizer with seek debouncing and jitter damping
            window._songTopSync = function(targetTime, isPaused, delaySec) {
                if (typeof targetTime !== 'number' || !isFinite(targetTime) || targetTime < 0) return;
                var p = document.getElementById('movie_player');
                var v = document.querySelector('video.html5-main-video') || document.querySelector('video');
                if (!v) return;

                // Never interfere while an ad is active
                if (p && p.classList && (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting'))) {
                    return;
                }

                var delay = (typeof delaySec === 'number' && isFinite(delaySec)) ? delaySec : 0.0;
                var effectiveTarget = Math.max(0, targetTime - delay);

                if (isPaused) {
                    if (!v.paused) {
                        try { v.pause(); } catch(e) {}
                    }
                    if (p && p.pauseVideo) {
                        try { p.pauseVideo(); } catch(e) {}
                    }
                    // When paused, snap frame if off by more than 80ms
                    if (Math.abs(v.currentTime - effectiveTarget) > 0.08) {
                        v.currentTime = effectiveTarget;
                    }
                    v.playbackRate = 1.0;
                    return;
                }

                // Should be playing
                if (v.paused) {
                    try { v.play().catch(function(){}); } catch(e) {}
                }
                if (p && p.playVideo && p.getPlayerState && p.getPlayerState() !== 1) {
                    try { p.playVideo(); } catch(e) {}
                }

                var diff = v.currentTime - effectiveTarget; // positive: panel video is ahead; negative: panel video is behind
                var now = Date.now();

                // 1. Initial sync or major jump (> 1.2s, e.g. user scrubbed in browser)
                if (!window._songTopInitialSynced || Math.abs(diff) > 1.2) {
                    window._songTopInitialSynced = true;
                    lastSeekTimestamp = now;
                    if (p && p.seekTo) {
                        try { p.seekTo(effectiveTarget, true); } catch(e) {}
                    }
                    v.currentTime = effectiveTarget;
                    v.playbackRate = 1.0;
                    return;
                }

                // 2. Prevent seek thrashing! Keep at least 2.5s between hard seeks so playback is silky smooth
                if (now - lastSeekTimestamp < 2500) {
                    return;
                }

                // 3. Significant drift (> 0.45s): snap frame cleanly
                if (Math.abs(diff) > 0.45) {
                    lastSeekTimestamp = now;
                    if (p && p.seekTo) {
                        try { p.seekTo(effectiveTarget, true); } catch(e) {}
                    }
                    v.currentTime = effectiveTarget;
                    v.playbackRate = 1.0;
                    return;
                }

                // 4. Subtle, imperceptible rate convergence (±4%)
                // Micro-adjusting by 4% is invisible to human eye, perfectly eliminates small drift,
                // and NEVER triggers YouTube buffer re-requests or stuttering
                if (diff < -0.06) {
                    v.playbackRate = 1.04;
                } else if (diff > 0.06) {
                    v.playbackRate = 0.96;
                } else {
                    v.playbackRate = 1.0;
                }
            };

            setInterval(function() {
                var p = document.getElementById('movie_player');
                var v = document.querySelector('video.html5-main-video') || document.querySelector('video');

                if (p) {
                    try { p.mute(); } catch(e) {}
                }
                if (v) {
                    v.muted = true;
                }

                // Strict ad detection (checks actual player classes, avoids false positives)
                var isAd = false;
                if (p && p.classList) {
                    if (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting')) {
                        isAd = true;
                    }
                }

                if (isAd !== lastAdState) {
                    lastAdState = isAd;
                    try { window.webkit.messageHandlers.playerBridge.postMessage(isAd ? 'ad_detected' : 'ad_cleared'); } catch(e) {}
                }

                if (isAd) {
                    // Try auto-clicking YouTube skip button if ready
                    var skipButtons = [
                        '.ytp-ad-skip-button-modern',
                        '.ytp-ad-skip-button',
                        '.videoAdUiSkipButton',
                        '.ytp-skip-ad-button',
                        '.ytp-ad-skip-button-container button',
                        'button.ytp-ad-skip-button-modern'
                    ];
                    for (var i = 0; i < skipButtons.length; i++) {
                        var btn = document.querySelector(skipButtons[i]);
                        if (btn) {
                            try { btn.click(); } catch(e) {}
                        }
                    }
                } else if (v) {
                    if (!readyNotified && (v.readyState >= 1 || (p && p.getPlayerState))) {
                        readyNotified = true;
                        try {
                            if (p && p.setPlaybackQualityRange) {
                                p.setPlaybackQualityRange('small', 'medium');
                            } else if (p && p.setPlaybackQuality) {
                                p.setPlaybackQuality('medium');
                            }
                        } catch(e) {}
                        try { window.webkit.messageHandlers.playerBridge.postMessage('ready'); } catch(e) {}
                    }

                    var pState = (p && p.getPlayerState) ? p.getPlayerState() : -1;
                    var isPlaying = (pState === 1) || (!v.paused && !v.ended && v.readyState >= 2);
                    var stateMsg = isPlaying ? 'state_1' : 'state_2';
                    if (stateMsg !== lastPlayState) {
                        lastPlayState = stateMsg;
                        try { window.webkit.messageHandlers.playerBridge.postMessage(stateMsg); } catch(e) {}
                    }

                    var cur = (p && p.getCurrentTime) ? p.getCurrentTime() : (v.currentTime || 0);
                    var dur = (p && p.getDuration) ? p.getDuration() : (v.duration || 0);
                    try {
                        window.webkit.messageHandlers.playerBridge.postMessage('progress_' + cur.toFixed(2) + '_' + dur.toFixed(1));
                    } catch(e) {}
                }
            }, 250);
        })();
        """
        ucc.addUserScript(WKUserScript(source: injectedBridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        
        config.userContentController = ucc
        
        webView = WKWebView(frame: bounds, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 12
        webView.layer?.masksToBounds = true
        webView.navigationDelegate = self
        webView.alphaValue = 0.0
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        addSubview(webView)
        
        // 3. Transparent Click & Hover Overlay
        clickOverlay.wantsLayer = true
        clickOverlay.onClicked = { [weak self] in
            self?.onVideoClicked?()
        }
        clickOverlay.onSkipAdClicked = { [weak self] in
            self?.skipAd()
        }
        clickOverlay.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.isHovered = isHovered
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                self.playOverlay.animator().alphaValue = isHovered ? 0.85 : 0.0
            }
        }
        addSubview(clickOverlay)
        
        // 4. Subtle Centered Play/Pause Indicator (Fades in on hover)
        playOverlay.wantsLayer = true
        playOverlay.alphaValue = 0.0
        updatePlayOverlayIcon()
        addSubview(playOverlay)
        
        // 5. Interactive Native Skip Ad Button
        skipAdButton.title = "⏭️ Skip Ad"
        skipAdButton.isBordered = false
        skipAdButton.wantsLayer = true
        skipAdButton.layer?.cornerRadius = 8
        skipAdButton.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        skipAdButton.layer?.borderWidth = 1.0
        skipAdButton.layer?.borderColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        skipAdButton.layer?.shadowColor = NSColor.black.cgColor
        skipAdButton.layer?.shadowOpacity = 0.6
        skipAdButton.layer?.shadowRadius = 6
        skipAdButton.layer?.shadowOffset = CGSize(width: 0, height: -2)
        skipAdButton.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        skipAdButton.contentTintColor = .white
        skipAdButton.target = self
        skipAdButton.action = #selector(handleSkipAdClicked)
        skipAdButton.alphaValue = 0.0
        skipAdButton.isHidden = true
        addSubview(skipAdButton)
        
        // 6. Loading Spinner
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        addSubview(loadingIndicator)
    }
    
    public override func layout() {
        super.layout()
        thumbnailImageView.frame = bounds
        webView.frame = bounds
        clickOverlay.frame = bounds
        
        let overlaySize: CGFloat = 44
        playOverlay.frame = NSRect(
            x: (bounds.width - overlaySize) / 2,
            y: (bounds.height - overlaySize) / 2,
            width: overlaySize,
            height: overlaySize
        )
        
        let spinnerSize: CGFloat = 20
        loadingIndicator.frame = NSRect(
            x: (bounds.width - spinnerSize) / 2,
            y: (bounds.height - spinnerSize) / 2,
            width: spinnerSize,
            height: spinnerSize
        )
        
        let skipW: CGFloat = 88
        let skipH: CGFloat = 26
        skipAdButton.frame = NSRect(
            x: bounds.width - skipW - 10,
            y: 10,
            width: skipW,
            height: skipH
        )
    }
    
    private func updatePlayOverlayIcon() {
        let symbolName = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 38, weight: .regular)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            playOverlay.image = img
            playOverlay.contentTintColor = NSColor(white: 1.0, alpha: 0.9)
        }
    }
    
    public func loadVideo(id: String, startSeconds: Double = 0) {
        guard !id.isEmpty else {
            clearVideo()
            return
        }
        
        browserCurrentTime = max(0.0, startSeconds)
        let effectiveStart = max(0.0, startSeconds - syncDelay)
        let startVal = effectiveStart
        panelCurrentTime = effectiveStart
        
        if currentVideoId == id {
            if isReady && !isAdActive {
                syncWithBrowser(targetTime: startVal, isPaused: !shouldBePlaying)
                if shouldBePlaying {
                    play()
                }
            }
            return
        }
        
        currentVideoId = id
        isReady = false
        isPlaying = false
        shouldBePlaying = true
        isAdActive = false
        duration = 0.0
        
        loadingIndicator.startAnimation(nil)
        thumbnailImageView.alphaValue = 1.0
        webView.alphaValue = 0.0
        skipAdButton.isHidden = true
        skipAdButton.alphaValue = 0.0
        
        loadHighResThumbnail(id: id)
        
        // Fast SPA video switch if webView is already on YouTube watch page
        let startInt = Int(startVal)
        let spaJS = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.loadVideoById) {
                p.loadVideoById({ videoId: '\(id)', startSeconds: \(startVal) });
                p.mute();
                p.playVideo();
                window._songTopInitialSynced = false;
                return true;
            }
            return false;
        })();
        """
        webView.evaluateJavaScript(spaJS) { [weak self] result, error in
            guard let self = self else { return }
            let didSPA = (result as? Bool) ?? false
            if !didSPA {
                if let targetURL = URL(string: "https://www.youtube.com/watch?v=\(id)&t=\(startInt)s") {
                    self.webView.load(URLRequest(url: targetURL))
                }
            }
        }
    }
    
    private func loadHighResThumbnail(id: String) {
        let maxResURL = URL(string: "https://img.youtube.com/vi/\(id)/maxresdefault.jpg")!
        let hqURL = URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")!
        
        URLSession.shared.dataTask(with: maxResURL) { [weak self] data, response, _ in
            guard let self = self else { return }
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
               let data = data, let img = NSImage(data: data), img.size.width > 120 {
                DispatchQueue.main.async {
                    self.thumbnailImageView.image = img
                }
            } else {
                URLSession.shared.dataTask(with: hqURL) { [weak self] data, _, _ in
                    guard let self = self, let data = data, let img = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self.thumbnailImageView.image = img
                    }
                }.resume()
            }
        }.resume()
    }
    
    public func clearVideo() {
        currentVideoId = nil
        isReady = false
        isPlaying = false
        isAdActive = false
        browserCurrentTime = 0.0
        panelCurrentTime = 0.0
        duration = 0.0
        thumbnailImageView.image = nil
        thumbnailImageView.alphaValue = 1.0
        webView.alphaValue = 0.0
        skipAdButton.isHidden = true
        skipAdButton.alphaValue = 0.0
        loadingIndicator.stopAnimation(nil)
        webView.loadHTMLString("about:blank", baseURL: nil)
    }
    
    public func updateFromTelemetry(cur: Double, dur: Double, paused: Bool, vol: Int, muted: Bool) {
        if dur > 0 { self.duration = dur }
        self.browserCurrentTime = cur
        
        let nowPlaying = !paused
        if self.isPlaying != nowPlaying {
            self.isPlaying = nowPlaying
            updatePlayOverlayIcon()
            onPlaybackStateChanged?(nowPlaying)
        }
        
        // Synchronize live playback with browser position
        if !isAdActive && cur >= 0 {
            syncWithBrowser(targetTime: cur, isPaused: paused)
        }
        
        self.volume = vol
        self.isMuted = muted
        onProgressUpdated?(self.currentTime, self.duration)
        onVolumeChanged?(vol, muted)
    }
    
    public func syncWithBrowser(targetTime: Double, isPaused: Bool) {
        guard isReady, !isAdActive, targetTime >= 0 else { return }
        let js = """
        (function() {
            if (typeof window._songTopSync === 'function') {
                window._songTopSync(\(targetTime), \(isPaused), \(syncDelay));
            } else {
                var effective = Math.max(0, \(targetTime) - \(syncDelay));
                var p = document.getElementById('movie_player');
                var v = document.querySelector('video.html5-main-video') || document.querySelector('video');
                if (v && Math.abs(v.currentTime - effective) > 1.0) {
                    v.currentTime = effective;
                }
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
    
    public func play() {
        shouldBePlaying = true
        isPlaying = true
        updatePlayOverlayIcon()
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.playVideo) { p.playVideo(); }
            var v = document.querySelector('video');
            if (v && v.paused) { v.play().catch(function(){}); }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
        onPlaybackStateChanged?(true)
    }
    
    public func pause() {
        shouldBePlaying = false
        isPlaying = false
        updatePlayOverlayIcon()
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.pauseVideo) { p.pauseVideo(); }
            var v = document.querySelector('video.html5-main-video') || document.querySelector('video');
            if (v && !v.paused) { v.pause(); }
            if (v) { v.playbackRate = 1.0; }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
        onPlaybackStateChanged?(false)
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func seekTo(seconds: Double) {
        browserCurrentTime = max(0, min(duration > 0 ? duration : 36000, seconds))
        syncSeekTo(browserCurrentTime)
        onProgressUpdated?(browserCurrentTime, duration)
    }
    
    public func syncSeekTo(_ seconds: Double) {
        let effective = max(0.0, seconds - syncDelay)
        panelCurrentTime = effective
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.seekTo) { p.seekTo(\(effective), true); }
            var v = document.querySelector('video.html5-main-video') || document.querySelector('video');
            if (v) {
                v.currentTime = \(effective);
                v.playbackRate = 1.0;
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
    
    public func skip(by seconds: Double) {
        seekTo(seconds: currentTime + seconds)
    }
    
    public func setVolume(volume: Int) {
        self.volume = max(0, min(100, volume))
        let fraction = Double(self.volume) / 100.0
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.setVolume) { p.setVolume(\(self.volume)); }
            var v = document.querySelector('video');
            if (v) { v.volume = \(fraction); }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
        onVolumeChanged?(self.volume, isMuted)
    }
    
    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p) {
                if (\(muted) && p.mute) { p.mute(); }
                else if (!\(muted) && p.unMute) { p.unMute(); }
            }
            var v = document.querySelector('video');
            if (v) { v.muted = \(muted); }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
        onVolumeChanged?(volume, isMuted)
    }
    
    public func toggleMute() {
        setMuted(!isMuted)
    }
    
    @objc public func handleSkipAdClicked() {
        skipAd()
    }
    
    public func skipAd() {
        let js = """
        (function() {
            var btns = document.querySelectorAll('.ytp-ad-skip-button-modern, .ytp-ad-skip-button, .videoAdUiSkipButton, .ytp-skip-ad-button, .ytp-ad-skip-button-container button');
            btns.forEach(function(b) { try { b.click(); } catch(e){} });
            
            var p = document.getElementById('movie_player');
            var v = document.querySelector('video.html5-main-video') || document.querySelector('video');
            if (p && (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting')) && v) {
                if (isFinite(v.duration) && v.duration > 0) {
                    v.currentTime = v.duration;
                }
            }
            return 'OK';
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.skipAdButton.animator().alphaValue = 0.0
        }
        
        // Resync playback with browser tab position after 0.4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            if self.browserCurrentTime > 0 {
                self.syncSeekTo(self.browserCurrentTime)
            }
        }
    }
    
    // MARK: - YouTubeVideoPlayerDelegate
    func handleBridgeMessage(_ body: Any) {
        guard let message = body as? String else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if message == "ready" {
                self.isReady = true
                self.loadingIndicator.stopAnimation(nil)
                if self.browserCurrentTime > 0 && !self.isAdActive {
                    self.syncWithBrowser(targetTime: self.browserCurrentTime, isPaused: !self.shouldBePlaying)
                }
                if self.shouldBePlaying {
                    self.play()
                } else {
                    self.pause()
                }
            } else if message == "state_1" { // Live video playing!
                self.isPlaying = true
                self.isReady = true
                self.loadingIndicator.stopAnimation(nil)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    self.thumbnailImageView.animator().alphaValue = 0.0
                    self.webView.animator().alphaValue = 1.0
                }
                self.onPlaybackStateChanged?(true)
                
                // Immediately align video with current browser audio position
                if self.browserCurrentTime > 0 && !self.isAdActive {
                    self.syncWithBrowser(targetTime: self.browserCurrentTime, isPaused: false)
                }
            } else if message == "state_2" { // Paused
                self.isPlaying = false
                self.onPlaybackStateChanged?(false)
            } else if message == "ad_detected" {
                if !self.isAdActive {
                    self.isAdActive = true
                    self.clickOverlay.isAdActive = true
                    self.skipAdButton.isHidden = false
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.2
                        self.skipAdButton.animator().alphaValue = 1.0
                    }
                }
            } else if message == "ad_cleared" {
                if self.isAdActive {
                    self.isAdActive = false
                    self.clickOverlay.isAdActive = false
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.2
                        self.skipAdButton.animator().alphaValue = 0.0
                    }, completionHandler: {
                        if !self.isAdActive {
                            self.skipAdButton.isHidden = true
                        }
                    })
                    // Resync to browser time immediately when ad finishes
                    if self.browserCurrentTime > 0 {
                        self.syncSeekTo(self.browserCurrentTime)
                    }
                }
            } else if message.hasPrefix("progress_") {
                let parts = message.dropFirst("progress_".count).split(separator: "_")
                if parts.count >= 2 {
                    if let cur = Double(parts[0]), let dur = Double(parts[1]) {
                        self.panelCurrentTime = cur
                        if dur > 0 { self.duration = dur }
                    }
                }
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.mute) { p.mute(); }
            var v = document.querySelector('video');
            if (v) { v.muted = true; }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimation(nil)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimation(nil)
    }
}
