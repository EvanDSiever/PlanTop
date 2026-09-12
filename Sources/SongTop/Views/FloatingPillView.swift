import AppKit

final class ResizeHandleView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
    
    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }
    
    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }
}

public final class FloatingPillView: NSView {
    private let clipContainer = NSView()
    private let visualEffectView = NSVisualEffectView()
    private let resizeHandle = ResizeHandleView()
    private let gripBar = NSView()
    private let badgeContainer = NSView()
    private let equalizerView = EqualizerView(barColor: .white)
    
    // Video Player
    private let videoPlayerView = YouTubeVideoPlayerView()
    public var isVideoPreviewEnabled: Bool = true {
        didSet {
            update(with: currentTrack)
        }
    }
    
    // Playhead Scrubber Controls
    private let scrubberSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let currentTimeLabel = NSTextField(labelWithString: "00:00")
    private let durationLabel = NSTextField(labelWithString: "00:00")
    private var isUserScrubbing: Bool = false
    public var onSeekRequested: ((Double) -> Void)?
    
    // Transport & Audio Controls
    private let skipBackButton = NSButton()
    private let skipForwardButton = NSButton()
    private let volumeButton = NSButton()
    private let volumeSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var seekDebounceTimer: Timer?
    
    // Dynamic Drag-Scaling Support
    public var preferredPanelWidth: CGFloat = 340
    public var onResizeWidthChanged: ((CGFloat) -> Void)?
    public var onResizeCompleted: (() -> Void)?
    private var isDraggingResize: Bool = false
    private var dragStartMouseX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    
    // Pin Control
    private let pinButton = NSButton()
    public var isPinned: Bool = false {
        didSet {
            updatePinButtonIcon()
        }
    }
    public var onTogglePin: (() -> Void)?
    
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let browserBadge = NSTextField(labelWithString: "")
    
    private let playPauseButton = NSButton()
    private let openButton = NSButton()
    private let copyButton = NSButton()
    private let closeButton = NSButton()
    
    private var trackingArea: NSTrackingArea?
    public private(set) var isStretchedOut: Bool = false
    
    public var onOpenTab: (() -> Void)?
    public var onCopyTitle: (() -> Void)?
    public var onTogglePlayPause: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var onHoverStateChanged: ((Bool) -> Void)?
    
    private var currentTrack: TrackInfo?
    
    public var currentTime: Double {
        return videoPlayerView.currentTime
    }
    
    public var duration: Double {
        return videoPlayerView.duration
    }
    
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
        layer?.masksToBounds = false
        
        // Clip container masks the drawer sliding in from the right edge
        clipContainer.wantsLayer = true
        clipContainer.layer?.masksToBounds = true
        addSubview(clipContainer)
        
        // Background Frosted Glass
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.2
        visualEffectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.22).cgColor
        visualEffectView.appearance = NSAppearance(named: .darkAqua)
        clipContainer.addSubview(visualEffectView)
        
        // Left Edge Drawer Accent Grip Bar & Interactive Resize Handle
        resizeHandle.wantsLayer = true
        resizeHandle.onMouseDown = { [weak self] event in
            guard let self = self else { return }
            self.isDraggingResize = true
            self.dragStartMouseX = NSEvent.mouseLocation.x
            self.dragStartWidth = self.bounds.width
        }
        resizeHandle.onMouseDragged = { [weak self] event in
            guard let self = self, self.isDraggingResize else { return }
            let currentMouseX = NSEvent.mouseLocation.x
            let delta = self.dragStartMouseX - currentMouseX
            let targetWidth = max(260, min(650, self.dragStartWidth + delta))
            self.preferredPanelWidth = targetWidth
            self.onResizeWidthChanged?(targetWidth)
        }
        resizeHandle.onMouseUp = { [weak self] event in
            guard let self = self, self.isDraggingResize else { return }
            self.isDraggingResize = false
            self.onResizeCompleted?()
        }
        visualEffectView.addSubview(resizeHandle)
        
        gripBar.wantsLayer = true
        gripBar.layer?.cornerRadius = 2
        gripBar.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.45).cgColor
        resizeHandle.addSubview(gripBar)
        
        // Video Player View (16:9 Live Preview)
        videoPlayerView.wantsLayer = true
        videoPlayerView.layer?.cornerRadius = 12
        videoPlayerView.layer?.masksToBounds = true
        videoPlayerView.isHidden = true
        videoPlayerView.onVideoClicked = { [weak self] in
            self?.togglePlayPause()
        }
        videoPlayerView.onPlaybackStateChanged = { [weak self] isPlaying in
            self?.updatePlayPauseState(isPlaying: isPlaying)
        }
        videoPlayerView.onProgressUpdated = { [weak self] cur, dur in
            self?.handlePlayerProgress(cur: cur, dur: dur)
        }
        videoPlayerView.onVolumeChanged = { [weak self] vol, isMuted in
            self?.updateVolumeUI(vol: vol, isMuted: isMuted)
        }
        visualEffectView.addSubview(videoPlayerView)
        
        // Scrubber / Timeline Bar
        scrubberSlider.isContinuous = true
        scrubberSlider.target = self
        scrubberSlider.action = #selector(handleScrubberChanged)
        visualEffectView.addSubview(scrubberSlider)
        
        currentTimeLabel.isBezeled = false
        currentTimeLabel.drawsBackground = false
        currentTimeLabel.isEditable = false
        currentTimeLabel.isSelectable = false
        currentTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        currentTimeLabel.textColor = NSColor(white: 1.0, alpha: 0.8)
        visualEffectView.addSubview(currentTimeLabel)
        
        durationLabel.isBezeled = false
        durationLabel.drawsBackground = false
        durationLabel.isEditable = false
        durationLabel.isSelectable = false
        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        durationLabel.textColor = NSColor(white: 1.0, alpha: 0.55)
        durationLabel.alignment = .right
        visualEffectView.addSubview(durationLabel)
        
        // Skip Buttons
        configureIconButton(skipBackButton, symbol: "gobackward.10", tooltip: "Skip Back 10 Seconds")
        skipBackButton.target = self
        skipBackButton.action = #selector(handleSkipBack)
        visualEffectView.addSubview(skipBackButton)
        
        configureIconButton(skipForwardButton, symbol: "goforward.10", tooltip: "Skip Forward 10 Seconds")
        skipForwardButton.target = self
        skipForwardButton.action = #selector(handleSkipForward)
        visualEffectView.addSubview(skipForwardButton)
        
        // Volume Control
        configureIconButton(volumeButton, symbol: "speaker.wave.2.fill", tooltip: "Toggle Audio Mute")
        volumeButton.target = self
        volumeButton.action = #selector(handleVolumeButton)
        visualEffectView.addSubview(volumeButton)
        
        volumeSlider.isContinuous = true
        volumeSlider.target = self
        volumeSlider.action = #selector(handleVolumeSliderChanged)
        visualEffectView.addSubview(volumeSlider)
        
        // Red Icon Circle
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 13
        badgeContainer.layer?.backgroundColor = NSColor(red: 0.92, green: 0.1, blue: 0.14, alpha: 1.0).cgColor
        badgeContainer.layer?.shadowColor = NSColor.red.cgColor
        badgeContainer.layer?.shadowOpacity = 0.5
        badgeContainer.layer?.shadowRadius = 8
        badgeContainer.layer?.shadowOffset = CGSize(width: 0, height: -1)
        visualEffectView.addSubview(badgeContainer)
        
        // Equalizer in Icon Circle
        equalizerView.frame = NSRect(x: 2, y: 5, width: 22, height: 16)
        badgeContainer.addSubview(equalizerView)
        equalizerView.startAnimating()
        
        // Title Label
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        visualEffectView.addSubview(titleLabel)
        
        // Browser Badge
        browserBadge.isBezeled = false
        browserBadge.drawsBackground = true
        browserBadge.backgroundColor = NSColor(white: 1.0, alpha: 0.16)
        browserBadge.isEditable = false
        browserBadge.isSelectable = false
        browserBadge.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        browserBadge.textColor = NSColor(white: 1.0, alpha: 0.88)
        browserBadge.alignment = .center
        browserBadge.wantsLayer = true
        browserBadge.layer?.cornerRadius = 4
        browserBadge.layer?.masksToBounds = true
        visualEffectView.addSubview(browserBadge)
        
        // Artist / Channel Label
        artistLabel.isBezeled = false
        artistLabel.drawsBackground = false
        artistLabel.isEditable = false
        artistLabel.isSelectable = false
        artistLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        artistLabel.textColor = NSColor(white: 1.0, alpha: 0.72)
        artistLabel.lineBreakMode = .byTruncatingTail
        visualEffectView.addSubview(artistLabel)
        
        // Pin Button
        configureIconButton(pinButton, symbol: "pin", tooltip: "Pin Panel on Screen")
        pinButton.target = self
        pinButton.action = #selector(handlePinToggle)
        visualEffectView.addSubview(pinButton)
        updatePinButtonIcon()
        
        // Play / Pause Button
        configureIconButton(playPauseButton, symbol: "pause.fill", tooltip: "Play / Pause Video")
        playPauseButton.target = self
        playPauseButton.action = #selector(handlePlayPause)
        visualEffectView.addSubview(playPauseButton)
        
        // Open Tab Button
        configureIconButton(openButton, symbol: "arrow.up.forward.app", tooltip: "Bring YouTube Tab to Front")
        openButton.target = self
        openButton.action = #selector(handleOpen)
        visualEffectView.addSubview(openButton)
        
        // Copy Title Button
        configureIconButton(copyButton, symbol: "doc.on.doc", tooltip: "Copy Song Title")
        copyButton.target = self
        copyButton.action = #selector(handleCopy)
        visualEffectView.addSubview(copyButton)
        
        // Close Button (Chevron Right indicates sliding back into right edge)
        configureIconButton(closeButton, symbol: "chevron.right", tooltip: "Retract Side Panel")
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        visualEffectView.addSubview(closeButton)
    }
    
    // Left Edge Drag-Resize Cursor Support
    public override func resetCursorRects() {
        super.resetCursorRects()
        let resizeRect = NSRect(x: 0, y: 0, width: 18, height: bounds.height)
        addCursorRect(resizeRect, cursor: .resizeLeftRight)
    }
    
    public override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if localPoint.x <= 18 {
            isDraggingResize = true
            dragStartMouseX = NSEvent.mouseLocation.x
            dragStartWidth = bounds.width
            return
        }
        super.mouseDown(with: event)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        if isDraggingResize {
            let currentMouseX = NSEvent.mouseLocation.x
            let delta = dragStartMouseX - currentMouseX
            let targetWidth = max(260, min(650, dragStartWidth + delta))
            preferredPanelWidth = targetWidth
            onResizeWidthChanged?(targetWidth)
            return
        }
        super.mouseDragged(with: event)
    }
    
    public override func mouseUp(with event: NSEvent) {
        if isDraggingResize {
            isDraggingResize = false
            onResizeCompleted?()
            return
        }
        super.mouseUp(with: event)
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
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverStateChanged?(true)
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverStateChanged?(false)
    }
    
    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        button.toolTip = tooltip
        
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            button.image = img
            button.imagePosition = .imageOnly
            button.contentTintColor = .white
        }
    }
    
    private func updatePinButtonIcon() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        let tooltip = isPinned ? "Unpin Panel (Auto-Retract on Mouse Leave)" : "Pin Panel on Screen (Keep Permanently Visible)"
        pinButton.toolTip = tooltip
        
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            pinButton.image = img
            pinButton.imagePosition = .imageOnly
            pinButton.contentTintColor = isPinned ? NSColor(red: 0.1, green: 0.85, blue: 1.0, alpha: 1.0) : .white
        }
        pinButton.layer?.backgroundColor = isPinned
            ? NSColor(red: 0.1, green: 0.85, blue: 1.0, alpha: 0.28).cgColor
            : NSColor(white: 1.0, alpha: 0.14).cgColor
    }
    
    public func update(with track: TrackInfo?) {
        self.currentTrack = track
        
        let hasVideo = isVideoPreviewEnabled && (track?.isVideo ?? false)
        
        if let track = track {
            titleLabel.stringValue = track.title
            artistLabel.stringValue = track.artist.isEmpty ? "YouTube Audio" : track.artist
            browserBadge.stringValue = " \(track.browser) "
            browserBadge.isHidden = false
            browserBadge.sizeToFit()
            
            badgeContainer.layer?.backgroundColor = NSColor(red: 0.92, green: 0.1, blue: 0.14, alpha: 1.0).cgColor
            equalizerView.startAnimating()
            copyButton.isHidden = false
            playPauseButton.isHidden = false
            updatePlayPauseState(isPlaying: true)
            openButton.toolTip = "Bring YouTube Tab to Front (\(track.browser))"
            
            if hasVideo, let vid = track.youtubeVideoId {
                videoPlayerView.isHidden = false
                videoPlayerView.loadVideo(id: vid, startSeconds: track.startSeconds ?? 0)
                if isStretchedOut {
                    videoPlayerView.play()
                }
            } else {
                videoPlayerView.isHidden = true
                videoPlayerView.clearVideo()
            }
        } else {
            titleLabel.stringValue = "No YouTube Audio Playing"
            artistLabel.stringValue = "Play music in Chrome, Safari, Brave, or Arc"
            browserBadge.isHidden = true
            currentTimeLabel.stringValue = "00:00"
            durationLabel.stringValue = "00:00"
            scrubberSlider.doubleValue = 0
            
            badgeContainer.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1.0).cgColor
            equalizerView.stopAnimating()
            copyButton.isHidden = true
            playPauseButton.isHidden = true
            updatePlayPauseState(isPlaying: false)
            openButton.toolTip = "Open YouTube"
            
            videoPlayerView.isHidden = true
            videoPlayerView.clearVideo()
        }
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        clipContainer.frame = bounds
        
        if isStretchedOut {
            visualEffectView.frame = bounds
        } else {
            visualEffectView.frame = NSRect(x: bounds.width, y: 0, width: bounds.width, height: bounds.height)
        }
        
        let hasVideo = isVideoPreviewEnabled && (currentTrack?.isVideo ?? false)
        let gripHeight: CGFloat = hasVideo ? 50 : 28
        resizeHandle.frame = NSRect(x: 0, y: 0, width: 18, height: bounds.height)
        gripBar.frame = NSRect(x: 5, y: (bounds.height - gripHeight) / 2, width: 3.5, height: gripHeight)
        window?.invalidateCursorRects(for: resizeHandle)
        
        if hasVideo {
            // Show video, scrubber, and transport controls
            videoPlayerView.isHidden = false
            scrubberSlider.isHidden = false
            currentTimeLabel.isHidden = false
            durationLabel.isHidden = false
            skipBackButton.isHidden = false
            skipForwardButton.isHidden = false
            volumeButton.isHidden = false
            volumeSlider.isHidden = false
            
            let padLeft: CGFloat = 18
            let padRight: CGFloat = 14
            let videoW = bounds.width - padLeft - padRight
            let videoH = videoW * 9.0 / 16.0
            let videoY = bounds.height - 14 - videoH
            videoPlayerView.frame = NSRect(x: padLeft, y: videoY, width: videoW, height: videoH)
            
            // 1. Scrubber Row (Timeline): y = videoY - 22
            let scrubberY = videoY - 22
            currentTimeLabel.frame = NSRect(x: padLeft, y: scrubberY, width: 34, height: 14)
            durationLabel.frame = NSRect(x: bounds.width - padRight - 34, y: scrubberY, width: 34, height: 14)
            let sliderX = currentTimeLabel.frame.maxX + 4
            let sliderW = durationLabel.frame.minX - 4 - sliderX
            scrubberSlider.frame = NSRect(x: sliderX, y: scrubberY - 2, width: max(40, sliderW), height: 16)
            
            // 2. Transport & Volume Row: y = scrubberY - 30
            let transY = scrubberY - 30
            let btnSize: CGFloat = 24
            let spacing: CGFloat = 4
            
            skipBackButton.frame = NSRect(x: padLeft, y: transY, width: btnSize, height: btnSize)
            playPauseButton.frame = NSRect(x: skipBackButton.frame.maxX + spacing, y: transY - 1, width: btnSize + 2, height: btnSize + 2)
            skipForwardButton.frame = NSRect(x: playPauseButton.frame.maxX + spacing, y: transY, width: btnSize, height: btnSize)
            
            volumeButton.frame = NSRect(x: skipForwardButton.frame.maxX + 8, y: transY, width: btnSize, height: btnSize)
            let maxVolWidth: CGFloat = min(60, max(28, bounds.width - 240))
            volumeSlider.frame = NSRect(x: volumeButton.frame.maxX + 4, y: transY + 2, width: maxVolWidth, height: 18)
            
            // Right edge action buttons on transport row
            closeButton.frame = NSRect(x: bounds.width - padRight - btnSize, y: transY, width: btnSize, height: btnSize)
            openButton.frame = NSRect(x: closeButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            copyButton.frame = NSRect(x: openButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            pinButton.frame = NSRect(x: copyButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            
            // 3. Metadata row: bottom area (y: 6 to transY - 4)
            let metaY: CGFloat = 8
            let iconSize: CGFloat = 26
            badgeContainer.frame = NSRect(x: padLeft, y: metaY, width: iconSize, height: iconSize)
            badgeContainer.layer?.cornerRadius = 13
            equalizerView.frame = NSRect(x: 2, y: 5, width: 22, height: 16)
            
            let textLeft = badgeContainer.frame.maxX + 8
            let textWidth = max(50, bounds.width - textLeft - padRight)
            titleLabel.frame = NSRect(x: textLeft, y: metaY + 12, width: textWidth, height: 16)
            artistLabel.frame = NSRect(x: textLeft, y: metaY - 1, width: max(40, textWidth - 55), height: 14)
            browserBadge.frame = NSRect(x: textLeft + max(40, textWidth - 55) + 4, y: metaY, width: 45, height: 13)
        } else {
            // Compact Audio Mode Layout (Height: 56)
            videoPlayerView.isHidden = true
            scrubberSlider.isHidden = true
            currentTimeLabel.isHidden = true
            durationLabel.isHidden = true
            skipBackButton.isHidden = true
            skipForwardButton.isHidden = true
            volumeButton.isHidden = true
            volumeSlider.isHidden = true
            
            let paddingLeft: CGFloat = 16
            let paddingRight: CGFloat = 12
            let iconSize: CGFloat = 36
            
            badgeContainer.frame = NSRect(x: paddingLeft, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            badgeContainer.layer?.cornerRadius = 18
            equalizerView.frame = NSRect(x: 7, y: 10, width: 22, height: 16)
            
            let buttonSize: CGFloat = 26
            let btnSpacing: CGFloat = 6
            
            closeButton.frame = NSRect(x: bounds.width - paddingRight - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            openButton.frame = NSRect(x: closeButton.frame.minX - btnSpacing - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            copyButton.frame = NSRect(x: openButton.frame.minX - btnSpacing - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            playPauseButton.frame = NSRect(x: copyButton.frame.minX - btnSpacing - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            pinButton.frame = NSRect(x: playPauseButton.frame.minX - btnSpacing - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            
            let textLeft = badgeContainer.frame.maxX + 10
            let textRight = pinButton.frame.minX - 10
            let availableWidth = max(80, textRight - textLeft)
            
            if browserBadge.isHidden {
                titleLabel.frame = NSRect(x: textLeft, y: (bounds.height / 2) + 1, width: min(availableWidth, 320), height: 18)
            } else {
                let badgeWidth = browserBadge.frame.width + 4
                let titleWidth = min(availableWidth - badgeWidth - 6, 280)
                titleLabel.frame = NSRect(x: textLeft, y: (bounds.height / 2) + 1, width: titleWidth, height: 18)
                browserBadge.frame = NSRect(x: titleLabel.frame.maxX + 6, y: (bounds.height / 2) + 2, width: badgeWidth, height: 16)
            }
            
            artistLabel.frame = NSRect(x: textLeft, y: (bounds.height / 2) - 18, width: availableWidth, height: 16)
        }
    }
    
    public func stretchOut(animated: Bool = true) {
        isStretchedOut = true
        if !animated {
            visualEffectView.frame = bounds
            videoPlayerView.play()
            return
        }
        visualEffectView.frame = NSRect(x: bounds.width, y: 0, width: bounds.width, height: bounds.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            visualEffectView.animator().frame = bounds
        }, completionHandler: { [weak self] in
            self?.videoPlayerView.play()
        })
    }
    
    public func slideIn(animated: Bool = true, completion: (() -> Void)? = nil) {
        isStretchedOut = false
        videoPlayerView.pause()
        if !animated {
            visualEffectView.frame = NSRect(x: bounds.width, y: 0, width: bounds.width, height: bounds.height)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            visualEffectView.animator().frame = NSRect(x: bounds.width, y: 0, width: bounds.width, height: bounds.height)
        }, completionHandler: completion)
    }
    
    public func playVideo() {
        videoPlayerView.play()
    }
    
    public func pauseVideo() {
        videoPlayerView.pause()
    }
    
    public func seekTo(seconds: Double) {
        videoPlayerView.seekTo(seconds: seconds)
        currentTimeLabel.stringValue = formatTime(seconds)
        scrubberSlider.doubleValue = seconds
    }
    
    public func setPiPAudio(enabled: Bool) {
        videoPlayerView.setMuted(!enabled)
    }
    
    public func calculateFittingSize() -> NSSize {
        let width = max(260, min(650, preferredPanelWidth))
        let hasVideo = isVideoPreviewEnabled && (currentTrack?.isVideo ?? false)
        if hasVideo {
            let padLeft: CGFloat = 18
            let padRight: CGFloat = 14
            let videoW = width - padLeft - padRight
            let videoH = videoW * 9.0 / 16.0
            let bottomBarHeight: CGFloat = 104
            let topPadding: CGFloat = 14
            let height = topPadding + videoH + bottomBarHeight
            return NSSize(width: width, height: height)
        }
        
        let titleFont = titleLabel.font ?? NSFont.systemFont(ofSize: 13)
        let artistFont = artistLabel.font ?? NSFont.systemFont(ofSize: 11)
        
        let titleWidth = (titleLabel.stringValue as NSString).size(withAttributes: [.font: titleFont]).width
        let artistWidth = (artistLabel.stringValue as NSString).size(withAttributes: [.font: artistFont]).width
        let maxTextWidth = min(max(titleWidth + (browserBadge.isHidden ? 0 : 70), artistWidth), 330)
        
        let buttonsCount: CGFloat = 5
        let totalWidth = 16 + 36 + 10 + maxTextWidth + 12 + (buttonsCount * 26) + ((buttonsCount - 1) * 6) + 12
        return NSSize(width: max(width, max(380, totalWidth)), height: 56)
    }
    
    @objc private func handleScrubberChanged() {
        let val = scrubberSlider.doubleValue
        currentTimeLabel.stringValue = formatTime(val)
        videoPlayerView.seekTo(seconds: val)
        seekDebounceTimer?.invalidate()
        seekDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.onSeekRequested?(val)
        }
    }
    
    @objc private func handleSkipBack() {
        videoPlayerView.skip(by: -10)
        let newTime = videoPlayerView.currentTime
        currentTimeLabel.stringValue = formatTime(newTime)
        scrubberSlider.doubleValue = newTime
        seekDebounceTimer?.invalidate()
        seekDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.onSeekRequested?(newTime)
        }
    }
    
    @objc private func handleSkipForward() {
        videoPlayerView.skip(by: 10)
        let newTime = videoPlayerView.currentTime
        currentTimeLabel.stringValue = formatTime(newTime)
        scrubberSlider.doubleValue = newTime
        seekDebounceTimer?.invalidate()
        seekDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.onSeekRequested?(newTime)
        }
    }
    
    @objc private func handleVolumeButton() {
        videoPlayerView.toggleMute()
    }
    
    @objc private func handleVolumeSliderChanged() {
        let vol = Int(volumeSlider.doubleValue)
        videoPlayerView.setVolume(volume: vol)
        if videoPlayerView.isMuted && vol > 0 {
            videoPlayerView.setMuted(false)
        }
    }
    
    private func handlePlayerProgress(cur: Double, dur: Double) {
        if !isUserScrubbing {
            currentTimeLabel.stringValue = formatTime(cur)
            if dur > 0 {
                durationLabel.stringValue = formatTime(dur)
                scrubberSlider.maxValue = dur
                scrubberSlider.doubleValue = cur
            }
        }
    }
    
    private func updateVolumeUI(vol: Int, isMuted: Bool) {
        volumeSlider.doubleValue = Double(vol)
        let sym = isMuted || vol == 0 ? "speaker.slash.fill" : (vol < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            volumeButton.image = img
            volumeButton.contentTintColor = isMuted ? NSColor(white: 0.6, alpha: 1.0) : .white
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let mins = s / 60
        let secs = s % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    @objc private func handleOpen() {
        if currentTrack != nil {
            onOpenTab?()
        } else {
            if let url = URL(string: "https://www.youtube.com") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func handlePlayPause() {
        togglePlayPause()
    }
    
    public func togglePlayPause() {
        let willPlay = !videoPlayerView.isPlaying
        if willPlay {
            videoPlayerView.play()
        } else {
            videoPlayerView.pause()
        }
        updatePlayPauseState(isPlaying: willPlay)
        onTogglePlayPause?()
    }
    
    public func updatePlayPauseState(isPlaying: Bool) {
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        let tooltip = isPlaying ? "Pause Video" : "Play Video"
        playPauseButton.toolTip = tooltip
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            playPauseButton.image = img
            playPauseButton.imagePosition = .imageOnly
            playPauseButton.contentTintColor = .white
        }
        if isPlaying {
            equalizerView.startAnimating()
        } else {
            equalizerView.stopAnimating()
        }
    }
    
    @objc private func handlePinToggle() {
        onTogglePin?()
    }
    
    @objc private func handleCopy() {
        onCopyTitle?()
        
        let originalConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let checkImg = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")?.withSymbolConfiguration(originalConfig) {
            copyButton.image = checkImg
            copyButton.contentTintColor = .systemGreen
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            if let docImg = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)?.withSymbolConfiguration(originalConfig) {
                self.copyButton.image = docImg
                self.copyButton.contentTintColor = .white
            }
        }
    }
    
    @objc private func handleClose() {
        onDismiss?()
    }
}
