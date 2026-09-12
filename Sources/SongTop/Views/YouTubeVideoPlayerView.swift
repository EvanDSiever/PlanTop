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

final class VideoClickOverlayView: NSView {
    var onClicked: (() -> Void)?
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClicked?()
        }
    }
}

public final class YouTubeVideoPlayerView: NSView, YouTubeVideoPlayerDelegate {
    private var webView: WKWebView!
    private let clickOverlay = VideoClickOverlayView()
    private let loadingIndicator = NSProgressIndicator()
    private let loadingLabel = NSTextField(labelWithString: "Loading Video Preview...")
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
        
        // Fallback Image View
        fallbackImageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackImageView.wantsLayer = true
        fallbackImageView.layer?.cornerRadius = 12
        fallbackImageView.layer?.masksToBounds = true
        fallbackImageView.isHidden = true
        addSubview(fallbackImageView)
        
        // WebKit Configuration
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        
        let ucc = WKUserContentController()
        let proxy = ScriptMessageProxy(delegate: self)
        ucc.add(proxy, name: "playerBridge")
        config.userContentController = ucc
        
        webView = WKWebView(frame: bounds, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 12
        webView.layer?.masksToBounds = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        addSubview(webView)
        
        // Transparent Click Overlay:
        // Sits on top of the webView so YouTube never receives mouse hover events,
        // eliminating all YouTube hover chrome/titles/pause buttons, while allowing clicks to toggle play/pause!
        clickOverlay.wantsLayer = true
        clickOverlay.onClicked = { [weak self] in
            self?.onVideoClicked?()
        }
        addSubview(clickOverlay)
        
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
        clickOverlay.frame = bounds
        window?.invalidateCursorRects(for: clickOverlay)
        
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
        
        let html = generatePlayerHTML(videoId: id, startSeconds: startSeconds)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
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
        webView.evaluateJavaScript("if (window.player && player.playVideo) { player.playVideo(); }", completionHandler: nil)
        isPlaying = true
        onPlaybackStateChanged?(true)
    }
    
    public func pause() {
        shouldBePlaying = false
        guard isReady else { return }
        webView.evaluateJavaScript("if (window.player && player.pauseVideo) { player.pauseVideo(); }", completionHandler: nil)
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
        webView.evaluateJavaScript("if (window.player && player.seekTo) { player.seekTo(\(target), true); }", completionHandler: nil)
    }
    
    public func skip(by seconds: Double) {
        seekTo(seconds: currentTime + seconds)
    }
    
    public func setVolume(volume: Int) {
        let clamped = max(0, min(100, volume))
        self.volume = clamped
        guard isReady else { return }
        webView.evaluateJavaScript("if (window.player && player.setVolume) { player.setVolume(\(clamped)); }", completionHandler: nil)
        onVolumeChanged?(clamped, isMuted)
    }
    
    public func setMuted(_ muted: Bool) {
        isMuted = muted
        updateMuteButtonIcon()
        guard isReady else { return }
        let js = muted ? "if (window.player && player.mute) player.mute();" : "if (window.player && player.unMute) player.unMute();"
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
    
    // YouTubeVideoPlayerDelegate
    func handleBridgeMessage(_ body: Any) {
        guard let message = body as? String else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if message == "ready" {
                self.isReady = true
                self.loadingIndicator.stopAnimation(nil)
                self.loadingLabel.isHidden = true
                if self.shouldBePlaying {
                    self.play()
                } else {
                    self.pause()
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
                // Format: progress_CURRENT_DURATION_VOLUME_MUTED
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
            } else if message.hasPrefix("error_") {
                // Video embedding restricted by copyright holder (e.g. error 150/101)
                self.loadingIndicator.stopAnimation(nil)
                self.loadingLabel.stringValue = "Thumbnail View (Author restricted embedding)"
                self.fallbackImageView.isHidden = false
            }
        }
    }
    
    private func generatePlayerHTML(videoId: String, startSeconds: Double = 0) -> String {
        let startVal = max(0, Int(startSeconds))
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <style>
        * { margin:0; padding:0; box-sizing:border-box; user-select:none; -webkit-user-select:none; }
        body, html { width:100%; height:100%; overflow:hidden; background:#0d0d11; display:flex; align-items:center; justify-content:center; }
        #player, iframe { width:100vw; height:100vh; object-fit:cover; pointer-events:none !important; border:none; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        var progressInterval = null;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            videoId: '\(videoId)',
            playerVars: {
              'autoplay': 1,
              'mute': 1,
              'controls': 0,
              'playsinline': 1,
              'loop': 1,
              'start': \(startVal),
              'playlist': '\(videoId)',
              'disablekb': 1,
              'fs': 0,
              'rel': 0,
              'modestbranding': 1,
              'iv_load_policy': 3,
              'origin': 'https://www.youtube-nocookie.com'
            },
            events: {
              'onReady': function(e) {
                window.webkit.messageHandlers.playerBridge.postMessage("ready");
                e.target.mute();
                if (\(startVal) > 0) {
                  try { e.target.seekTo(\(startVal), true); } catch(err) {}
                }
                e.target.playVideo();
                
                if (!progressInterval) {
                  progressInterval = setInterval(function() {
                    if (player && player.getCurrentTime) {
                      try {
                        var cur = player.getCurrentTime() || 0;
                        var dur = player.getDuration() || 0;
                        var vol = player.getVolume ? player.getVolume() : 100;
                        var muted = player.isMuted ? (player.isMuted() ? 1 : 0) : 1;
                        window.webkit.messageHandlers.playerBridge.postMessage("progress_" + cur.toFixed(1) + "_" + dur.toFixed(1) + "_" + vol + "_" + muted);
                      } catch(err) {}
                    }
                  }, 250);
                }
              },
              'onStateChange': function(e) {
                window.webkit.messageHandlers.playerBridge.postMessage("state_" + e.data);
              },
              'onError': function(e) {
                window.webkit.messageHandlers.playerBridge.postMessage("error_" + e.data);
              }
            }
          });
        }
        </script>
        </body>
        </html>
        """
    }
}
