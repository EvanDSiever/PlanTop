import Foundation
import AppKit

public enum CalendarDayMode {
    case classes
    case today
    case tomorrow
}

final class FlippedCalendarDocumentView: NSView {
    override var isFlipped: Bool { return true }
}

// MARK: - Calendar Event Card View
final class FlippedContainerView: NSView {
    override var isFlipped: Bool { return true }
}

final class CalendarEventCardView: NeumorphicDepressedCardView {
    override var isFlipped: Bool { return true }
    public let event: CalendarEvent
    public var onOpenMeetURL: ((URL) -> Void)?
    public var onToggleExpand: (() -> Void)?
    
    public var isExpanded: Bool = false {
        didSet {
            updateExpandedViewsVisibility()
            needsLayout = true
        }
    }
    
    public var dayMode: CalendarDayMode = .today
    
    // Header elements (Row 1: Title & Chevron; Row 2: Full Time Range & Live Countdown Timer Badge)
    private let titleLabel = NSTextField(labelWithString: "")
    private let expandChevron = NSImageView()
    private let timeRangeLabel = NSTextField(labelWithString: "")
    private let timerBadgeLabel = NSTextField(labelWithString: "")
    
    // Expanded Detail Subviews inside elevated container casing
    public let detailCasing = NeumorphicElevatedCardView()
    private let fullDateLabel = NSTextField(labelWithString: "")
    private let locationLabel = NSTextField(labelWithString: "")
    private let notesLabel = NSTextField(wrappingLabelWithString: "")
    private let expandedMeetBtn = NeumorphicDynamicButton(frame: .zero)
    private let openCalAppBtn = NeumorphicDynamicButton(frame: .zero)
    
    public init(event: CalendarEvent, dayMode: CalendarDayMode = .today, frame: NSRect) {
        self.event = event
        self.dayMode = dayMode
        super.init(frame: frame)
        cornerRadiusValue = 12
        surfaceColor = NSColor.white
        outlineWidth = 0.5
        outlineColor = NeumorphicTheme.specularHighlightBorder
        setupViews()
        updateLiveStatus(relativeTo: Date())
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // 1. Collapsed Title Label (Avenir bold)
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.font = NeumorphicTheme.avenirFont(ofSize: 13.5, weight: .bold)
        titleLabel.textColor = NeumorphicTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        
        // 2. Expand chevron indicator
        let config = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
        expandChevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Toggle")?.withSymbolConfiguration(config)
        expandChevron.contentTintColor = NeumorphicTheme.textTertiary
        addSubview(expandChevron)
        
        // 3. Full Time Range Label (Row 2 Left - Both start and end, Avenir medium)
        timeRangeLabel.isBezeled = false
        timeRangeLabel.drawsBackground = false
        timeRangeLabel.isEditable = false
        timeRangeLabel.isSelectable = false
        timeRangeLabel.font = NeumorphicTheme.avenirFont(ofSize: 11.5, weight: .medium)
        timeRangeLabel.textColor = NeumorphicTheme.textSecondary
        timeRangeLabel.lineBreakMode = .byTruncatingTail
        addSubview(timeRangeLabel)
        
        // 4. Live Countdown Timer Badge Label (Row 2 Right - Monospaced digits)
        timerBadgeLabel.isBezeled = false
        timerBadgeLabel.drawsBackground = false
        timerBadgeLabel.isEditable = false
        timerBadgeLabel.isSelectable = false
        timerBadgeLabel.alignment = .right
        addSubview(timerBadgeLabel)
        
        // 4. Expanded Detail Casing (Plain flat container - borderless, lightened gray)
        detailCasing.cornerRadiusValue = 12
        detailCasing.surfaceColor = NSColor(white: 0.985, alpha: 1.0)
        detailCasing.outlineWidth = 0.0
        detailCasing.outlineColor = .clear
        detailCasing.isHidden = true
        detailCasing.alphaValue = 0.0
        addSubview(detailCasing)
        
        // Detail subviews inside casing (Larger typography, no duplicate title)
        fullDateLabel.isBezeled = false
        fullDateLabel.drawsBackground = false
        fullDateLabel.isEditable = false
        fullDateLabel.isSelectable = false
        detailCasing.addSubview(fullDateLabel)
        
        locationLabel.isBezeled = false
        locationLabel.drawsBackground = false
        locationLabel.isEditable = false
        locationLabel.isSelectable = false
        detailCasing.addSubview(locationLabel)
        
        notesLabel.isBezeled = false
        notesLabel.drawsBackground = false
        notesLabel.isEditable = false
        notesLabel.isSelectable = false
        detailCasing.addSubview(notesLabel)
        
        // Dynamic interactive buttons inside detail casing (drop shadow unpressed, inner shadow pressed)
        let meetStyle = NSMutableParagraphStyle()
        meetStyle.alignment = .center
        expandedMeetBtn.cornerRadiusValue = 8
        expandedMeetBtn.unpressedBackgroundColor = NeumorphicTheme.accentColor
        expandedMeetBtn.pressedBackgroundColor = NeumorphicTheme.accentColor.withAlphaComponent(0.85)
        expandedMeetBtn.attributedTitle = NSAttributedString(
            string: "Join Google Meet ↗",
            attributes: [
                .font: NeumorphicTheme.roundedFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: meetStyle
            ]
        )
        expandedMeetBtn.target = self
        expandedMeetBtn.action = #selector(handleMeetClicked)
        detailCasing.addSubview(expandedMeetBtn)
        
        let calStyle = NSMutableParagraphStyle()
        calStyle.alignment = .center
        openCalAppBtn.cornerRadiusValue = 8
        openCalAppBtn.unpressedBackgroundColor = NeumorphicTheme.cardElevated
        openCalAppBtn.pressedBackgroundColor = NeumorphicTheme.baseBackground
        openCalAppBtn.attributedTitle = NSAttributedString(
            string: "Open in Calendar ↗",
            attributes: [
                .font: NeumorphicTheme.roundedFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: NeumorphicTheme.textPrimary,
                .paragraphStyle: calStyle
            ]
        )
        openCalAppBtn.target = self
        openCalAppBtn.action = #selector(handleOpenCalAppClicked)
        detailCasing.addSubview(openCalAppBtn)
        
        updateExpandedViewsVisibility(animated: false)
    }
    
    private func timerAttributedString() -> NSAttributedString {
        let now = Date()
        let isClasses = (dayMode == .classes)
        let isToday = (dayMode == .today)
        let info = event.statusTimerInfo(isClassesCategory: isClasses, isTodayCategory: isToday, relativeTo: now)
        
        let prefixFont = NeumorphicTheme.avenirFont(ofSize: 11.0, weight: .medium)
        let timerFont = NeumorphicTheme.timerFont(ofSize: 11.5, weight: .bold)
        
        let color: NSColor
        if info.isEnded {
            color = NeumorphicTheme.textTertiary
        } else if event.isHappeningNow {
            color = NeumorphicTheme.coralAccent
        } else if isToday {
            color = NeumorphicTheme.accentColor
        } else {
            color = NeumorphicTheme.textSecondary
        }
        
        let attr = NSMutableAttributedString()
        if !info.prefix.isEmpty {
            attr.append(NSAttributedString(string: info.prefix, attributes: [
                .font: prefixFont,
                .foregroundColor: color.withAlphaComponent(0.85)
            ]))
        }
        attr.append(NSAttributedString(string: info.timer, attributes: [
            .font: timerFont,
            .foregroundColor: color
        ]))
        return attr
    }
    
    public func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        updateExpandedViewsVisibility(animated: animated)
    }
    
    private func updateExpandedViewsVisibility(animated: Bool = true) {
        let config = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
        let symName = isExpanded ? "chevron.up" : "chevron.down"
        expandChevron.image = NSImage(systemSymbolName: symName, accessibilityDescription: "Toggle")?.withSymbolConfiguration(config)
        
        if isExpanded {
            populateDetailData()
            detailCasing.isHidden = false
            if animated {
                detailCasing.alphaValue = 0.0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.30
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.detailCasing.animator().alphaValue = 1.0
                }
            } else {
                detailCasing.alphaValue = 1.0
            }
        } else {
            if animated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.detailCasing.animator().alphaValue = 0.0
                }, completionHandler: { [weak self] in
                    self?.detailCasing.isHidden = true
                })
            } else {
                detailCasing.alphaValue = 0.0
                detailCasing.isHidden = true
            }
        }
    }
    
    private func populateDetailData() {
        // Date & Time Typography (No emojis, bold uppercase day/date + monospaced rounded time span)
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE, MMM d"
        let startFmt = DateFormatter()
        startFmt.dateFormat = "h:mm a"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "h:mm a"
        
        let dayStr = dayFmt.string(from: event.startDate).uppercased()
        let timeSpan = "\(startFmt.string(from: event.startDate)) – \(endFmt.string(from: event.endDate))"
        
        let dateAttr = NSMutableAttributedString()
        dateAttr.append(NSAttributedString(
            string: dayStr,
            attributes: [
                .font: NeumorphicTheme.roundedFont(ofSize: 12.5, weight: .bold),
                .foregroundColor: NeumorphicTheme.textPrimary
            ]
        ))
        dateAttr.append(NSAttributedString(
            string: "  •  ",
            attributes: [
                .font: NeumorphicTheme.roundedFont(ofSize: 12.0, weight: .regular),
                .foregroundColor: NeumorphicTheme.textTertiary
            ]
        ))
        dateAttr.append(NSAttributedString(
            string: timeSpan,
            attributes: [
                .font: NeumorphicTheme.monospacedRoundedFont(ofSize: 12.0, weight: .medium),
                .foregroundColor: NeumorphicTheme.textSecondary
            ]
        ))
        fullDateLabel.attributedStringValue = dateAttr
        
        // Location Typography (No emojis, bold micro-tag + italic slate value)
        if let loc = event.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let locText = loc.trimmingCharacters(in: .whitespacesAndNewlines)
            let locAttr = NSMutableAttributedString()
            locAttr.append(NSAttributedString(
                string: "LOCATION  ",
                attributes: [
                    .font: NeumorphicTheme.roundedFont(ofSize: 11.0, weight: .bold),
                    .foregroundColor: NeumorphicTheme.accentColor
                ]
            ))
            let baseFont = NeumorphicTheme.roundedFont(ofSize: 12.5, weight: .medium)
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            locAttr.append(NSAttributedString(
                string: locText,
                attributes: [
                    .font: italicFont,
                    .foregroundColor: NeumorphicTheme.textSecondary
                ]
            ))
            locationLabel.attributedStringValue = locAttr
            locationLabel.isHidden = false
        } else {
            locationLabel.isHidden = true
        }
        
        // Notes Typography (No emojis, clean flat text, larger readable size)
        if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesLabel.stringValue = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            notesLabel.font = NeumorphicTheme.roundedFont(ofSize: 12.5, weight: .regular)
            notesLabel.textColor = NeumorphicTheme.textPrimary
            notesLabel.isHidden = false
        } else {
            let baseFont = NeumorphicTheme.roundedFont(ofSize: 12.0, weight: .regular)
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            notesLabel.stringValue = "No additional notes recorded for this event"
            notesLabel.font = italicFont
            notesLabel.textColor = NeumorphicTheme.textTertiary
            notesLabel.isHidden = false
        }
        
        let hasMeet = (event.meetURL != nil || event.url != nil)
        expandedMeetBtn.isHidden = !hasMeet
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let view = super.hitTest(point)
        if view == expandedMeetBtn || view == openCalAppBtn {
            return view
        }
        return self
    }
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    public override func mouseDown(with event: NSEvent) {
    }
    
    public override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        if isExpanded {
            let casingLoc = detailCasing.convert(loc, from: self)
            if !expandedMeetBtn.isHidden && expandedMeetBtn.frame.contains(casingLoc) {
                return
            }
            if !openCalAppBtn.isHidden && openCalAppBtn.frame.contains(casingLoc) {
                return
            }
        }
        onToggleExpand?()
    }
    
    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    @objc private func handleMeetClicked() {
        guard let url = event.meetURL ?? event.url else { return }
        if let onOpen = onOpenMeetURL {
            onOpen(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func handleOpenCalAppClicked() {
        GoogleCalendarService.shared.openCalendarApp()
    }
    
    public static func height(for event: CalendarEvent, isExpanded: Bool, width: CGFloat) -> CGFloat {
        if !isExpanded {
            return 64
        }
        let casingPad: CGFloat = 8
        let innerW = max(100, width - (casingPad * 2) - 24)
        
        var casingContentH: CGFloat = 12 // top padding inside detail container
        
        // 1. Full Date & Time (Avenir readable typography)
        casingContentH += 20 + 8
        
        // 2. Location (if any)
        if let loc = event.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            casingContentH += 20 + 8
        }
        
        // 3. Notes (Avenir readable typography)
        if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let notesFont = NeumorphicTheme.avenirFont(ofSize: 12.5, weight: .regular)
            let notesBounds = (notes as NSString).boundingRect(
                with: CGSize(width: innerW, height: 160),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: notesFont]
            )
            casingContentH += max(20, min(85, ceil(notesBounds.height))) + 12
        } else {
            casingContentH += 20 + 12
        }
        
        // 4. Buttons (height 32pt)
        casingContentH += 32 + 12
        
        let totalH = 62 + casingContentH + 10
        return totalH
    }
    
    public override func layout() {
        super.layout()
        updateWidth(bounds.width)
    }
    
    public func updateWidth(_ width: CGFloat) {
        let chevSize: CGFloat = 12
        let chevX = max(10, width - chevSize - 14)
        expandChevron.frame = NSRect(x: chevX, y: 14, width: chevSize, height: chevSize)
        
        let titleW = max(30, chevX - 14 - 8)
        titleLabel.frame = NSRect(x: 14, y: 10, width: titleW, height: 20)
        
        let timerAttr = timerAttributedString()
        timerBadgeLabel.attributedStringValue = timerAttr
        let timerSize = timerAttr.size()
        let timerW = ceil(timerSize.width) + 4
        let timerX = max(10, width - timerW - 14)
        timerBadgeLabel.frame = NSRect(x: timerX, y: 35, width: timerW, height: 18)
        
        let timeRangeW = max(20, timerX - 14 - 8)
        timeRangeLabel.frame = NSRect(x: 14, y: 35, width: timeRangeW, height: 18)
        
        if isExpanded {
            let targetCardH = CalendarEventCardView.height(for: event, isExpanded: true, width: width)
            let casingPad: CGFloat = 8
            let casingW = max(100, width - (casingPad * 2))
            let casingH = max(10, targetCardH - 62 - 10)
            detailCasing.frame = NSRect(x: casingPad, y: 62, width: casingW, height: casingH)
            
            let innerW = max(80, casingW - 24)
            var curY: CGFloat = 12
            
            fullDateLabel.frame = NSRect(x: 12, y: curY, width: innerW, height: 20)
            curY += 28
            
            if let loc = event.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                locationLabel.frame = NSRect(x: 12, y: curY, width: innerW, height: 20)
                curY += 28
            }
            
            let notesText = notesLabel.stringValue
            let notesFont = NeumorphicTheme.avenirFont(ofSize: 12.5, weight: .regular)
            let notesBounds = (notesText as NSString).boundingRect(
                with: CGSize(width: innerW, height: 160),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: notesFont]
            )
            let notesH = max(20, min(85, ceil(notesBounds.height)))
            notesLabel.frame = NSRect(x: 12, y: curY, width: innerW, height: notesH)
            curY += notesH + 14
            
            let hasMeet = (event.meetURL != nil || event.url != nil)
            let btnH: CGFloat = 32
            if hasMeet {
                let btnW = (innerW - 8) / 2
                expandedMeetBtn.frame = NSRect(x: 12, y: curY, width: btnW, height: btnH)
                openCalAppBtn.frame = NSRect(x: 12 + btnW + 8, y: curY, width: btnW, height: btnH)
            } else {
                openCalAppBtn.frame = NSRect(x: 12, y: curY, width: innerW, height: btnH)
            }
        }
    }
    
    public func updateLiveStatus(relativeTo now: Date) {
        let isPast = event.isPast
        let isHappeningNow = event.isHappeningNow
        
        timerBadgeLabel.attributedStringValue = timerAttributedString()
        
        if isPast {
            titleLabel.textColor = NeumorphicTheme.textTertiary
            timeRangeLabel.textColor = NeumorphicTheme.textTertiary
        } else if isHappeningNow {
            titleLabel.textColor = NeumorphicTheme.coralAccent
            timeRangeLabel.textColor = NeumorphicTheme.textPrimary
        } else {
            titleLabel.textColor = NeumorphicTheme.textPrimary
            timeRangeLabel.textColor = NeumorphicTheme.textSecondary
        }
        
        titleLabel.stringValue = event.title
        
        // Show full time range (both start and end, plus day if classes in future)
        let showDay = (dayMode == .classes)
        timeRangeLabel.stringValue = event.fullTimeRangeString(includeDay: showDay)
        
        updateWidth(frame.width)
    }
}

// MARK: - Neumorphic Tab Button
public final class NeumorphicTabButton: NeumorphicDynamicButton {
    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Single Unified Calendar Panel View with Switcher
public final class CalendarPanelView: NSView {
    public var dayMode: CalendarDayMode = .today {
        didSet {
            updateTabButtons()
            updateDateHeader()
            reloadFromService()
        }
    }
    public var onHeightChanged: (() -> Void)?
    public var onOpenMeetURL: ((URL) -> Void)?
    
    // Switcher bar container & tabs
    private let switcherContainer = NSView()
    private let classesTabBtn = NeumorphicTabButton()
    private let todayTabBtn = NeumorphicTabButton()
    private let tomorrowTabBtn = NeumorphicTabButton()
    private let openCalButton = NeumorphicTabButton()
    
    // Subtitle date header
    private let subtitleLabel = NSTextField(labelWithString: "")
    
    // Scrollable List
    private let scrollView = NSScrollView()
    private let documentContainer = FlippedCalendarDocumentView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let permissionContainer = NSView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let grantAccessButton = NeumorphicDynamicButton(frame: .zero)
    private let openSettingsButton = NeumorphicDynamicButton(frame: .zero)
    
    public var expandedEventId: String? = nil
    private var events: [CalendarEvent] = []
    private var secondTickerTimer: Timer?
    
    public init(dayMode: CalendarDayMode = .today, frame: NSRect = .zero) {
        self.dayMode = dayMode
        super.init(frame: frame)
        setupViews()
        registerObservers()
        updateTabButtons()
        updateDateHeader()
        reloadFromService()
        startSecondTicker()
    }
    
    required init?(coder: NSCoder) {
        self.dayMode = .today
        super.init(coder: coder)
        setupViews()
        registerObservers()
        updateTabButtons()
        updateDateHeader()
        reloadFromService()
        startSecondTicker()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        secondTickerTimer?.invalidate()
    }
    
    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalendarUpdated),
            name: .songTopCalendarUpdated,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalendarUpdated),
            name: .songTopSettingsChanged,
            object: nil
        )
    }
    
    @objc private func handleCalendarUpdated() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTabButtons()
            self?.updateDateHeader()
            self?.reloadFromService()
        }
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // 1. Switcher Container
        switcherContainer.wantsLayer = true
        addSubview(switcherContainer)
        
        styleTabButton(classesTabBtn, title: "Classes")
        styleTabButton(todayTabBtn, title: "Today")
        styleTabButton(tomorrowTabBtn, title: "Tomorrow")
        
        switcherContainer.addSubview(classesTabBtn)
        switcherContainer.addSubview(todayTabBtn)
        switcherContainer.addSubview(tomorrowTabBtn)
        
        configureIconButton(openCalButton, symbol: "calendar.badge.clock", tooltip: "Open Calendar App")
        openCalButton.target = self
        openCalButton.action = #selector(handleOpenCalendarClicked)
        switcherContainer.addSubview(openCalButton)
        
        // 2. Subtitle Label
        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.font = NeumorphicTheme.roundedFont(ofSize: 11, weight: .semibold)
        subtitleLabel.textColor = NeumorphicTheme.textTertiary
        addSubview(subtitleLabel)
        
        // 3. Scrollable List of Events (No scrollbars, clean edge-to-edge)
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 14
        scrollView.layer?.masksToBounds = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentContainer
        addSubview(scrollView)
        
        // 4. Empty State Label
        emptyStateLabel.isBezeled = false
        emptyStateLabel.drawsBackground = false
        emptyStateLabel.isEditable = false
        emptyStateLabel.isSelectable = false
        emptyStateLabel.font = NeumorphicTheme.roundedFont(ofSize: 11.5, weight: .medium)
        emptyStateLabel.textColor = NeumorphicTheme.textTertiary
        emptyStateLabel.alignment = .center
        emptyStateLabel.isHidden = true
        addSubview(emptyStateLabel)
        
        // 5. Permission State Container
        setupPermissionView()
        addSubview(permissionContainer)
        permissionContainer.isHidden = true
    }
    
    private func styleTabButton(_ btn: NeumorphicTabButton, title: String) {
        btn.title = title
        btn.cornerRadiusValue = 9
        btn.unpressedBackgroundColor = NSColor.white
        btn.pressedBackgroundColor = NeumorphicTheme.baseBackground
        btn.target = self
        btn.action = #selector(handleTabClicked(_:))
        btn.updateAppearance()
    }
    
    private func configureIconButton(_ button: NeumorphicTabButton, symbol: String, tooltip: String) {
        button.cornerRadiusValue = 9
        button.unpressedBackgroundColor = NSColor.white
        button.pressedBackgroundColor = NeumorphicTheme.baseBackground
        button.toolTip = tooltip
        
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            button.image = img
            button.imagePosition = .imageOnly
            button.contentTintColor = NeumorphicTheme.buttonIconTint
        }
        button.updateAppearance()
    }
    
    private func setupPermissionView() {
        permissionContainer.wantsLayer = true
        permissionContainer.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        permissionContainer.layer?.cornerRadius = 10
        
        permissionLabel.isBezeled = false
        permissionLabel.drawsBackground = false
        permissionLabel.isEditable = false
        permissionLabel.isSelectable = false
        permissionLabel.font = NeumorphicTheme.roundedFont(ofSize: 11, weight: .medium)
        permissionLabel.textColor = NeumorphicTheme.textSecondary
        permissionLabel.alignment = .center
        permissionLabel.stringValue = "Connect Google Calendar to see schedule"
        permissionContainer.addSubview(permissionLabel)
        
        styleMiniButton(grantAccessButton, title: "Grant Access")
        grantAccessButton.target = self
        grantAccessButton.action = #selector(handleGrantAccess)
        permissionContainer.addSubview(grantAccessButton)
        
        styleMiniButton(openSettingsButton, title: "Google Accounts")
        openSettingsButton.target = self
        openSettingsButton.action = #selector(handleOpenAccounts)
        permissionContainer.addSubview(openSettingsButton)
    }
    
    private func styleMiniButton(_ btn: NeumorphicDynamicButton, title: String) {
        btn.title = title
        btn.cornerRadiusValue = 7
        btn.unpressedBackgroundColor = NSColor.white
        btn.pressedBackgroundColor = NeumorphicTheme.baseBackground
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NeumorphicTheme.roundedFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NeumorphicTheme.textPrimary,
                .paragraphStyle: style
            ]
        )
        btn.updateAppearance()
    }
    
    public func updateTabButtons() {
        classesTabBtn.title = "Classes"
        todayTabBtn.title = "Today"
        tomorrowTabBtn.title = "Tomorrow"
        
        let tabs: [(NeumorphicTabButton, CalendarDayMode)] = [
            (classesTabBtn, .classes),
            (todayTabBtn, .today),
            (tomorrowTabBtn, .tomorrow)
        ]
        
        for (btn, mode) in tabs {
            let isSelected = (dayMode == mode)
            btn.isPressedDown = isSelected
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            if isSelected {
                btn.activeAccentColor = NeumorphicTheme.coralAccent
                btn.attributedTitle = NSAttributedString(
                    string: btn.title,
                    attributes: [
                        .font: NeumorphicTheme.roundedFont(ofSize: 11.5, weight: .bold),
                        .foregroundColor: NSColor.white,
                        .paragraphStyle: style
                    ]
                )
            } else {
                btn.activeAccentColor = nil
                btn.attributedTitle = NSAttributedString(
                    string: btn.title,
                    attributes: [
                        .font: NeumorphicTheme.roundedFont(ofSize: 11.5, weight: .medium),
                        .foregroundColor: NeumorphicTheme.textSecondary,
                        .paragraphStyle: style
                    ]
                )
            }
            btn.updateAppearance()
        }
    }
    
    private func updateDateHeader() {
        switch dayMode {
        case .classes:
            subtitleLabel.stringValue = "Academic Classes & Lectures"
        case .today:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            subtitleLabel.stringValue = formatter.string(from: Date())
        case .tomorrow:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            let targetDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            subtitleLabel.stringValue = formatter.string(from: targetDate)
        }
    }
    
    public func selectDayMode(_ mode: CalendarDayMode) {
        guard self.dayMode != mode else { return }
        self.dayMode = mode
        self.expandedEventId = nil
        self.updateTabButtons()
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.scrollView.animator().alphaValue = 0.0
            self.emptyStateLabel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.reloadFromService()
            self.needsLayout = true
            self.onHeightChanged?()
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.scrollView.animator().alphaValue = 1.0
                self.emptyStateLabel.animator().alphaValue = 1.0
            }
        })
    }
    
    @objc private func handleTabClicked(_ sender: NSButton) {
        if sender == classesTabBtn {
            selectDayMode(.classes)
        } else if sender == todayTabBtn {
            selectDayMode(.today)
        } else if sender == tomorrowTabBtn {
            selectDayMode(.tomorrow)
        }
    }
    
    public func reloadFromService() {
        updateTabButtons()
        updateDateHeader()
        let service = GoogleCalendarService.shared
        switch dayMode {
        case .classes:
            self.events = service.classesEvents
        case .today:
            self.events = service.todaysEvents
        case .tomorrow:
            self.events = service.tomorrowsEvents
        }
        
        let status = service.syncStatus
        switch status {
        case .needsPermission, .unauthorized:
            permissionContainer.isHidden = false
            scrollView.isHidden = true
            emptyStateLabel.isHidden = true
        default:
            permissionContainer.isHidden = true
            if events.isEmpty {
                emptyStateLabel.isHidden = false
                scrollView.isHidden = true
                switch dayMode {
                case .classes:
                    emptyStateLabel.stringValue = "No upcoming classes scheduled"
                case .today:
                    emptyStateLabel.stringValue = "No more events today"
                case .tomorrow:
                    emptyStateLabel.stringValue = "No events scheduled for tomorrow"
                }
            } else {
                emptyStateLabel.isHidden = true
                scrollView.isHidden = false
                rebuildEventCards()
            }
        }
        
        needsLayout = true
        onHeightChanged?()
    }
    
    private func rebuildEventCards() {
        documentContainer.subviews.forEach { $0.removeFromSuperview() }
        
        let stackWidth = scrollView.frame.width
        let cardPad: CGFloat = 4
        let cardW = max(180, stackWidth - (cardPad * 2))
        let cardGap: CGFloat = 7
        
        var totalH: CGFloat = 4
        for ev in events {
            let isExp = (expandedEventId == ev.id)
            let h = CalendarEventCardView.height(for: ev, isExpanded: isExp, width: cardW)
            totalH += h + cardGap
        }
        totalH = max(scrollView.frame.height, totalH + 4)
        documentContainer.frame = NSRect(x: 0, y: 0, width: stackWidth, height: totalH)
        
        var curY: CGFloat = 4
        for event in events {
            let isExp = (expandedEventId == event.id)
            let cardH = CalendarEventCardView.height(for: event, isExpanded: isExp, width: cardW)
            let card = CalendarEventCardView(event: event, dayMode: self.dayMode, frame: NSRect(x: cardPad, y: curY, width: cardW, height: cardH))
            card.setExpanded(isExp, animated: false)
            card.updateWidth(cardW)
            card.onOpenMeetURL = onOpenMeetURL
            card.onToggleExpand = { [weak self] in
                guard let self = self else { return }
                self.toggleExpandCard(for: event.id)
            }
            documentContainer.addSubview(card)
            curY += cardH + cardGap
        }
    }
    
    private func toggleExpandCard(for eventId: String) {
        if self.expandedEventId == eventId {
            self.expandedEventId = nil
        } else {
            self.expandedEventId = eventId
        }
        
        let stackWidth = scrollView.frame.width
        let cardPad: CGFloat = 4
        let cardW = max(180, stackWidth - (cardPad * 2))
        let cardGap: CGFloat = 7
        
        var totalH: CGFloat = 4
        for ev in events {
            let isExp = (expandedEventId == ev.id)
            let h = CalendarEventCardView.height(for: ev, isExpanded: isExp, width: cardW)
            totalH += h + cardGap
        }
        totalH = max(scrollView.frame.height, totalH + 4)
        
        let existingCards = documentContainer.subviews.compactMap { $0 as? CalendarEventCardView }
        
        // Notify parent controller to smoothly adjust panel window frame simultaneously
        self.onHeightChanged?()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            documentContainer.animator().frame = NSRect(x: 0, y: 0, width: stackWidth, height: totalH)
            
            var curY: CGFloat = 4
            for card in existingCards {
                let isExp = (self.expandedEventId == card.event.id)
                let cardH = CalendarEventCardView.height(for: card.event, isExpanded: isExp, width: cardW)
                let targetFrame = NSRect(x: cardPad, y: curY, width: cardW, height: cardH)
                card.animator().frame = targetFrame
                card.setExpanded(isExp, animated: true)
                card.updateWidth(cardW)
                curY += cardH + cardGap
            }
        }
    }
    
    private func startSecondTicker() {
        secondTickerTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCardTimers()
        }
        RunLoop.main.add(timer, forMode: .common)
        secondTickerTimer = timer
    }
    
    private func updateCardTimers() {
        guard !events.isEmpty else { return }
        let now = Date()
        for subview in documentContainer.subviews {
            if let card = subview as? CalendarEventCardView {
                card.updateLiveStatus(relativeTo: now)
            }
        }
    }
    
    @objc private func handleOpenCalendarClicked() {
        GoogleCalendarService.shared.openCalendarApp()
    }
    
    @objc private func handleGrantAccess() {
        GoogleCalendarService.shared.requestAccess { [weak self] _ in
            DispatchQueue.main.async {
                self?.reloadFromService()
            }
        }
    }
    
    @objc private func handleOpenAccounts() {
        GoogleCalendarService.shared.openSystemSettingsAccounts()
    }
    
    public func calculateFittingHeight(forWidth width: CGFloat) -> CGFloat {
        if !GoogleCalendarService.shared.isCalendarEnabled {
            return 0
        }
        
        let headerH: CGFloat = 58 // 30 (switcher) + 6 (gap) + 16 (subtitle) + 6 (gap)
        
        let status = GoogleCalendarService.shared.syncStatus
        if status == .needsPermission || status == .unauthorized {
            return headerH + 60
        }
        
        if events.isEmpty {
            return headerH + 40
        }
        
        let cardW = max(180, width - 28)
        let totalCardsH = events.reduce(CGFloat(0)) { sum, ev in
            let isExp = (expandedEventId == ev.id)
            let h = CalendarEventCardView.height(for: ev, isExpanded: isExp, width: cardW)
            return sum + h + 7
        }
        
        let boundedHeight = min(540, max(60, totalCardsH))
        return headerH + boundedHeight + 10
    }
    
    public override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        
        guard GoogleCalendarService.shared.isCalendarEnabled && h > 0 else {
            switcherContainer.isHidden = true
            subtitleLabel.isHidden = true
            scrollView.isHidden = true
            emptyStateLabel.isHidden = true
            permissionContainer.isHidden = true
            return
        }
        
        switcherContainer.isHidden = false
        subtitleLabel.isHidden = false
        
        // 1. Switcher Row (Top): y = h - 34
        let switcherY = h - 34
        switcherContainer.frame = NSRect(x: 14, y: switcherY, width: max(10, w - 28), height: 30)
        
        let calBtnSize: CGFloat = 28
        openCalButton.frame = NSRect(x: switcherContainer.frame.width - calBtnSize, y: 1, width: calBtnSize, height: calBtnSize)
        
        let tabAreaW = max(60, switcherContainer.frame.width - calBtnSize - 8)
        let tabGap: CGFloat = 5
        let tabW = max(40, (tabAreaW - (tabGap * 2)) / 3)
        
        classesTabBtn.frame = NSRect(x: 0, y: 1, width: tabW, height: 28)
        todayTabBtn.frame = NSRect(x: tabW + tabGap, y: 1, width: tabW, height: 28)
        tomorrowTabBtn.frame = NSRect(x: (tabW + tabGap) * 2, y: 1, width: tabW, height: 28)
        
        // 2. Subtitle Row: y = switcherY - 20
        let subY = switcherY - 20
        subtitleLabel.frame = NSRect(x: 16, y: subY, width: max(10, w - 32), height: 16)
        
        // 3. Content area below subtitle
        let contentY: CGFloat = 6
        let contentHeight = max(10, subY - contentY - 4)
        
        let status = GoogleCalendarService.shared.syncStatus
        if status == .needsPermission || status == .unauthorized {
            permissionContainer.isHidden = false
            emptyStateLabel.isHidden = true
            scrollView.isHidden = true
            permissionContainer.frame = NSRect(x: 14, y: contentY, width: max(10, w - 28), height: contentHeight)
            permissionLabel.frame = NSRect(x: 10, y: contentHeight - 24, width: permissionContainer.frame.width - 20, height: 16)
            grantAccessButton.frame = NSRect(x: (permissionContainer.frame.width / 2) - 95, y: 6, width: 90, height: 22)
            openSettingsButton.frame = NSRect(x: (permissionContainer.frame.width / 2) + 5, y: 6, width: 100, height: 22)
        } else if events.isEmpty {
            permissionContainer.isHidden = true
            emptyStateLabel.isHidden = false
            scrollView.isHidden = true
            emptyStateLabel.frame = NSRect(x: 14, y: contentY, width: max(10, w - 28), height: contentHeight)
        } else {
            permissionContainer.isHidden = true
            emptyStateLabel.isHidden = true
            scrollView.isHidden = false
            scrollView.frame = NSRect(x: 14, y: contentY, width: max(10, w - 28), height: contentHeight)
            let stackWidth = scrollView.frame.width
            let cardPad: CGFloat = 4
            let cardW = max(180, stackWidth - (cardPad * 2))
            let cardGap: CGFloat = 7
            
            var totalH: CGFloat = 4
            for ev in events {
                let isExp = (expandedEventId == ev.id)
                let ch = CalendarEventCardView.height(for: ev, isExpanded: isExp, width: cardW)
                totalH += ch + cardGap
            }
            totalH = max(contentHeight, totalH + 4)
            
            documentContainer.frame = NSRect(x: 0, y: 0, width: stackWidth, height: totalH)
            
            var curY: CGFloat = 4
            for subview in documentContainer.subviews {
                if let card = subview as? CalendarEventCardView {
                    let isExp = (expandedEventId == card.event.id)
                    let cardH = CalendarEventCardView.height(for: card.event, isExpanded: isExp, width: cardW)
                    let targetFrame = NSRect(x: cardPad, y: curY, width: cardW, height: cardH)
                    card.frame = targetFrame
                    card.updateWidth(cardW)
                    curY += cardH + cardGap
                }
            }
        }
    }
}
