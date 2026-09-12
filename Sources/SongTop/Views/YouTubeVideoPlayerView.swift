import AppKit

public final class YouTubeVideoPlayerView: NSView {
    private let thumbnailImageView = NSImageView()
    private let playOverlay = NSImageView()
    private let loadingIndicator = NSProgressIndicator()
    
    public private(set) var currentVideoId: String?
    public private(set) var isMuted: Bool = false
    public private(set) var isPlaying: Bool = true
    public private(set) var isReady: Bool = false
    public private(set) var currentTime: Double = 0.0
    public private(set) var duration: Double = 0.0
    public private(set) var volume: Int = 100
    
    public var onVideoClicked: (() -> Void)?
    public var onPlaybackStateChanged: ((Bool) -> Void)?
    public var onProgressUpdated: ((Double, Double) -> Void)?
    public var onVolumeChanged: ((Int, Bool) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // Crisp Video Artwork / Thumbnail
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.wantsLayer = true
        thumbnailImageView.layer?.cornerRadius = 12
        thumbnailImageView.layer?.masksToBounds = true
        addSubview(thumbnailImageView)
        
        // Subtle Centered Play/Pause Indicator (Fades in slightly on hover)
        playOverlay.wantsLayer = true
        playOverlay.alphaValue = 0.0
        updatePlayOverlayIcon()
        addSubview(playOverlay)
        
        // Loading Spinner
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        addSubview(loadingIndicator)
    }
    
    public override func layout() {
        super.layout()
        thumbnailImageView.frame = bounds
        
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
    }
    
    public override func updateTrackingAreas() {
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
    
    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            playOverlay.animator().alphaValue = 0.85
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            playOverlay.animator().alphaValue = 0.0
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onVideoClicked?()
        }
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
        
        if currentVideoId == id {
            currentTime = startSeconds
            return
        }
        
        currentVideoId = id
        isReady = false
        currentTime = startSeconds
        loadingIndicator.startAnimation(nil)
        
        loadHighResThumbnail(id: id)
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
                    self.loadingIndicator.stopAnimation(nil)
                    self.isReady = true
                }
            } else {
                // Fallback to HQ thumbnail
                URLSession.shared.dataTask(with: hqURL) { [weak self] data, _, _ in
                    guard let self = self, let data = data, let img = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self.thumbnailImageView.image = img
                        self.loadingIndicator.stopAnimation(nil)
                        self.isReady = true
                    }
                }.resume()
            }
        }.resume()
    }
    
    public func clearVideo() {
        currentVideoId = nil
        isReady = false
        isPlaying = false
        currentTime = 0.0
        duration = 0.0
        thumbnailImageView.image = nil
        loadingIndicator.stopAnimation(nil)
    }
    
    public func updateFromTelemetry(cur: Double, dur: Double, paused: Bool, vol: Int, muted: Bool) {
        self.currentTime = cur
        if dur > 0 { self.duration = dur }
        let nowPlaying = !paused
        if self.isPlaying != nowPlaying {
            self.isPlaying = nowPlaying
            updatePlayOverlayIcon()
            onPlaybackStateChanged?(nowPlaying)
        }
        self.volume = vol
        self.isMuted = muted
        onProgressUpdated?(cur, self.duration)
        onVolumeChanged?(vol, muted)
    }
    
    public func play() {
        isPlaying = true
        updatePlayOverlayIcon()
        onPlaybackStateChanged?(true)
    }
    
    public func pause() {
        isPlaying = false
        updatePlayOverlayIcon()
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
        currentTime = max(0, min(duration > 0 ? duration : 36000, seconds))
        onProgressUpdated?(currentTime, duration)
    }
    
    public func skip(by seconds: Double) {
        seekTo(seconds: currentTime + seconds)
    }
    
    public func setVolume(volume: Int) {
        self.volume = max(0, min(100, volume))
        onVolumeChanged?(self.volume, isMuted)
    }
    
    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        onVolumeChanged?(volume, isMuted)
    }
    
    public func toggleMute() {
        setMuted(!isMuted)
    }
}
