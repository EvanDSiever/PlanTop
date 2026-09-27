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
        
        // 1. Month / Year title at top (SF Pro headline / footnote semibold)
        let titleFont = AppleTheme.font(size: 13.0, weight: .semibold)
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: AppleTheme.primary,
            .paragraphStyle: titleStyle
        ]
        let titleRect = NSRect(x: 0, y: 0, width: w, height: 16)
        (monthYearString as NSString).draw(in: titleRect, withAttributes: titleAttrs)
        
        // 2. Day Headers (S M T W T F S)
        let headerFont = AppleTheme.font(size: 10.5, weight: .medium)
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .center
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: AppleTheme.tertiaryLabel,
            .paragraphStyle: headerStyle
        ]
        
        let headerY: CGFloat = 20
        let headerH: CGFloat = 14
        for (i, dayName) in dayHeaders.enumerated() {
            let x = CGFloat(i) * colW
            let r = NSRect(x: x, y: headerY, width: colW, height: headerH)
            (dayName as NSString).draw(in: r, withAttributes: headerAttrs)
        }
        
        // 3. Days Grid
        let gridStartY = headerY + headerH + 4
        let availableH = h - gridStartY - 2
        let totalCells = firstWeekdayOffset + daysInMonth
        let numRows = max(5, Int(ceil(Double(totalCells) / 7.0)))
        let rowH = max(12, availableH / CGFloat(numRows))
        
        let dayFont = AppleTheme.font(size: 12.0, weight: .regular)
        let todayFont = AppleTheme.font(size: 12.5, weight: .bold)
        
        let normalStyle = NSMutableParagraphStyle()
        normalStyle.alignment = .center
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: dayFont,
            .foregroundColor: AppleTheme.secondaryLabel,
            .paragraphStyle: normalStyle
        ]
        
        let todayStyle = NSMutableParagraphStyle()
        todayStyle.alignment = .center
        let todayAttrs: [NSAttributedString.Key: Any] = [
            .font: todayFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: todayStyle
        ]
        
        for day in 1...daysInMonth {
            let cellIndex = firstWeekdayOffset + (day - 1)
            let col = cellIndex % 7
            let row = cellIndex / 7
            let x = CGFloat(col) * colW
            let y = gridStartY + CGFloat(row) * rowH
            
            let textH: CGFloat = 14
            let textY = y + max(0, (rowH - textH) / 2)
            
            if day == cachedToday {
                let badgeSize: CGFloat = min(22, min(rowH - 1, colW - 2))
                let badgeRect = NSRect(
                    x: x + (colW - badgeSize) / 2,
                    y: y + (rowH - badgeSize) / 2,
                    width: badgeSize,
                    height: badgeSize
                )
                AppleTheme.primary.setFill()
                let path = NSBezierPath(ovalIn: badgeRect)
                path.fill()
                
                let textRect = NSRect(x: x, y: textY, width: colW, height: textH)
                ("\(day)" as NSString).draw(in: textRect, withAttributes: todayAttrs)
            } else {
                let textRect = NSRect(x: x, y: textY, width: colW, height: textH)
                ("\(day)" as NSString).draw(in: textRect, withAttributes: normalAttrs)
            }
        }
    }
}

// MARK: - Dedicated Clock & Calendar Panel View
// MARK: - Apple HIG Clock View (SF Pro Monospaced Digits, Content-First)
public final class FuturisticClockView: NSView {
    override public var isFlipped: Bool { return true }
    
    public var timeString: String = "" {
        didSet {
            if oldValue != timeString {
                needsDisplay = true
            }
        }
    }
    
    override public init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .planTopSettingsChanged,
            object: nil
        )
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleSettingsChanged() {
        needsDisplay = true
    }
    
    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !timeString.isEmpty else { return }
        
        let w = bounds.width
        let h = bounds.height
        guard w > 20 && h > 20 else { return }
        
        let sampleText = timeString as NSString
        // Proportional, bold lockscreen clock fitting comfortably in available space
        var fontSize: CGFloat = min(64, min(h * 0.60, w * 0.40))
        while fontSize > 18 {
            let font = AppleTheme.timeFont(size: fontSize, weight: .bold)
            let s = sampleText.size(withAttributes: [.font: font])
            if s.width <= (w - 12) && s.height <= (h - 12) {
                break
            }
            fontSize -= 1
        }
        
        let font = AppleTheme.timeFont(size: fontSize, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
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
        surfaceColor = AppleTheme.cardBackground
        outlineWidth = 0.5
        outlineColor = AppleTheme.cardBorder
        
        // 1. Apple Clock View (Left section, vertically centered, no clipping)
        addSubview(clockView)
        
        // 2. Subtle Vertical Divider (0.5pt hairline)
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = AppleTheme.separator.withAlphaComponent(0.4).cgColor
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
        
        // Right calendar gets generous, comfortable space (~160-195pt), giving maximum legibility
        let rightTargetW: CGFloat = max(160, min(195, w * 0.44))
        let splitX = max(140, min(260, w - rightTargetW - 12))
        let leftW = splitX - 4
        
        dividerView.frame = NSRect(x: splitX - 1, y: 12, width: 0.5, height: max(10, h - 24))
        
        clockView.frame = NSRect(x: 4, y: 0, width: leftW - 4, height: h)
        
        let rightX = splitX + 8
        let rightW = max(80, w - rightX - 8)
        let calTopY: CGFloat = 10
        let calH = max(20, h - calTopY - 10)
        miniCalendarView.frame = NSRect(x: rightX, y: calTopY, width: rightW, height: calH)
    }
}

// MARK: - Pass Through Label (Allows clicks to pass directly to text view)
private final class PassThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - Dedicated Quick Notes Text View with Markdown & List Support
public final class QuickNotesTextView: NSTextView {
    public var onReturnPressed: (() -> Bool)?
    public var onUserInteraction: (() -> Void)?
    public var onMouseHover: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseHover?()
    }
    
    override public func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseHover?()
    }
    
    override public func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            window?.makeKey()
        }
        return ok
    }
    
    override public func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
        onUserInteraction?()
    }
    
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        
        if flags == .command {
            switch chars {
            case "a":
                setSelectedRange(NSRange(location: 0, length: (string as NSString).length))
                onUserInteraction?()
                return true
            case "c":
                copy(nil)
                onUserInteraction?()
                return true
            case "v":
                paste(nil)
                onUserInteraction?()
                return true
            case "x":
                cut(nil)
                onUserInteraction?()
                return true
            case "z":
                if let undo = undoManager, undo.canUndo {
                    undo.undo()
                    onUserInteraction?()
                    return true
                }
            case "b":
                toggleBold()
                onUserInteraction?()
                return true
            case "i":
                toggleItalic()
                onUserInteraction?()
                return true
            case "u":
                toggleUnderline()
                onUserInteraction?()
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            switch chars {
            case "z":
                if let undo = undoManager, undo.canRedo {
                    undo.redo()
                    onUserInteraction?()
                    return true
                }
            case "8":
                toggleBullet()
                onUserInteraction?()
                return true
            case "7":
                toggleNumbered()
                onUserInteraction?()
                return true
            case "u":
                toggleBullet()
                onUserInteraction?()
                return true
            case "o":
                toggleNumbered()
                onUserInteraction?()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override public func insertNewline(_ sender: Any?) {
        if let handled = onReturnPressed?(), handled {
            return
        }
        super.insertNewline(sender)
    }
    
    // MARK: - Markdown Formatting Actions
    
    public func toggleBold() {
        let sel = selectedRange()
        let curSize = self.font?.pointSize ?? QuickNotesPanelView.baseFontSize
        let regularFont = AppleTheme.font(size: curSize, weight: .regular)
        let boldFont = AppleTheme.font(size: curSize, weight: .bold)
        
        guard let storage = textStorage else { return }
        
        if sel.length > 0 {
            var isAllBold = true
            storage.enumerateAttribute(.font, in: sel, options: []) { value, _, stop in
                if let font = value as? NSFont {
                    let isBold = font.fontDescriptor.symbolicTraits.contains(.bold) ||
                                 font.fontName.contains("Heavy") ||
                                 font.fontName.contains("Black") ||
                                 font.fontName.contains("Bold")
                    if !isBold {
                        isAllBold = false
                        stop.pointee = true
                    }
                } else {
                    isAllBold = false
                    stop.pointee = true
                }
            }
            let targetFont = isAllBold ? regularFont : boldFont
            storage.beginEditing()
            storage.addAttribute(.font, value: targetFont, range: sel)
            storage.endEditing()
            didChangeText()
        } else {
            let currentFont = (typingAttributes[.font] as? NSFont) ?? regularFont
            let isBold = currentFont.fontDescriptor.symbolicTraits.contains(.bold) ||
                         currentFont.fontName.contains("Heavy") ||
                         currentFont.fontName.contains("Black") ||
                         currentFont.fontName.contains("Bold")
            typingAttributes[.font] = isBold ? regularFont : boldFont
        }
    }
    
    public func toggleItalic() {
        let sel = selectedRange()
        let curSize = self.font?.pointSize ?? QuickNotesPanelView.baseFontSize
        let regularFont = AppleTheme.font(size: curSize, weight: .regular)
        let italicFont = NSFontManager.shared.convert(regularFont, toHaveTrait: .italicFontMask)
        
        guard let storage = textStorage else { return }
        
        if sel.length > 0 {
            var isAllItalic = true
            storage.enumerateAttribute(.font, in: sel, options: []) { value, _, stop in
                if let font = value as? NSFont {
                    let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic) ||
                                   font.fontName.contains("Oblique") ||
                                   font.fontName.contains("Italic")
                    if !isItalic {
                        isAllItalic = false
                        stop.pointee = true
                    }
                } else {
                    isAllItalic = false
                    stop.pointee = true
                }
            }
            let targetFont = isAllItalic ? regularFont : italicFont
            storage.beginEditing()
            storage.addAttribute(.font, value: targetFont, range: sel)
            storage.endEditing()
            didChangeText()
        } else {
            let currentFont = (typingAttributes[.font] as? NSFont) ?? regularFont
            let isItalic = currentFont.fontDescriptor.symbolicTraits.contains(.italic) ||
                           currentFont.fontName.contains("Oblique") ||
                           currentFont.fontName.contains("Italic")
            typingAttributes[.font] = isItalic ? regularFont : italicFont
        }
    }
    
    public func toggleUnderline() {
        let sel = selectedRange()
        guard let storage = textStorage else { return }
        
        if sel.length > 0 {
            var isAllUnderlined = true
            storage.enumerateAttribute(.underlineStyle, in: sel, options: []) { value, _, stop in
                if let val = value as? Int, val != 0 {
                    // Underlined
                } else {
                    isAllUnderlined = false
                    stop.pointee = true
                }
            }
            let targetVal = isAllUnderlined ? 0 : NSUnderlineStyle.single.rawValue
            storage.beginEditing()
            if targetVal == 0 {
                storage.removeAttribute(.underlineStyle, range: sel)
            } else {
                storage.addAttribute(.underlineStyle, value: targetVal, range: sel)
            }
            storage.endEditing()
            didChangeText()
        } else {
            let currentVal = (typingAttributes[.underlineStyle] as? Int) ?? 0
            if currentVal != 0 {
                typingAttributes.removeValue(forKey: .underlineStyle)
            } else {
                typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
        }
    }
    
    public func toggleBullet() {
        let sel = selectedRange()
        let ns = string as NSString
        let lineRange = ns.lineRange(for: sel)
        let block = ns.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        
        let endsWithNL = block.hasSuffix("\n")
        var processLines = lines
        if endsWithNL && processLines.last == "" {
            processLines.removeLast()
        }
        
        let allAreBullets = processLines.allSatisfy { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ")
        }
        
        var newLines: [String] = []
        if allAreBullets {
            for line in processLines {
                if let r = line.range(of: "^([ \\t]*)([-*•][ \\t]+)", options: .regularExpression) {
                    var modified = line
                    modified.removeSubrange(r)
                    newLines.append(modified)
                } else {
                    newLines.append(line)
                }
            }
        } else {
            for line in processLines {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    newLines.append(line)
                } else {
                    var cleanLine = line
                    if let r = cleanLine.range(of: "^([ \\t]*)(\\d+\\.[ \\t]+)", options: .regularExpression) {
                        cleanLine.removeSubrange(r)
                    }
                    newLines.append("- " + cleanLine)
                }
            }
        }
        
        var replacement = newLines.joined(separator: "\n")
        if endsWithNL { replacement += "\n" }
        
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
        }
    }
    
    public func toggleNumbered() {
        let sel = selectedRange()
        let ns = string as NSString
        let lineRange = ns.lineRange(for: sel)
        let block = ns.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        
        let endsWithNL = block.hasSuffix("\n")
        var processLines = lines
        if endsWithNL && processLines.last == "" {
            processLines.removeLast()
        }
        
        let allAreNumbers = processLines.allSatisfy { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || (line.range(of: "^[ \\t]*\\d+\\.[ \\t]+", options: .regularExpression) != nil)
        }
        
        var newLines: [String] = []
        if allAreNumbers {
            for line in processLines {
                if let r = line.range(of: "^([ \\t]*)(\\d+\\.[ \\t]+)", options: .regularExpression) {
                    var modified = line
                    modified.removeSubrange(r)
                    newLines.append(modified)
                } else {
                    newLines.append(line)
                }
            }
        } else {
            var counter = 1
            for line in processLines {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    newLines.append(line)
                } else {
                    var cleanLine = line
                    if let r = cleanLine.range(of: "^([ \\t]*)([-*•][ \\t]+)", options: .regularExpression) {
                        cleanLine.removeSubrange(r)
                    }
                    newLines.append("\(counter). " + cleanLine)
                    counter += 1
                }
            }
        }
        
        var replacement = newLines.joined(separator: "\n")
        if endsWithNL { replacement += "\n" }
        
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
        }
    }
}

// MARK: - Quick Notes Panel View (Underneath Clock & Date, Above Categories)
public final class QuickNotesPanelView: NeumorphicDepressedCardView, NSTextViewDelegate {
    override public var isFlipped: Bool { return true }
    public static let baseFontSize: CGFloat = 16.0
    
    public var onUserInteraction: (() -> Void)?
    public var onEditingStateChanged: ((Bool) -> Void)?
    public private(set) var isEditing: Bool = false
    
    // Text Editor
    private let scrollView = NSScrollView()
    private let textView = QuickNotesTextView()
    private let placeholderLabel = PassThroughLabel(labelWithString: "Write notes, bullet lists (- or 1.), bold (⌘B), italic (⌘I), underline (⌘U)...")
    
    // Bottom Formatting Toolbar Container (Fades in on mouse hover)
    private let toolbarContainer = NSView()
    private let toolbarDivider = NSView()
    private let bulletButton = NSButton()
    private let numberedButton = NSButton()
    private let boldButton = NSButton()
    private let italicButton = NSButton()
    private let underlineButton = NSButton()
    private let clearButton = NSButton()
    
    private var trackingArea: NSTrackingArea?
    private let notesStorageKey = "plantop_panel_quick_notes"
    
    override public init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        setupViews()
        loadPersistedNotes()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        cornerRadiusValue = 14
        surfaceColor = AppleTheme.cardBackground
        outlineWidth = 0.5
        outlineColor = AppleTheme.cardBorder
        
        // 1. Scroll View & Text View (Primary writing surface)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = AppleTheme.font(size: QuickNotesPanelView.baseFontSize, weight: .regular)
        textView.textColor = AppleTheme.label
        textView.insertionPointColor = AppleTheme.primary
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.delegate = self
        textView.onUserInteraction = { [weak self] in
            self?.onUserInteraction?()
        }
        textView.onMouseHover = { [weak self] in
            self?.focusForTyping()
        }
        textView.onReturnPressed = { [weak self] in
            return self?.handleSmartReturn() ?? false
        }
        
        scrollView.documentView = textView
        addSubview(scrollView)
        
        // 2. Placeholder Label (Passes clicks directly to text view)
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.font = AppleTheme.font(size: 15.0, weight: .regular)
        placeholderLabel.textColor = AppleTheme.tertiaryLabel
        addSubview(placeholderLabel)
        
        // 3. Toolbar Container (Hidden initially, smoothly fades in on hover)
        toolbarContainer.wantsLayer = true
        toolbarContainer.alphaValue = 0.0
        addSubview(toolbarContainer)
        
        // Hairline Divider for Bottom Toolbar
        toolbarDivider.wantsLayer = true
        toolbarDivider.layer?.backgroundColor = AppleTheme.separator.withAlphaComponent(0.4).cgColor
        toolbarContainer.addSubview(toolbarDivider)
        
        // 4. Formatting Buttons
        configureToolbarButton(bulletButton, symbolName: "list.bullet", tooltip: "Bullet list (Cmd+Shift+8)", action: #selector(handleToggleBullet))
        configureToolbarButton(numberedButton, symbolName: "list.number", tooltip: "Numbered list (Cmd+Shift+7)", action: #selector(handleToggleNumbered))
        configureToolbarButton(boldButton, title: "B", isBold: true, tooltip: "Bold (Cmd+B)", action: #selector(handleToggleBold))
        configureToolbarButton(italicButton, title: "I", isItalic: true, tooltip: "Italic (Cmd+I)", action: #selector(handleToggleItalic))
        configureToolbarButton(underlineButton, title: "U", isUnderline: true, tooltip: "Underline (Cmd+U)", action: #selector(handleToggleUnderline))
        
        // Clear Button (Far right of toolbar, visible when text is non-empty)
        configureToolbarButton(clearButton, symbolName: "trash", tooltip: "Clear notes", action: #selector(handleClearNotes))
        clearButton.contentTintColor = AppleTheme.tertiaryLabel
        clearButton.isHidden = true
    }
    
    private func configureToolbarButton(
        _ button: NSButton,
        symbolName: String? = nil,
        title: String? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        tooltip: String,
        action: Selector
    ) {
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        
        if let symbolName = symbolName {
            let config = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
            button.contentTintColor = AppleTheme.secondaryLabel
        } else if let title = title {
            button.title = title
            if isUnderline {
                let font = AppleTheme.font(size: 12.5, weight: .bold)
                let attr = NSMutableAttributedString(string: title, attributes: [
                    .font: font,
                    .foregroundColor: AppleTheme.secondaryLabel,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ])
                button.attributedTitle = attr
            } else if isItalic {
                let baseF = AppleTheme.font(size: 12.5, weight: .semibold)
                button.font = NSFontManager.shared.convert(baseF, toHaveTrait: .italicFontMask)
                button.contentTintColor = AppleTheme.secondaryLabel
            } else if isBold {
                button.font = AppleTheme.font(size: 12.5, weight: .bold)
                button.contentTintColor = AppleTheme.secondaryLabel
            } else {
                button.font = AppleTheme.font(size: 12.5, weight: .semibold)
                button.contentTintColor = AppleTheme.secondaryLabel
            }
        }
        
        toolbarContainer.addSubview(button)
    }
    
    private func loadPersistedNotes() {
        if let rtfData = UserDefaults.standard.data(forKey: "plantop_panel_quick_notes_rtf"),
           let attr = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           attr.length > 0 {
            if attr.string.contains("**") || attr.string.contains("~~") || attr.string.contains("<u>") {
                let cleaned = QuickNotesPanelView.convertMarkdownToRichText(attr.string)
                textView.textStorage?.setAttributedString(cleaned)
            } else {
                textView.textStorage?.setAttributedString(attr)
            }
            // Enlarge any loaded text that has old smaller font size
            if let storage = textView.textStorage, storage.length > 0 {
                storage.beginEditing()
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                    if let font = value as? NSFont, font.pointSize < QuickNotesPanelView.baseFontSize {
                        let isBold = font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.contains("Bold")
                        let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic) || font.fontName.contains("Italic")
                        var newFont = AppleTheme.font(size: QuickNotesPanelView.baseFontSize, weight: isBold ? .bold : .regular)
                        if isItalic {
                            newFont = NSFontManager.shared.convert(newFont, toHaveTrait: .italicFontMask)
                        }
                        storage.addAttribute(.font, value: newFont, range: range)
                    }
                }
                storage.endEditing()
            }
            placeholderLabel.isHidden = true
            clearButton.isHidden = false
        } else {
            let saved = UserDefaults.standard.string(forKey: notesStorageKey) ?? ""
            if !saved.isEmpty {
                let cleaned = QuickNotesPanelView.convertMarkdownToRichText(saved)
                textView.textStorage?.setAttributedString(cleaned)
                placeholderLabel.isHidden = true
                clearButton.isHidden = false
                savePersistedNotes()
            } else {
                textView.string = ""
                placeholderLabel.isHidden = false
                clearButton.isHidden = true
            }
        }
    }
    
    private func savePersistedNotes() {
        let text = textView.string
        UserDefaults.standard.set(text, forKey: notesStorageKey)
        if let storage = textView.textStorage, storage.length > 0 {
            if let rtfData = try? storage.data(from: NSRange(location: 0, length: storage.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                UserDefaults.standard.set(rtfData, forKey: "plantop_panel_quick_notes_rtf")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "plantop_panel_quick_notes_rtf")
        }
    }
    
    @objc private func handleToggleBullet() {
        textView.toggleBullet()
        onUserInteraction?()
    }
    
    @objc private func handleToggleNumbered() {
        textView.toggleNumbered()
        onUserInteraction?()
    }
    
    @objc private func handleToggleBold() {
        textView.toggleBold()
        onUserInteraction?()
    }
    
    @objc private func handleToggleItalic() {
        textView.toggleItalic()
        onUserInteraction?()
    }
    
    @objc private func handleToggleUnderline() {
        textView.toggleUnderline()
        onUserInteraction?()
    }
    
    @objc private func handleClearNotes() {
        textView.string = ""
        UserDefaults.standard.removeObject(forKey: notesStorageKey)
        UserDefaults.standard.removeObject(forKey: "plantop_panel_quick_notes_rtf")
        placeholderLabel.isHidden = false
        clearButton.isHidden = true
        onUserInteraction?()
    }
    
    // MARK: - Hover Auto-Focus & Mouse Tracking for Toolbar
    public func focusForTyping() {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if window?.isKeyWindow == false {
            window?.makeKey()
        }
        if window?.firstResponder != textView {
            window?.makeFirstResponder(textView)
        }
        let length = (textView.string as NSString).length
        let curSel = textView.selectedRange()
        if curSel.length == 0 && curSel.location == 0 && length > 0 {
            textView.setSelectedRange(NSRange(location: length, length: 0))
        }
        showToolbar(animated: true)
        onUserInteraction?()
    }
    
    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        focusForTyping()
    }
    
    override public func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if window?.firstResponder != textView {
            focusForTyping()
        }
        if toolbarContainer.alphaValue < 0.99 {
            showToolbar(animated: true)
        }
    }
    
    override public func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let mouseLoc = NSEvent.mouseLocation
        if let win = window {
            let winLoc = win.convertPoint(fromScreen: mouseLoc)
            let localLoc = convert(winLoc, from: nil)
            if bounds.contains(localLoc) {
                return
            }
        }
        hideToolbar(animated: true)
    }
    
    private func showToolbar(animated: Bool = true) {
        guard toolbarContainer.alphaValue < 0.99 else { return }
        if !animated {
            toolbarContainer.alphaValue = 1.0
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            toolbarContainer.animator().alphaValue = 1.0
        }
    }
    
    private func hideToolbar(animated: Bool = true) {
        guard toolbarContainer.alphaValue > 0.01 else { return }
        if !animated {
            toolbarContainer.alphaValue = 0.0
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            toolbarContainer.animator().alphaValue = 0.0
        }
    }
    
    // MARK: - Smart Return Continuation
    private func handleSmartReturn() -> Bool {
        let sel = textView.selectedRange()
        let ns = textView.string as NSString
        guard sel.length == 0 else { return false }
        
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let currentLine = ns.substring(with: lineRange)
        let cursorInLine = sel.location - lineRange.location
        let linePrefix = (currentLine as NSString).substring(to: min(cursorInLine, (currentLine as NSString).length))
        
        let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "-" || trimmed == "*" || trimmed == "•" || trimmed == "- " || trimmed == "* " || trimmed == "• " {
            if textView.shouldChangeText(in: lineRange, replacementString: "") {
                textView.replaceCharacters(in: lineRange, with: "")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                return true
            }
        }
        
        if let numOnlyRegex = try? NSRegularExpression(pattern: "^\\d+\\.\\s*$"),
           numOnlyRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
            if textView.shouldChangeText(in: lineRange, replacementString: "") {
                textView.replaceCharacters(in: lineRange, with: "")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                return true
            }
        }
        
        if let bulletRegex = try? NSRegularExpression(pattern: "^([ \\t]*)([-*•])[ \\t]+(.*)$"),
           let match = bulletRegex.firstMatch(in: linePrefix, range: NSRange(location: 0, length: (linePrefix as NSString).length)) {
            let indent = (linePrefix as NSString).substring(with: match.range(at: 1))
            let symbol = (linePrefix as NSString).substring(with: match.range(at: 2))
            let insertion = "\n\(indent)\(symbol) "
            if textView.shouldChangeText(in: sel, replacementString: insertion) {
                textView.replaceCharacters(in: sel, with: insertion)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: sel.location + (insertion as NSString).length, length: 0))
                return true
            }
        }
        
        if let numRegex = try? NSRegularExpression(pattern: "^([ \\t]*)(\\d+)\\.[ \\t]+(.*)$"),
           let match = numRegex.firstMatch(in: linePrefix, range: NSRange(location: 0, length: (linePrefix as NSString).length)) {
            let indent = (linePrefix as NSString).substring(with: match.range(at: 1))
            let numStr = (linePrefix as NSString).substring(with: match.range(at: 2))
            let nextNum = (Int(numStr) ?? 1) + 1
            let insertion = "\n\(indent)\(nextNum). "
            if textView.shouldChangeText(in: sel, replacementString: insertion) {
                textView.replaceCharacters(in: sel, with: insertion)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: sel.location + (insertion as NSString).length, length: 0))
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Markdown Conversion & Highlighting
    
    /// Converts markdown syntax (like **bold**, *italic*, ~~strikethrough~~) into a clean rich NSAttributedString without raw syntax delimiters.
    public static func convertMarkdownToRichText(_ raw: String, baseFontSize: CGFloat = QuickNotesPanelView.baseFontSize) -> NSAttributedString {
        let regularFont = AppleTheme.font(size: baseFontSize, weight: .regular)
        let boldFont = AppleTheme.font(size: baseFontSize, weight: .bold)
        let italicFont = NSFontManager.shared.convert(regularFont, toHaveTrait: .italicFontMask)
        let boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.0
        
        let attr = NSMutableAttributedString(string: raw, attributes: [
            .font: regularFont,
            .foregroundColor: AppleTheme.label,
            .paragraphStyle: paragraphStyle
        ])
        
        func replacePattern(_ pattern: String, font: NSFont? = nil, isStrikethrough: Bool = false) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            var searchRange = NSRange(location: 0, length: attr.length)
            while searchRange.location < attr.length,
                  let match = regex.firstMatch(in: attr.string, options: [], range: searchRange) {
                let fullRange = match.range
                let ns = attr.string as NSString
                guard match.numberOfRanges >= 2 else { break }
                let innerText = ns.substring(with: match.range(at: 1))
                
                attr.replaceCharacters(in: fullRange, with: innerText)
                let newRange = NSRange(location: fullRange.location, length: (innerText as NSString).length)
                
                if let font = font {
                    attr.addAttribute(.font, value: font, range: newRange)
                }
                if isStrikethrough {
                    attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
                }
                
                let nextLoc = fullRange.location + newRange.length
                searchRange = NSRange(location: nextLoc, length: attr.length - nextLoc)
            }
        }
        
        // 1. Bold Italic: ***text***
        replacePattern("\\*\\*\\*(.+?)\\*\\*\\*", font: boldItalicFont)
        
        // 2. Bold: **text**
        replacePattern("(?<!\\*)\\*\\*(?!\\*)([^\n]+?)(?<!\\*)\\*\\*(?!\\*)", font: boldFont)
        
        // 3. Italic: *text*
        replacePattern("(?<!\\*)\\*(?!\\*)([^\\*\\n]+?)(?<!\\*)\\*(?!\\*)", font: italicFont)
        
        // 4. Strikethrough: ~~text~~
        replacePattern("\\~\\~(.+?)\\~\\~", isStrikethrough: true)
        
        // 5. Underline: <u>text</u>
        func replaceUnderline() {
            guard let regex = try? NSRegularExpression(pattern: "(?i)<u>(.+?)</u>") else { return }
            var searchRange = NSRange(location: 0, length: attr.length)
            while searchRange.location < attr.length,
                  let match = regex.firstMatch(in: attr.string, options: [], range: searchRange) {
                let fullRange = match.range
                let ns = attr.string as NSString
                guard match.numberOfRanges >= 2 else { break }
                let innerText = ns.substring(with: match.range(at: 1))
                attr.replaceCharacters(in: fullRange, with: innerText)
                let newRange = NSRange(location: fullRange.location, length: (innerText as NSString).length)
                attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
                let nextLoc = fullRange.location + newRange.length
                searchRange = NSRange(location: nextLoc, length: attr.length - nextLoc)
            }
        }
        replaceUnderline()
        
        // 6. Bullets
        if let bulletRegex = try? NSRegularExpression(pattern: "(?m)^([ \\t]*)([-*•])[ \\t]+") {
            for match in bulletRegex.matches(in: attr.string, range: NSRange(location: 0, length: attr.length)) {
                let symbolRange = match.range(at: 2)
                attr.addAttribute(.foregroundColor, value: AppleTheme.primary, range: symbolRange)
                attr.addAttribute(.font, value: boldFont, range: symbolRange)
            }
        }
        
        // 7. Numbered list
        if let numRegex = try? NSRegularExpression(pattern: "(?m)^([ \\t]*)(\\d+\\.)[ \\t]+") {
            for match in numRegex.matches(in: attr.string, range: NSRange(location: 0, length: attr.length)) {
                let numRange = match.range(at: 2)
                attr.addAttribute(.foregroundColor, value: AppleTheme.primary, range: numRange)
                attr.addAttribute(.font, value: boldFont, range: numRange)
            }
        }
        
        return attr
    }
    
    private func applyMarkdownSyntaxHighlighting() {
        guard let storage = textView.textStorage else { return }
        let text = textView.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return }
        
        let sel = textView.selectedRange()
        let boldFont = AppleTheme.font(size: QuickNotesPanelView.baseFontSize, weight: .bold)
        
        storage.beginEditing()
        
        // Bullets: (?m)^([ \t]*)([-*•])[ \t]+
        if let bulletRegex = try? NSRegularExpression(pattern: "(?m)^([ \\t]*)([-*•])[ \\t]+") {
            for match in bulletRegex.matches(in: text, range: fullRange) {
                let symbolRange = match.range(at: 2)
                storage.addAttribute(.foregroundColor, value: AppleTheme.primary, range: symbolRange)
                storage.addAttribute(.font, value: boldFont, range: symbolRange)
            }
        }
        
        // Numbered list: (?m)^([ \t]*)(\d+\.)[ \t]+
        if let numRegex = try? NSRegularExpression(pattern: "(?m)^([ \\t]*)(\\d+\\.)[ \\t]+") {
            for match in numRegex.matches(in: text, range: fullRange) {
                let numRange = match.range(at: 2)
                storage.addAttribute(.foregroundColor, value: AppleTheme.primary, range: numRange)
                storage.addAttribute(.font, value: boldFont, range: numRange)
            }
        }
        
        // Headings: (?m)^(#+)[ \t]+(.*)$
        if let hRegex = try? NSRegularExpression(pattern: "(?m)^(#+)[ \\t]+(.*)$") {
            for match in hRegex.matches(in: text, range: fullRange) {
                storage.addAttribute(.font, value: AppleTheme.font(size: QuickNotesPanelView.baseFontSize + 1.0, weight: .bold), range: match.range)
                let hashRange = match.range(at: 1)
                storage.addAttribute(.foregroundColor, value: AppleTheme.primary, range: hashRange)
            }
        }
        
        storage.endEditing()
        textView.setSelectedRange(sel)
    }
    
    // MARK: - NSTextViewDelegate
    public func textDidChange(_ notification: Notification) {
        let text = textView.string
        placeholderLabel.isHidden = !text.isEmpty
        clearButton.isHidden = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        // If user typed completed markdown like **word** or ~~word~~, convert it in-place to rich text!
        if text.contains("**") || text.contains("~~") || text.contains("<u>") {
            let sel = textView.selectedRange()
            let cleaned = QuickNotesPanelView.convertMarkdownToRichText(text)
            if cleaned.string != text {
                textView.textStorage?.setAttributedString(cleaned)
                let newLoc = min(sel.location, (cleaned.string as NSString).length)
                textView.setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }
        
        savePersistedNotes()
        applyMarkdownSyntaxHighlighting()
        onUserInteraction?()
    }
    
    public func textDidBeginEditing(_ notification: Notification) {
        isEditing = true
        onEditingStateChanged?(true)
        onUserInteraction?()
    }
    
    public func textDidEndEditing(_ notification: Notification) {
        isEditing = false
        onEditingStateChanged?(false)
    }
    
    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focusForTyping()
    }
    
    override public func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        guard w > 0 && h > 0 else { return }
        
        // Bottom Toolbar Container (26pt height + 8pt buffer)
        let toolbarH: CGFloat = 26
        let toolbarY: CGFloat = h - toolbarH - 6
        toolbarContainer.frame = NSRect(x: 0, y: toolbarY - 2, width: w, height: toolbarH + 8)
        
        toolbarDivider.frame = NSRect(x: 10, y: 0, width: max(0, w - 20), height: 0.5)
        
        var btnX: CGFloat = 10
        let btnW: CGFloat = 28
        let btnH: CGFloat = 24
        let btnSpacing: CGFloat = 6
        
        bulletButton.frame = NSRect(x: btnX, y: 3, width: btnW, height: btnH)
        btnX += btnW + btnSpacing
        
        numberedButton.frame = NSRect(x: btnX, y: 3, width: btnW, height: btnH)
        btnX += btnW + btnSpacing
        
        boldButton.frame = NSRect(x: btnX, y: 3, width: btnW, height: btnH)
        btnX += btnW + btnSpacing
        
        italicButton.frame = NSRect(x: btnX, y: 3, width: btnW, height: btnH)
        btnX += btnW + btnSpacing
        
        underlineButton.frame = NSRect(x: btnX, y: 3, width: btnW, height: btnH)
        btnX += btnW + btnSpacing
        
        let clearW: CGFloat = 28
        clearButton.frame = NSRect(x: max(btnX + 10, w - clearW - 10), y: 3, width: clearW, height: btnH)
        
        // Editor Scroll View & Text View (Top down to toolbar)
        let topPadding: CGFloat = 8
        let contentH = max(10, toolbarY - 4 - topPadding)
        scrollView.frame = NSRect(x: 10, y: topPadding, width: max(0, w - 20), height: contentH)
        textView.frame = NSRect(x: 0, y: 0, width: max(0, w - 20), height: contentH)
        
        placeholderLabel.frame = NSRect(x: 13, y: topPadding + 2, width: max(0, w - 26), height: 24)
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
    
    // Quick Notes Panel (Underneath Clock & Date, Above Category Switcher)
    private let notesPanel = QuickNotesPanelView()
    
    // Calendar Panel with Neumorphic Switcher
    private let calendarPanel = CalendarPanelView(dayMode: .today)
    
    // Dynamic Drag-Scaling Support
    public var preferredPanelWidth: CGFloat = 340
    public var onResizeWidthChanged: ((CGFloat) -> Void)?
    public var onResizeCompleted: (() -> Void)?
    public var onNotesEditingStateChanged: ((Bool) -> Void)?
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
        
        // Clip container hosts the floating islands sliding in from the right edge
        clipContainer.wantsLayer = true
        clipContainer.layer?.backgroundColor = NSColor.clear.cgColor
        clipContainer.layer?.cornerRadius = 20
        clipContainer.layer?.masksToBounds = false
        addSubview(clipContainer)
        
        // Master Coordination Container (100% transparent, no overall background)
        masterPanel.cornerRadiusValue = 20
        masterPanel.isBackgroundVisible = false
        masterPanel.panelBackgroundColor = .clear
        clipContainer.addSubview(masterPanel)
        
        // 1. Dedicated Large Clock Panel (Floating Island 1)
        masterPanel.contentView.addSubview(clockPanel)
        
        // 2. Quick Notes Panel (Floating Island 2)
        notesPanel.onUserInteraction = { [weak self] in
            self?.onUserInteraction?()
        }
        notesPanel.onEditingStateChanged = { [weak self] isEditing in
            self?.onNotesEditingStateChanged?(isEditing)
        }
        masterPanel.contentView.addSubview(notesPanel)
        
        // 3. Integrated Calendar Panel (Floating Island 3 & Event Islands)
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
        calendarPanel.onOpenGoogleCalendarURL = { url in
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
        let config = NSImage.SymbolConfiguration(pointSize: 12.0, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        button.contentTintColor = AppleTheme.secondaryLabel
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
    }
    
    private func updatePinButtonIcon() {
        let sym = isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12.0, weight: .medium)
        pinButton.image = NSImage(systemSymbolName: sym, accessibilityDescription: "Pin")?.withSymbolConfiguration(config)
        pinButton.contentTintColor = isPinned ? AppleTheme.primary : AppleTheme.secondaryLabel
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
    private var isAnimatingSlide: Bool = false
    
    public func stretchOut(animated: Bool = true, completion: (() -> Void)? = nil) {
        isStretchedOut = true
        let hPad: CGFloat = 8
        let panelW = max(260, bounds.width - hPad)
        let panelH = bounds.height
        let finalRect = NSRect(x: hPad, y: 0, width: panelW, height: panelH)
        
        masterPanel.frame = finalRect
        masterPanel.layoutSubtreeIfNeeded()
        
        let cardW = panelW
        let cardH = panelH
        let islandW = max(0, cardW - 28)
        
        let clockH: CGFloat = 160
        let clockY: CGFloat = 8
        let finalClockRect = NSRect(x: 14, y: clockY, width: islandW, height: clockH)
        
        let notesH: CGFloat = 106
        let notesY = clockY + clockH + 11
        let finalNotesRect = NSRect(x: 14, y: notesY, width: islandW, height: notesH)
        
        let calY = notesY + notesH + 11
        let calH = max(0, cardH - calY)
        let finalCalRect = NSRect(x: 0, y: calY, width: cardW, height: calH)
        
        if !animated {
            clockPanel.frame = finalClockRect
            notesPanel.frame = finalNotesRect
            calendarPanel.frame = finalCalRect
            clipContainer.layer?.masksToBounds = false
            completion?()
            return
        }
        
        isAnimatingSlide = true
        clipContainer.layer?.masksToBounds = false
        
        let offscreenX = bounds.width + 50
        clockPanel.frame = NSRect(x: offscreenX, y: clockY, width: islandW, height: clockH)
        notesPanel.frame = NSRect(x: offscreenX + 30, y: notesY, width: islandW, height: notesH)
        calendarPanel.frame = NSRect(x: offscreenX + 60, y: calY, width: cardW, height: calH)
        
        let springTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        let slideOutDuration: TimeInterval = 0.55
        
        // 1. Clock Island (Enters first)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = slideOutDuration
            ctx.timingFunction = springTiming
            clockPanel.animator().frame = finalClockRect
        }
        
        // 2. Notes Island (Staggered micro-delay +0.05s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.isStretchedOut else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = slideOutDuration
                ctx.timingFunction = springTiming
                self.notesPanel.animator().frame = finalNotesRect
            }
        }
        
        // 3. Schedule Island (Staggered micro-delay +0.10s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self = self, self.isStretchedOut else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = slideOutDuration
                ctx.timingFunction = springTiming
                self.calendarPanel.animator().frame = finalCalRect
            }, completionHandler: { [weak self] in
                self?.isAnimatingSlide = false
                completion?()
            })
        }
    }
    
    public func slideIn(animated: Bool = true, completion: (() -> Void)? = nil) {
        isStretchedOut = false
        let offscreenX = bounds.width + 50
        let easeInTiming = CAMediaTimingFunction(name: .easeIn)
        let slideInDuration: TimeInterval = 0.32
        
        if !animated {
            clockPanel.frame.origin.x = offscreenX
            notesPanel.frame.origin.x = offscreenX + 30
            calendarPanel.frame.origin.x = offscreenX + 60
            masterPanel.frame.origin.x = bounds.width
            completion?()
            return
        }
        
        isAnimatingSlide = true
        
        // 1. Clock Island (Slides back first)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = slideInDuration
            ctx.timingFunction = easeInTiming
            self.clockPanel.animator().frame.origin.x = offscreenX
        }
        
        // 2. Notes Island (Staggered micro-delay +0.05s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, !self.isStretchedOut else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = slideInDuration
                ctx.timingFunction = easeInTiming
                self.notesPanel.animator().frame.origin.x = offscreenX + 30
            }
        }
        
        // 3. Schedule Island (Staggered micro-delay +0.10s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self = self, !self.isStretchedOut else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = slideInDuration
                ctx.timingFunction = easeInTiming
                self.calendarPanel.animator().frame.origin.x = offscreenX + 60
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                self.masterPanel.frame.origin.x = self.bounds.width
                self.isAnimatingSlide = false
                completion?()
            })
        }
    }
    
    public func calculateFittingSize() -> NSSize {
        let width = max(260, min(650, preferredPanelWidth))
        let screen = window?.screen ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        let currentTop: CGFloat
        if let win = window, win.frame.height > 10, win.frame.maxY > visibleFrame.minY + 200 {
            currentTop = win.frame.maxY
        } else {
            currentTop = min(visibleFrame.maxY - 16, visibleFrame.midY + 250)
        }
        let totalH = max(380, currentTop - screenFrame.minY)
        return NSSize(width: width, height: totalH)
    }
    
    public func calculatePanelHeight(forWidth cardW: CGFloat) -> CGFloat {
        let clockH: CGFloat = 120
        let notesH: CGFloat = 106
        let calH = calendarPanel.calculateFittingHeight(forWidth: cardW)
        return clockH + notesH + calH + 36
    }
    
    public override func layout() {
        super.layout()
        
        let b = bounds
        clipContainer.frame = b
        
        let hPad: CGFloat = 8
        let panelW = max(260, b.width - hPad)
        let panelH = b.height
        
        let targetX = isStretchedOut ? hPad : b.width
        masterPanel.frame = NSRect(x: targetX, y: 0, width: panelW, height: panelH)
        masterPanel.layoutSubtreeIfNeeded()
        
        guard !isAnimatingSlide else { return }
        
        let cardW = panelW
        let cardH = panelH
        let islandW = max(0, cardW - 28)
        
        // 1. Dedicated Large Clock & Monthly Calendar Panel (Floating Island 1)
        let clockH: CGFloat = 160
        let clockY: CGFloat = 8
        clockPanel.frame = NSRect(x: 14, y: clockY, width: islandW, height: clockH)
        
        // 2. Quick Notes Panel (Floating Island 2)
        let notesH: CGFloat = 106
        let notesY = clockY + clockH + 11
        notesPanel.frame = NSRect(x: 14, y: notesY, width: islandW, height: notesH)
        
        // 3. Calendar panel occupies space below notes panel (Floating Island 3 & Events)
        let calY = notesY + notesH + 11
        let calH = max(0, cardH - calY)
        calendarPanel.frame = NSRect(x: 0, y: calY, width: cardW, height: calH)
        
        resizeHandle.frame = NSRect(x: 0, y: 0, width: hPad + 14, height: bounds.height)
        window?.invalidateCursorRects(for: resizeHandle)
    }
}

