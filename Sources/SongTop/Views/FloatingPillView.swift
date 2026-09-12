import AppKit

public final class FloatingPillView: NSView {
    private let clipContainer = NSView()
    private let visualEffectView = NSVisualEffectView()
    private let badgeContainer = NSView()
    private let equalizerView = EqualizerView(barColor: .white)
    
    // Video Player
    private let videoPlayerView = YouTubeVideoPlayerView()
    public var isVideoPreviewEnabled: Bool = true {
        didSet {
            update(with: currentTrack)
        }
    }
    
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
        // Masked corners: rounded on the left side, flush on the right screen bezel
        visualEffectView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.2
        visualEffectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.22).cgColor
        visualEffectView.appearance = NSAppearance(named: .darkAqua)
        clipContainer.addSubview(visualEffectView)
        
        // Left Edge Drawer Accent Grip Bar
        let gripBar = NSView()
        gripBar.wantsLayer = true
        gripBar.layer?.cornerRadius = 2
        gripBar.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.35).cgColor
        gripBar.identifier = NSUserInterfaceItemIdentifier("gripBar")
        visualEffectView.addSubview(gripBar)
        
        // Video Player View (16:9 Live Preview)
        videoPlayerView.wantsLayer = true
        videoPlayerView.layer?.cornerRadius = 12
        videoPlayerView.layer?.masksToBounds = true
        videoPlayerView.isHidden = true
        visualEffectView.addSubview(videoPlayerView)
        
        // Red Icon Circle
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 18
        badgeContainer.layer?.backgroundColor = NSColor(red: 0.92, green: 0.1, blue: 0.14, alpha: 1.0).cgColor
        badgeContainer.layer?.shadowColor = NSColor.red.cgColor
        badgeContainer.layer?.shadowOpacity = 0.5
        badgeContainer.layer?.shadowRadius = 8
        badgeContainer.layer?.shadowOffset = CGSize(width: 0, height: -1)
        visualEffectView.addSubview(badgeContainer)
        
        // Equalizer in Icon Circle
        equalizerView.frame = NSRect(x: 7, y: 10, width: 22, height: 16)
        badgeContainer.addSubview(equalizerView)
        equalizerView.startAnimating()
        
        // Title Label
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
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
        artistLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        artistLabel.textColor = NSColor(white: 1.0, alpha: 0.72)
        artistLabel.lineBreakMode = .byTruncatingTail
        visualEffectView.addSubview(artistLabel)
        
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
        button.layer?.cornerRadius = 13
        button.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        button.toolTip = tooltip
        
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            button.image = img
            button.imagePosition = .imageOnly
            button.contentTintColor = .white
        }
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
            openButton.toolTip = "Bring YouTube Tab to Front (\(track.browser))"
            
            if hasVideo, let vid = track.youtubeVideoId {
                videoPlayerView.isHidden = false
                videoPlayerView.loadVideo(id: vid)
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
            
            badgeContainer.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1.0).cgColor
            equalizerView.stopAnimating()
            copyButton.isHidden = true
            playPauseButton.isHidden = true
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
        
        if hasVideo {
            // Video Mode Layout (340 wide x 260 tall)
            if let grip = visualEffectView.subviews.first(where: { $0.identifier?.rawValue == "gripBar" }) {
                grip.frame = NSRect(x: 5, y: (bounds.height - 44) / 2, width: 3.5, height: 44)
            }
            
            let padLeft: CGFloat = 18
            let padRight: CGFloat = 14
            let videoW = bounds.width - padLeft - padRight
            let videoH = videoW * 9.0 / 16.0
            let videoY = bounds.height - 14 - videoH
            videoPlayerView.frame = NSRect(x: padLeft, y: videoY, width: videoW, height: videoH)
            videoPlayerView.isHidden = false
            
            // Bottom control bar area (height = videoY)
            let iconSize: CGFloat = 30
            badgeContainer.frame = NSRect(x: padLeft, y: (videoY - iconSize) / 2, width: iconSize, height: iconSize)
            badgeContainer.layer?.cornerRadius = 15
            equalizerView.frame = NSRect(x: 4, y: 7, width: 22, height: 16)
            
            let btnSize: CGFloat = 24
            let btnSpacing: CGFloat = 5
            
            closeButton.frame = NSRect(x: bounds.width - padRight - btnSize, y: (videoY - btnSize) / 2, width: btnSize, height: btnSize)
            openButton.frame = NSRect(x: closeButton.frame.minX - btnSpacing - btnSize, y: (videoY - btnSize) / 2, width: btnSize, height: btnSize)
            copyButton.frame = NSRect(x: openButton.frame.minX - btnSpacing - btnSize, y: (videoY - btnSize) / 2, width: btnSize, height: btnSize)
            playPauseButton.frame = NSRect(x: copyButton.frame.minX - btnSpacing - btnSize, y: (videoY - btnSize) / 2, width: btnSize, height: btnSize)
            
            let textLeft = badgeContainer.frame.maxX + 8
            let textRight = playPauseButton.frame.minX - 8
            let textWidth = max(50, textRight - textLeft)
            
            titleLabel.frame = NSRect(x: textLeft, y: (videoY / 2) + 1, width: textWidth, height: 16)
            artistLabel.frame = NSRect(x: textLeft, y: (videoY / 2) - 16, width: max(30, textWidth - 45), height: 14)
            browserBadge.frame = NSRect(x: textLeft + max(30, textWidth - 45) + 4, y: (videoY / 2) - 15, width: 40, height: 13)
        } else {
            // Compact Audio Mode Layout (Height: 56)
            videoPlayerView.isHidden = true
            
            if let grip = visualEffectView.subviews.first(where: { $0.identifier?.rawValue == "gripBar" }) {
                grip.frame = NSRect(x: 5, y: (bounds.height - 28) / 2, width: 3.5, height: 28)
            }
            
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
            
            if copyButton.isHidden {
                playPauseButton.frame = NSRect(x: openButton.frame.minX - btnSpacing - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            } else {
                copyButton.frame = NSRect(x: openButton.frame.minX - btnSpacing - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
                playPauseButton.frame = NSRect(x: copyButton.frame.minX - btnSpacing - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            }
            
            let textLeft = badgeContainer.frame.maxX + 10
            let rightmostBtn = playPauseButton.isHidden ? (copyButton.isHidden ? openButton : copyButton) : playPauseButton
            let textRight = rightmostBtn.frame.minX - 10
            let availableWidth = max(100, textRight - textLeft)
            
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
    
    public func calculateFittingSize() -> NSSize {
        let hasVideo = isVideoPreviewEnabled && (currentTrack?.isVideo ?? false)
        if hasVideo {
            return NSSize(width: 340, height: 260)
        }
        
        let titleFont = titleLabel.font ?? NSFont.systemFont(ofSize: 13)
        let artistFont = artistLabel.font ?? NSFont.systemFont(ofSize: 11)
        
        let titleWidth = (titleLabel.stringValue as NSString).size(withAttributes: [.font: titleFont]).width
        let artistWidth = (artistLabel.stringValue as NSString).size(withAttributes: [.font: artistFont]).width
        let maxTextWidth = min(max(titleWidth + (browserBadge.isHidden ? 0 : 70), artistWidth), 330)
        
        let buttonsCount: CGFloat = 4
        let totalWidth = 16 + 36 + 10 + maxTextWidth + 12 + (buttonsCount * 26) + ((buttonsCount - 1) * 6) + 12
        return NSSize(width: max(380, totalWidth), height: 56)
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
        onTogglePlayPause?()
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
