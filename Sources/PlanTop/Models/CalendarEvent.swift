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
            return NeumorphicTheme.activeText
        case .urgent:
            return NeumorphicTheme.urgentText
        case .almostUrgent:
            return NeumorphicTheme.almostUrgentText
        case .notUrgent:
            return NeumorphicTheme.notUrgentText
        case .neutral:
            return NeumorphicTheme.textSecondary
        }
    }
    
    public var pillBackground: NSColor {
        switch self {
        case .active:
            return NeumorphicTheme.activePill
        case .urgent:
            return NeumorphicTheme.urgentPill
        case .almostUrgent:
            return NeumorphicTheme.almostUrgentPill
        case .notUrgent:
            return NeumorphicTheme.notUrgentPill
        case .neutral:
            return NeumorphicTheme.classNeutralPill
        }
    }
    
    public var pillBorder: NSColor {
        switch self {
        case .active:
            return NeumorphicTheme.activeHairline
        case .urgent:
            return NeumorphicTheme.urgentHairline
        case .almostUrgent:
            return NeumorphicTheme.almostUrgentHairline
        case .notUrgent:
            return NeumorphicTheme.notUrgentHairline
        case .neutral:
            return NeumorphicTheme.classNeutralHairline
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
            return NeumorphicTheme.textSecondary
        }
    }
    
    public var blockBackground: NSColor {
        switch self {
        case .active:
            return NSColor(red: 1.0, green: 0.94, blue: 0.94, alpha: 1.0)
        case .urgent:
            return NSColor(red: 1.0, green: 0.965, blue: 0.95, alpha: 1.0)
        case .almostUrgent, .notUrgent, .neutral:
            return NeumorphicTheme.cardElevated
        }
    }
    
    public var blockBorder: NSColor {
        return .clear
    }
    
    public var titleTextColor: NSColor {
        switch self {
        case .active:
            return NeumorphicTheme.activeText
        case .urgent, .almostUrgent, .notUrgent, .neutral:
            return NeumorphicTheme.textPrimary
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
        sourceAccount: String = "evandsiever@gmail.com"
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
    
    public var isClassOrAlfatih: Bool {
        let lower = title.lowercased()
        let identifierStr = UserDefaults.standard.string(forKey: "plantop_class_identifiers")
            ?? UserDefaults.standard.string(forKey: "calendarClassIdentifiers")
            ?? UserDefaults.standard.string(forKey: "songtop_class_identifiers")
            ?? "Class IEL, Alfatih"
        let keywords = identifierStr
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        if keywords.isEmpty {
            return lower.contains("class iel") || lower.contains("alfatih")
        }
        
        for kw in keywords {
            if lower.contains(kw) {
                return true
            }
        }
        return false
    }
    
    public var isClassIEL: Bool {
        return isClassOrAlfatih
    }
    
    public func urgencyLevel(relativeTo now: Date = Date()) -> EventUrgencyLevel {
        if startDate <= now && now <= endDate {
            return .active
        }
        if isPast || isClassOrAlfatih {
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
        guard !isClassOrAlfatih && !isHappeningNow && !isPast else { return false }
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
        if isAllDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)
        return "\(startStr) – \(endStr)"
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
        return url
    }
}
