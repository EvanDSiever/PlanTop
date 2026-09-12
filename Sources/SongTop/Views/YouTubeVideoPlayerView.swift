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

public final class YouTubeVideoPlayerView: NSView, YouTubeVideoPlayerDelegate, WKNavigationDelegate {
    private var webView: WKWebView!
    private let loadingIndicator = NSProgressIndicator()
    private let loadingLabel = NSTextField(labelWithString: "Loading Video Stream...")
    private let fallbackImageView = NSImageView()
    private let muteButton = NSButton()
    
    public private(set) var currentVideoId: String?
    public private(set) var isMuted: Bool = true
    public private(set) var isPlaying: Bool = false
    public private(set) var isReady: Bool = false
    public private(set) var currentTime: Double = 0.0
    public private(set) var duration: Double = 0.0
    public private(set) var volume: Int = 100
    private var shouldBePlaying: Bool = true
    
    public var onVideoClicked: (() -> Void)?
    public var onPlaybackStateChanged: ((Bool) -> Void)?
    public var onProgressUpdated: ((Double, Double) -> Void)?
    public var onVolumeChanged: ((Int, Bool) -> Void)?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        setupAuthObserver()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupAuthObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "playerBridge")
    }
    
    private func setupAuthObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthChanged),
            name: .songTopYouTubeAuthChanged,
            object: nil
        )
    }
    
    @objc private func handleAuthChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let vid = self.currentVideoId else { return }
            // Reload with newly authenticated credentials (e.g. YouTube Premium)
            let curTime = self.currentTime
            self.clearVideo()
            self.loadVideo(id: vid, startSeconds: curTime)
        }
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // Fallback Image View
        fallbackImageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackImageView.wantsLayer = true
        fallbackImageView.layer?.cornerRadius = 12
        fallbackImageView.layer?.masksToBounds = true
        fallbackImageView.isHidden = true
        addSubview(fallbackImageView)
        
        // WebKit Configuration with Persistent Data Store (Preserves YouTube Premium & Logged-in accounts)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        
        let ucc = WKUserContentController()
        let proxy = ScriptMessageProxy(delegate: self)
        ucc.add(proxy, name: "playerBridge")
        
        // Injected CSS: Pins the video to 100vw x 100vh, eliminates all extraneous mastheads, sidebars, comments,
        // and hides all YouTube hover chrome (title, gradient, bottom controls) while keeping ad skip buttons fully interactive!
        let injectedCSS = """
        html, body, ytd-app, #content, #page-manager, ytd-watch-flexy, #columns, #primary, #primary-inner, #player, #player-container-outer, #player-container-inner, #player-container {
            margin: 0 !important;
            padding: 0 !important;
            overflow: hidden !important;
            width: 100vw !important;
            height: 100vh !important;
            background: #000 !important;
        }

        #masthead-container,
        #secondary,
        #below,
        #chat-container,
        ytd-miniplayer,
        #guide,
        tp-yt-app-drawer,
        #comments,
        ytd-watch-metadata,
        #related,
        ytd-merch-shelf-renderer,
        ytd-banner-promo-renderer,
        #clarify-box,
        #donation-shelf,
        #panels,
        #ticket-shelf,
        #actions,
        #meta,
        #info,
        ytd-engagement-panel-section-list-renderer,
        ytd-popup-container,
        #guide-wrapper,
        #voice-search-button,
        #search-form {
            display: none !important;
            visibility: hidden !important;
            pointer-events: none !important;
        }

        #movie_player,
        .html5-video-player,
        #player-theater-container {
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            width: 100vw !important;
            height: 100vh !important;
            max-width: 100vw !important;
            max-height: 100vh !important;
            z-index: 99999 !important;
            background: #000 !important;
        }

        video.html5-main-video {
            width: 100% !important;
            height: 100% !important;
            object-fit: contain !important;
        }

        .ytp-chrome-top,
        .ytp-title-text,
        .ytp-title-channel,
        .ytp-title,
        .ytp-gradient-top,
        .ytp-gradient-bottom,
        .ytp-chrome-bottom,
        .ytp-pause-overlay,
        .ytp-watermark,
        .ytp-ce-element,
        .ytp-cards-button,
        .ytp-cards-teaser,
        .ytp-bezel,
        .ytp-bezel-text,
        .ytp-expand-pause-overlay,
        .ytp-paid-content-overlay {
            opacity: 0 !important;
            visibility: hidden !important;
            pointer-events: none !important;
        }

        .ytp-ad-module,
        .ytp-ad-skip-button-container,
        .ytp-ad-skip-button-modern,
        .ytp-ad-skip-button,
        .ytp-ad-overlay-container,
        .ytp-ad-text,
        .videoAdUiSkipButton,
        .ytp-ad-preview-container {
            display: block !important;
            visibility: visible !important;
            opacity: 1 !important;
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
        let cssScript = WKUserScript(source: styleInjectionJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(cssScript)
        
        // Injected JS: Polling HTML5 video element, auto-skipping ads, handling click interactions
        let injectedBridgeJS = """
        (function() {
            if (window._songTopInjected) return;
            window._songTopInjected = true;

            function getPlayer() {
                return document.getElementById('movie_player');
            }

            function getVideo() {
                return document.querySelector('video.html5-main-video') || document.querySelector('video');
            }

            function autoSkipAds() {
                var skipBtn = document.querySelector('.ytp-ad-skip-button-modern, .ytp-ad-skip-button, .videoAdUiSkipButton, .ytp-skip-ad-button');
                if (skipBtn) {
                    try { skipBtn.click(); } catch(e) {}
                }
            }

            document.addEventListener('click', function(e) {
                if (e.target && e.target.closest && e.target.closest('.ytp-ad-skip-button-modern, .ytp-ad-skip-button, .videoAdUiSkipButton, .ytp-skip-ad-button, .ytp-ad-module')) {
                    return;
                }
                try {
                    window.webkit.messageHandlers.playerBridge.postMessage('videoClicked');
                } catch(err) {}
            }, true);

            var lastPlayingState = null;
            var readyNotified = false;

            setInterval(function() {
                autoSkipAds();

                var v = getVideo();
                var p = getPlayer();

                if (v) {
                    if (!readyNotified && v.readyState >= 1) {
                        readyNotified = true;
                        try {
                            window.webkit.messageHandlers.playerBridge.postMessage('ready');
                        } catch(e) {}
                    }

                    var isPlaying = (!v.paused && !v.ended && v.readyState > 2);
                    var stateMsg = isPlaying ? 'state_1' : 'state_2';
                    if (stateMsg !== lastPlayingState) {
                        lastPlayingState = stateMsg;
                        try {
                            window.webkit.messageHandlers.playerBridge.postMessage(stateMsg);
                        } catch(e) {}
                    }

                    var cur = v.currentTime || 0;
                    var dur = v.duration || (p && p.getDuration ? p.getDuration() : 0) || 0;
                    var vol = Math.round((v.volume || 0) * 100);
                    var muted = v.muted ? 1 : 0;

                    try {
                        window.webkit.messageHandlers.playerBridge.postMessage('progress_' + cur.toFixed(1) + '_' + dur.toFixed(1) + '_' + vol + '_' + muted);
                    } catch(e) {}
                }
            }, 250);
        })();
        """
        let bridgeScript = WKUserScript(source: injectedBridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        ucc.addUserScript(bridgeScript)
        
        config.userContentController = ucc
        
        webView = WKWebView(frame: bounds, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 12
        webView.layer?.masksToBounds = true
        webView.navigationDelegate = self
        // Standard Desktop Safari User-Agent avoids Google OAuth blocks and renders desktop layout
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        addSubview(webView)
        
        // Loading Spinner
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        addSubview(loadingIndicator)
        
        // Loading Label
        loadingLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        loadingLabel.textColor = NSColor(white: 1.0, alpha: 0.6)
        loadingLabel.alignment = .center
        addSubview(loadingLabel)
        
        // Mute / Unmute Button Overlay
        muteButton.isBordered = false
        muteButton.wantsLayer = true
        muteButton.layer?.cornerRadius = 12
        muteButton.layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.65).cgColor
        muteButton.target = self
        muteButton.action = #selector(handleMuteClicked)
        updateMuteButtonIcon()
        addSubview(muteButton)
    }
    
    public override func layout() {
        super.layout()
        fallbackImageView.frame = bounds
        webView.frame = bounds
        
        let spinnerSize: CGFloat = 20
        loadingIndicator.frame = NSRect(
            x: (bounds.width - spinnerSize) / 2,
            y: (bounds.height / 2) + 2,
            width: spinnerSize,
            height: spinnerSize
        )
        loadingLabel.frame = NSRect(
            x: 10,
            y: (bounds.height / 2) - 22,
            width: bounds.width - 20,
            height: 16
        )
        
        let btnSize: CGFloat = 26
        muteButton.frame = NSRect(
            x: bounds.width - btnSize - 8,
            y: bounds.height - btnSize - 8,
            width: btnSize,
            height: btnSize
        )
    }
    
    public func loadVideo(id: String, startSeconds: Double = 0) {
        guard !id.isEmpty else {
            clearVideo()
            return
        }
        
        let startVal = max(0, Int(startSeconds))
        
        if currentVideoId == id && isReady {
            if startSeconds > 0 && abs(currentTime - startSeconds) > 3 {
                seekTo(seconds: startSeconds)
            }
            if shouldBePlaying {
                play()
            }
            return
        }
        
        currentVideoId = id
        isReady = false
        isPlaying = false
        shouldBePlaying = true
        currentTime = startSeconds
        duration = 0.0
        fallbackImageView.isHidden = true
        
        loadingIndicator.startAnimation(nil)
        loadingLabel.isHidden = false
        loadingLabel.stringValue = "Loading Video Preview..."
        
        loadFallbackThumbnail(id: id)
        
        // If webView is already on youtube.com, perform instant SPA player switch
        if let host = webView.url?.host, host.contains("youtube.com") {
            let spaJS = """
            (function() {
                var p = document.getElementById('movie_player');
                if (p && p.loadVideoById) {
                    p.loadVideoById({ videoId: '\(id)', startSeconds: \(startVal) });
                    if (\(isMuted) && p.mute) { p.mute(); }
                    return true;
                } else {
                    window.location.href = 'https://www.youtube.com/watch?v=\(id)&t=\(startVal)s';
                    return false;
                }
            })();
            """
            webView.evaluateJavaScript(spaJS) { [weak self] res, error in
                guard let self = self else { return }
                if error != nil {
                    if let targetURL = URL(string: "https://www.youtube.com/watch?v=\(id)&t=\(startVal)s") {
                        self.webView.load(URLRequest(url: targetURL))
                    }
                }
            }
        } else {
            if let targetURL = URL(string: "https://www.youtube.com/watch?v=\(id)&t=\(startVal)s") {
                webView.load(URLRequest(url: targetURL))
            }
        }
    }
    
    public func clearVideo() {
        currentVideoId = nil
        isReady = false
        isPlaying = false
        currentTime = 0.0
        duration = 0.0
        loadingIndicator.stopAnimation(nil)
        loadingLabel.isHidden = true
        fallbackImageView.isHidden = true
        fallbackImageView.image = nil
        webView.loadHTMLString("about:blank", baseURL: nil)
    }
    
    public func play() {
        shouldBePlaying = true
        guard isReady else { return }
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.playVideo) { p.playVideo(); }
            var v = document.querySelector('video');
            if (v && v.paused) { v.play().catch(function(){}); }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
        isPlaying = true
        onPlaybackStateChanged?(true)
    }
    
    public func pause() {
        shouldBePlaying = false
        guard isReady else { return }
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.pauseVideo) { p.pauseVideo(); }
            var v = document.querySelector('video');
            if (v && !v.paused) { v.pause(); }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
        isPlaying = false
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
        let target = max(0, min(duration > 0 ? duration : 36000, seconds))
        currentTime = target
        guard isReady else { return }
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.seekTo) { p.seekTo(\(target), true); }
            var v = document.querySelector('video');
            if (v) { v.currentTime = \(target); }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    public func skip(by seconds: Double) {
        seekTo(seconds: currentTime + seconds)
    }
    
    public func setVolume(volume: Int) {
        let clamped = max(0, min(100, volume))
        self.volume = clamped
        guard isReady else { return }
        let fraction = Double(clamped) / 100.0
        let js = """
        (function() {
            var p = document.getElementById('movie_player');
            if (p && p.setVolume) { p.setVolume(\(clamped)); }
            var v = document.querySelector('video');
            if (v) { v.volume = \(fraction); }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
        onVolumeChanged?(clamped, isMuted)
    }
    
    public func setMuted(_ muted: Bool) {
        isMuted = muted
        updateMuteButtonIcon()
        guard isReady else { return }
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
        webView.evaluateJavaScript(js, completionHandler: nil)
        onVolumeChanged?(volume, isMuted)
    }
    
    public func toggleMute() {
        setMuted(!isMuted)
    }
    
    @objc private func handleMuteClicked() {
        toggleMute()
    }
    
    private func updateMuteButtonIcon() {
        let symbolName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let tooltip = isMuted ? "Audio Muted (Click to Unmute)" : "Audio Playing (Click to Mute)"
        muteButton.toolTip = tooltip
        
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            muteButton.image = img
            muteButton.imagePosition = .imageOnly
            muteButton.contentTintColor = isMuted ? NSColor(white: 0.8, alpha: 1.0) : .systemGreen
        }
    }
    
    private func loadFallbackThumbnail(id: String) {
        guard let url = URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.fallbackImageView.image = img
            }
        }.resume()
    }
    
    // MARK: - YouTubeVideoPlayerDelegate
    func handleBridgeMessage(_ body: Any) {
        guard let message = body as? String else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if message == "videoClicked" {
                self.onVideoClicked?()
            } else if message == "ready" {
                self.isReady = true
                self.loadingIndicator.stopAnimation(nil)
                self.loadingLabel.isHidden = true
                if self.shouldBePlaying {
                    self.play()
                } else {
                    self.pause()
                }
                if self.isMuted {
                    self.setMuted(true)
                }
            } else if message == "state_1" { // Playing
                self.isPlaying = true
                self.shouldBePlaying = true
                self.loadingIndicator.stopAnimation(nil)
                self.loadingLabel.isHidden = true
                self.fallbackImageView.isHidden = true
                self.onPlaybackStateChanged?(true)
            } else if message == "state_2" { // Paused
                self.isPlaying = false
                self.shouldBePlaying = false
                self.onPlaybackStateChanged?(false)
            } else if message.hasPrefix("progress_") {
                let parts = message.dropFirst("progress_".count).split(separator: "_")
                if parts.count >= 4 {
                    if let cur = Double(parts[0]), let dur = Double(parts[1]), let vol = Int(parts[2]), let muted = Int(parts[3]) {
                        self.currentTime = cur
                        if dur > 0 { self.duration = dur }
                        self.volume = vol
                        self.isMuted = (muted == 1)
                        self.updateMuteButtonIcon()
                        self.onProgressUpdated?(cur, self.duration)
                    }
                }
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Enforce muted state if needed
        if isMuted {
            setMuted(true)
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimation(nil)
        fallbackImageView.isHidden = false
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimation(nil)
        fallbackImageView.isHidden = false
    }
}
