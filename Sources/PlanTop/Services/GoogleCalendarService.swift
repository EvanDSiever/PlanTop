import Foundation
import AppKit
import EventKit
import Combine

extension Notification.Name {
    public static let planTopCalendarUpdated = Notification.Name("com.plantop.calendarUpdated")
    public static let songTopCalendarUpdated = planTopCalendarUpdated
    public static let planTopSettingsChanged = Notification.Name("com.plantop.settingsChanged")
    public static let songTopSettingsChanged = planTopSettingsChanged
}

public enum CalendarSyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date, todayCount: Int, tomorrowCount: Int)
    case needsPermission
    case unauthorized
    case error(String)
}

public final class GoogleCalendarService: ObservableObject {
    public static let shared = GoogleCalendarService()
    
    @Published public private(set) var classesEvents: [CalendarEvent] = []
    @Published public private(set) var todaysEvents: [CalendarEvent] = []
    @Published public private(set) var tomorrowsEvents: [CalendarEvent] = []
    @Published public private(set) var dismissedEventIds: Set<String> = []
    @Published public private(set) var syncStatus: CalendarSyncStatus = .idle
    @Published public private(set) var lastSyncDate: Date?
    
    private var customOrderClasses: [String] = []
    private var customOrderToday: [String] = []
    private var customOrderTomorrow: [String] = []
    
    public let targetEmail: String = "evandsiever@gmail.com"
    
    @Published public var customICalURL: String {
        didSet {
            UserDefaults.standard.set(customICalURL, forKey: "googleCalendarICalURL")
            if !customICalURL.isEmpty {
                fetchFromICal()
            }
        }
    }
    
    @Published public var isCalendarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCalendarEnabled, forKey: "isCalendarEnabled")
            NotificationCenter.default.post(name: .planTopSettingsChanged, object: nil)
        }
    }
    
    @Published public var isClassesExpanded: Bool {
        didSet {
            UserDefaults.standard.set(isClassesExpanded, forKey: "isClassesCalendarExpanded")
            NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
        }
    }
    
    @Published public var isTodayExpanded: Bool {
        didSet {
            UserDefaults.standard.set(isTodayExpanded, forKey: "isTodayCalendarExpanded")
            NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
        }
    }
    
    @Published public var isTomorrowExpanded: Bool {
        didSet {
            UserDefaults.standard.set(isTomorrowExpanded, forKey: "isTomorrowCalendarExpanded")
            NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
        }
    }
    
    private let eventStore = EKEventStore()
    private var liveSyncTimer: Timer?
    private var timeTickerTimer: Timer?
    private let queue = DispatchQueue(label: "com.plantop.calendar.sync", qos: .userInitiated)
    
    public init() {
        self.customICalURL = UserDefaults.standard.string(forKey: "googleCalendarICalURL") ?? ""
        self.isCalendarEnabled = UserDefaults.standard.object(forKey: "isCalendarEnabled") != nil
            ? UserDefaults.standard.bool(forKey: "isCalendarEnabled")
            : true
        self.isClassesExpanded = UserDefaults.standard.object(forKey: "isClassesCalendarExpanded") != nil
            ? UserDefaults.standard.bool(forKey: "isClassesCalendarExpanded")
            : true
        self.isTodayExpanded = UserDefaults.standard.object(forKey: "isTodayCalendarExpanded") != nil
            ? UserDefaults.standard.bool(forKey: "isTodayCalendarExpanded")
            : true
        self.isTomorrowExpanded = UserDefaults.standard.object(forKey: "isTomorrowCalendarExpanded") != nil
            ? UserDefaults.standard.bool(forKey: "isTomorrowCalendarExpanded")
            : true
        
        if let dismissed = UserDefaults.standard.stringArray(forKey: "plantop_dismissed_event_ids") {
            self.dismissedEventIds = Set(dismissed)
        }
        self.customOrderClasses = UserDefaults.standard.stringArray(forKey: "plantop_order_classes") ?? []
        self.customOrderToday = UserDefaults.standard.stringArray(forKey: "plantop_order_today") ?? []
        self.customOrderTomorrow = UserDefaults.standard.stringArray(forKey: "plantop_order_tomorrow") ?? []
        
        setupObservers()
        startLiveSync()
        
        // Initial fetch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        liveSyncTimer?.invalidate()
        timeTickerTimer?.invalidate()
    }
    
    private func setupObservers() {
        // Observe macOS calendar database changes for instant live updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalendarStoreChanged),
            name: .EKEventStoreChanged,
            object: nil
        )
        // Observe SongTop settings changes (custom class identifiers, theme, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .songTopSettingsChanged,
            object: nil
        )
    }
    
    private func startLiveSync() {
        liveSyncTimer?.invalidate()
        // Fast background live sync (every 15 seconds) to ensure changes in Google Calendar sync instantly without manual refresh
        liveSyncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        
        timeTickerTimer?.invalidate()
        // Fast ticker (every 15 seconds) to keep "NOW" and relative minute countdowns live
        timeTickerTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
                NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
            }
        }
    }
    
    @objc private func handleCalendarStoreChanged() {
        queue.async { [weak self] in
            self?.fetchEvents()
        }
    }
    
    @objc private func handleSettingsChanged() {
        queue.async { [weak self] in
            self?.fetchEvents()
        }
    }
    
    public func dismissEvent(id: String) {
        dismissedEventIds.insert(id)
        UserDefaults.standard.set(Array(dismissedEventIds), forKey: "plantop_dismissed_event_ids")
        classesEvents.removeAll { $0.id == id }
        todaysEvents.removeAll { $0.id == id }
        tomorrowsEvents.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
    }
    
    public func restoreDismissedEvents() {
        dismissedEventIds.removeAll()
        UserDefaults.standard.removeObject(forKey: "plantop_dismissed_event_ids")
        refresh()
    }
    
    public func saveCustomOrder(eventIds: [String], forMode mode: CalendarDayMode) {
        switch mode {
        case .classes:
            self.customOrderClasses = eventIds
            UserDefaults.standard.set(eventIds, forKey: "plantop_order_classes")
        case .today:
            self.customOrderToday = eventIds
            UserDefaults.standard.set(eventIds, forKey: "plantop_order_today")
        case .tomorrow:
            self.customOrderTomorrow = eventIds
            UserDefaults.standard.set(eventIds, forKey: "plantop_order_tomorrow")
        }
    }
    
    public func applyCustomOrder(_ list: [CalendarEvent], forMode mode: CalendarDayMode) -> [CalendarEvent] {
        let order: [String]
        switch mode {
        case .classes: order = customOrderClasses
        case .today: order = customOrderToday
        case .tomorrow: order = customOrderTomorrow
        }
        guard !order.isEmpty else { return list }
        var map = [String: Int]()
        for (i, id) in order.enumerated() {
            map[id] = i
        }
        return list.sorted {
            let rank0 = map[$0.id] ?? (10000 + abs($0.startDate.timeIntervalSince1970.hashValue % 10000))
            let rank1 = map[$1.id] ?? (10000 + abs($1.startDate.timeIntervalSince1970.hashValue % 10000))
            if rank0 != rank1 {
                return rank0 < rank1
            }
            return $0.startDate < $1.startDate
        }
    }
    
    public func setTestEvents(classes: [CalendarEvent], today: [CalendarEvent], tomorrow: [CalendarEvent]) {
        self.classesEvents = classes.filter { !dismissedEventIds.contains($0.id) }
        self.todaysEvents = today.filter { !dismissedEventIds.contains($0.id) }
        self.tomorrowsEvents = tomorrow.filter { !dismissedEventIds.contains($0.id) }
        self.syncStatus = .synced(Date(), todayCount: todaysEvents.count + classesEvents.count, tomorrowCount: tomorrowsEvents.count)
        NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
    }
    
    public func refresh() {
        guard isCalendarEnabled else { return }
        
        if !customICalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fetchFromICal()
            return
        }
        
        checkAuthorizationAndFetch()
    }
    
    public func syncNow() {
        refresh()
    }
    
    public func requestAccess(completion: @escaping (Bool) -> Void) {
        NSLog("[PlanTop-Calendar] requestAccess called")
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                NSLog("[PlanTop-Calendar] requestFullAccessToEvents callback granted: %d, error: %@", granted ? 1 : 0, String(describing: error))
                DispatchQueue.main.async {
                    if granted {
                        self?.fetchEvents()
                    } else {
                        self?.syncStatus = .unauthorized
                    }
                    completion(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                NSLog("[PlanTop-Calendar] requestAccess callback granted: %d, error: %@", granted ? 1 : 0, String(describing: error))
                DispatchQueue.main.async {
                    if granted {
                        self?.fetchEvents()
                    } else {
                        self?.syncStatus = .unauthorized
                    }
                    completion(granted)
                }
            }
        }
    }
    
    private func checkAuthorizationAndFetch() {
        let status = EKEventStore.authorizationStatus(for: .event)
        NSLog("[PlanTop-Calendar] checkAuthorizationAndFetch status rawValue = %ld", status.rawValue)
        
        if status.rawValue == 3 {
            fetchEvents()
            return
        }
        
        if #available(macOS 14.0, *) {
            if status == .fullAccess {
                fetchEvents()
                return
            }
        } else {
            if status == .authorized {
                fetchEvents()
                return
            }
        }
        
        if status == .notDetermined {
            self.syncStatus = .needsPermission
            requestAccess { [weak self] granted in
                if granted { self?.fetchEvents() }
            }
        } else if status == .denied || status == .restricted {
            self.syncStatus = .unauthorized
        } else {
            self.syncStatus = .needsPermission
        }
    }
    
    public func fetchEvents() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Trigger calendar source refresh if needed so Google syncs with macOS
            self.eventStore.refreshSourcesIfNecessary()
            
            let calendar = Calendar.current
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)
            guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
                  let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) else {
                DispatchQueue.main.async {
                    self.syncStatus = .error("Failed to compute date bounds")
                }
                return
            }
            let endOfToday = startOfTomorrow
            
            let allCalendars = self.eventStore.calendars(for: .event)
            let emailLower = self.targetEmail.lowercased()
            
            // Filter calendars strictly for evandsiever@gmail.com
            var targetCalendars = allCalendars.filter { cal in
                let sourceTitle = cal.source.title.lowercased()
                let calTitle = cal.title.lowercased()
                return sourceTitle.contains(emailLower) ||
                       calTitle.contains(emailLower) ||
                       (sourceTitle.contains("google") || sourceTitle.contains("gmail"))
            }
            
            if targetCalendars.isEmpty {
                targetCalendars = allCalendars.filter { cal in
                    cal.source.sourceType == .calDAV || cal.source.title.lowercased().contains("google")
                }
            }
            
            let calendarsToQuery = targetCalendars.isEmpty ? allCalendars : targetCalendars
            
            // 1. Query Today's Events
            let todayPred = self.eventStore.predicateForEvents(withStart: startOfToday, end: endOfToday, calendars: calendarsToQuery)
            let ekToday = self.eventStore.events(matching: todayPred)
            let mappedToday = self.mapEvents(ekToday)
            
            // 2. Query Tomorrow's Events
            let tomorrowPred = self.eventStore.predicateForEvents(withStart: startOfTomorrow, end: endOfTomorrow, calendars: calendarsToQuery)
            let ekTomorrow = self.eventStore.events(matching: tomorrowPred)
            let mappedTomorrow = self.mapEvents(ekTomorrow)
            
            // 3. Query Classes (30-day window from startOfToday)
            let endOfClassesWindow = calendar.date(byAdding: .day, value: 30, to: startOfToday) ?? endOfTomorrow
            let classesPred = self.eventStore.predicateForEvents(withStart: startOfToday, end: endOfClassesWindow, calendars: calendarsToQuery)
            let ekClasses = self.eventStore.events(matching: classesPred)
            let mappedClasses = self.mapEvents(ekClasses)
            
            // Separate Classes & Alfatih events from general agenda (excluding dismissed events)
            let classesList = self.applyCustomOrder(
                mappedClasses.filter { $0.isClassOrAlfatih && !$0.isPast && !self.dismissedEventIds.contains($0.id) },
                forMode: .classes
            )
            let todayFiltered = self.applyCustomOrder(
                mappedToday.filter { !$0.isClassOrAlfatih && !self.dismissedEventIds.contains($0.id) },
                forMode: .today
            )
            let tomorrowFiltered = self.applyCustomOrder(
                mappedTomorrow.filter { !$0.isClassOrAlfatih && !self.dismissedEventIds.contains($0.id) },
                forMode: .tomorrow
            )
            
            DispatchQueue.main.async {
                NSLog("[PlanTop-Calendar] fetchEvents: %ld classes, %ld today, %ld tomorrow", classesList.count, todayFiltered.count, tomorrowFiltered.count)
                self.classesEvents = classesList
                self.todaysEvents = todayFiltered
                self.tomorrowsEvents = tomorrowFiltered
                self.lastSyncDate = Date()
                self.syncStatus = .synced(Date(), todayCount: todayFiltered.count + classesList.count, tomorrowCount: tomorrowFiltered.count)
                NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
            }
        }
    }
    
    private func mapEvents(_ ekEvents: [EKEvent]) -> [CalendarEvent] {
        return ekEvents.map { ev in
            let calColor = ev.calendar.color ?? NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)
            return CalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "Untitled Event",
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                location: ev.location,
                notes: ev.notes,
                url: ev.url,
                calendarName: ev.calendar.title,
                calendarColor: calColor,
                sourceAccount: targetEmail
            )
        }.sorted {
            if $0.isAllDay && !$1.isAllDay { return true }
            if !$0.isAllDay && $1.isAllDay { return false }
            return $0.startDate < $1.startDate
        }
    }
    
    // Direct iCal (.ics) feed parser fallback
    public func fetchFromICal() {
        fetchICS(urlString: customICalURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    public func fetchICS(urlString: String) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.syncStatus = .error("Invalid iCal URL format")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.syncStatus = .syncing
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.syncStatus = .error(error.localizedDescription)
                }
                return
            }
            
            guard let data = data, let icsString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.syncStatus = .error("Failed to read iCal stream")
                }
                return
            }
            
            let (todayFiltered, tomorrowFiltered, classesList) = self.parseICS(icsString)
            
            DispatchQueue.main.async {
                self.classesEvents = classesList
                self.todaysEvents = todayFiltered
                self.tomorrowsEvents = tomorrowFiltered
                self.lastSyncDate = Date()
                self.syncStatus = .synced(Date(), todayCount: todayFiltered.count + classesList.count, tomorrowCount: tomorrowFiltered.count)
                NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
            }
        }
        task.resume()
    }
    
    private func parseICS(_ ics: String) -> ([CalendarEvent], [CalendarEvent], [CalendarEvent]) {
        var today: [CalendarEvent] = []
        var tomorrow: [CalendarEvent] = []
        var classes: [CalendarEvent] = []
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return ([], [], []) }
        
        let lines = ics.components(separatedBy: .newlines)
        var inEvent = false
        var currentSummary = ""
        var currentStart: Date?
        var currentEnd: Date?
        var isAllDay = false
        var currentLocation = ""
        var currentURL: URL?
        var currentDescription = ""
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "BEGIN:VEVENT" {
                inEvent = true
                currentSummary = ""
                currentStart = nil
                currentEnd = nil
                isAllDay = false
                currentLocation = ""
                currentURL = nil
                currentDescription = ""
            } else if line == "END:VEVENT" {
                inEvent = false
                if let start = currentStart {
                    let end = currentEnd ?? start.addingTimeInterval(3600)
                    let event = CalendarEvent(
                        title: currentSummary.isEmpty ? "Google Calendar Event" : currentSummary,
                        startDate: start,
                        endDate: end,
                        isAllDay: isAllDay,
                        location: currentLocation.isEmpty ? nil : currentLocation,
                        notes: currentDescription.isEmpty ? nil : currentDescription,
                        url: currentURL,
                        calendarName: "Google Calendar",
                        sourceAccount: targetEmail
                    )
                    
                    if event.isClassOrAlfatih && event.endDate >= startOfToday {
                        classes.append(event)
                    }
                    
                    if (start >= startOfToday && start < startOfTomorrow) || (end > startOfToday && end <= startOfTomorrow) {
                        if !event.isClassOrAlfatih {
                            today.append(event)
                        }
                    } else if (start >= startOfTomorrow && start < endOfTomorrow) || (end > startOfTomorrow && end <= endOfTomorrow) {
                        if !event.isClassOrAlfatih {
                            tomorrow.append(event)
                        }
                    }
                }
            } else if inEvent {
                if line.hasPrefix("SUMMARY:") {
                    currentSummary = String(line.dropFirst("SUMMARY:".count))
                } else if line.hasPrefix("LOCATION:") {
                    currentLocation = String(line.dropFirst("LOCATION:".count))
                } else if line.hasPrefix("DESCRIPTION:") {
                    currentDescription = String(line.dropFirst("DESCRIPTION:".count))
                } else if line.hasPrefix("URL:") {
                    currentURL = URL(string: String(line.dropFirst("URL:".count)))
                } else if line.hasPrefix("DTSTART") {
                    let (date, allDay) = parseICSDate(line)
                    currentStart = date
                    if allDay { isAllDay = true }
                } else if line.hasPrefix("DTEND") {
                    let (date, _) = parseICSDate(line)
                    currentEnd = date
                }
            }
        }
        
        return (
            applyCustomOrder(today.filter { !dismissedEventIds.contains($0.id) }, forMode: .today),
            applyCustomOrder(tomorrow.filter { !dismissedEventIds.contains($0.id) }, forMode: .tomorrow),
            applyCustomOrder(classes.filter { !dismissedEventIds.contains($0.id) }, forMode: .classes)
        )
    }
    
    private func parseICSDate(_ line: String) -> (Date?, Bool) {
        let parts = line.components(separatedBy: ":")
        guard parts.count >= 2 else { return (nil, false) }
        let dateVal = parts.last!
        let isDateOnly = line.contains("VALUE=DATE") || dateVal.count == 8
        
        let formatter = DateFormatter()
        if isDateOnly {
            formatter.dateFormat = "yyyyMMdd"
            return (formatter.date(from: dateVal), true)
        } else if dateVal.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return (formatter.date(from: dateVal), false)
        } else {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            return (formatter.date(from: dateVal), false)
        }
    }
    
    public func openCalendarApp() {
        NSWorkspace.shared.open(URL(string: "ical://")!)
    }
    
    public func openSystemSettingsAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/InternetAccounts.prefPane"))
        }
    }
}
