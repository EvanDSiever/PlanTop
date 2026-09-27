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

public struct DismissedEventRecord: Codable, Equatable {
    public let id: String
    public let title: String
    public let timestamp: Date
    public let externalIdentifier: String?
    
    public init(id: String, title: String, timestamp: Date = Date(), externalIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.externalIdentifier = externalIdentifier
    }
}

public final class GoogleCalendarService: ObservableObject {
    public static let shared = GoogleCalendarService()
    
    @Published public private(set) var classesEvents: [CalendarEvent] = []
    @Published public private(set) var tasksEvents: [CalendarEvent] = []
    public var reportsEvents: [CalendarEvent] { return tasksEvents }
    @Published public private(set) var todaysEvents: [CalendarEvent] = []
    @Published public private(set) var tomorrowsEvents: [CalendarEvent] = []
    @Published public private(set) var dismissedEventIds: Set<String> = []
    @Published public private(set) var dismissedHistory: [DismissedEventRecord] = []
    @Published public private(set) var syncStatus: CalendarSyncStatus = .idle
    @Published public private(set) var lastSyncDate: Date?
    
    private var customOrderClasses: [String] = []
    private var customOrderTasks: [String] = []
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
        if let data = UserDefaults.standard.data(forKey: "plantop_dismissed_history"),
           let history = try? JSONDecoder().decode([DismissedEventRecord].self, from: data) {
            self.dismissedHistory = history
        }
        self.customOrderClasses = UserDefaults.standard.stringArray(forKey: "plantop_order_classes") ?? []
        self.customOrderTasks = UserDefaults.standard.stringArray(forKey: "plantop_order_tasks")
            ?? UserDefaults.standard.stringArray(forKey: "plantop_order_reports")
            ?? []
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
    
    /// Returns the date range for the current week starting on Monday at 00:00:00 and ending on Sunday at 23:59:59 (next Monday 00:00:00).
    public static func currentWeekInterval(for date: Date = Date()) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday is start of week
        cal.timeZone = TimeZone.current
        if let interval = cal.dateInterval(of: .weekOfYear, for: date) {
            return (interval.start, interval.end)
        }
        let weekday = cal.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        let startOfDay = cal.startOfDay(for: date)
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday) ?? monday.addingTimeInterval(7 * 86400)
        return (monday, nextMonday)
    }
    
    /// Deduplicates recurring events and repeated events with matching titles so that only one set/instance is displayed.
    /// Prioritizes the active or next upcoming instance; falls back to the earliest instance if all have ended.
    public static func deduplicateRecurringEvents(_ events: [CalendarEvent], relativeTo now: Date = Date()) -> [CalendarEvent] {
        var groups: [String: [CalendarEvent]] = [:]
        var groupOrder: [String] = []
        
        for event in events {
            let normalizedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = event.recurrenceKey ?? normalizedTitle
            
            if groups[key] == nil {
                groups[key] = []
                groupOrder.append(key)
            }
            groups[key]?.append(event)
        }
        
        var chosen: [CalendarEvent] = []
        for key in groupOrder {
            guard let instances = groups[key], !instances.isEmpty else { continue }
            if instances.count == 1 {
                chosen.append(instances[0])
                continue
            }
            
            let sortedInstances = instances.sorted { $0.startDate < $1.startDate }
            if let active = sortedInstances.first(where: { $0.isHappeningNow }) {
                chosen.append(active)
            } else if let nextUpcoming = sortedInstances.first(where: { $0.endDate >= now }) {
                chosen.append(nextUpcoming)
            } else {
                chosen.append(sortedInstances.last!)
            }
        }
        
        return chosen.sorted {
            if $0.isAllDay && !$1.isAllDay { return true }
            if !$0.isAllDay && $1.isAllDay { return false }
            return $0.startDate < $1.startDate
        }
    }
    
    private func saveDismissedState() {
        UserDefaults.standard.set(Array(dismissedEventIds), forKey: "plantop_dismissed_event_ids")
        if let data = try? JSONEncoder().encode(dismissedHistory) {
            UserDefaults.standard.set(data, forKey: "plantop_dismissed_history")
        }
    }
    
    public func dismissEvent(_ event: CalendarEvent) {
        dismissEvent(id: event.id, title: event.title, externalIdentifier: event.externalIdentifier)
    }
    
    public func dismissEvent(id: String, title: String? = nil, externalIdentifier: String? = nil) {
        dismissedEventIds.insert(id)
        if let ext = externalIdentifier, !ext.isEmpty {
            dismissedEventIds.insert(ext)
        }
        let eventTitle = title ?? (eventStore.event(withIdentifier: id)?.title ?? "Event")
        let record = DismissedEventRecord(id: id, title: eventTitle, timestamp: Date(), externalIdentifier: externalIdentifier)
        dismissedHistory.removeAll { $0.id == id }
        dismissedHistory.append(record)
        
        saveDismissedState()
        
        classesEvents.removeAll { $0.id == id || (externalIdentifier != nil && $0.externalIdentifier == externalIdentifier) }
        tasksEvents.removeAll { $0.id == id || (externalIdentifier != nil && $0.externalIdentifier == externalIdentifier) }
        todaysEvents.removeAll { $0.id == id || (externalIdentifier != nil && $0.externalIdentifier == externalIdentifier) }
        tomorrowsEvents.removeAll { $0.id == id || (externalIdentifier != nil && $0.externalIdentifier == externalIdentifier) }
        NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
        NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
    }
    
    @discardableResult
    public func undoLastDismissedEvent() -> DismissedEventRecord? {
        guard let lastRecord = dismissedHistory.popLast() else {
            if let firstId = dismissedEventIds.first {
                restoreEvent(id: firstId)
            }
            return nil
        }
        restoreEvent(id: lastRecord.id, externalIdentifier: lastRecord.externalIdentifier)
        return lastRecord
    }
    
    public func restoreEvent(id: String, externalIdentifier: String? = nil) {
        let base = id.components(separatedBy: "/RID=").first ?? id
        dismissedEventIds = dismissedEventIds.filter { existing in
            if existing == id || existing == base || existing.hasPrefix(base + "/RID=") {
                return false
            }
            if let ext = externalIdentifier, !ext.isEmpty && existing == ext {
                return false
            }
            return true
        }
        dismissedHistory.removeAll { $0.id == id || $0.id == base }
        saveDismissedState()
        refresh()
        NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
        NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
    }
    
    public func restoreDismissedEvents() {
        dismissedEventIds.removeAll()
        dismissedHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "plantop_dismissed_event_ids")
        UserDefaults.standard.removeObject(forKey: "plantop_dismissed_history")
        refresh()
        NotificationCenter.default.post(name: .planTopCalendarUpdated, object: nil)
        NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
    }
    
    public func saveCustomOrder(eventIds: [String], forMode mode: CalendarDayMode) {
        switch mode {
        case .classes:
            self.customOrderClasses = eventIds
            UserDefaults.standard.set(eventIds, forKey: "plantop_order_classes")
        case .tasks:
            self.customOrderTasks = eventIds
            UserDefaults.standard.set(eventIds, forKey: "plantop_order_tasks")
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
        case .tasks: order = customOrderTasks
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
    
    public func setTestEvents(classes: [CalendarEvent], today: [CalendarEvent], tomorrow: [CalendarEvent], tasks: [CalendarEvent] = [], reports: [CalendarEvent] = []) {
        let allTasks = tasks.isEmpty ? reports : tasks
        self.classesEvents = classes.filter { !dismissedEventIds.contains($0.id) }
        self.tasksEvents = GoogleCalendarService.deduplicateRecurringEvents(allTasks.filter { !dismissedEventIds.contains($0.id) })
        self.todaysEvents = today.filter { !dismissedEventIds.contains($0.id) }
        self.tomorrowsEvents = tomorrow.filter { !dismissedEventIds.contains($0.id) }
        self.syncStatus = .synced(Date(), todayCount: todaysEvents.count + classesEvents.count + tasksEvents.count, tomorrowCount: tomorrowsEvents.count)
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
            
            // 3. Query Classes (Only for the day - startOfToday to endOfToday)
            let classesPred = self.eventStore.predicateForEvents(withStart: startOfToday, end: endOfToday, calendars: calendarsToQuery)
            let ekClasses = self.eventStore.events(matching: classesPred)
            let mappedClasses = self.mapEvents(ekClasses)
            
            // 4. Query Tasks (Strictly limited to the current week: starting on Monday and ending on Sunday)
            let (startOfWeek, endOfWeek) = GoogleCalendarService.currentWeekInterval(for: Date())
            let tasksPred = self.eventStore.predicateForEvents(withStart: startOfWeek, end: endOfWeek, calendars: calendarsToQuery)
            let ekTasks = self.eventStore.events(matching: tasksPred)
            let mappedTasks = self.mapEvents(ekTasks)
            // Separate into dedicated category lists (excluding dismissed events, strictly within current week)
            let rawTasks = mappedTasks.filter {
                $0.isReportOrHomework &&
                $0.startDate < endOfWeek && $0.endDate >= startOfWeek &&
                !self.dismissedEventIds.contains($0.id)
            }
            let deduplicatedTasks = GoogleCalendarService.deduplicateRecurringEvents(rawTasks)
            let tasksList = self.applyCustomOrder(deduplicatedTasks, forMode: .tasks)
            
            let classesList = self.applyCustomOrder(
                mappedClasses.filter { $0.isClassOrAlfatih && !$0.isReportOrHomework && $0.startDate >= startOfToday && $0.startDate < startOfTomorrow && !self.dismissedEventIds.contains($0.id) },
                forMode: .classes
            )
            let todayFiltered = self.applyCustomOrder(
                mappedToday.filter { !$0.isClassOrAlfatih && !$0.isReportOrHomework && !self.dismissedEventIds.contains($0.id) },
                forMode: .today
            )
            let tomorrowFiltered = self.applyCustomOrder(
                mappedTomorrow.filter { !$0.isClassOrAlfatih && !$0.isReportOrHomework && !self.dismissedEventIds.contains($0.id) },
                forMode: .tomorrow
            )
            
            DispatchQueue.main.async {
                NSLog("[PlanTop-Calendar] fetchEvents: %ld classes, %ld tasks, %ld today, %ld tomorrow", classesList.count, tasksList.count, todayFiltered.count, tomorrowFiltered.count)
                self.classesEvents = classesList
                self.tasksEvents = tasksList
                self.todaysEvents = todayFiltered
                self.tomorrowsEvents = tomorrowFiltered
                self.lastSyncDate = Date()
                self.syncStatus = .synced(Date(), todayCount: todayFiltered.count + classesList.count + tasksList.count, tomorrowCount: tomorrowFiltered.count)
                NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
            }
        }
    }
    
    private func mapEvents(_ ekEvents: [EKEvent]) -> [CalendarEvent] {
        return ekEvents.map { ev in
            let calColor = ev.calendar.color ?? NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)
            let hasRules = ev.hasRecurrenceRules || (ev.recurrenceRules != nil && !ev.recurrenceRules!.isEmpty) || ev.isDetached
            let extId = ev.calendarItemExternalIdentifier
            let isRecurring = hasRules || (extId != nil && !extId!.isEmpty)
            let recurrenceKey = isRecurring ? (extId ?? "\(ev.calendar.calendarIdentifier)_\(ev.title ?? "")".lowercased()) : nil
            
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
                sourceAccount: targetEmail,
                isRecurring: isRecurring,
                recurrenceKey: recurrenceKey,
                externalIdentifier: extId
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
            
            let (todayFiltered, tomorrowFiltered, classesList, tasksList) = self.parseICS(icsString)
            
            DispatchQueue.main.async {
                self.classesEvents = classesList
                self.tasksEvents = tasksList
                self.todaysEvents = todayFiltered
                self.tomorrowsEvents = tomorrowFiltered
                self.lastSyncDate = Date()
                self.syncStatus = .synced(Date(), todayCount: todayFiltered.count + classesList.count + tasksList.count, tomorrowCount: tomorrowFiltered.count)
                NotificationCenter.default.post(name: .songTopCalendarUpdated, object: nil)
            }
        }
        task.resume()
    }
    
    private func parseICS(_ ics: String) -> ([CalendarEvent], [CalendarEvent], [CalendarEvent], [CalendarEvent]) {
        var today: [CalendarEvent] = []
        var tomorrow: [CalendarEvent] = []
        var classes: [CalendarEvent] = []
        var tasks: [CalendarEvent] = []
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return ([], [], [], []) }
        let (startOfWeek, endOfWeek) = GoogleCalendarService.currentWeekInterval(for: Date())
        
        let lines = ics.components(separatedBy: .newlines)
        var inEvent = false
        var currentSummary = ""
        var currentStart: Date?
        var currentEnd: Date?
        var isAllDay = false
        var currentLocation = ""
        var currentURL: URL?
        var currentDescription = ""
        var currentUID = ""
        var isRecurring = false
        
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
                currentUID = ""
                isRecurring = false
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
                        sourceAccount: targetEmail,
                        isRecurring: isRecurring,
                        recurrenceKey: currentUID.isEmpty ? nil : currentUID,
                        externalIdentifier: currentUID.isEmpty ? nil : currentUID
                    )
                    
                    if event.isReportOrHomework && (start < endOfWeek && end >= startOfWeek) {
                        tasks.append(event)
                    } else if event.isClassOrAlfatih && (start >= startOfToday && start < startOfTomorrow) {
                        classes.append(event)
                    } else if (start >= startOfToday && start < startOfTomorrow) || (end > startOfToday && end <= startOfTomorrow) {
                        today.append(event)
                    } else if (start >= startOfTomorrow && start < endOfTomorrow) || (end > startOfTomorrow && end <= endOfTomorrow) {
                        tomorrow.append(event)
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
                } else if line.hasPrefix("UID:") {
                    currentUID = String(line.dropFirst("UID:".count))
                } else if line.hasPrefix("RRULE:") || line.hasPrefix("RECURRENCE-ID") {
                    isRecurring = true
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
        
        let deduplicatedTasks = GoogleCalendarService.deduplicateRecurringEvents(tasks.filter { !dismissedEventIds.contains($0.id) })
        return (
            applyCustomOrder(today.filter { !dismissedEventIds.contains($0.id) }, forMode: .today),
            applyCustomOrder(tomorrow.filter { !dismissedEventIds.contains($0.id) }, forMode: .tomorrow),
            applyCustomOrder(classes.filter { !dismissedEventIds.contains($0.id) }, forMode: .classes),
            applyCustomOrder(deduplicatedTasks, forMode: .tasks)
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
        if let url = URL(string: "https://calendar.google.com/calendar/r") {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = URL(string: "https://calendar.google.com") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func openSystemSettingsAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/InternetAccounts.prefPane"))
        }
    }
}
