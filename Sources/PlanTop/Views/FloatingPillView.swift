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

// MARK: - Mini Monthly Calendar Grid View
public final class MiniMonthCalendarView: NSView {
    override public var isFlipped: Bool { return true }
    
    private var cachedYear: Int = 0
    private var cachedMonth: Int = 0
    private var cachedToday: Int = 0
    private var daysInMonth: Int = 30
    private var firstWeekdayOffset: Int = 0
    private var monthYearString: String = ""
    private var dayHeaders: [String] = ["S", "M", "T", "W", "T", "F", "S"]
    
    override public init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateCalendarData()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateCalendarData() {
        let now = Date()
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let today = cal.component(.day, from: now)
        
        if year == cachedYear && month == cachedMonth && today == cachedToday {
            return
        }
        
        cachedYear = year
        cachedMonth = month
        cachedToday = today
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        monthYearString = formatter.string(from: now).uppercased()
        
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        
        let firstDayIdx = cal.firstWeekday - 1
        let shortSymbols = cal.shortStandaloneWeekdaySymbols.isEmpty ? cal.shortWeekdaySymbols : cal.shortStandaloneWeekdaySymbols
        dayHeaders = (0..<7).map { i -> String in
            let idx = (firstDayIdx + i) % 7
            return String(shortSymbols[idx].prefix(1)).uppercased()
        }
        
        if let firstDate = cal.date(from: comps) {
            let weekday = cal.component(.weekday, from: firstDate)
            let weekdayIdx = weekday - 1
            firstWeekdayOffset = (weekdayIdx - firstDayIdx + 7) % 7
        }
        
        if let range = cal.range(of: .day, in: .month, for: now) {
            daysInMonth = range.count
        }
        
        needsDisplay = true
    }
    
    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let w = bounds.width
        let h = bounds.height
        guard w > 40 && h > 40 else { return }
        
        let colW = w / 7.0
        
        // 1. Month / Year title at top
        let titleFont = NeumorphicTheme.avenirFont(ofSize: 10.5, weight: .bold)
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NeumorphicTheme.accentColor,
            .paragraphStyle: titleStyle
        ]
        let titleRect = NSRect(x: 0, y: 0, width: w, height: 14)
        (monthYearString as NSString).draw(in: titleRect, withAttributes: titleAttrs)
        
        // 2. Day Headers (S M T W T F S)
        let headerFont = NeumorphicTheme.avenirFont(ofSize: 8.0, weight: .semibold)
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .center
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NeumorphicTheme.textTertiary,
            .paragraphStyle: headerStyle
        ]
        
        let headerY: CGFloat = 16
        let headerH: CGFloat = 11
        for (i, dayName) in dayHeaders.enumerated() {
            let x = CGFloat(i) * colW
            let r = NSRect(x: x, y: headerY, width: colW, height: headerH)
            (dayName as NSString).draw(in: r, withAttributes: headerAttrs)
        }
        
        // 3. Days Grid
        let gridStartY = headerY + headerH + 3
        let availableH = h - gridStartY - 2
        let totalCells = firstWeekdayOffset + daysInMonth
        let numRows = max(5, Int(ceil(Double(totalCells) / 7.0)))
        let rowH = max(10, availableH / CGFloat(numRows))
        
        let dayFont = NeumorphicTheme.avenirFont(ofSize: 8.5, weight: .medium)
        let todayFont = NeumorphicTheme.avenirFont(ofSize: 9.0, weight: .heavy)
        
        let normalStyle = NSMutableParagraphStyle()
        normalStyle.alignment = .center
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: dayFont,
            .foregroundColor: NeumorphicTheme.textSecondary,
            .paragraphStyle: normalStyle
        ]
        
        let todayStyle = NSMutableParagraphStyle()
        todayStyle.alignment = .center
        let todayAttrs: [NSAttributedString.Key: Any] = [
            .font: todayFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: todayStyle
        ]
        
        for day in 1...daysInMonth {
            let cellIndex = firstWeekdayOffset + (day - 1)
            let col = cellIndex % 7
            let row = cellIndex / 7
            let x = CGFloat(col) * colW
            let y = gridStartY + CGFloat(row) * rowH
            
            if day == cachedToday {
                let badgeSize: CGFloat = min(rowH - 1, colW - 2)
                let badgeRect = NSRect(
                    x: x + (colW - badgeSize) / 2,
                    y: y + (rowH - badgeSize) / 2,
                    width: badgeSize,
                    height: badgeSize
                )
                NeumorphicTheme.accentColor.setFill()
                let path = NSBezierPath(ovalIn: badgeRect)
                path.fill()
                
                let textY = y + (rowH - 11) / 2 - 0.5
                let textRect = NSRect(x: x, y: textY, width: colW, height: 11)
                ("\(day)" as NSString).draw(in: textRect, withAttributes: todayAttrs)
            } else {
                let textY = y + (rowH - 11) / 2 - 0.5
                let textRect = NSRect(x: x, y: textY, width: colW, height: 11)
                ("\(day)" as NSString).draw(in: textRect, withAttributes: normalAttrs)
            }
        }
    }
}

// MARK: - Dedicated Clock & Calendar Panel View
// MARK: - Futuristic Dominant Clock View
public final class FuturisticClockView: NSView {
    override public var isFlipped: Bool { return true }
    
    public var timeString: String = "" {
        didSet {
            if oldValue != timeString {
                needsDisplay = true
            }
        }
    }
    
    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !timeString.isEmpty else { return }
        
        let w = bounds.width
        let h = bounds.height
        guard w > 20 && h > 20 else { return }
        
        let sampleText = timeString as NSString
        // Allow the clock to be dominantly large and fill the space prominently
        var fontSize: CGFloat = min(78, min(h * 0.70, w * 0.44))
        while fontSize > 24 {
            let font = NeumorphicTheme.futuristicTimeFont(ofSize: fontSize)
            let s = sampleText.size(withAttributes: [.font: font])
            if s.width <= (w - 6) && s.height <= (h - 10) {
                break
            }
            fontSize -= 1
        }
        
        let font = NeumorphicTheme.futuristicTimeFont(ofSize: fontSize)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NeumorphicTheme.accentColor,
            .paragraphStyle: style
        ]
        
        let textSize = sampleText.size(withAttributes: attrs)
        let drawY = max(0, (h - textSize.height) / 2)
        let drawRect = NSRect(x: 0, y: drawY, width: w, height: textSize.height)
        sampleText.draw(in: drawRect, withAttributes: attrs)
    }
}

// MARK: - Dedicated Clock & Calendar Panel View
public final class ClockPanelView: NeumorphicDepressedCardView {
    override public var isFlipped: Bool { return true }
    
    private let clockView = FuturisticClockView()
    private let dividerView = NSView()
    private let miniCalendarView = MiniMonthCalendarView()
    
    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        let template = "jmmss"
        df.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: Locale.current) ?? "HH:mm:ss"
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
        cornerRadiusValue = 16
        surfaceColor = NSColor.white
        outlineWidth = 0.5
        outlineColor = NeumorphicTheme.specularHighlightBorder
        
        // 1. Futuristic Dominant Clock View (Left section, vertically centered, no clipping)
        addSubview(clockView)
        
        // 2. Subtle Vertical Divider
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NeumorphicTheme.specularHighlightBorder.withAlphaComponent(0.6).cgColor
        addSubview(dividerView)
        
        // 3. Mini Month Calendar View (Spacious right section)
        addSubview(miniCalendarView)
    }
    
    public func updateTime() {
        let now = Date()
        let newTime = timeFormatter.string(from: now)
        if clockView.timeString != newTime {
            clockView.timeString = newTime
        }
        miniCalendarView.updateCalendarData()
    }
    
    override public func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        guard w > 0 && h > 0 else { return }
        
        // Right calendar gets comfortable space (~118-136pt), giving maximum room to the enlarged clock
        let rightTargetW: CGFloat = max(118, min(136, w * 0.38))
        let splitX = max(150, min(260, w - rightTargetW - 10))
        let leftW = splitX - 4
        
        dividerView.frame = NSRect(x: splitX - 1, y: 10, width: 0.5, height: max(10, h - 20))
        
        clockView.frame = NSRect(x: 4, y: 0, width: leftW - 4, height: h)
        
        let rightX = splitX + 6
        let rightW = max(50, w - rightX - 6)
        let calTopY: CGFloat = 8
        let calH = max(20, h - calTopY - 8)
        miniCalendarView.frame = NSRect(x: rightX, y: calTopY, width: rightW, height: calH)
    }
}

public final class FloatingPillView: NSView {
    override public var isFlipped: Bool { return true }
    private let clipContainer = NSView()
    private let masterPanel = NeumorphicPanelContainerView()
    private let resizeHandle = ResizeHandleView()
    
    // Top Action Buttons
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
    public var onUserInteraction: (() -> Void)?
    public var onDragStateChanged: ((Bool) -> Void)?
    
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
        
        // Clip container hosts the drawer sliding in from the right edge
        clipContainer.wantsLayer = true
        clipContainer.layer?.backgroundColor = NSColor.clear.cgColor
        clipContainer.layer?.cornerRadius = 20
        clipContainer.layer?.masksToBounds = true
        addSubview(clipContainer)
        
        // Master Neumorphic Ceramic Slab Container
        masterPanel.cornerRadiusValue = 20
        masterPanel.panelBackgroundColor = NeumorphicTheme.masterBackground
        clipContainer.addSubview(masterPanel)
        
        // 1. Dedicated Large Clock Panel (occupies the top of the panel)
        masterPanel.contentView.addSubview(clockPanel)
        
        // 2. Integrated Calendar Panel
        calendarPanel.onHeightChanged = { [weak self] in
            self?.needsLayout = true
            self?.onHeightChanged?()
        }
        calendarPanel.onUserInteraction = { [weak self] in
            self?.onUserInteraction?()
        }
        calendarPanel.onDragStateChanged = { [weak self] isDragging in
            self?.onDragStateChanged?(isDragging)
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
        timeTickerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.clockPanel.updateTime()
        }
        if let timer = timeTickerTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String) {
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        let config = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        button.contentTintColor = NeumorphicTheme.textSecondary
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
    }
    
    private func updatePinButtonIcon() {
        let sym = isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        pinButton.image = NSImage(systemSymbolName: sym, accessibilityDescription: "Pin")?.withSymbolConfiguration(config)
        pinButton.contentTintColor = isPinned ? NeumorphicTheme.accentColor : NeumorphicTheme.textSecondary
        pinButton.toolTip = isPinned ? "Unpin side panel (auto-retract)" : "Pin side panel permanently"
    }
    
    @objc private func syncButtonClicked() {
        onUserInteraction?()
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
        onUserInteraction?()
        onOpenSettings?()
    }
    
    @objc private func pinButtonClicked() {
        onUserInteraction?()
        onTogglePin?()
    }
    
    @objc private func dismissButtonClicked() {
        onUserInteraction?()
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
        let hPad: CGFloat = 8
        let vPad: CGFloat = 8
        let finalRect = NSRect(x: hPad, y: vPad, width: max(200, bounds.width - hPad), height: max(100, bounds.height - (vPad * 2)))
        clipContainer.layer?.masksToBounds = true
        if !animated {
            masterPanel.frame = finalRect
            completion?()
            return
        }
        masterPanel.frame = NSRect(x: bounds.width, y: vPad, width: finalRect.width, height: finalRect.height)
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
        let hPad: CGFloat = 8
        let vPad: CGFloat = 8
        let targetRect = NSRect(x: bounds.width, y: vPad, width: max(200, bounds.width - hPad), height: max(100, bounds.height - (vPad * 2)))
        if !animated {
            masterPanel.frame = targetRect
            clipContainer.layer?.masksToBounds = true
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            masterPanel.animator().frame = targetRect
        }, completionHandler: { [weak self] in
            self?.clipContainer.layer?.masksToBounds = true
            completion?()
        })
    }
    
    public func calculateFittingSize() -> NSSize {
        let width = max(260, min(650, preferredPanelWidth))
        let panelW = max(200, width - 8)
        let clockH: CGFloat = 120
        let calH = calendarPanel.calculateFittingHeight(forWidth: panelW)
        let screenMaxH: CGFloat = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        let totalH = min(screenMaxH, max(340, clockH + calH + 24))
        return NSSize(width: width, height: totalH)
    }
    
    public func calculatePanelHeight(forWidth cardW: CGFloat) -> CGFloat {
        let clockH: CGFloat = 120
        let calH = calendarPanel.calculateFittingHeight(forWidth: cardW)
        return clockH + calH + 24
    }
    
    public override func layout() {
        super.layout()
        
        let b = bounds
        clipContainer.frame = b
        
        let hPad: CGFloat = 8
        let vPad: CGFloat = 8
        let panelW = max(260, b.width - hPad)
        let panelH = b.height - (vPad * 2)
        
        let targetX = isStretchedOut ? hPad : b.width
        masterPanel.frame = NSRect(x: targetX, y: vPad, width: panelW, height: panelH)
        masterPanel.layoutSubtreeIfNeeded()
        
        let cardW = panelW
        let cardH = panelH
        
        // 1. Dedicated Large Clock & Monthly Calendar Panel (top of panel)
        let clockH: CGFloat = 120
        let clockY: CGFloat = 10
        clockPanel.frame = NSRect(x: 14, y: clockY, width: max(0, cardW - 28), height: clockH)
        
        // 2. Calendar panel occupies space below clock panel
        let calY = clockY + clockH + 8
        let calH = max(0, cardH - calY - 6)
        calendarPanel.frame = NSRect(x: 0, y: calY, width: cardW, height: calH)
        
        resizeHandle.frame = NSRect(x: 0, y: 0, width: hPad + 14, height: bounds.height)
        window?.invalidateCursorRects(for: resizeHandle)
    }
}

