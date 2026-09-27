import Foundation
import AppKit

public enum CalendarDayMode {
    case classes
    case tasks
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

public final class CalendarEventCardView: NeumorphicDepressedCardView {
    override public var isFlipped: Bool { return true }
    public let event: CalendarEvent
    public var onOpenMeetURL: ((URL) -> Void)?
    public var onOpenGoogleCalendarURL: ((URL) -> Void)?
    public var onToggleExpand: (() -> Void)?
    public var onRemoveEvent: (() -> Void)?
    public var onDragStart: ((CalendarEventCardView) -> Void)?
    public var onDragMoved: ((CalendarEventCardView, CGFloat, CGFloat) -> Void)?
    public var onDragEnd: ((CalendarEventCardView) -> Void)?
    
    public var isExpanded: Bool = false {
        didSet {
            updateExpandedViewsVisibility()
            needsLayout = true
        }
    }
    
    public var dayMode: CalendarDayMode = .today
    
    // Collapsed card height constant
    // Collapsed card height constant (Generous Apple HIG spacing convention)
    public static let collapsedCardHeight: CGFloat = 76
    
    // Header elements:
    // Left: titleClipView containing titleLabel (slides on hover if title overflows)
    // Left row 2: timerBadgeLabel (countdown timer) + expandChevron
    // Right: timeRangeLabel (prominent time display)
    // Far right: removeButton (fades in on hover)
    private let titleClipView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeRangeLabel = NSTextField(labelWithString: "")
    private let timerBadgeLabel = NSTextField(labelWithString: "")
    private let expandChevron = NSImageView()
    private let removeButton = NSButton()
    
    // Title marquee sliding on hover
    private var isTitleOverflowing: Bool = false
    private var titleOverflowAmount: CGFloat = 0.0
    private var isMouseInside: Bool = false
    private var titleSlideWorkItem: DispatchWorkItem?
    
    // Hover tracking
    private var trackingArea: NSTrackingArea?
    
    // Drag detection
    private var mouseDownLocation: NSPoint = .zero
    public var dragInitialOffsetInCardY: CGFloat = 0
    private var isDraggingCard: Bool = false
    private var hasTriggeredDragStart: Bool = false
    
    // Expanded Detail Subviews inside elevated container casing
    public let detailCasing = NeumorphicElevatedCardView()
    private let fullDateLabel = NSTextField(labelWithString: "")
    private let locationLabel = NSTextField(labelWithString: "")
    private let notesTextView: NSTextView = {
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isRichText = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        return tv
    }()
    private let expandedMeetBtn = NeumorphicDynamicButton(frame: .zero)
    private let openCalAppBtn = NeumorphicDynamicButton(frame: .zero)
    
    public init(event: CalendarEvent, dayMode: CalendarDayMode = .today, frame: NSRect) {
        self.event = event
        self.dayMode = dayMode
        super.init(frame: frame)
        cornerRadiusValue = 12
        surfaceColor = AppleTheme.cardBackground
        outlineWidth = 0.5
        outlineColor = AppleTheme.cardBorder
        setupViews()
        updateLiveStatus(relativeTo: Date())
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // 1. Collapsed Title Clipping View & Label (SF Pro headline 17pt, legibility floor)
        titleClipView.wantsLayer = true
        titleClipView.layer?.masksToBounds = true
        
        titleLabel.wantsLayer = true
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.font = AppleTheme.headlineFont
        titleLabel.textColor = AppleTheme.label
        titleLabel.lineBreakMode = .byClipping
        titleClipView.addSubview(titleLabel)
        addSubview(titleClipView)
        
        // 2. Event Time Label (SF Pro Monospaced Digits, calm and legible)
        timeRangeLabel.isBezeled = false
        timeRangeLabel.drawsBackground = false
        timeRangeLabel.isEditable = false
        timeRangeLabel.isSelectable = false
        timeRangeLabel.alignment = .right
        timeRangeLabel.font = AppleTheme.monospacedDigitFont(size: 20.0, weight: .regular)
        timeRangeLabel.textColor = AppleTheme.primary
        timeRangeLabel.lineBreakMode = .byClipping
        addSubview(timeRangeLabel)
        
        // 3. Remove Button (Fades in on hover on right edge)
        removeButton.isBordered = false
        removeButton.setButtonType(.momentaryChange)
        let removeConfig = NSImage.SymbolConfiguration(pointSize: 10.0, weight: .medium)
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove Event")?.withSymbolConfiguration(removeConfig) {
            removeButton.image = img
            removeButton.imagePosition = .imageOnly
            removeButton.contentTintColor = AppleTheme.secondaryLabel
        }
        removeButton.wantsLayer = true
        removeButton.layer?.cornerRadius = 11
        removeButton.layer?.backgroundColor = AppleTheme.cardBorder.cgColor
        removeButton.alphaValue = 0.0 // hidden until hover
        removeButton.target = self
        removeButton.action = #selector(handleRemoveClicked)
        addSubview(removeButton)
        
        // 4. Live Countdown Timer Badge Label (SF Pro subhead)
        timerBadgeLabel.isBezeled = false
        timerBadgeLabel.drawsBackground = false
        timerBadgeLabel.isEditable = false
        timerBadgeLabel.isSelectable = false
        timerBadgeLabel.alignment = .left
        timerBadgeLabel.lineBreakMode = .byClipping
        addSubview(timerBadgeLabel)
        
        // 5. Expand chevron indicator (Row 2 right)
        let config = NSImage.SymbolConfiguration(pointSize: 10.0, weight: .medium)
        expandChevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Toggle")?.withSymbolConfiguration(config)
        expandChevron.contentTintColor = AppleTheme.tertiaryLabel
        addSubview(expandChevron)
        
        // 6. Expanded Detail Casing (Translucent Inset Well)
        detailCasing.cornerRadiusValue = 12
        detailCasing.surfaceColor = AppleTheme.insetWell
        detailCasing.outlineWidth = 0.5
        detailCasing.outlineColor = AppleTheme.cardBorder
        detailCasing.isHidden = true
        detailCasing.alphaValue = 0.0
        addSubview(detailCasing)
        
        // Detail subviews inside casing
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
        
        detailCasing.addSubview(notesTextView)
        
        // Dynamic interactive buttons inside detail casing (Apple HIG minimum tap targets)
        let meetStyle = NSMutableParagraphStyle()
        meetStyle.alignment = .center
        expandedMeetBtn.cornerRadiusValue = 8
        expandedMeetBtn.unpressedBackgroundColor = AppleTheme.primary
        expandedMeetBtn.pressedBackgroundColor = AppleTheme.primary.withAlphaComponent(0.85)
        expandedMeetBtn.attributedTitle = NSAttributedString(
            string: "Join Google Meet ↗",
            attributes: [
                .font: AppleTheme.font(size: 13.0, weight: .bold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: meetStyle
            ]
        )
        expandedMeetBtn.target = self
        expandedMeetBtn.action = #selector(handleMeetClicked)
        detailCasing.addSubview(expandedMeetBtn)
        
        let calStyle = NSMutableParagraphStyle()
        calStyle.alignment = .center
        openCalAppBtn.cornerRadiusValue = 8
        openCalAppBtn.unpressedBackgroundColor = AppleTheme.cardBackground
        openCalAppBtn.pressedBackgroundColor = AppleTheme.secondarySystemBackground
        openCalAppBtn.attributedTitle = NSAttributedString(
            string: "Open in Google Calendar ↗",
            attributes: [
                .font: AppleTheme.font(size: 13.0, weight: .semibold),
                .foregroundColor: AppleTheme.label,
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
        
        // For Tasks section: only show the timer if the event is happening or due on the current day.
        // For all events that are not due or happening on the current day, simply show the date underneath the title.
        if dayMode == .tasks && !event.isHappeningOrDueToday(relativeTo: now) {
            let isCompact = (bounds.width > 0 && bounds.width < 340)
            let dateStr = event.occurrenceDateString(relativeTo: now, compact: isCompact)
            let dateFont = AppleTheme.font(size: 13.5, weight: .semibold)
            let dateColor = AppleTheme.secondaryLabel
            return NSAttributedString(string: dateStr, attributes: [
                .font: dateFont,
                .foregroundColor: dateColor
            ])
        }
        
        let isClasses = (dayMode == .classes || dayMode == .tasks)
        let isToday = (dayMode == .today)
        let info = event.statusTimerInfo(isClassesCategory: isClasses, isTodayCategory: isToday, relativeTo: now)
        
        let prefixFont = AppleTheme.font(size: 13.5, weight: .regular)
        let timerFont = AppleTheme.font(size: 14.5, weight: .semibold)
        
        let color: NSColor
        if info.isEnded {
            color = AppleTheme.tertiaryLabel
        } else if event.isHappeningNow || event.urgencyLevel(relativeTo: now) == .urgent {
            color = AppleTheme.primary
        } else {
            color = AppleTheme.secondaryLabel
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
        let config = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .regular)
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
        // Date & Time Typography (SF Pro)
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
                .font: AppleTheme.font(size: 13.0, weight: .medium),
                .foregroundColor: AppleTheme.label
            ]
        ))
        dateAttr.append(NSAttributedString(
            string: "  •  ",
            attributes: [
                .font: AppleTheme.font(size: 12.0, weight: .regular),
                .foregroundColor: AppleTheme.tertiaryLabel
            ]
        ))
        dateAttr.append(NSAttributedString(
            string: timeSpan,
            attributes: [
                .font: AppleTheme.font(size: 13.0, weight: .regular),
                .foregroundColor: AppleTheme.secondaryLabel
            ]
        ))
        fullDateLabel.attributedStringValue = dateAttr
        
        // Location Typography (Unbolded regular)
        if let loc = event.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let locText = loc.trimmingCharacters(in: .whitespacesAndNewlines)
            let locAttr = NSMutableAttributedString()
            locAttr.append(NSAttributedString(
                string: "LOCATION  ",
                attributes: [
                    .font: AppleTheme.font(size: 11.0, weight: .semibold),
                    .foregroundColor: AppleTheme.primary
                ]
            ))
            locAttr.append(NSAttributedString(
                string: locText,
                attributes: [
                    .font: AppleTheme.font(size: 13.0, weight: .regular),
                    .foregroundColor: AppleTheme.secondaryLabel
                ]
            ))
            locationLabel.attributedStringValue = locAttr
            locationLabel.isHidden = false
        } else {
            locationLabel.isHidden = true
        }
        
        // Notes Typography with HTML & Markdown rendering (no raw tags or syntax)
        if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formattedNotes = CalendarEvent.formatNotesAttributedString(
                notes,
                baseFontSize: 13.0,
                textColor: AppleTheme.label,
                linkColor: AppleTheme.primary
            )
            notesTextView.textStorage?.setAttributedString(formattedNotes)
            notesTextView.isHidden = false
        } else {
            let baseFont = AppleTheme.font(size: 13.0, weight: .regular)
            let emptyNotes = NSAttributedString(
                string: "No additional notes recorded for this event",
                attributes: [
                    .font: baseFont,
                    .foregroundColor: AppleTheme.tertiaryLabel
                ]
            )
            notesTextView.textStorage?.setAttributedString(emptyNotes)
            notesTextView.isHidden = false
        }
        
        let hasMeet = (event.meetURL != nil || event.url != nil)
        expandedMeetBtn.isHidden = !hasMeet
        
        let calStyle = NSMutableParagraphStyle()
        calStyle.alignment = .center
        let calTitle = hasMeet ? "Google Calendar ↗" : "Open in Google Calendar ↗"
        openCalAppBtn.attributedTitle = NSAttributedString(
            string: calTitle,
            attributes: [
                .font: AppleTheme.font(size: 12.5, weight: .semibold),
                .foregroundColor: AppleTheme.label,
                .paragraphStyle: calStyle
            ]
        )
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isMouseInside = true
        applyHoverEffect(isHovered: true, animated: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.removeButton.animator().alphaValue = 1.0
        }
        startTitleSlideAnimation()
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isMouseInside = false
        applyHoverEffect(isHovered: false, animated: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.removeButton.animator().alphaValue = 0.0
        }
        stopTitleSlideAnimation()
    }
    
    public func applyHoverEffect(isHovered: Bool, animated: Bool = true) {
        guard !isDraggingCard else { return }
        
        let targetSurface = isHovered ? AppleTheme.primary.withAlphaComponent(0.12) : AppleTheme.cardBackground
        let targetOutline = isHovered ? AppleTheme.primary.withAlphaComponent(0.50) : AppleTheme.cardBorder
        let targetBorderWidth: CGFloat = isHovered ? 0.75 : 0.5
        let targetShadowOpacity: Float = isHovered ? 0.36 : 0.22
        let targetShadowRadius: CGFloat = isHovered ? 13.0 : 8.0
        let targetShadowOffset = CGSize(width: 0, height: isHovered ? -3.5 : -2.5)
        
        let targetTransform: CATransform3D
        if isHovered && bounds.width > 0 && bounds.height > 0 {
            let midX = bounds.midX
            let midY = bounds.midY
            var t = CATransform3DMakeTranslation(midX, midY, 0)
            t = CATransform3DScale(t, 1.022, 1.022, 1.0)
            targetTransform = CATransform3DTranslate(t, -midX, -midY, 0)
        } else {
            targetTransform = CATransform3DIdentity
        }
        
        let duration: TimeInterval = isHovered ? 0.32 : 0.28
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        
        if isHovered {
            layer?.zPosition = 100
        }
        
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(timing)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self = self else { return }
                if !self.isMouseInside && !self.isDraggingCard {
                    self.layer?.zPosition = 0
                }
            }
            
            // 1. Gradual Scale & Position Transform
            let animTransform = CABasicAnimation(keyPath: "transform")
            animTransform.fromValue = layer?.presentation()?.transform ?? layer?.transform
            animTransform.toValue = targetTransform
            animTransform.duration = duration
            animTransform.timingFunction = timing
            layer?.add(animTransform, forKey: "hoverTransform")
            layer?.transform = targetTransform
            
            // 2. Gradual Background Color Interpolation
            let animBg = CABasicAnimation(keyPath: "backgroundColor")
            animBg.fromValue = visualEffectView.layer?.presentation()?.backgroundColor ?? visualEffectView.layer?.backgroundColor
            animBg.toValue = targetSurface.cgColor
            animBg.duration = duration
            animBg.timingFunction = timing
            visualEffectView.layer?.add(animBg, forKey: "hoverBg")
            visualEffectView.layer?.backgroundColor = targetSurface.cgColor
            
            // 3. Gradual Border Color Interpolation
            let animBorder = CABasicAnimation(keyPath: "borderColor")
            animBorder.fromValue = visualEffectView.layer?.presentation()?.borderColor ?? visualEffectView.layer?.borderColor
            animBorder.toValue = targetOutline.cgColor
            animBorder.duration = duration
            animBorder.timingFunction = timing
            visualEffectView.layer?.add(animBorder, forKey: "hoverBorder")
            visualEffectView.layer?.borderColor = targetOutline.cgColor
            
            // 4. Subtle Border Width Interpolation
            let animBorderW = CABasicAnimation(keyPath: "borderWidth")
            animBorderW.fromValue = visualEffectView.layer?.presentation()?.borderWidth ?? visualEffectView.layer?.borderWidth
            animBorderW.toValue = targetBorderWidth
            animBorderW.duration = duration
            animBorderW.timingFunction = timing
            visualEffectView.layer?.add(animBorderW, forKey: "hoverBorderW")
            visualEffectView.layer?.borderWidth = targetBorderWidth
            
            // 5. Shadow Depth Animations
            let animShadowOp = CABasicAnimation(keyPath: "shadowOpacity")
            animShadowOp.fromValue = layer?.presentation()?.shadowOpacity ?? layer?.shadowOpacity
            animShadowOp.toValue = targetShadowOpacity
            animShadowOp.duration = duration
            animShadowOp.timingFunction = timing
            layer?.add(animShadowOp, forKey: "hoverShadowOp")
            layer?.shadowOpacity = targetShadowOpacity
            
            let animShadowRad = CABasicAnimation(keyPath: "shadowRadius")
            animShadowRad.fromValue = layer?.presentation()?.shadowRadius ?? layer?.shadowRadius
            animShadowRad.toValue = targetShadowRadius
            animShadowRad.duration = duration
            animShadowRad.timingFunction = timing
            layer?.add(animShadowRad, forKey: "hoverShadowRad")
            layer?.shadowRadius = targetShadowRadius
            
            let animShadowOff = CABasicAnimation(keyPath: "shadowOffset")
            animShadowOff.fromValue = layer?.presentation()?.shadowOffset ?? layer?.shadowOffset
            animShadowOff.toValue = targetShadowOffset
            animShadowOff.duration = duration
            animShadowOff.timingFunction = timing
            layer?.add(animShadowOff, forKey: "hoverShadowOff")
            layer?.shadowOffset = targetShadowOffset
            
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.zPosition = isHovered ? 100 : 0
            layer?.transform = targetTransform
            layer?.shadowOpacity = targetShadowOpacity
            layer?.shadowRadius = targetShadowRadius
            layer?.shadowOffset = targetShadowOffset
            visualEffectView.layer?.backgroundColor = targetSurface.cgColor
            visualEffectView.layer?.borderColor = targetOutline.cgColor
            visualEffectView.layer?.borderWidth = targetBorderWidth
            CATransaction.commit()
        }
    }
    
    private func startTitleSlideAnimation() {
        titleSlideWorkItem?.cancel()
        titleSlideWorkItem = nil
        
        guard isTitleOverflowing else { return }
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isMouseInside, self.isTitleOverflowing else { return }
            self.performTitleSlide()
        }
        titleSlideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    
    private func stopTitleSlideAnimation() {
        titleSlideWorkItem?.cancel()
        titleSlideWorkItem = nil
        
        if isTitleOverflowing {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.titleLabel.animator().frame.origin.x = 0
            }
        }
    }
    
    private func performTitleSlide() {
        guard isMouseInside, isTitleOverflowing else { return }
        let targetX = -(titleOverflowAmount + 8)
        let duration = max(1.0, min(3.5, Double(titleOverflowAmount) / 40.0))
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.titleLabel.animator().frame.origin.x = targetX
        }, completionHandler: { [weak self] in
            guard let self = self, self.isMouseInside else { return }
            let pauseWork = DispatchWorkItem { [weak self] in
                guard let self = self, self.isMouseInside else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.50
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.titleLabel.animator().frame.origin.x = 0
                }, completionHandler: { [weak self] in
                    guard let self = self, self.isMouseInside else { return }
                    let loopWork = DispatchWorkItem { [weak self] in
                        guard let self = self, self.isMouseInside else { return }
                        self.performTitleSlide()
                    }
                    self.titleSlideWorkItem = loopWork
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: loopWork)
                })
            }
            self.titleSlideWorkItem = pauseWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: pauseWork)
        })
    }
    
    deinit {
        titleSlideWorkItem?.cancel()
    }
    
    @objc private func handleRemoveClicked() {
        onRemoveEvent?()
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        guard let view = super.hitTest(point) else { return nil }
        if view == removeButton || view.isDescendant(of: removeButton) {
            return removeButton
        }
        if view == expandedMeetBtn || view.isDescendant(of: expandedMeetBtn) {
            return expandedMeetBtn
        }
        if view == openCalAppBtn || view.isDescendant(of: openCalAppBtn) {
            return openCalAppBtn
        }
        if view == notesTextView || view.isDescendant(of: notesTextView) {
            return view
        }
        return self
    }
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    public override func mouseDown(with event: NSEvent) {
        let locInView = convert(event.locationInWindow, from: nil)
        if removeButton.frame.contains(locInView) {
            return
        }
        if isExpanded {
            let casingLoc = detailCasing.convert(locInView, from: self)
            if (!expandedMeetBtn.isHidden && expandedMeetBtn.frame.contains(casingLoc)) ||
               (!openCalAppBtn.isHidden && openCalAppBtn.frame.contains(casingLoc)) ||
               (!notesTextView.isHidden && notesTextView.frame.contains(casingLoc)) {
                return
            }
        }
        mouseDownLocation = event.locationInWindow
        dragInitialOffsetInCardY = max(0, min(bounds.height, locInView.y))
        isDraggingCard = false
        hasTriggeredDragStart = false
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let cur = event.locationInWindow
        let dx = cur.x - mouseDownLocation.x
        let dy = cur.y - mouseDownLocation.y
        
        if !isDraggingCard && (abs(dy) > 3 || abs(dx) > 3) {
            isDraggingCard = true
            hasTriggeredDragStart = true
            stopTitleSlideAnimation()
            onDragStart?(self)
        }
        
        if isDraggingCard {
            let parentLoc = superview?.convert(cur, from: nil) ?? .zero
            onDragMoved?(self, dy, parentLoc.y)
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        if isDraggingCard {
            isDraggingCard = false
            hasTriggeredDragStart = false
            onDragEnd?(self)
            return
        }
        
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        if removeButton.frame.contains(loc) {
            return
        }
        if isExpanded {
            let casingLoc = detailCasing.convert(loc, from: self)
            if !expandedMeetBtn.isHidden && expandedMeetBtn.frame.contains(casingLoc) {
                handleMeetClicked()
                return
            }
            if !openCalAppBtn.isHidden && openCalAppBtn.frame.contains(casingLoc) {
                handleOpenCalAppClicked()
                return
            }
            if !notesTextView.isHidden && notesTextView.frame.contains(casingLoc) {
                return
            }
        }
        onToggleExpand?()
    }
    
    public func setDraggingAppearance(_ isDragging: Bool) {
        if isDragging {
            outlineWidth = 1.5
            outlineColor = AppleTheme.primary.withAlphaComponent(0.65)
            surfaceColor = AppleTheme.cardBackground
            layer?.masksToBounds = false
            layer?.transform = CATransform3DIdentity
            layer?.zPosition = 200
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowRadius = 8.0
            layer?.shadowOpacity = 0.16
            layer?.shadowOffset = CGSize(width: 0, height: -2)
            alphaValue = 0.95
        } else {
            alphaValue = 1.0
            layer?.zPosition = isMouseInside ? 100 : 0
            applyHoverEffect(isHovered: isMouseInside, animated: false)
        }
        updateAppearance()
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
        let url = event.googleCalendarURL
        if let onOpen = onOpenGoogleCalendarURL {
            onOpen(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    
    public static func height(for event: CalendarEvent, isExpanded: Bool, width: CGFloat) -> CGFloat {
        if !isExpanded {
            return collapsedCardHeight
        }
        let casingPad: CGFloat = 8
        let innerW = max(100, width - (casingPad * 2) - 24)
        
        var casingContentH: CGFloat = 12 // top padding inside detail container
        
        // 1. Full Date & Time (SF Pro readable typography)
        casingContentH += 22 + 8
        
        // 2. Location (if any)
        if let loc = event.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            casingContentH += 20 + 8
        }
        
        // 3. Notes (SF Pro readable typography with rich formatted rendering)
        if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formattedNotes = CalendarEvent.formatNotesAttributedString(
                notes,
                baseFontSize: 13.0,
                textColor: AppleTheme.label,
                linkColor: AppleTheme.primary
            )
            let notesBounds = formattedNotes.boundingRect(
                with: CGSize(width: innerW, height: 220),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            casingContentH += max(20, min(140, ceil(notesBounds.height))) + 12
        } else {
            casingContentH += 20 + 12
        }
        
        // 4. Buttons (height 36pt, Apple HIG 8pt grid)
        casingContentH += 36 + 12
        
        let totalH = collapsedCardHeight + casingContentH + 10
        return totalH
    }
    
    public override func layout() {
        super.layout()
        updateWidth(bounds.width)
        if isMouseInside && !isDraggingCard {
            applyHoverEffect(isHovered: true, animated: false)
        }
    }
    
    public func updateWidth(_ width: CGFloat) {
        // Far Right: removeButton (fades in on hover in top-right corner)
        let rightPad: CGFloat = 16
        let removeBtnSize: CGFloat = 16
        let removeBtnX = max(10, width - removeBtnSize - 12)
        let removeBtnY: CGFloat = 6
        removeButton.frame = NSRect(x: removeBtnX, y: removeBtnY, width: removeBtnSize, height: removeBtnSize)
        removeButton.layer?.zPosition = 50
        
        let isUrgent = event.isHappeningNow || event.urgencyLevel(relativeTo: Date()) == .urgent
        let timeTextColor: NSColor
        if event.isPast {
            timeTextColor = AppleTheme.tertiaryLabel
        } else if isUrgent {
            timeTextColor = AppleTheme.primary
        } else {
            timeTextColor = NSColor(white: 0.90, alpha: 1.0)
        }
        
        let timeRangeW: CGFloat
        let timeLabelH: CGFloat
        if event.isAllDay {
            let timeFont = AppleTheme.font(size: 18.0, weight: .semibold)
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .right
            let attr = NSAttributedString(string: "All Day", attributes: [
                .font: timeFont,
                .foregroundColor: timeTextColor,
                .paragraphStyle: pStyle
            ])
            timeRangeLabel.attributedStringValue = attr
            let timeStrSize = attr.size()
            timeRangeW = min(max(75, width * 0.45), ceil(timeStrSize.width) + 4)
            timeLabelH = 28.0
        } else if event.startDate == event.endDate {
            let timeFmt = DateFormatter()
            timeFmt.timeStyle = .short
            let s = timeFmt.string(from: event.startDate)
            let timeFont = AppleTheme.monospacedDigitFont(size: 20.0, weight: .semibold)
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .right
            let attr = NSAttributedString(string: s, attributes: [
                .font: timeFont,
                .foregroundColor: timeTextColor,
                .paragraphStyle: pStyle
            ])
            timeRangeLabel.attributedStringValue = attr
            let timeStrSize = attr.size()
            timeRangeW = min(max(80, width * 0.50), ceil(timeStrSize.width) + 4)
            timeLabelH = 30.0
        } else {
            // Single Line Starting Time & Ending Time (Unstacked, prominent on one line)
            let timeFmt = DateFormatter()
            timeFmt.timeStyle = .short
            let s = timeFmt.string(from: event.startDate)
            let e = timeFmt.string(from: event.endDate)
            
            let timeFontSize: CGFloat
            if width >= 520 {
                timeFontSize = 20.0
            } else if width >= 460 {
                timeFontSize = 19.0
            } else if width >= 400 {
                timeFontSize = 18.0
            } else if width >= 340 {
                timeFontSize = 17.0
            } else {
                timeFontSize = 15.0
            }
            
            let timeFont = AppleTheme.monospacedDigitFont(size: timeFontSize, weight: .semibold)
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .right
            
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: s, attributes: [
                .font: timeFont,
                .foregroundColor: timeTextColor,
                .paragraphStyle: pStyle
            ]))
            attr.append(NSAttributedString(string: " – ", attributes: [
                .font: timeFont,
                .foregroundColor: timeTextColor.withAlphaComponent(0.65),
                .paragraphStyle: pStyle
            ]))
            attr.append(NSAttributedString(string: e, attributes: [
                .font: timeFont,
                .foregroundColor: timeTextColor,
                .paragraphStyle: pStyle
            ]))
            
            timeRangeLabel.attributedStringValue = attr
            let timeStrSize = attr.size()
            timeRangeW = min(max(90, width * 0.62), ceil(timeStrSize.width) + 4)
            timeLabelH = 28.0
        }
        
        // Vertically centered inside collapsed card container with balanced padding
        let timeLabelY = (CalendarEventCardView.collapsedCardHeight - timeLabelH) / 2
        let timeRangeX = max(10, width - timeRangeW - rightPad)
        timeRangeLabel.frame = NSRect(x: timeRangeX, y: timeLabelY, width: timeRangeW, height: timeLabelH)
        
        // Row 1: Left = titleClipView containing titleLabel (16pt left padding matching rightPad)
        let leftPad: CGFloat = 16
        let titleAvailableW = max(30, timeRangeX - leftPad - 12)
        let titleFont = AppleTheme.headlineFont
        titleLabel.font = titleFont
        titleLabel.textColor = AppleTheme.label
        titleLabel.stringValue = event.title
        let fullTitleSize = (event.title as NSString).size(withAttributes: [.font: titleFont])
        let fullTitleW = ceil(fullTitleSize.width) + 6
        
        titleClipView.frame = NSRect(x: leftPad, y: 12, width: titleAvailableW, height: 24)
        
        if fullTitleW > titleAvailableW {
            isTitleOverflowing = true
            titleOverflowAmount = fullTitleW - titleAvailableW
            titleLabel.frame = NSRect(x: 0, y: 0, width: fullTitleW, height: 24)
        } else {
            isTitleOverflowing = false
            titleOverflowAmount = 0
            titleLabel.frame = NSRect(x: 0, y: 0, width: titleAvailableW, height: 24)
        }
        if !isMouseInside {
            titleLabel.frame.origin.x = 0
        }
        
        // Row 2: Left = timerBadgeLabel underneath title, Right of timer = expandChevron
        let timerAttr = timerAttributedString()
        timerBadgeLabel.attributedStringValue = timerAttr
        let timerSize = timerAttr.size()
        let maxTimerW = max(40, timeRangeX - leftPad - 8)
        let timerW = min(maxTimerW, ceil(timerSize.width) + 4)
        timerBadgeLabel.frame = NSRect(x: leftPad, y: 40, width: timerW, height: 24)
        
        let chevSize: CGFloat = 12
        let chevX = timerBadgeLabel.frame.maxX + 6
        if chevX + chevSize + 4 <= timeRangeX {
            expandChevron.isHidden = false
            expandChevron.frame = NSRect(x: chevX, y: 46, width: chevSize, height: chevSize)
        } else {
            expandChevron.isHidden = true
        }
        
        if isExpanded {
            let targetCardH = CalendarEventCardView.height(for: event, isExpanded: true, width: width)
            let casingPad: CGFloat = 8
            let casingW = max(100, width - (casingPad * 2))
            let casingH = max(10, targetCardH - CalendarEventCardView.collapsedCardHeight - 10)
            detailCasing.frame = NSRect(x: casingPad, y: CalendarEventCardView.collapsedCardHeight, width: casingW, height: casingH)
            
            let innerW = max(80, casingW - 24)
            var curY: CGFloat = 12
            
            fullDateLabel.frame = NSRect(x: 12, y: curY, width: innerW, height: 22)
            curY += 30
            
            if let loc = event.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                locationLabel.frame = NSRect(x: 12, y: curY, width: innerW, height: 20)
                curY += 28
            }
            
            let notesBounds: NSRect
            if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let formattedNotes = CalendarEvent.formatNotesAttributedString(
                    notes,
                    baseFontSize: 13.0,
                    textColor: AppleTheme.label,
                    linkColor: AppleTheme.primary
                )
                notesBounds = formattedNotes.boundingRect(
                    with: CGSize(width: innerW, height: 220),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                notesTextView.textStorage?.setAttributedString(formattedNotes)
            } else {
                let baseFont = AppleTheme.font(size: 13.0, weight: .regular)
                let emptyNotes = NSAttributedString(
                    string: "No additional notes recorded for this event",
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: AppleTheme.tertiaryLabel
                    ]
                )
                notesBounds = NSRect(x: 0, y: 0, width: innerW, height: 20)
                notesTextView.textStorage?.setAttributedString(emptyNotes)
            }
            let notesH = max(20, min(140, ceil(notesBounds.height)))
            notesTextView.frame = NSRect(x: 12, y: curY, width: innerW, height: notesH)
            curY += notesH + 14
            
            let hasMeet = (event.meetURL != nil || event.url != nil)
            let btnH: CGFloat = 36
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
        
        timerBadgeLabel.attributedStringValue = timerAttributedString()
        
        if isPast {
            titleLabel.textColor = AppleTheme.tertiaryLabel
        } else {
            titleLabel.textColor = AppleTheme.label
        }
        
        titleLabel.stringValue = event.title
        
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
    override public var isFlipped: Bool { return true }
    public var dayMode: CalendarDayMode = .today {
        didSet {
            guard !isTransitioningCategory else { return }
            updateTabButtons()
            updateDateHeader()
            reloadFromService()
        }
    }
    public var onHeightChanged: (() -> Void)?
    public var onOpenMeetURL: ((URL) -> Void)?
    public var onOpenGoogleCalendarURL: ((URL) -> Void)?
    public var onUserInteraction: (() -> Void)?
    
    // Switcher bar container & tabs (Floating Glass Pill Island)
    private let switcherContainer = NeumorphicDepressedCardView()
    private let classesTabBtn = NeumorphicTabButton()
    private let tasksTabBtn = NeumorphicTabButton()
    private let todayTabBtn = NeumorphicTabButton()
    private let tomorrowTabBtn = NeumorphicTabButton()
    private let openCalButton = NeumorphicTabButton()
    
    // Subtitle date header
    private let subtitleLabel = NSTextField(labelWithString: "")
    
    // Scrollable List with Soft Gradient Dissolve
    private let scrollView = NSScrollView()
    private let scrollFadeMask = CAGradientLayer()
    private let documentContainer = FlippedCalendarDocumentView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let permissionContainer = NeumorphicDepressedCardView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let grantAccessButton = NeumorphicDynamicButton(frame: .zero)
    private let openSettingsButton = NeumorphicDynamicButton(frame: .zero)
    
    // Undo Toast HUD
    private let undoToastView = NeumorphicDepressedCardView()
    private let undoToastIcon = NSImageView()
    private let undoToastLabel = NSTextField(labelWithString: "")
    private let undoToastButton = NeumorphicDynamicButton(frame: .zero)
    private let undoToastCloseBtn = NSButton()
    private var undoToastDismissTimer: Timer?
    
    public var expandedEventId: String? = nil
    public var onDragStateChanged: ((Bool) -> Void)?
    private var events: [CalendarEvent] = []
    private var cardViews: [CalendarEventCardView] = []
    private var isDraggingAnyCard: Bool = false
    private var autoScrollTimer: Timer?
    private var lastDragMouseParentY: CGFloat = 0
    private var isTransitioningCategory: Bool = false
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
        autoScrollTimer?.invalidate()
        undoToastDismissTimer?.invalidate()
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
            guard let self = self, !self.isDraggingAnyCard && !self.isTransitioningCategory else { return }
            self.updateTabButtons()
            self.updateDateHeader()
            self.reloadFromService()
        }
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // 1. Switcher Container (Floating Liquid Glass Pill Island)
        switcherContainer.cornerRadiusValue = 12
        switcherContainer.surfaceColor = AppleTheme.cardBackground
        switcherContainer.outlineColor = AppleTheme.cardBorder
        switcherContainer.outlineWidth = 0.5
        addSubview(switcherContainer)
        
        styleTabButton(classesTabBtn, title: "Classes")
        styleTabButton(tasksTabBtn, title: "Tasks")
        styleTabButton(todayTabBtn, title: "Today")
        styleTabButton(tomorrowTabBtn, title: "Tomorrow")
        
        switcherContainer.addSubview(classesTabBtn)
        switcherContainer.addSubview(tasksTabBtn)
        switcherContainer.addSubview(todayTabBtn)
        switcherContainer.addSubview(tomorrowTabBtn)
        
        configureIconButton(openCalButton, symbol: "calendar.badge.clock", tooltip: "Open Google Calendar")
        openCalButton.target = self
        openCalButton.action = #selector(handleOpenCalendarClicked)
        switcherContainer.addSubview(openCalButton)
        
        // 2. Subtitle Label (SF Pro typography)
        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.font = AppleTheme.font(size: 13.0, weight: .medium)
        subtitleLabel.textColor = AppleTheme.secondaryLabel
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
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollViewBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        addSubview(scrollView)
        
        // 4. Empty State Label (SF Pro callout)
        emptyStateLabel.isBezeled = false
        emptyStateLabel.drawsBackground = false
        emptyStateLabel.isEditable = false
        emptyStateLabel.isSelectable = false
        emptyStateLabel.font = AppleTheme.calloutFont
        emptyStateLabel.textColor = AppleTheme.secondaryLabel
        emptyStateLabel.alignment = .center
        emptyStateLabel.isHidden = true
        addSubview(emptyStateLabel)
        
        // 5. Permission State Container
        setupPermissionView()
        addSubview(permissionContainer)
        permissionContainer.isHidden = true
        
        // 6. Undo Toast HUD
        setupUndoToastView()
    }
    
    private func styleTabButton(_ btn: NeumorphicTabButton, title: String) {
        btn.title = title
        btn.cornerRadiusValue = 8
        btn.unpressedBackgroundColor = NSColor.clear
        btn.unpressedBorderColor = NSColor.clear
        btn.unpressedBorderWidth = 0.0
        btn.pressedBackgroundColor = AppleTheme.primary
        btn.target = self
        btn.action = #selector(handleTabClicked(_:))
        btn.updateAppearance()
    }
    
    private func configureIconButton(_ button: NeumorphicTabButton, symbol: String, tooltip: String) {
        button.cornerRadiusValue = 8
        button.unpressedBackgroundColor = NSColor.clear
        button.unpressedBorderColor = NSColor.clear
        button.unpressedBorderWidth = 0.0
        button.pressedBackgroundColor = AppleTheme.insetWell
        button.toolTip = tooltip
        
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            button.image = img
            button.imagePosition = .imageOnly
            button.contentTintColor = AppleTheme.primary
        }
        button.updateAppearance()
    }
    
    private func setupPermissionView() {
        permissionContainer.cornerRadiusValue = 14
        permissionContainer.surfaceColor = AppleTheme.cardBackground
        permissionContainer.outlineColor = AppleTheme.cardBorder
        permissionContainer.outlineWidth = 0.5
        
        permissionLabel.isBezeled = false
        permissionLabel.drawsBackground = false
        permissionLabel.isEditable = false
        permissionLabel.isSelectable = false
        permissionLabel.font = AppleTheme.subheadFont
        permissionLabel.textColor = AppleTheme.secondaryLabel
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
        btn.cornerRadiusValue = 8
        btn.unpressedBackgroundColor = AppleTheme.cardBackground
        btn.pressedBackgroundColor = AppleTheme.insetWell
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AppleTheme.font(size: 12.0, weight: .medium),
                .foregroundColor: AppleTheme.primary,
                .paragraphStyle: style
            ]
        )
        btn.updateAppearance()
    }
    
    public func updateTabButtons() {
        classesTabBtn.title = "Classes"
        tasksTabBtn.title = "Tasks"
        todayTabBtn.title = "Today"
        tomorrowTabBtn.title = "Tomorrow"
        
        let tabs: [(NeumorphicTabButton, CalendarDayMode)] = [
            (classesTabBtn, .classes),
            (tasksTabBtn, .tasks),
            (todayTabBtn, .today),
            (tomorrowTabBtn, .tomorrow)
        ]
        
        for (btn, mode) in tabs {
            let isSelected = (dayMode == mode)
            btn.isPressedDown = isSelected
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            if isSelected {
                btn.activeAccentColor = AppleTheme.primary
                btn.attributedTitle = NSAttributedString(
                    string: btn.title,
                    attributes: [
                        .font: AppleTheme.font(size: 13.0, weight: .bold),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: style
                    ]
                )
            } else {
                btn.activeAccentColor = nil
                btn.attributedTitle = NSAttributedString(
                    string: btn.title,
                    attributes: [
                        .font: AppleTheme.font(size: 13.0, weight: .regular),
                        .foregroundColor: AppleTheme.secondaryLabel,
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
            subtitleLabel.stringValue = "Today's Classes & Lectures"
        case .tasks:
            subtitleLabel.stringValue = "This Week's Tasks & Deadlines"
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
        onUserInteraction?()
        isTransitioningCategory = true
        self.dayMode = mode
        self.expandedEventId = nil
        self.updateTabButtons()
        self.updateDateHeader()
        
        let service = GoogleCalendarService.shared
        
        // Fast, smooth crossfade transition
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.scrollView.animator().alphaValue = 0.0
            self.emptyStateLabel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            let currentMode = self.dayMode
            let nextEvents: [CalendarEvent]
            switch currentMode {
            case .classes:
                nextEvents = service.classesEvents
            case .tasks:
                let (startOfWeek, endOfWeek) = GoogleCalendarService.currentWeekInterval(for: Date())
                nextEvents = service.tasksEvents.filter {
                    $0.isReportOrHomework && $0.startDate < endOfWeek && $0.endDate >= startOfWeek
                }
            case .today:
                nextEvents = service.todaysEvents
            case .tomorrow:
                nextEvents = service.tomorrowsEvents
            }
            self.events = nextEvents
            
            // Reset scroll position cleanly to top
            self.scrollView.contentView.scroll(to: .zero)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            
            let status = service.syncStatus
            if status == .needsPermission || status == .unauthorized {
                self.permissionContainer.isHidden = false
                self.scrollView.isHidden = true
                self.emptyStateLabel.isHidden = true
            } else if self.events.isEmpty {
                self.permissionContainer.isHidden = true
                self.emptyStateLabel.isHidden = false
                self.scrollView.isHidden = true
                switch self.dayMode {
                case .classes: self.emptyStateLabel.stringValue = "No classes scheduled for today"
                case .tasks: self.emptyStateLabel.stringValue = "No tasks scheduled for this week"
                case .today: self.emptyStateLabel.stringValue = "No more events today"
                case .tomorrow: self.emptyStateLabel.stringValue = "No events scheduled for tomorrow"
                }
            } else {
                self.permissionContainer.isHidden = true
                self.emptyStateLabel.isHidden = true
                self.scrollView.isHidden = false
                self.rebuildEventCards()
            }
            
            // Adjust panel height cleanly for destination size
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.onHeightChanged?()
            
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.scrollView.animator().alphaValue = 1.0
                self.emptyStateLabel.animator().alphaValue = 1.0
            }, completionHandler: { [weak self] in
                self?.isTransitioningCategory = false
            })
        })
    }
    
    @objc private func handleTabClicked(_ sender: NSButton) {
        onUserInteraction?()
        if sender == classesTabBtn {
            selectDayMode(.classes)
        } else if sender == tasksTabBtn {
            selectDayMode(.tasks)
        } else if sender == todayTabBtn {
            selectDayMode(.today)
        } else if sender == tomorrowTabBtn {
            selectDayMode(.tomorrow)
        }
    }
    
    public func reloadFromService() {
        guard !isTransitioningCategory else { return }
        updateTabButtons()
        updateDateHeader()
        let service = GoogleCalendarService.shared
        switch dayMode {
        case .classes:
            self.events = service.classesEvents
        case .tasks:
            let (startOfWeek, endOfWeek) = GoogleCalendarService.currentWeekInterval(for: Date())
            self.events = service.tasksEvents.filter {
                $0.isReportOrHomework && $0.startDate < endOfWeek && $0.endDate >= startOfWeek
            }
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
                    emptyStateLabel.stringValue = "No classes scheduled for today"
                case .tasks:
                    emptyStateLabel.stringValue = "No tasks scheduled for this week"
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
        cardViews.removeAll()
        
        let stackWidth = scrollView.frame.width
        let cardPad: CGFloat = 6
        let cardW = max(180, stackWidth - (cardPad * 2))
        let cardGap: CGFloat = 11
        
        var curY: CGFloat = 6
        for event in events {
            let isExp = (expandedEventId == event.id)
            let cardH = CalendarEventCardView.height(for: event, isExpanded: isExp, width: cardW)
            let card = CalendarEventCardView(event: event, dayMode: self.dayMode, frame: NSRect(x: cardPad, y: curY, width: cardW, height: cardH))
            card.setExpanded(isExp, animated: false)
            card.updateWidth(cardW)
            card.onOpenMeetURL = onOpenMeetURL
            card.onOpenGoogleCalendarURL = onOpenGoogleCalendarURL
            card.onToggleExpand = { [weak self] in
                guard let self = self else { return }
                self.toggleExpandCard(for: event.id)
            }
            card.onRemoveEvent = { [weak self, weak card] in
                guard let self = self, let card = card else { return }
                self.handleRemoveEvent(card: card)
            }
            card.onDragStart = { [weak self, weak card] _ in
                guard let self = self, let card = card else { return }
                self.handleDragStart(card: card)
            }
            card.onDragMoved = { [weak self, weak card] _, dy, parentY in
                guard let self = self, let card = card else { return }
                self.handleDragMoved(card: card, dy: dy, parentY: parentY)
            }
            card.onDragEnd = { [weak self, weak card] _ in
                guard let self = self, let card = card else { return }
                self.handleDragEnd(card: card)
            }
            documentContainer.addSubview(card)
            cardViews.append(card)
            curY += cardH + cardGap
        }
        
        updateCardStackPositions(animated: false)
    }
    
    private func handleRemoveEvent(card: CalendarEventCardView) {
        let event = card.event
        GoogleCalendarService.shared.dismissEvent(event)
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            card.animator().frame.origin.x = self.bounds.width + 40
            card.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            card.removeFromSuperview()
            self.events.removeAll(where: { $0.id == event.id })
            self.cardViews.removeAll(where: { $0 == card })
            
            if self.events.isEmpty {
                self.reloadFromService()
            } else {
                self.updateCardStackPositions(animated: true)
                self.onHeightChanged?()
            }
            
            self.showUndoToast(for: event.title)
        })
    }
    
    private func handleDragStart(card: CalendarEventCardView) {
        isDraggingAnyCard = true
        onDragStateChanged?(true)
        onUserInteraction?()
        
        // Elevate card above peers without removing from superview
        documentContainer.addSubview(card, positioned: .above, relativeTo: nil)
        card.layer?.zPosition = 1000
        card.setDraggingAppearance(true)
        
        startAutoScrollTimer(for: card)
    }
    
    private func startAutoScrollTimer(for card: CalendarEventCardView) {
        autoScrollTimer?.invalidate()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self, weak card] _ in
            guard let self = self, let card = card, self.isDraggingAnyCard else { return }
            self.checkAndPerformAutoScroll(card: card)
        }
    }
    
    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
    
    private func checkAndPerformAutoScroll(card: CalendarEventCardView) {
        guard isDraggingAnyCard else { return }
        let visibleRect = scrollView.contentView.bounds
        let parentY = lastDragMouseParentY
        guard parentY > 0 else { return }
        
        let scrollMargin: CGFloat = 36.0
        let topThreshold = visibleRect.minY + scrollMargin
        let bottomThreshold = visibleRect.maxY - scrollMargin
        
        var didScroll = false
        if parentY < topThreshold {
            let distance = topThreshold - parentY
            let step = max(2.0, min(12.0, (distance / scrollMargin) * 12.0))
            let newY = max(0, visibleRect.minY - step)
            if newY != visibleRect.minY {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: newY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                didScroll = true
            }
        } else if parentY > bottomThreshold {
            let distance = parentY - bottomThreshold
            let step = max(2.0, min(12.0, (distance / scrollMargin) * 12.0))
            let maxScroll = max(0, documentContainer.frame.height - visibleRect.height)
            let newY = min(maxScroll, visibleRect.minY + step)
            if newY != visibleRect.minY {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: newY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                didScroll = true
            }
        }
        
        if didScroll {
            let rawTargetY = parentY - card.dragInitialOffsetInCardY
            let minCardY: CGFloat = 4
            let maxCardY = max(minCardY, documentContainer.frame.height - card.frame.height - 4)
            let clampedY = max(minCardY, min(maxCardY, rawTargetY))
            card.frame.origin.y = clampedY
            reorderSlotsIfNeeded(for: card, clampedY: clampedY)
        }
    }
    
    private func handleDragMoved(card: CalendarEventCardView, dy: CGFloat, parentY: CGFloat) {
        guard isDraggingAnyCard else { return }
        lastDragMouseParentY = parentY
        
        let rawTargetY = parentY - card.dragInitialOffsetInCardY
        let minCardY: CGFloat = 4
        let maxCardY = max(minCardY, documentContainer.frame.height - card.frame.height - 4)
        let clampedY = max(minCardY, min(maxCardY, rawTargetY))
        card.frame.origin.y = clampedY
        
        reorderSlotsIfNeeded(for: card, clampedY: clampedY)
    }
    
    private func reorderSlotsIfNeeded(for card: CalendarEventCardView, clampedY: CGFloat) {
        guard cardViews.count > 1 else { return }
        guard let currentIndex = cardViews.firstIndex(of: card) else { return }
        
        let cardGap: CGFloat = 7
        var slotCenters: [CGFloat] = []
        var runningY: CGFloat = 4
        for c in cardViews {
            let h = c.frame.height
            slotCenters.append(runningY + (h / 2.0))
            runningY += h + cardGap
        }
        
        let draggedCenterY = clampedY + (card.frame.height / 2.0)
        var targetIndex = currentIndex
        let hysteresis: CGFloat = 10.0
        
        // Check if should move UP
        while targetIndex > 0 {
            let boundaryUp = (slotCenters[targetIndex - 1] + slotCenters[targetIndex]) / 2.0
            if draggedCenterY < boundaryUp - hysteresis {
                targetIndex -= 1
            } else {
                break
            }
        }
        
        // Check if should move DOWN
        while targetIndex < cardViews.count - 1 {
            let boundaryDown = (slotCenters[targetIndex] + slotCenters[targetIndex + 1]) / 2.0
            if draggedCenterY > boundaryDown + hysteresis {
                targetIndex += 1
            } else {
                break
            }
        }
        
        if targetIndex != currentIndex {
            let movedCard = cardViews.remove(at: currentIndex)
            cardViews.insert(movedCard, at: targetIndex)
            
            repositionOtherCardsAnimated(except: card)
        }
    }
    
    private func repositionOtherCardsAnimated(except draggingCard: CalendarEventCardView) {
        let stackWidth = scrollView.frame.width
        let cardPad: CGFloat = 4
        let cardW = max(180, stackWidth - (cardPad * 2))
        let cardGap: CGFloat = 7
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            var runningY: CGFloat = 4
            for c in self.cardViews {
                let h = c.frame.height
                if c != draggingCard {
                    c.animator().frame = NSRect(x: cardPad, y: runningY, width: cardW, height: h)
                }
                runningY += h + cardGap
            }
        }
    }
    
    private func handleDragEnd(card: CalendarEventCardView) {
        isDraggingAnyCard = false
        stopAutoScrollTimer()
        onDragStateChanged?(false)
        onUserInteraction?()
        
        let stackWidth = scrollView.frame.width
        let cardPad: CGFloat = 6
        let cardW = max(180, stackWidth - (cardPad * 2))
        let cardGap: CGFloat = 11
        
        var targetSlotY: CGFloat = 6
        var runningY: CGFloat = 6
        for c in cardViews {
            if c == card {
                targetSlotY = runningY
            }
            runningY += c.frame.height + cardGap
        }
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.animator().frame = NSRect(x: cardPad, y: targetSlotY, width: cardW, height: card.frame.height)
            card.animator().alphaValue = 1.0
            card.layer?.shadowOpacity = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            card.layer?.zPosition = 0
            card.setDraggingAppearance(false)
            
            self.events = self.cardViews.map { $0.event }
            GoogleCalendarService.shared.saveCustomOrder(
                eventIds: self.events.map { $0.id },
                forMode: self.dayMode
            )
            
            self.updateCardStackPositions(animated: false)
        })
    }
    
    private func toggleExpandCard(for eventId: String) {
        if self.expandedEventId == eventId {
            self.expandedEventId = nil
        } else {
            self.expandedEventId = eventId
        }
        
        for card in self.cardViews {
            let isExp = (self.expandedEventId == card.event.id)
            card.setExpanded(isExp, animated: true)
        }
        
        self.onHeightChanged?()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            updateCardStackPositions(animated: true)
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
        
        let headerH: CGFloat = 66 // 32 (switcher) + 8 (gap) + 18 (subtitle) + 8 (gap)
        
        let status = GoogleCalendarService.shared.syncStatus
        if status == .needsPermission || status == .unauthorized {
            return headerH + 68
        }
        
        if events.isEmpty {
            return headerH + 48
        }
        
        let cardW = max(180, width - 28)
        let totalCardsH = events.reduce(CGFloat(0)) { sum, ev in
            let isExp = (expandedEventId == ev.id)
            let h = CalendarEventCardView.height(for: ev, isExpanded: isExp, width: cardW)
            return sum + h + 8
        }
        
        let boundedHeight = max(60, totalCardsH)
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
        
        // 1. Switcher Row (Top): y = 2
        let switcherY: CGFloat = 2
        switcherContainer.frame = NSRect(x: 14, y: switcherY, width: max(10, w - 28), height: 34)
        
        let calBtnSize: CGFloat = 28
        openCalButton.frame = NSRect(x: switcherContainer.frame.width - calBtnSize - 4, y: 3, width: calBtnSize, height: calBtnSize)
        
        let tabAreaW = max(60, switcherContainer.frame.width - calBtnSize - 10)
        let tabGap: CGFloat = 4
        let numTabs: CGFloat = 4
        let tabW = max(35, (tabAreaW - (tabGap * (numTabs - 1)) - 6) / numTabs)
        
        classesTabBtn.frame = NSRect(x: 4, y: 3, width: tabW, height: 28)
        tasksTabBtn.frame = NSRect(x: 4 + tabW + tabGap, y: 3, width: tabW, height: 28)
        todayTabBtn.frame = NSRect(x: 4 + (tabW + tabGap) * 2, y: 3, width: tabW, height: 28)
        tomorrowTabBtn.frame = NSRect(x: 4 + (tabW + tabGap) * 3, y: 3, width: tabW, height: 28)
        
        // 2. Subtitle Row: y = switcherY + 34 + 11 (11pt spacing)
        let subY = switcherY + 34 + 11
        subtitleLabel.frame = NSRect(x: 16, y: subY, width: max(10, w - 32), height: 18)
        
        // 3. Content area below subtitle: y = subY + 18 + 9
        let contentY = subY + 18 + 9
        let contentHeight = max(10, h - contentY)
        
        updateScrollMask()
        
        let status = GoogleCalendarService.shared.syncStatus
        if status == .needsPermission || status == .unauthorized {
            permissionContainer.isHidden = false
            emptyStateLabel.isHidden = true
            scrollView.isHidden = true
            permissionContainer.frame = NSRect(x: 14, y: contentY, width: max(10, w - 28), height: contentHeight)
            permissionLabel.frame = NSRect(x: 10, y: 14, width: permissionContainer.frame.width - 20, height: 18)
            grantAccessButton.frame = NSRect(x: (permissionContainer.frame.width / 2) - 100, y: 40, width: 95, height: 28)
            openSettingsButton.frame = NSRect(x: (permissionContainer.frame.width / 2) + 5, y: 40, width: 110, height: 28)
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
            scrollView.layer?.mask = nil
            
            updateCardStackPositions(animated: false)
        }
        
        layoutUndoToast()
    }
    
    @objc private func handleScrollViewBoundsChanged(_ notification: Notification) {
        updateCardStackPositions(animated: false)
    }
    
    private func updateCardStackPositions(animated: Bool = false) {
        guard !isDraggingAnyCard else { return }
        guard !cardViews.isEmpty else { return }
        guard scrollView.frame.height > 20 else { return }
        
        let visibleRect = scrollView.contentView.bounds
        let stackWidth = scrollView.frame.width
        guard stackWidth > 20 else { return }
        
        let cardPad: CGFloat = 6.0
        let cardW = max(180, stackWidth - (cardPad * 2))
        let cardGap: CGFloat = 11.0
        let stackStep: CGFloat = 8.0
        let maxStackOffset: CGFloat = 32.0 // Up to 4 cards peek at 8pt each
        
        let topBound = visibleRect.origin.y + 6.0
        
        // 1. Natural vertical layout coordinates
        var naturalY: [CGFloat] = []
        var cardHeights: [CGFloat] = []
        var runningY: CGFloat = 6.0
        
        for card in cardViews {
            let isExp = (expandedEventId == card.event.id)
            let ch = CalendarEventCardView.height(for: card.event, isExpanded: isExp, width: cardW)
            cardHeights.append(ch)
            naturalY.append(runningY)
            runningY += ch + cardGap
        }
        
        // Headroom for scrolling when cards are stacked at the top
        let topStackReserve = min(maxStackOffset, CGFloat(max(0, cardViews.count - 1)) * stackStep) + 20.0
        let totalDocumentH = max(scrollView.frame.height, runningY + topStackReserve)
        
        if abs(documentContainer.frame.height - totalDocumentH) > 0.5 || abs(documentContainer.frame.width - stackWidth) > 0.5 {
            documentContainer.frame = NSRect(x: 0, y: 0, width: stackWidth, height: totalDocumentH)
        }
        
        let count = cardViews.count
        var targetY = naturalY
        var isTopStacked = [Bool](repeating: false, count: count)
        
        // 2. Compute Top Stack: cards reaching the upper bound as user scrolls down
        for i in 0..<count {
            let topOffset = min(maxStackOffset, CGFloat(i) * stackStep)
            let topLimit = topBound + topOffset
            if targetY[i] < topLimit {
                targetY[i] = topLimit
                isTopStacked[i] = true
            }
            if i > 0 && targetY[i] < targetY[i - 1] + stackStep {
                targetY[i] = targetY[i - 1] + stackStep
            }
        }
        
        // 3. Apply frames, z-ordering, and physical card shadows
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        
        for i in 0..<count {
            let card = cardViews[i]
            let ch = cardHeights[i]
            let cardFrame = NSRect(x: cardPad, y: targetY[i], width: cardW, height: ch)
            
            if animated {
                card.animator().frame = cardFrame
            } else {
                card.frame = cardFrame
            }
            card.updateWidth(cardW)
            
            card.layer?.zPosition = 100.0 + CGFloat(i)
            if isTopStacked[i] {
                // Top stack: later cards overlay earlier cards with subtle ambient shadow
                card.layer?.shadowColor = NSColor.black.cgColor
                card.layer?.shadowOpacity = 0.35
                card.layer?.shadowRadius = 4.0
                card.layer?.shadowOffset = CGSize(width: 0, height: -2)
            } else {
                // Natural flowing card: displayed all the way down the screen
                card.layer?.shadowOpacity = 0.0
            }
        }
        
        if !animated {
            CATransaction.commit()
        }
    }
    
    private func updateScrollMask() {
        scrollView.layer?.mask = nil
    }
    
    // MARK: - Undo Toast HUD
    private func setupUndoToastView() {
        undoToastView.cornerRadiusValue = 18
        undoToastView.surfaceColor = NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 0.95)
        undoToastView.outlineColor = AppleTheme.primary.withAlphaComponent(0.45)
        undoToastView.outlineWidth = 1.0
        undoToastView.wantsLayer = true
        undoToastView.layer?.zPosition = 5000
        undoToastView.alphaValue = 0.0
        undoToastView.isHidden = true
        
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold)
        undoToastIcon.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Deleted")?.withSymbolConfiguration(iconConfig)
        undoToastIcon.contentTintColor = AppleTheme.danger
        undoToastView.addSubview(undoToastIcon)
        
        undoToastLabel.isBezeled = false
        undoToastLabel.drawsBackground = false
        undoToastLabel.isEditable = false
        undoToastLabel.isSelectable = false
        undoToastLabel.font = AppleTheme.font(size: 12.0, weight: .medium)
        undoToastLabel.textColor = AppleTheme.label
        undoToastLabel.lineBreakMode = .byTruncatingTail
        undoToastView.addSubview(undoToastLabel)
        
        undoToastButton.cornerRadiusValue = 11
        undoToastButton.unpressedBackgroundColor = AppleTheme.primary.withAlphaComponent(0.18)
        undoToastButton.pressedBackgroundColor = AppleTheme.primary.withAlphaComponent(0.35)
        undoToastButton.unpressedBorderColor = AppleTheme.primary.withAlphaComponent(0.40)
        undoToastButton.unpressedBorderWidth = 0.5
        let undoStyle = NSMutableParagraphStyle()
        undoStyle.alignment = .center
        undoToastButton.attributedTitle = NSAttributedString(
            string: "Undo",
            attributes: [
                .font: AppleTheme.font(size: 11.5, weight: .bold),
                .foregroundColor: AppleTheme.primary,
                .paragraphStyle: undoStyle
            ]
        )
        undoToastButton.target = self
        undoToastButton.action = #selector(handleUndoClicked)
        undoToastView.addSubview(undoToastButton)
        
        undoToastCloseBtn.isBordered = false
        undoToastCloseBtn.setButtonType(.momentaryChange)
        let closeConfig = NSImage.SymbolConfiguration(pointSize: 9.0, weight: .medium)
        undoToastCloseBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")?.withSymbolConfiguration(closeConfig)
        undoToastCloseBtn.contentTintColor = AppleTheme.tertiaryLabel
        undoToastCloseBtn.target = self
        undoToastCloseBtn.action = #selector(hideUndoToast)
        undoToastView.addSubview(undoToastCloseBtn)
        
        addSubview(undoToastView)
    }
    
    private func layoutUndoToast() {
        guard !undoToastView.isHidden else { return }
        let w = bounds.width
        let h = bounds.height
        let toastH: CGFloat = 36
        let toastW = min(360, max(240, w - 28))
        let toastX = (w - toastW) / 2
        let toastY = h - toastH - 12
        undoToastView.frame = NSRect(x: toastX, y: toastY, width: toastW, height: toastH)
        
        undoToastIcon.frame = NSRect(x: 10, y: 10, width: 16, height: 16)
        
        let closeBtnW: CGFloat = 18
        undoToastCloseBtn.frame = NSRect(x: toastW - closeBtnW - 8, y: 9, width: closeBtnW, height: 18)
        
        let undoBtnW: CGFloat = 52
        undoToastButton.frame = NSRect(x: toastW - closeBtnW - undoBtnW - 10, y: 6, width: undoBtnW, height: 24)
        
        let labelX: CGFloat = 32
        let labelW = max(50, toastW - labelX - undoBtnW - closeBtnW - 16)
        undoToastLabel.frame = NSRect(x: labelX, y: 8, width: labelW, height: 20)
    }
    
    public func showUndoToast(for title: String) {
        undoToastDismissTimer?.invalidate()
        
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold)
        undoToastIcon.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Deleted")?.withSymbolConfiguration(iconConfig)
        undoToastIcon.contentTintColor = AppleTheme.danger
        
        undoToastLabel.stringValue = "Deleted \"\(title)\""
        undoToastButton.isHidden = false
        
        let w = bounds.width
        let h = bounds.height
        let toastH: CGFloat = 36
        let toastW = min(360, max(240, w - 28))
        let toastX = (w - toastW) / 2
        let targetY = h - toastH - 12
        let startY = h - toastH + 12
        
        undoToastView.frame = NSRect(x: toastX, y: startY, width: toastW, height: toastH)
        layoutUndoToast()
        undoToastView.isHidden = false
        undoToastView.alphaValue = 0.0
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            undoToastView.animator().frame.origin.y = targetY
            undoToastView.animator().alphaValue = 1.0
        }
        
        undoToastDismissTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            self?.hideUndoToast()
        }
    }
    
    @objc public func hideUndoToast() {
        undoToastDismissTimer?.invalidate()
        undoToastDismissTimer = nil
        
        let currentOrigin = undoToastView.frame.origin
        let destY = currentOrigin.y + 12
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.undoToastView.animator().frame.origin.y = destY
            self.undoToastView.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.undoToastView.isHidden = true
        })
    }
    
    @objc public func handleUndoClicked() {
        undoToastDismissTimer?.invalidate()
        onUserInteraction?()
        
        if let restoredRecord = GoogleCalendarService.shared.undoLastDismissedEvent() {
            let iconConfig = NSImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold)
            undoToastIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Restored")?.withSymbolConfiguration(iconConfig)
            undoToastIcon.contentTintColor = AppleTheme.primary
            undoToastLabel.stringValue = "Restored \"\(restoredRecord.title)\""
            undoToastButton.isHidden = true
            
            reloadFromService()
            
            undoToastDismissTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
                self?.hideUndoToast()
            }
        } else {
            hideUndoToast()
        }
    }
    
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" && !event.modifierFlags.contains(.shift) {
            handleUndoClicked()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
