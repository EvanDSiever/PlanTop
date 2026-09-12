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
    private var shouldBePlaying: Bool = true
    
    public var onVideoClicked: (() -> Void)?
    public var onPlaybackStateChanged: ((Bool) -> Void)?
    
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
    
    public func loadVideo(id: String) {
        guard !id.isEmpty else {
            clearVideo()
            return
        }
        
        if currentVideoId == id && isReady {
            if shouldBePlaying {
                play()
            }
            return
        }
        
        currentVideoId = id
        isReady = false
        isPlaying = false
        shouldBePlaying = true
        fallbackImageView.isHidden = true
        
        loadingIndicator.startAnimation(nil)
        loadingLabel.isHidden = false
        loadingLabel.stringValue = "Loading Video Preview..."
        
        loadFallbackThumbnail(id: id)
        
        let html = generatePlayerHTML(videoId: id)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }
    
    public func clearVideo() {
        currentVideoId = nil
        isReady = false
        isPlaying = false
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
    
    public func toggleMute() {
        isMuted.toggle()
        updateMuteButtonIcon()
        let js = isMuted ? "if (window.player && player.mute) player.mute();" : "if (window.player && player.unMute) player.unMute();"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    @objc private func handleMuteClicked() {
        toggleMute()
    }
    
    private func updateMuteButtonIcon() {
        let symbolName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let tooltip = isMuted ? "Preview Audio Muted (Click to Unmute)" : "Preview Audio Playing (Click to Mute)"
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
            } else if message.hasPrefix("error_") {
                // Video embedding restricted by copyright holder (e.g. error 150/101)
                self.loadingIndicator.stopAnimation(nil)
                self.loadingLabel.stringValue = "Thumbnail View (Author restricted embedding)"
                self.fallbackImageView.isHidden = false
            }
        }
    }
    
    private func generatePlayerHTML(videoId: String) -> String {
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
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            videoId: '\(videoId)',
            playerVars: {
              'autoplay': 1,
              'mute': 1,
              'controls': 0,
              'playsinline': 1,
              'loop': 1,
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
                e.target.playVideo();
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
