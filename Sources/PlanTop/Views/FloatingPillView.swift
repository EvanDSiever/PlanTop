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

// MARK: - Dedicated Clock Panel View (Full Width, Prominent Futuristic Display)
public final class ClockPanelView: NeumorphicDepressedCardView {
    override public var isFlipped: Bool { return true }
    
    private let timeLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    
    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d, yyyy"
        return df
    }()
    
    override public init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        setupViews()
        updateTime()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        cornerRadiusValue = 14
        surfaceColor = NSColor.white
        outlineWidth = 0.5
        outlineColor = NeumorphicTheme.specularHighlightBorder
        
        // Large Futuristic Clock Label (Spans full width)
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        timeLabel.alignment = .center
        timeLabel.textColor = NeumorphicTheme.accentColor
        addSubview(timeLabel)
        
        // Full Formatted Date Label
        dateLabel.isBezeled = false
        dateLabel.drawsBackground = false
        dateLabel.isEditable = false
        dateLabel.isSelectable = false
        dateLabel.alignment = .center
        dateLabel.font = NeumorphicTheme.avenirFont(ofSize: 12.0, weight: .regular)
        dateLabel.textColor = NeumorphicTheme.textSecondary
        addSubview(dateLabel)
    }
    
    public func updateTime() {
        let now = Date()
        timeLabel.stringValue = timeFormatter.string(from: now)
        dateLabel.stringValue = dateFormatter.string(from: now)
        needsLayout = true
    }
    
    override public func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        guard w > 0 && h > 0 else { return }
        
        // Dynamic font size taking full width
        let timeFontSize: CGFloat = min(48, max(36, w * 0.135))
        timeLabel.font = NeumorphicTheme.futuristicTimeFont(ofSize: timeFontSize)
        
        let dateH: CGFloat = 16
        let timeH: CGFloat = ceil(timeFontSize * 1.05)
        let totalContentH = timeH + 2 + dateH
        let topY = max(4, (h - totalContentH) / 2)
        
        timeLabel.frame = NSRect(x: 4, y: topY, width: max(0, w - 8), height: timeH)
        dateLabel.frame = NSRect(x: 4, y: topY + timeH + 2, width: max(0, w - 8), height: dateH)
    }
}

public final class FloatingPillView: NSView {
    private let clipContainer = NSView()
    private let masterPanel = NeumorphicPanelContainerView()
    private let resizeHandle = ResizeHandleView()
    
    // Header controls
    private let headerContainer = NSView()
    private let calendarIconView = NSImageView()
    private let appTitleLabel = NSTextField(labelWithString: "PlanTop")
    private let syncButton = NSButton()
    private let settingsButton = NSButton()
    private let pinButton = NSButton()
    private let dismissButton = NSButton()
    
    // Dedicated Separate Clock Panel (Above Calendar Panel, Full Width)
    private let clockPanel = ClockPanelView()
    
    // Calendar Panel with Neumorphic Switcher
    private let calendarPanel = CalendarPanelView(dayMode: .today)
    
    // Dynamic Drag-Scaling Support
    public var preferredPanelWidth: CGFloat = 340
    public var onResizeWidthChanged: ((CGFloat) -> Void)?
    public var onResizeCompleted: (() -> Void)?
    private var isDraggingResize: Bool = false
    private var dragStartMouseX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    
    // Pin Control
    public var isPinned: Bool = false {
        didSet {
            updatePinButtonIcon()
        }
    }
    public var onTogglePin: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onHeightChanged: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var onHoverStateChanged: ((Bool) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    private var timeTickerTimer: Timer?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    deinit {
        timeTickerTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .planTopSettingsChanged,
            object: nil
        )
        
        // Clip container masks the drawer sliding in from the right edge
        clipContainer.wantsLayer = true
        clipContainer.layer?.backgroundColor = NSColor.clear.cgColor
        clipContainer.layer?.cornerRadius = 20
        clipContainer.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        clipContainer.layer?.masksToBounds = true
        addSubview(clipContainer)
        
        // Master Neumorphic Ceramic Slab Container
        masterPanel.cornerRadiusValue = 20
        masterPanel.panelBackgroundColor = NeumorphicTheme.masterBackground
        clipContainer.addSubview(masterPanel)
        
        // 1. Setup Header Container
        headerContainer.wantsLayer = true
        headerContainer.layer?.backgroundColor = NSColor.clear.cgColor
        masterPanel.contentView.addSubview(headerContainer)
        
        // Calendar App Icon / Glyph
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        calendarIconView.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Planner")?.withSymbolConfiguration(config)
        calendarIconView.contentTintColor = NeumorphicTheme.accentColor
        headerContainer.addSubview(calendarIconView)
        
        // App Title Label (Unbolded Avenir medium)
        appTitleLabel.isBezeled = false
        appTitleLabel.drawsBackground = false
        appTitleLabel.isEditable = false
        appTitleLabel.isSelectable = false
        appTitleLabel.font = NeumorphicTheme.avenirFont(ofSize: 13.5, weight: .medium)
        appTitleLabel.textColor = NeumorphicTheme.textPrimary
        headerContainer.addSubview(appTitleLabel)
        
        // Action Buttons
        configureIconButton(syncButton, symbol: "arrow.clockwise", tooltip: "Sync Google Calendar")
        syncButton.target = self
        syncButton.action = #selector(syncButtonClicked)
        headerContainer.addSubview(syncButton)
        
        configureIconButton(settingsButton, symbol: "gearshape", tooltip: "PlanTop Settings")
        settingsButton.target = self
        settingsButton.action = #selector(settingsButtonClicked)
        headerContainer.addSubview(settingsButton)
        
        configureIconButton(pinButton, symbol: "pin", tooltip: "Pin Side Panel on Screen")
        pinButton.target = self
        pinButton.action = #selector(pinButtonClicked)
        headerContainer.addSubview(pinButton)
        updatePinButtonIcon()
        
        configureIconButton(dismissButton, symbol: "xmark", tooltip: "Close Side Panel")
        dismissButton.target = self
        dismissButton.action = #selector(dismissButtonClicked)
        headerContainer.addSubview(dismissButton)
        
        // 2. Separate Dedicated Clock Panel
        masterPanel.contentView.addSubview(clockPanel)
        
        // 3. Integrated Calendar Panel
        calendarPanel.onHeightChanged = { [weak self] in
            self?.needsLayout = true
            self?.onHeightChanged?()
        }
        calendarPanel.onOpenMeetURL = { url in
            NSWorkspace.shared.open(url)
        }
        masterPanel.contentView.addSubview(calendarPanel)
        
        // Left Edge Resize Handle
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
        clipContainer.addSubview(resizeHandle)
        
        // Setup Clock & Date Timer
        clockPanel.updateTime()
        timeTickerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.clockPanel.updateTime()
        }
        if let timer = timeTickerTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String) {
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        button.contentTintColor = NeumorphicTheme.textSecondary
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
    }
    
    private func updatePinButtonIcon() {
        let sym = isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        pinButton.image = NSImage(systemSymbolName: sym, accessibilityDescription: "Pin")?.withSymbolConfiguration(config)
        pinButton.contentTintColor = isPinned ? NeumorphicTheme.accentColor : NeumorphicTheme.textSecondary
        pinButton.toolTip = isPinned ? "Unpin side panel (auto-retract)" : "Pin side panel permanently"
    }
    
    @objc private func syncButtonClicked() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = -Double.pi * 2
        rotation.duration = 0.6
        rotation.repeatCount = 1
        syncButton.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        syncButton.layer?.add(rotation, forKey: "rotationAnimation")
        
        GoogleCalendarService.shared.syncNow()
        calendarPanel.reloadFromService()
    }
    
    @objc private func settingsButtonClicked() {
        onOpenSettings?()
    }
    
    @objc private func pinButtonClicked() {
        onTogglePin?()
    }
    
    @objc private func dismissButtonClicked() {
        onDismiss?()
    }
    
    @objc private func handleSettingsChanged() {
        clockPanel.updateTime()
        updatePinButtonIcon()
        calendarPanel.reloadFromService()
        needsLayout = true
    }
    
    public func reloadCalendar() {
        calendarPanel.reloadFromService()
        needsLayout = true
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverStateChanged?(true)
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverStateChanged?(false)
    }
    
    public private(set) var isStretchedOut: Bool = false
    
    public func stretchOut(animated: Bool = true, completion: (() -> Void)? = nil) {
        isStretchedOut = true
        let finalRect = NSRect(x: 16, y: 12, width: max(200, bounds.width - 16), height: max(100, bounds.height - 24))
        if !animated {
            masterPanel.frame = finalRect
            completion?()
            return
        }
        masterPanel.frame = NSRect(x: bounds.width, y: 12, width: finalRect.width, height: finalRect.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            masterPanel.animator().frame = finalRect
        }, completionHandler: {
            completion?()
        })
    }
    
    public func slideIn(animated: Bool = true, completion: (() -> Void)? = nil) {
        isStretchedOut = false
        let targetRect = NSRect(x: bounds.width, y: 12, width: max(200, bounds.width - 16), height: max(100, bounds.height - 24))
        if !animated {
            masterPanel.frame = targetRect
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            masterPanel.animator().frame = targetRect
        }, completionHandler: {
            completion?()
        })
    }
    
    public func calculateFittingSize() -> NSSize {
        let width = max(260, min(650, preferredPanelWidth))
        let panelW = max(200, width - 16)
        let headerH: CGFloat = 30
        let clockH: CGFloat = 74
        let calH = calendarPanel.calculateFittingHeight(forWidth: panelW)
        let screenMaxH: CGFloat = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        let totalH = min(screenMaxH, max(340, headerH + clockH + calH + 36))
        return NSSize(width: width, height: totalH)
    }
    
    public func calculatePanelHeight(forWidth cardW: CGFloat) -> CGFloat {
        let headerH: CGFloat = 30
        let clockH: CGFloat = 74
        let calH = calendarPanel.calculateFittingHeight(forWidth: cardW)
        return headerH + clockH + calH + 36
    }
    
    public override func layout() {
        super.layout()
        
        let b = bounds
        clipContainer.frame = b
        
        let hPad: CGFloat = 16
        let vPad: CGFloat = 12
        let panelW = max(260, b.width - hPad)
        let panelH = b.height - (vPad * 2)
        
        let targetX = isStretchedOut ? hPad : b.width
        masterPanel.frame = NSRect(x: targetX, y: vPad, width: panelW, height: panelH)
        masterPanel.layoutSubtreeIfNeeded()
        
        let cardW = panelW
        let cardH = panelH
        
        // 1. Header layout (Top of panel)
        let headerH: CGFloat = 30
        let headerY = cardH - headerH - 8
        headerContainer.frame = NSRect(x: 14, y: headerY, width: max(0, cardW - 28), height: headerH)
        
        // Buttons on right of header
        let btnSize: CGFloat = 26
        let closeX = headerContainer.bounds.width - btnSize
        let pinX = closeX - btnSize - 4
        let setX = pinX - btnSize - 4
        let syncX = setX - btnSize - 4
        
        dismissButton.frame = NSRect(x: closeX, y: (headerH - btnSize) / 2, width: btnSize, height: btnSize)
        pinButton.frame = NSRect(x: pinX, y: (headerH - btnSize) / 2, width: btnSize, height: btnSize)
        settingsButton.frame = NSRect(x: setX, y: (headerH - btnSize) / 2, width: btnSize, height: btnSize)
        syncButton.frame = NSRect(x: syncX, y: (headerH - btnSize) / 2, width: btnSize, height: btnSize)
        
        // Icon and Title on left of header
        calendarIconView.frame = NSRect(x: 0, y: (headerH - 18) / 2, width: 18, height: 18)
        let titleW = max(50, syncX - 26)
        appTitleLabel.frame = NSRect(x: 24, y: (headerH - 18) / 2, width: titleW, height: 18)
        
        // 2. Separate Dedicated Clock Panel (above Calendar Panel, full width)
        let clockH: CGFloat = 74
        let clockY = headerY - clockH - 8
        clockPanel.frame = NSRect(x: 14, y: clockY, width: max(0, cardW - 28), height: clockH)
        
        // 3. Calendar panel occupies remaining space below clock panel
        let calH = max(0, clockY - 6)
        calendarPanel.frame = NSRect(x: 0, y: 4, width: cardW, height: calH)
        
        resizeHandle.frame = NSRect(x: 0, y: 0, width: hPad + 14, height: bounds.height)
        window?.invalidateCursorRects(for: resizeHandle)
    }
}

