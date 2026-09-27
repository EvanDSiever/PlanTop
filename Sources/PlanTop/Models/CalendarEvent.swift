import Foundation
import AppKit

public enum EventUrgencyLevel {
    case active        // Ongoing right now
    case urgent        // Starting in < 1h
    case almostUrgent  // Starting in 1h - 4h
    case notUrgent     // Starting in > 4h
    case neutral       // (Class IEL) when not active, or past events
    
    public var accentColor: NSColor {
        switch self {
        case .active:
            return AppleTheme.danger
        case .urgent:
            return AppleTheme.danger
        case .almostUrgent:
            return AppleTheme.primary
        case .notUrgent:
            return AppleTheme.primary
        case .neutral:
            return AppleTheme.secondaryLabel
        }
    }
    
    public var pillBackground: NSColor {
        switch self {
        case .active:
            return AppleTheme.danger
        case .urgent:
            return AppleTheme.danger
        case .almostUrgent:
            return AppleTheme.primary
        case .notUrgent:
            return AppleTheme.insetWell
        case .neutral:
            return AppleTheme.insetWell
        }
    }
    
    public var pillBorder: NSColor {
        switch self {
        case .active:
            return AppleTheme.danger.withAlphaComponent(0.3)
        case .urgent:
            return AppleTheme.danger.withAlphaComponent(0.3)
        case .almostUrgent:
            return AppleTheme.primary.withAlphaComponent(0.3)
        case .notUrgent:
            return AppleTheme.cardBorder
        case .neutral:
            return AppleTheme.cardBorder
        }
    }
    
    public var hairlineBorder: NSColor {
        return .clear
    }
    
    public var pillTextColor: NSColor {
        switch self {
        case .active, .urgent:
            return .white
        case .almostUrgent, .notUrgent, .neutral:
            return AppleTheme.secondaryLabel
        }
    }
    
    public var blockBackground: NSColor {
        return AppleTheme.cardBackground
    }
    
    public var blockBorder: NSColor {
        return AppleTheme.cardBorder
    }
    
    public var titleTextColor: NSColor {
        switch self {
        case .active:
            return AppleTheme.danger
        case .urgent, .almostUrgent, .notUrgent, .neutral:
            return AppleTheme.label
        }
    }
}

public struct CalendarEvent: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let url: URL?
    public let calendarName: String
    public let calendarColor: NSColor
    public let sourceAccount: String
    public let isRecurring: Bool
    public let recurrenceKey: String?
    public let externalIdentifier: String?
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        calendarName: String = "Google Calendar",
        calendarColor: NSColor = NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0),
        sourceAccount: String = "evandsiever@gmail.com",
        isRecurring: Bool = false,
        recurrenceKey: String? = nil,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Event" : title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.sourceAccount = sourceAccount
        self.isRecurring = isRecurring
        self.recurrenceKey = recurrenceKey
        self.externalIdentifier = externalIdentifier
    }
    
    public var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && now <= endDate
    }
    
    public var isPast: Bool {
        return endDate < Date()
    }
    
    public var isUpcoming: Bool {
        return startDate > Date()
    }
    
    public var hasIELPrefix: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[](){}:-–—#* \t"))
        let lowerStripped = stripped.lowercased()
        if lowerStripped.hasPrefix("iel") {
            if lowerStripped.count == 3 { return true }
            let fourthChar = lowerStripped[lowerStripped.index(lowerStripped.startIndex, offsetBy: 3)]
            return !fourthChar.isLetter || fourthChar.isWhitespace || fourthChar.isNumber
        }
        return false
    }
    
    public var isClassOrAlfatih: Bool {
        if hasIELPrefix {
            return true
        }
        let lower = title.lowercased()
        let identifierStr = UserDefaults.standard.string(forKey: "plantop_class_identifiers")
            ?? UserDefaults.standard.string(forKey: "calendarClassIdentifiers")
            ?? UserDefaults.standard.string(forKey: "songtop_class_identifiers")
            ?? "IEL, Class IEL, Alfatih"
        let keywords = identifierStr
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        if keywords.isEmpty {
            return lower.contains("class iel") || lower.contains("alfatih")
        }
        
        for kw in keywords {
            if kw == "iel" {
                if hasIELPrefix { return true }
            } else if lower.contains(kw) {
                return true
            }
        }
        return false
    }
    
    public var isClassIEL: Bool {
        return isClassOrAlfatih
    }
    
    public var hasReportOrHomeworkPrefix: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[](){}:-–—#* \t"))
        let lowerStripped = stripped.lowercased()
        
        if lowerStripped.hasPrefix("report") {
            if lowerStripped.count == 6 { return true }
            let nextChar = lowerStripped[lowerStripped.index(lowerStripped.startIndex, offsetBy: 6)]
            if !nextChar.isLetter || nextChar.isWhitespace || nextChar.isNumber {
                return true
            }
        }
        
        if lowerStripped.hasPrefix("homework") {
            if lowerStripped.count == 8 { return true }
            let nextChar = lowerStripped[lowerStripped.index(lowerStripped.startIndex, offsetBy: 8)]
            if !nextChar.isLetter || nextChar.isWhitespace || nextChar.isNumber {
                return true
            }
        }
        
        return false
    }
    
    public var isReportOrHomework: Bool {
        if hasReportOrHomeworkPrefix {
            return true
        }
        let lower = title.lowercased()
        let identifierStr = UserDefaults.standard.string(forKey: "plantop_task_identifiers")
            ?? UserDefaults.standard.string(forKey: "calendarTaskIdentifiers")
        if let identifierStr = identifierStr {
            let keywords = identifierStr
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            for kw in keywords {
                let stripped = lower.trimmingCharacters(in: CharacterSet(charactersIn: "[](){}:-–—#* \t"))
                if stripped.hasPrefix(kw) {
                    return true
                }
            }
        }
        return false
    }
    
    public func urgencyLevel(relativeTo now: Date = Date()) -> EventUrgencyLevel {
        if startDate <= now && now <= endDate {
            return .active
        }
        if isPast || isClassOrAlfatih || isReportOrHomework {
            return .neutral
        }
        let diff = startDate.timeIntervalSince(now)
        if diff <= 7200 { // < 2 hours: Most Urgent (Red)
            return .urgent
        } else if diff <= 21600 { // 2 to 6 hours: Almost Urgent (Orange)
            return .almostUrgent
        } else { // > 6 hours: Not Urgent (Green)
            return .notUrgent
        }
    }
    
    public func countdownTimerText(relativeTo now: Date = Date()) -> String {
        if isHappeningNow {
            let remaining = max(0, endDate.timeIntervalSince(now))
            let mins = Int(remaining) / 60
            if mins >= 60 {
                let hrs = mins / 60
                let rem = mins % 60
                return "\(hrs)h \(rem)m left"
            } else {
                let secs = Int(remaining) % 60
                return String(format: "%02dm %02ds left", mins, secs)
            }
        }
        
        if now > endDate {
            return "Ended"
        }
        
        let diff = max(0, startDate.timeIntervalSince(now))
        let totalSecs = Int(diff)
        let hrs = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        
        if hrs >= 24 {
            let days = hrs / 24
            let remHrs = hrs % 24
            return "in \(days)d \(remHrs)h"
        } else if hrs > 0 {
            return String(format: "T-%02d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "T-%02d:%02d", mins, secs)
        }
    }
    
    public func shouldBlink(relativeTo now: Date = Date()) -> Bool {
        guard !isClassOrAlfatih && !isReportOrHomework && !isHappeningNow && !isPast else { return false }
        let diff = startDate.timeIntervalSince(now)
        return diff > 0 && diff <= 1800 // Within 30 minutes
    }
    
    public func blinkPulseDuration(relativeTo now: Date = Date()) -> Double {
        let diff = startDate.timeIntervalSince(now)
        if diff <= 600 { // Within 10 minutes: faster pulse
            return 0.55
        } else {
            return 1.1
        }
    }
    
    public var formattedTime: String {
        return fullTimeRangeString(includeDay: false)
    }
    
    /// Full time range (both start and end if any), optionally including relative or formatted day
    public func fullTimeRangeString(includeDay: Bool = false) -> String {
        if isAllDay {
            if includeDay {
                let cal = Calendar.current
                if cal.isDateInToday(startDate) {
                    return "Today • All Day"
                } else if cal.isDateInTomorrow(startDate) {
                    return "Tomorrow • All Day"
                } else {
                    let dayFmt = DateFormatter()
                    dayFmt.dateFormat = "EEE, MMM d"
                    return "\(dayFmt.string(from: startDate)) • All Day"
                }
            }
            return "All Day"
        }
        
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        let startStr = timeFmt.string(from: startDate)
        let endStr = timeFmt.string(from: endDate)
        let timeSpan = "\(startStr) – \(endStr)"
        
        if includeDay {
            let cal = Calendar.current
            if !cal.isDateInToday(startDate) {
                if cal.isDateInTomorrow(startDate) {
                    return "Tomorrow • \(timeSpan)"
                } else {
                    let dayFmt = DateFormatter()
                    dayFmt.dateFormat = "EEE, MMM d"
                    return "\(dayFmt.string(from: startDate)) • \(timeSpan)"
                }
            }
        }
        return timeSpan
    }
    
    /// Formats remaining duration according to "XX days XX hours XX mins XXs" specifications (down to the second)
    public static func formatRemainingDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if days > 0 {
            let dUnit = days == 1 ? "day" : "days"
            let hUnit = hours == 1 ? "hour" : "hours"
            let mUnit = minutes == 1 ? "min" : "mins"
            return "\(days) \(dUnit) \(hours) \(hUnit) \(minutes) \(mUnit) \(seconds)s"
        } else if hours > 0 {
            let hUnit = hours == 1 ? "hour" : "hours"
            let mUnit = minutes == 1 ? "min" : "mins"
            return "\(hours) \(hUnit) \(minutes) \(mUnit) \(seconds)s"
        } else if minutes > 0 {
            let mUnit = minutes == 1 ? "min" : "mins"
            return "\(minutes) \(mUnit) \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    /// Compact duration formatter (e.g. "1h 30m", "45m", "2h")
    public static func formatShortDuration(_ interval: TimeInterval) -> String {
        let totalMins = max(1, Int(round(interval / 60)))
        let hours = totalMins / 60
        let mins = totalMins % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    
    /// Returns the countdown timer prefix and duration text for Classes, Today, or other categories
    public func statusTimerInfo(isClassesCategory: Bool, isTodayCategory: Bool, relativeTo now: Date = Date()) -> (prefix: String, timer: String, isEnded: Bool) {
        if isClassesCategory {
            if now < startDate {
                let diff = startDate.timeIntervalSince(now)
                return ("Starts in ", CalendarEvent.formatRemainingDuration(diff), false)
            } else if now <= endDate {
                let diff = endDate.timeIntervalSince(now)
                return ("Ends in ", CalendarEvent.formatRemainingDuration(diff), false)
            } else {
                return ("", "Ended", true)
            }
        } else if isTodayCategory {
            if now <= endDate {
                let diff = endDate.timeIntervalSince(now)
                return ("Limit in ", CalendarEvent.formatRemainingDuration(diff), false)
            } else {
                return ("", "Ended", true)
            }
        } else {
            // General / Tomorrow category
            if now < startDate {
                let diff = startDate.timeIntervalSince(now)
                return ("Starts in ", CalendarEvent.formatRemainingDuration(diff), false)
            } else if now <= endDate {
                let diff = endDate.timeIntervalSince(now)
                return ("Ends in ", CalendarEvent.formatRemainingDuration(diff), false)
            } else {
                return ("", "Ended", true)
            }
        }
    }
    
    /// Returns true if this event is currently active, starts today, ends today, or spans across today.
    public func isHappeningOrDueToday(relativeTo now: Date = Date()) -> Bool {
        let cal = Calendar.current
        if cal.isDateInToday(startDate) || cal.isDateInToday(endDate) || isHappeningNow {
            return true
        }
        let startOfToday = cal.startOfDay(for: now)
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) else {
            return false
        }
        return startDate < startOfTomorrow && endDate >= startOfToday
    }
    
    /// Formatted date on which the event is scheduled to occur (e.g. "Thursday, Sep 24" or "Tomorrow, Sep 24")
    public func occurrenceDateString(relativeTo now: Date = Date(), compact: Bool = false) -> String {
        let cal = Calendar.current
        let targetDate = startDate
        let dayFmt = DateFormatter()
        
        if cal.isDateInToday(targetDate) {
            return "Today"
        }
        
        if cal.isDateInTomorrow(targetDate) {
            if compact {
                return "Tomorrow"
            } else {
                dayFmt.dateFormat = "MMM d"
                return "Tomorrow, \(dayFmt.string(from: targetDate))"
            }
        }
        
        let currentYear = cal.component(.year, from: now)
        let eventYear = cal.component(.year, from: targetDate)
        
        if compact {
            dayFmt.dateFormat = "EEE, MMM d"
        } else {
            if currentYear == eventYear {
                dayFmt.dateFormat = "EEEE, MMM d"
            } else {
                dayFmt.dateFormat = "EEE, MMM d, yyyy"
            }
        }
        return dayFmt.string(from: targetDate)
    }
    
    public var relativeStatusText: String {
        let now = Date()
        if isHappeningNow {
            let remaining = endDate.timeIntervalSince(now)
            let mins = Int(remaining / 60)
            if mins >= 60 {
                let hrs = mins / 60
                let remMins = mins % 60
                return remMins > 0 ? "\(hrs)h \(remMins)m left" : "\(hrs)h left"
            } else if mins > 0 {
                return "\(mins)m left"
            } else {
                return "Ending now"
            }
        } else if isUpcoming {
            let diff = startDate.timeIntervalSince(now)
            let mins = Int(diff / 60)
            if mins < 60 {
                return mins <= 1 ? "Starts in 1m" : "Starts in \(mins)m"
            } else if mins < 1440 {
                let hrs = mins / 60
                let remMins = mins % 60
                return remMins > 0 ? "In \(hrs)h \(remMins)m" : "In \(hrs)h"
            } else {
                return "Later"
            }
        } else {
            return "Ended"
        }
    }
    
    /// Detects video conference links (Google Meet, Zoom, Teams, Webex)
    public var meetURL: URL? {
        if let directURL = url, isVideoConferenceURL(directURL) {
            return directURL
        }
        if let loc = location, let detected = extractFirstURL(from: loc), isVideoConferenceURL(detected) {
            return detected
        }
        if let n = notes, let detected = extractFirstURL(from: n), isVideoConferenceURL(detected) {
            return detected
        }
        return nil
    }
    
    public var isGoogleMeet: Bool {
        guard let u = meetURL else { return false }
        return u.host?.contains("meet.google.com") ?? false
    }
    
    private func isVideoConferenceURL(_ u: URL) -> Bool {
        guard let host = u.host?.lowercased() else { return false }
        return host.contains("meet.google.com") ||
               host.contains("zoom.us") ||
               host.contains("teams.microsoft.com") ||
               host.contains("webex.com")
    }
    
    private func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        return matches.first?.url
    }
    
    public var formattedStartTime: String {
        if isAllDay { return "All Day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
    
    public var videoMeetingURL: URL? {
        return meetURL
    }
    
    public var webCalendarURL: URL? {
        return googleCalendarURL
    }
    
    /// Generates the direct web Google Calendar link for this specific event.
    public var googleCalendarURL: URL {
        // 1. Direct URL check: if event.url is already a Google Calendar link
        if let direct = url, let host = direct.host?.lowercased(), host.contains("google.com"), direct.absoluteString.contains("calendar") {
            return direct
        }
        
        // 2. Check notes for an embedded Google Calendar link (common in Google invites)
        if let notes = notes {
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                let matches = detector.matches(in: notes, options: [], range: NSRange(location: 0, length: (notes as NSString).length))
                for match in matches {
                    if let u = match.url, let host = u.host?.lowercased(), host.contains("google.com"), u.absoluteString.contains("calendar") {
                        return u
                    }
                }
            }
        }
        
        let email = sourceAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrefix: String = (email.contains("@") && email.contains(".")) ? "u/\(email)/" : ""
        
        // 3. Construct direct event edit link from externalIdentifier or recurrenceKey
        if let extId = externalIdentifier ?? recurrenceKey, !extId.isEmpty {
            let cleanId: String
            if extId.contains("@google.com") {
                cleanId = extId.components(separatedBy: "@google.com").first ?? extId
            } else if extId.contains("@") {
                cleanId = extId.components(separatedBy: "@").first ?? extId
            } else {
                cleanId = extId
            }
            
            let isAppleUUID = cleanId.contains("-") && cleanId.count == 36
            let isLikelyGoogleUID = extId.contains("@google.com") || (!isAppleUUID && cleanId.count >= 16 && cleanId.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil)
            
            if !cleanId.isEmpty && !isAppleUUID && isLikelyGoogleUID {
                let payload: String
                if email.contains("@group.calendar.google.com") {
                    let userPart = email.replacingOccurrences(of: "@group.calendar.google.com", with: "@g")
                    payload = "\(cleanId) \(userPart)"
                } else if email.contains("@") {
                    payload = "\(cleanId) \(email)"
                } else {
                    payload = cleanId
                }
                
                if let data = payload.data(using: .utf8) {
                    let b64 = data.base64EncodedString()
                        .replacingOccurrences(of: "=", with: "")
                        .replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_")
                    
                    if let u = URL(string: "https://calendar.google.com/calendar/\(userPrefix)r/eventedit/\(b64)") {
                        return u
                    }
                }
            }
        }
        
        // 4. Fallback: Search for the event title in Google Calendar
        if let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), !encodedTitle.isEmpty {
            if let searchURL = URL(string: "https://calendar.google.com/calendar/\(userPrefix)r/search?q=\(encodedTitle)") {
                return searchURL
            }
        }
        
        // 5. Ultimate fallback: Open Google Calendar on the day of the event
        let cal = Calendar.current
        let year = cal.component(.year, from: startDate)
        let month = cal.component(.month, from: startDate)
        let day = cal.component(.day, from: startDate)
        return URL(string: "https://calendar.google.com/calendar/\(userPrefix)r/day/\(year)/\(month)/\(day)") ?? URL(string: "https://calendar.google.com")!
    }
    
    /// Formats raw notes or event description containing HTML (from Google Calendar) or Markdown syntax
    /// into a clean, beautifully styled NSAttributedString without showing raw markup tags.
    public static func formatNotesAttributedString(
        _ raw: String,
        baseFontSize: CGFloat = 13.0,
        textColor: NSColor = AppleTheme.label,
        linkColor: NSColor = AppleTheme.primary
    ) -> NSAttributedString {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NSAttributedString() }
        
        // 1. Convert block HTML tags and line breaks
        var text = trimmed
        let lineBreakPatterns: [(pattern: String, replacement: String)] = [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</p\\s*>", "\n\n"),
            ("(?i)<p\\s*>", ""),
            ("(?i)<li\\s*>", "\n• "),
            ("(?i)</li\\s*>", ""),
            ("(?i)</?(?:ul|ol|div|blockquote)[^>]*>", "\n")
        ]
        for item in lineBreakPatterns {
            if let regex = try? NSRegularExpression(pattern: item.pattern) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length), withTemplate: item.replacement)
            }
        }
        
        // 2. Decode standard HTML entities
        let entities: [(encoded: String, decoded: String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " ")
        ]
        for entity in entities {
            text = text.replacingOccurrences(of: entity.encoded, with: entity.decoded)
        }
        
        // Decode numeric entities (e.g. &#65;)
        if let numEntityRegex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsText = text as NSString
            let matches = numEntityRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let codeStr = nsText.substring(with: match.range(at: 1))
                if let code = UInt32(codeStr), let scalar = UnicodeScalar(code) {
                    let charStr = String(Character(scalar))
                    text = (text as NSString).replacingCharacters(in: match.range, with: charStr)
                }
            }
        }
        
        // 3. Normalize multiple newlines (no more than 2 consecutive newlines)
        if let multiNL = try? NSRegularExpression(pattern: "\n{3,}") {
            text = multiNL.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "\n\n")
        }
        
        // Base fonts
        let regularFont = AppleTheme.font(size: baseFontSize, weight: .regular)
        let boldFont = AppleTheme.font(size: baseFontSize, weight: .bold)
        let italicFont = NSFontManager.shared.convert(regularFont, toHaveTrait: .italicFontMask)
        let linkFont = AppleTheme.font(size: baseFontSize, weight: .medium)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.0
        
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: regularFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])
        
        // Helper to iteratively parse and replace tag patterns with formatted inner text
        func processTagPattern(regexPattern: String, isLink: Bool = false, isBold: Bool = false, isItalic: Bool = false, isUnderline: Bool = false) {
            guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else { return }
            var searchRange = NSRange(location: 0, length: attr.length)
            while searchRange.location < attr.length,
                  let match = regex.firstMatch(in: attr.string, options: [], range: searchRange) {
                let fullRange = match.range
                let ns = attr.string as NSString
                
                let innerText: String
                var linkURL: URL? = nil
                
                if isLink {
                    if match.numberOfRanges >= 3 {
                        let g1 = ns.substring(with: match.range(at: 1))
                        let g2 = ns.substring(with: match.range(at: 2))
                        if g1.hasPrefix("http://") || g1.hasPrefix("https://") || g1.hasPrefix("mailto:") {
                            linkURL = URL(string: g1)
                            innerText = g2.isEmpty ? g1 : g2
                        } else {
                            linkURL = URL(string: g2)
                            innerText = g1.isEmpty ? g2 : g1
                        }
                    } else if match.numberOfRanges == 2 {
                        let g1 = ns.substring(with: match.range(at: 1))
                        linkURL = URL(string: g1)
                        innerText = g1
                    } else {
                        innerText = ns.substring(with: fullRange)
                    }
                } else {
                    if match.numberOfRanges >= 2 {
                        innerText = ns.substring(with: match.range(at: 1))
                    } else {
                        innerText = ns.substring(with: fullRange)
                    }
                }
                
                attr.replaceCharacters(in: fullRange, with: innerText)
                let newRange = NSRange(location: fullRange.location, length: (innerText as NSString).length)
                
                if isBold {
                    attr.addAttribute(.font, value: boldFont, range: newRange)
                }
                if isItalic {
                    attr.addAttribute(.font, value: italicFont, range: newRange)
                }
                if isUnderline {
                    attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
                }
                if let url = linkURL {
                    attr.addAttribute(.link, value: url, range: newRange)
                    attr.addAttribute(.foregroundColor, value: linkColor, range: newRange)
                    attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
                    attr.addAttribute(.font, value: linkFont, range: newRange)
                }
                
                let nextLoc = fullRange.location + newRange.length
                searchRange = NSRange(location: nextLoc, length: attr.length - nextLoc)
            }
        }
        
        // 4. Extract HTML Links: <a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>
        processTagPattern(regexPattern: "<a\\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", isLink: true)
        
        // 5. Extract Markdown Links: \[([^\]]+)\]\(((?:https?://|mailto:)[^\)]+)\)
        processTagPattern(regexPattern: "\\[([^\\]]+)\\]\\(((?:https?://|mailto:)[^\\)]+)\\)", isLink: true)
        
        // 6. Extract HTML Bold: <b>...</b>, <strong>...</strong>
        processTagPattern(regexPattern: "<(?:b|strong)>(.*?)</(?:b|strong)>", isBold: true)
        
        // 7. Extract Markdown Bold: **...** and __...__
        processTagPattern(regexPattern: "(?:\\*\\*|__)(.+?)(?:\\*\\*|__)", isBold: true)
        
        // 8. Extract HTML Italic: <i>...</i>, <em>...</em>
        processTagPattern(regexPattern: "<(?:i|em)>(.*?)</(?:i|em)>", isItalic: true)
        
        // 9. Extract Markdown Italic: *...* and _..._
        processTagPattern(regexPattern: "(?<!\\*)\\*(?!\\*)([^\\*\\n]+?)(?<!\\*)\\*(?!\\*)", isItalic: true)
        processTagPattern(regexPattern: "(?<!_)_(?!_)([^_\\n]+?)(?<!_)_(?!_)", isItalic: true)
        
        // 10. Extract HTML Underline: <u>...</u>
        processTagPattern(regexPattern: "<u>(.*?)</u>", isUnderline: true)
        
        // 11. Strip any remaining or unknown HTML tags: <[^>]+>
        if let leftoverHTML = try? NSRegularExpression(pattern: "<[^>]+>") {
            var searchRange = NSRange(location: 0, length: attr.length)
            while searchRange.location < attr.length,
                  let match = leftoverHTML.firstMatch(in: attr.string, options: [], range: searchRange) {
                attr.replaceCharacters(in: match.range, with: "")
                searchRange = NSRange(location: match.range.location, length: attr.length - match.range.location)
            }
        }
        
        // 12. Auto-linkify plain URLs (https://... or http://...) that don't already have a .link attribute
        if let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let fullRange = NSRange(location: 0, length: attr.length)
            for match in urlDetector.matches(in: attr.string, options: [], range: fullRange) {
                guard let url = match.url else { continue }
                var hasLink = false
                attr.enumerateAttribute(.link, in: match.range, options: []) { val, _, stop in
                    if val != nil {
                        hasLink = true
                        stop.pointee = true
                    }
                }
                if !hasLink {
                    attr.addAttribute(.link, value: url, range: match.range)
                    attr.addAttribute(.foregroundColor, value: linkColor, range: match.range)
                    attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
                    attr.addAttribute(.font, value: linkFont, range: match.range)
                }
            }
        }
        
        // 13. Trim leading/trailing whitespace & newlines from attributed string
        while attr.length > 0 {
            let firstChar = (attr.string as NSString).substring(to: 1)
            if firstChar == " " || firstChar == "\n" || firstChar == "\t" || firstChar == "\r" {
                attr.deleteCharacters(in: NSRange(location: 0, length: 1))
            } else {
                break
            }
        }
        while attr.length > 0 {
            let lastChar = (attr.string as NSString).substring(from: attr.length - 1)
            if lastChar == " " || lastChar == "\n" || lastChar == "\t" || lastChar == "\r" {
                attr.deleteCharacters(in: NSRange(location: attr.length - 1, length: 1))
            } else {
                break
            }
        }
        
        return attr
    }
}
