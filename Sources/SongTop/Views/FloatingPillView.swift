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
    public var onVolumeRequested: ((Int) -> Void)?
    public var onMuteRequested: ((Bool) -> Void)?
    
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
    
    // Audio / Video Lip-Sync Calibration Extension
    private let syncCalibrationButton = NSButton()
    public var isSyncCalibrationExpanded: Bool = false {
        didSet {
            updateSyncCalibrationButtonIcon()
            syncDrawerContainer.isHidden = !isSyncCalibrationExpanded
            needsLayout = true
            onHeightChanged?()
        }
    }
    public var onHeightChanged: (() -> Void)?
    
    // In-Panel Lip-Sync Calibration Drawer Controls
    private let syncDrawerContainer = NSView()
    private let syncDrawerTitleLabel = NSTextField(labelWithString: "Lip-Sync:")
    private let syncDrawerValueLabel = NSTextField(labelWithString: "0 ms")
    private let syncDrawerSlider = NSSlider(value: 0, minValue: -400, maxValue: 300, target: nil, action: nil)
    private let presetMinus250Button = NSButton()
    private let presetMinus120Button = NSButton()
    private let presetZeroButton = NSButton()
    private let presetPlus100Button = NSButton()
    
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let browserBadge = NSTextField(labelWithString: "")
    private let tabPickerButton = NSButton()
    public var availableTracks: [TrackInfo] = []
    public var isAutoTracking: Bool = true
    public var onSelectTrack: ((TrackInfo?) -> Void)?
    private let pipBadge = NSTextField(labelWithString: " 📺 PiP Active ")
    public var isNativePiPActive: Bool = false {
        didSet {
            guard oldValue != isNativePiPActive else { return }
            pipBadge.isHidden = !isNativePiPActive
            if isNativePiPActive {
                videoPlayerView.clearVideo()
                videoPlayerView.isHidden = true
            }
            needsLayout = true
        }
    }
    
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
    public var currentTrackUrl: String? { currentTrack?.url }
    
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .songTopSettingsChanged,
            object: nil
        )
        
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
        visualEffectView.layer?.borderWidth = 0.0
        visualEffectView.layer?.borderColor = NSColor.clear.cgColor
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
        
        // Multi-Tab Selection Badge Button
        tabPickerButton.isBordered = false
        tabPickerButton.wantsLayer = true
        tabPickerButton.layer?.cornerRadius = 4
        tabPickerButton.layer?.backgroundColor = NSColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.28).cgColor
        tabPickerButton.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        tabPickerButton.contentTintColor = NSColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1.0)
        tabPickerButton.toolTip = "Switch Active YouTube Video"
        tabPickerButton.target = self
        tabPickerButton.action = #selector(handleTabPickerClicked)
        tabPickerButton.isHidden = true
        visualEffectView.addSubview(tabPickerButton)
        
        // Native PiP Active Badge
        pipBadge.isBezeled = false
        pipBadge.drawsBackground = true
        pipBadge.backgroundColor = NSColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.28)
        pipBadge.isEditable = false
        pipBadge.isSelectable = false
        pipBadge.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        pipBadge.textColor = NSColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1.0)
        pipBadge.alignment = .center
        pipBadge.wantsLayer = true
        pipBadge.layer?.cornerRadius = 4
        pipBadge.layer?.masksToBounds = true
        pipBadge.isHidden = true
        visualEffectView.addSubview(pipBadge)
        
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
        
        // Sync Calibration Arrow Button
        configureIconButton(syncCalibrationButton, symbol: "chevron.down", tooltip: "Audio / Video Lip-Sync Calibration")
        syncCalibrationButton.target = self
        syncCalibrationButton.action = #selector(handleToggleSyncCalibration)
        visualEffectView.addSubview(syncCalibrationButton)
        
        // In-Panel Lip-Sync Calibration Drawer
        syncDrawerContainer.wantsLayer = true
        syncDrawerContainer.layer?.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 0.90).cgColor
        syncDrawerContainer.layer?.cornerRadius = 9
        syncDrawerContainer.layer?.borderWidth = 1.0
        syncDrawerContainer.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        syncDrawerContainer.isHidden = true
        visualEffectView.addSubview(syncDrawerContainer)
        
        syncDrawerTitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        syncDrawerTitleLabel.textColor = .secondaryLabelColor
        syncDrawerContainer.addSubview(syncDrawerTitleLabel)
        
        syncDrawerValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        syncDrawerValueLabel.textColor = .labelColor
        syncDrawerContainer.addSubview(syncDrawerValueLabel)
        
        syncDrawerSlider.isContinuous = true
        syncDrawerSlider.target = self
        syncDrawerSlider.action = #selector(handleDrawerSliderChanged)
        syncDrawerContainer.addSubview(syncDrawerSlider)
        
        configureDrawerPresetButton(presetMinus250Button, title: "-250ms", action: #selector(handlePresetMinus250))
        configureDrawerPresetButton(presetMinus120Button, title: "-120ms", action: #selector(handlePresetMinus120))
        configureDrawerPresetButton(presetZeroButton, title: "0ms", action: #selector(handlePresetZero))
        configureDrawerPresetButton(presetPlus100Button, title: "+100ms", action: #selector(handlePresetPlus100))
        
        syncDrawerContainer.addSubview(presetMinus250Button)
        syncDrawerContainer.addSubview(presetMinus120Button)
        syncDrawerContainer.addSubview(presetZeroButton)
        syncDrawerContainer.addSubview(presetPlus100Button)
        
        loadInitialSyncDelay()
    }
    
    // MARK: - Multi-Tab Selection Menu & Actions
    @objc private func handleTabPickerClicked(_ sender: NSButton) {
        let menu = NSMenu(title: "Active YouTube Tabs")
        
        let count = availableTracks.count
        let headerItem = NSMenuItem(title: "Active YouTube Tabs (\(count))", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let autoItem = NSMenuItem(title: "⚡ Auto (Follow Active Tab)", action: #selector(handleSelectAutoTrack), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = isAutoTracking ? .on : .off
        menu.addItem(autoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        for (index, track) in availableTracks.enumerated() {
            let activeTag = track.isActiveTab ? " • Active" : ""
            let trackName = track.title.isEmpty ? track.rawTitle : track.title
            let display = trackName.count > 38 ? String(trackName.prefix(35)) + "…" : trackName
            let itemTitle = "[\(track.browser)] \(display)\(activeTag)"
            
            let item = NSMenuItem(title: itemTitle, action: #selector(handleSelectSpecificTrack(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.toolTip = "\(track.title)\n\(track.url)"
            
            let isCurrent = (currentTrack?.url == track.url || (currentTrack?.youtubeVideoId != nil && currentTrack?.youtubeVideoId == track.youtubeVideoId))
            item.state = (!isAutoTracking && isCurrent) ? .on : .off
            menu.addItem(item)
        }
        
        let location = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: sender)
    }
    
    @objc private func handleSelectAutoTrack() {
        isAutoTracking = true
        onSelectTrack?(nil)
    }
    
    @objc private func handleSelectSpecificTrack(_ sender: NSMenuItem) {
        guard sender.tag >= 0 && sender.tag < availableTracks.count else { return }
        let track = availableTracks[sender.tag]
        isAutoTracking = false
        onSelectTrack?(track)
    }
    
    public func updateAvailableTracks(_ tracks: [TrackInfo], selectedTrack: TrackInfo?, isAuto: Bool) {
        self.availableTracks = tracks
        self.isAutoTracking = isAuto
        
        if tracks.count > 1 {
            tabPickerButton.isHidden = false
            tabPickerButton.title = " ⧉ \(tracks.count) Tabs ▾ "
            tabPickerButton.toolTip = "\(tracks.count) YouTube tabs open. Click to switch video display."
            tabPickerButton.sizeToFit()
            tabPickerButton.frame.size.width = max(68, tabPickerButton.frame.size.width + 6)
            tabPickerButton.frame.size.height = 14
        } else {
            tabPickerButton.isHidden = true
        }
        needsLayout = true
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
    
    public func update(with track: TrackInfo?, initialSeconds: Double? = nil) {
        let isDifferentTrack = (track?.url != currentTrack?.url)
        self.currentTrack = track
        
        if isDifferentTrack {
            currentTimeLabel.stringValue = "00:00"
            durationLabel.stringValue = "00:00"
            scrubberSlider.doubleValue = 0
        }
        
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
            
            if isNativePiPActive {
                videoPlayerView.isHidden = true
                videoPlayerView.clearVideo()
            } else if hasVideo, let vid = track.youtubeVideoId {
                videoPlayerView.isHidden = false
                let startSec = initialSeconds ?? track.startSeconds ?? 0
                videoPlayerView.loadVideo(id: vid, startSeconds: startSec)
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
        let isCompanion = isNativePiPActive
        let gripHeight: CGFloat = (hasVideo || isCompanion) ? 50 : 28
        resizeHandle.frame = NSRect(x: 0, y: 0, width: 18, height: bounds.height)
        gripBar.frame = NSRect(x: 5, y: (bounds.height - gripHeight) / 2, width: 3.5, height: gripHeight)
        window?.invalidateCursorRects(for: resizeHandle)
        
        if isCompanion {
            // Native PiP Companion Dock Layout (Height: 114)
            videoPlayerView.isHidden = true
            scrubberSlider.isHidden = false
            currentTimeLabel.isHidden = false
            durationLabel.isHidden = false
            skipBackButton.isHidden = false
            skipForwardButton.isHidden = false
            volumeButton.isHidden = false
            volumeSlider.isHidden = false
            pipBadge.isHidden = false
            
            let padLeft: CGFloat = 18
            let padRight: CGFloat = 14
            
            // Row 1 (Top: Metadata & PiP badge): y = bounds.height - 34
            let row1Y = bounds.height - 34
            let iconSize: CGFloat = 26
            badgeContainer.frame = NSRect(x: padLeft, y: row1Y - 2, width: iconSize, height: iconSize)
            badgeContainer.layer?.cornerRadius = 13
            equalizerView.frame = NSRect(x: 2, y: 5, width: 22, height: 16)
            
            pipBadge.sizeToFit()
            let badgeW = pipBadge.frame.width + 6
            pipBadge.frame = NSRect(x: bounds.width - padRight - badgeW, y: row1Y + 3, width: badgeW, height: 14)
            
            let textLeft = badgeContainer.frame.maxX + 8
            let textWidth = max(50, pipBadge.frame.minX - textLeft - 6)
            titleLabel.frame = NSRect(x: textLeft, y: row1Y + 12, width: textWidth, height: 16)
            let artistWidth = min(textWidth - 55, 120)
            artistLabel.frame = NSRect(x: textLeft, y: row1Y - 2, width: max(30, artistWidth), height: 14)
            browserBadge.frame = NSRect(x: textLeft + max(30, artistWidth) + 4, y: row1Y - 2, width: 45, height: 13)
            if !tabPickerButton.isHidden {
                let pickerW = max(68, tabPickerButton.frame.width)
                tabPickerButton.frame = NSRect(x: browserBadge.frame.maxX + 4, y: row1Y - 3, width: pickerW, height: 15)
            }
            
            // Row 2 (Middle: Scrubber): y = row1Y - 32
            let scrubberY = row1Y - 32
            currentTimeLabel.frame = NSRect(x: padLeft, y: scrubberY, width: 34, height: 14)
            durationLabel.frame = NSRect(x: bounds.width - padRight - 34, y: scrubberY, width: 34, height: 14)
            let sliderX = currentTimeLabel.frame.maxX + 4
            let sliderW = durationLabel.frame.minX - 4 - sliderX
            scrubberSlider.frame = NSRect(x: sliderX, y: scrubberY - 2, width: max(40, sliderW), height: 16)
            
            // Row 3 (Bottom: Transport & Volume): y = 10
            let transY: CGFloat = 10
            let btnSize: CGFloat = 24
            let spacing: CGFloat = 4
            
            skipBackButton.frame = NSRect(x: padLeft, y: transY, width: btnSize, height: btnSize)
            playPauseButton.frame = NSRect(x: skipBackButton.frame.maxX + spacing, y: transY - 1, width: btnSize + 2, height: btnSize + 2)
            skipForwardButton.frame = NSRect(x: playPauseButton.frame.maxX + spacing, y: transY, width: btnSize, height: btnSize)
            
            volumeButton.frame = NSRect(x: skipForwardButton.frame.maxX + 8, y: transY, width: btnSize, height: btnSize)
            let maxVolWidth: CGFloat = min(54, max(22, bounds.width - 275))
            volumeSlider.frame = NSRect(x: volumeButton.frame.maxX + 4, y: transY + 2, width: maxVolWidth, height: 18)
            
            closeButton.frame = NSRect(x: bounds.width - padRight - btnSize, y: transY, width: btnSize, height: btnSize)
            openButton.frame = NSRect(x: closeButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            copyButton.frame = NSRect(x: openButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            pinButton.frame = NSRect(x: copyButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            syncCalibrationButton.isHidden = false
            syncCalibrationButton.frame = NSRect(x: pinButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            
            layoutSyncDrawer(padLeft: padLeft, padRight: padRight)
        } else if hasVideo {
            // Full 16:9 Video Preview + Controls Layout (Height: 14 + videoH + 104 + drawerExtraHeight)
            pipBadge.isHidden = true
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
            let maxVolWidth: CGFloat = min(54, max(22, bounds.width - 275))
            volumeSlider.frame = NSRect(x: volumeButton.frame.maxX + 4, y: transY + 2, width: maxVolWidth, height: 18)
            
            // Right edge action buttons on transport row
            closeButton.frame = NSRect(x: bounds.width - padRight - btnSize, y: transY, width: btnSize, height: btnSize)
            openButton.frame = NSRect(x: closeButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            copyButton.frame = NSRect(x: openButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            pinButton.frame = NSRect(x: copyButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            syncCalibrationButton.isHidden = false
            syncCalibrationButton.frame = NSRect(x: pinButton.frame.minX - spacing - btnSize, y: transY, width: btnSize, height: btnSize)
            
            // 3. Metadata row: bottom area (y: 6 + bottomOffset to transY - 4)
            let bottomOffset: CGFloat = isSyncCalibrationExpanded ? 54 : 0
            let metaY: CGFloat = 8 + bottomOffset
            let iconSize: CGFloat = 26
            badgeContainer.frame = NSRect(x: padLeft, y: metaY, width: iconSize, height: iconSize)
            badgeContainer.layer?.cornerRadius = 13
            equalizerView.frame = NSRect(x: 2, y: 5, width: 22, height: 16)
            
            let textLeft = badgeContainer.frame.maxX + 8
            let textWidth = max(50, bounds.width - textLeft - padRight)
            titleLabel.frame = NSRect(x: textLeft, y: metaY + 12, width: textWidth, height: 16)
            let artistWidth = min(textWidth - 55, 120)
            artistLabel.frame = NSRect(x: textLeft, y: metaY - 1, width: max(30, artistWidth), height: 14)
            browserBadge.frame = NSRect(x: textLeft + max(30, artistWidth) + 4, y: metaY, width: 45, height: 13)
            if !tabPickerButton.isHidden {
                let pickerW = max(68, tabPickerButton.frame.width)
                tabPickerButton.frame = NSRect(x: browserBadge.frame.maxX + 4, y: metaY - 1, width: pickerW, height: 15)
            }
            
            layoutSyncDrawer(padLeft: padLeft, padRight: padRight)
        } else {
            // Compact Audio Mode Layout (Height: 56)
            syncCalibrationButton.isHidden = true
            syncDrawerContainer.isHidden = true
            pipBadge.isHidden = true
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
            
            let btnSpacing: CGFloat = 6
            let btnSize: CGFloat = 26
            
            closeButton.frame = NSRect(x: bounds.width - paddingRight - btnSize, y: (bounds.height - btnSize) / 2, width: btnSize, height: btnSize)
            openButton.frame = NSRect(x: closeButton.frame.minX - btnSpacing - btnSize, y: (bounds.height - btnSize) / 2, width: btnSize, height: btnSize)
            copyButton.frame = NSRect(x: openButton.frame.minX - btnSpacing - btnSize, y: (bounds.height - btnSize) / 2, width: btnSize, height: btnSize)
            playPauseButton.frame = NSRect(x: copyButton.frame.minX - btnSpacing - btnSize, y: (bounds.height - btnSize) / 2, width: btnSize, height: btnSize)
            pinButton.frame = NSRect(x: playPauseButton.frame.minX - btnSpacing - btnSize, y: (bounds.height - btnSize) / 2, width: btnSize, height: btnSize)
            
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
                if !tabPickerButton.isHidden {
                    let pickerW = max(68, tabPickerButton.frame.width)
                    tabPickerButton.frame = NSRect(x: browserBadge.frame.maxX + 6, y: (bounds.height / 2) + 2, width: pickerW, height: 16)
                }
            }
            
            artistLabel.frame = NSRect(x: textLeft, y: (bounds.height / 2) - 18, width: availableWidth, height: 16)
        }
    }
    
    public func stretchOut(animated: Bool = true) {
        isStretchedOut = true
        if !animated {
            visualEffectView.frame = bounds
            videoPlayerView.play()
            if videoPlayerView.browserCurrentTime > 0 {
                videoPlayerView.syncWithBrowser(targetTime: videoPlayerView.browserCurrentTime, isPaused: false)
            }
            return
        }
        visualEffectView.frame = NSRect(x: bounds.width, y: 0, width: bounds.width, height: bounds.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            visualEffectView.animator().frame = bounds
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.videoPlayerView.play()
            if self.videoPlayerView.browserCurrentTime > 0 {
                self.videoPlayerView.syncWithBrowser(targetTime: self.videoPlayerView.browserCurrentTime, isPaused: false)
            }
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
        let drawerExtraHeight: CGFloat = isSyncCalibrationExpanded ? 54 : 0
        
        if isNativePiPActive {
            return NSSize(width: width, height: 114 + drawerExtraHeight)
        }
        if hasVideo {
            let padLeft: CGFloat = 18
            let padRight: CGFloat = 14
            let videoW = width - padLeft - padRight
            let videoH = videoW * 9.0 / 16.0
            let bottomBarHeight: CGFloat = 104
            let topPadding: CGFloat = 14
            let height = topPadding + videoH + bottomBarHeight + drawerExtraHeight
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
        onMuteRequested?(videoPlayerView.isMuted)
    }
    
    @objc private func handleVolumeSliderChanged() {
        let vol = Int(volumeSlider.doubleValue)
        videoPlayerView.setVolume(volume: vol)
        if videoPlayerView.isMuted && vol > 0 {
            videoPlayerView.setMuted(false)
        }
        onVolumeRequested?(vol)
    }
    
    public func updateTelemetry(cur: Double, dur: Double, paused: Bool, vol: Int, muted: Bool) {
        videoPlayerView.updateFromTelemetry(cur: cur, dur: dur, paused: paused, vol: vol, muted: muted)
        if !isUserScrubbing {
            currentTimeLabel.stringValue = formatTime(cur)
            if dur > 0 {
                durationLabel.stringValue = formatTime(dur)
                scrubberSlider.maxValue = dur
                scrubberSlider.doubleValue = cur
            }
        }
        updatePlayPauseState(isPlaying: !paused)
        updateVolumeUI(vol: vol, isMuted: muted)
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
    
    private func layoutSyncDrawer(padLeft: CGFloat, padRight: CGFloat) {
        if isSyncCalibrationExpanded {
            syncDrawerContainer.isHidden = false
            let drawerW = bounds.width - padLeft - padRight
            syncDrawerContainer.frame = NSRect(x: padLeft, y: 8, width: drawerW, height: 48)
            
            let row1Y: CGFloat = 26
            syncDrawerTitleLabel.frame = NSRect(x: 8, y: row1Y, width: 52, height: 16)
            syncDrawerValueLabel.frame = NSRect(x: 62, y: row1Y, width: 50, height: 16)
            
            let btnH: CGFloat = 17
            presetPlus100Button.frame = NSRect(x: drawerW - 8 - 42, y: row1Y, width: 42, height: btnH)
            presetZeroButton.frame = NSRect(x: presetPlus100Button.frame.minX - 4 - 30, y: row1Y, width: 30, height: btnH)
            presetMinus120Button.frame = NSRect(x: presetZeroButton.frame.minX - 4 - 42, y: row1Y, width: 42, height: btnH)
            presetMinus250Button.frame = NSRect(x: presetMinus120Button.frame.minX - 4 - 44, y: row1Y, width: 44, height: btnH)
            
            syncDrawerSlider.frame = NSRect(x: 8, y: 5, width: drawerW - 16, height: 16)
        } else {
            syncDrawerContainer.isHidden = true
        }
    }
    
    private func configureDrawerPresetButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.85).cgColor
        button.layer?.cornerRadius = 4
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        button.target = self
        button.action = action
    }
    
    @objc private func handleToggleSyncCalibration() {
        isSyncCalibrationExpanded.toggle()
    }
    
    private func updateSyncCalibrationButtonIcon() {
        let symbol = isSyncCalibrationExpanded ? "chevron.up" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lip-Sync Calibration")?.withSymbolConfiguration(config) {
            syncCalibrationButton.image = img
            syncCalibrationButton.contentTintColor = isSyncCalibrationExpanded ? .systemBlue : .white
        }
    }
    
    @objc private func handleDrawerSliderChanged() {
        let val = round(syncDrawerSlider.doubleValue / 10.0) * 10.0
        applySyncOffset(val)
    }
    
    @objc private func handlePresetMinus250() { applySyncOffset(-250) }
    @objc private func handlePresetMinus120() { applySyncOffset(-120) }
    @objc private func handlePresetZero() { applySyncOffset(0) }
    @objc private func handlePresetPlus100() { applySyncOffset(100) }
    
    private func applySyncOffset(_ ms: Double) {
        syncDrawerSlider.doubleValue = ms
        syncDrawerValueLabel.stringValue = ms > 0 ? "+\(Int(ms)) ms" : "\(Int(ms)) ms"
        UserDefaults.standard.set(ms, forKey: "songtop_av_sync_delay_ms")
        videoPlayerView.syncDelay = ms / 1000.0
        if videoPlayerView.browserCurrentTime > 0 {
            videoPlayerView.syncWithBrowser(targetTime: videoPlayerView.browserCurrentTime, isPaused: !videoPlayerView.isPlaying)
        }
        NotificationCenter.default.post(name: .songTopSettingsChanged, object: nil)
    }
    
    private func loadInitialSyncDelay() {
        var ms = UserDefaults.standard.object(forKey: "songtop_av_sync_delay_ms") != nil
            ? UserDefaults.standard.double(forKey: "songtop_av_sync_delay_ms")
            : 0.0
        if ms == 250.0 {
            ms = 0.0
            UserDefaults.standard.set(0.0, forKey: "songtop_av_sync_delay_ms")
        }
        syncDrawerSlider.doubleValue = ms
        syncDrawerValueLabel.stringValue = ms > 0 ? "+\(Int(ms)) ms" : "\(Int(ms)) ms"
    }
    
    @objc private func handleSettingsChanged() {
        var ms = UserDefaults.standard.object(forKey: "songtop_av_sync_delay_ms") != nil
            ? UserDefaults.standard.double(forKey: "songtop_av_sync_delay_ms")
            : 0.0
        if ms == 250.0 {
            ms = 0.0
            UserDefaults.standard.set(0.0, forKey: "songtop_av_sync_delay_ms")
        }
        syncDrawerSlider.doubleValue = ms
        syncDrawerValueLabel.stringValue = ms > 0 ? "+\(Int(ms)) ms" : "\(Int(ms)) ms"
        videoPlayerView.syncDelay = ms / 1000.0
        if videoPlayerView.browserCurrentTime > 0 {
            videoPlayerView.syncWithBrowser(targetTime: videoPlayerView.browserCurrentTime, isPaused: !videoPlayerView.isPlaying)
        }
    }
}
