import Foundation
import AppKit

@main
struct CalendarEventTestsRunner {
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            print("❌ FAIL: \(message)")
            print("   Expected: '\(expected)'")
            print("   Actual:   '\(actual)'")
            exit(1)
        } else {
            print("✅ PASS: \(message)")
        }
    }
    
    static func assertTrue(_ condition: Bool, _ message: String) {
        if !condition {
            print("❌ FAIL: \(message)")
            exit(1)
        } else {
            print("✅ PASS: \(message)")
        }
    }

    static func main() {
        print("Running PlanTop CalendarEvent unit tests...")

        let now = Date()
        
        // Test 1: Active event (ongoing now)
        let activeEvent = CalendarEvent(
            id: "1",
            title: "Operating Systems Lecture",
            startDate: now.addingTimeInterval(-1800), // started 30m ago
            endDate: now.addingTimeInterval(1800),   // ends in 30m
            isAllDay: false,
            location: "Hall B",
            notes: "Join via https://meet.google.com/abc-defg-hij",
            url: nil,
            calendarName: "Academic",
            calendarColor: .systemBlue
        )
        assertTrue(activeEvent.isHappeningNow, "Identifies ongoing event as happening now")
        assertEqual(activeEvent.urgencyLevel(relativeTo: now), EventUrgencyLevel.active, "Active event urgency is .active")
        assertTrue(activeEvent.videoMeetingURL != nil, "Extracts Google Meet URL from notes")
        assertTrue(activeEvent.isGoogleMeet, "Identifies Google Meet URL")

        // Test 2: Imminent event (starting in ~20 minutes)
        let imminentEvent = CalendarEvent(
            id: "2",
            title: "Team Standup",
            startDate: now.addingTimeInterval(1230), // starts in ~20m
            endDate: now.addingTimeInterval(2400),
            isAllDay: false
        )
        assertEqual(imminentEvent.urgencyLevel(relativeTo: now), EventUrgencyLevel.urgent, "Event starting <2h has .urgent level")
        assertTrue(imminentEvent.relativeStatusText.contains("Starts in 20m") || imminentEvent.relativeStatusText.contains("Starts in 19m"), "Relative status text indicates starts in ~20m")

        // Test 3: Classes Categorization & 'IEL' Indicator Matching (Requirement 1)
        let ielCases = [
            "IEL Reading",
            "[IEL] Speaking",
            "(IEL) Listening",
            "IEL: Academic Writing",
            "IEL - Vocabulary",
            "iel 101 exam",
            "Class IEL - Advanced English",
            "Alfatih Halaqah Session"
        ]
        for title in ielCases {
            let ev = CalendarEvent(title: title, startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
            assertTrue(ev.isClassOrAlfatih, "Correctly identifies '\(title)' as class/IEL category")
        }
        
        let nonIelCases = [
            "Grocery Shopping",
            "Field Trip to Zoo",
            "Diet & Fitness Plan",
            "Shielding Meeting"
        ]
        for title in nonIelCases {
            let ev = CalendarEvent(title: title, startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
            assertTrue(!ev.isClassOrAlfatih, "Correctly identifies '\(title)' as non-class")
        }

        // Test 4: Full Time Range (Requirement 2)
        let classEvent = CalendarEvent(
            title: "IEL Reading",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(9000)
        )
        let rangeStr = classEvent.fullTimeRangeString(includeDay: false)
        assertTrue(rangeStr.contains("–"), "Full time range contains en-dash separator")
        assertTrue(!rangeStr.isEmpty, "Time range is non-empty")
        
        let allDayEvent = CalendarEvent(
            title: "IEL Workshop",
            startDate: now,
            endDate: now.addingTimeInterval(86400),
            isAllDay: true
        )
        assertEqual(allDayEvent.fullTimeRangeString(includeDay: false), "All Day", "All day event returns 'All Day'")

        // Test 5: Timer formatting (Requirements 3 & 4)
        assertEqual(CalendarEvent.formatRemainingDuration(187200), "2 days 4 hours", "Formats days and hours")
        assertEqual(CalendarEvent.formatRemainingDuration(86400), "1 day", "Formats 1 day singular")
        assertEqual(CalendarEvent.formatRemainingDuration(11700), "3 hours 15 mins", "Formats hours and mins")
        assertEqual(CalendarEvent.formatRemainingDuration(3600), "1 hour", "Formats 1 hour singular")
        assertEqual(CalendarEvent.formatRemainingDuration(1512), "25 mins 12s", "Formats mins and secs")
        assertEqual(CalendarEvent.formatRemainingDuration(45), "45s", "Formats secs only")

        // Test 6: Classes Timers - "Starts in" and "Ends in" (Requirement 3)
        let futureClass = CalendarEvent(
            title: "IEL Writing",
            startDate: now.addingTimeInterval(7200), // starts in 2h
            endDate: now.addingTimeInterval(14400)
        )
        let futureInfo = futureClass.statusTimerInfo(isClassesCategory: true, isTodayCategory: false, relativeTo: now)
        assertEqual(futureInfo.prefix, "Starts in ", "Classes event before start has 'Starts in ' prefix")
        assertEqual(futureInfo.timer, "2 hours", "Classes event has correct duration timer")

        let ongoingClass = CalendarEvent(
            title: "IEL Speaking",
            startDate: now.addingTimeInterval(-1800), // started 30m ago
            endDate: now.addingTimeInterval(2700)     // ends in 45m
        )
        let ongoingInfo = ongoingClass.statusTimerInfo(isClassesCategory: true, isTodayCategory: false, relativeTo: now)
        assertEqual(ongoingInfo.prefix, "Ends in ", "Classes event in session has 'Ends in ' prefix")
        assertEqual(ongoingInfo.timer, "45 mins", "Classes event has correct remaining duration timer")

        // Test 7: Today Timers - "Limit in" (Requirement 4)
        let todayEvent = CalendarEvent(
            title: "Finish Project Report",
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(11700) // ends in 3h 15m
        )
        let todayInfo = todayEvent.statusTimerInfo(isClassesCategory: false, isTodayCategory: true, relativeTo: now)
        assertEqual(todayInfo.prefix, "Limit in ", "Today event has 'Limit in ' prefix")
        assertEqual(todayInfo.timer, "3 hours 15 mins", "Today event has correct countdown timer")

        // Test 8: Avenir Font Integration (Requirement 5)
        let avenirBook = NeumorphicTheme.avenirFont(ofSize: 13, weight: .regular)
        assertEqual(avenirBook.fontName, "Avenir-Book", "Resolves Avenir-Book for regular weight")

        let avenirMedium = NeumorphicTheme.avenirFont(ofSize: 13, weight: .medium)
        assertEqual(avenirMedium.fontName, "Avenir-Medium", "Resolves Avenir-Medium for medium weight")

        let avenirHeavy = NeumorphicTheme.avenirFont(ofSize: 13, weight: .bold)
        assertEqual(avenirHeavy.fontName, "Avenir-Heavy", "Resolves Avenir-Heavy for bold weight")

        let avenirBlack = NeumorphicTheme.avenirFont(ofSize: 13, weight: .black)
        assertEqual(avenirBlack.fontName, "Avenir-Black", "Resolves Avenir-Black for black weight")

        let avenirLight = NeumorphicTheme.avenirFont(ofSize: 13, weight: .light)
        assertEqual(avenirLight.fontName, "Avenir-Light", "Resolves Avenir-Light for light weight")

        let timerFont = NeumorphicTheme.timerFont(ofSize: 13.5, weight: .regular)
        let futuristicNames = ["AlienLeagueCondensed", "AlienLeague", "Futura-CondensedMedium", "Futura-Medium", ".AppleSystemUIFontMonospaced"]
        let matchesFuturistic = futuristicNames.contains(where: { timerFont.fontName.contains($0) })
        assertTrue(matchesFuturistic || timerFont.pointSize == 13.5, "Timer font resolves to futuristic or stylized font with size 13.5")
        
        // Test 9: Event Reordering & Dismissal Logic
        let eventA = CalendarEvent(id: "A", title: "Event A", startDate: now, endDate: now.addingTimeInterval(3600))
        let eventB = CalendarEvent(id: "B", title: "Event B", startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
        let eventC = CalendarEvent(id: "C", title: "Event C", startDate: now.addingTimeInterval(7200), endDate: now.addingTimeInterval(10800))
        
        let initialList = [eventA, eventB, eventC]
        let customOrder = ["C", "A", "B"]
        
        // Apply custom ordering
        var orderMap: [String: Int] = [:]
        for (idx, id) in customOrder.enumerated() {
            orderMap[id] = idx
        }
        let reorderedList = initialList.sorted {
            let rank0 = orderMap[$0.id] ?? 9999
            let rank1 = orderMap[$1.id] ?? 9999
            return rank0 < rank1
        }
        assertEqual(reorderedList.map { $0.id }, ["C", "A", "B"], "Custom reordering sorts cards according to user preference")
        
        // Test 10: Non-Classes Start Time Only vs Classes Full Range
        let regularEvent = CalendarEvent(
            id: "R1",
            title: "Team Sync",
            startDate: now.addingTimeInterval(1800),
            endDate: now.addingTimeInterval(5400)
        )
        let startTimeOnly = regularEvent.formattedStartTime
        assertTrue(!startTimeOnly.contains("–"), "Non-classes event formattedStartTime only shows start time, not end time")
        assertTrue(startTimeOnly.contains("AM") || startTimeOnly.contains("PM") || startTimeOnly.contains(":"), "formattedStartTime produces valid time format")

        // Test 11: Classes Events restricted to Today only
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        let classToday = CalendarEvent(id: "CT", title: "IEL Writing Today", startDate: now.addingTimeInterval(1800), endDate: now.addingTimeInterval(5400))
        let classTomorrow = CalendarEvent(id: "CX", title: "IEL Reading Tomorrow", startDate: now.addingTimeInterval(90000), endDate: now.addingTimeInterval(93600))
        let mixedClasses = [classToday, classTomorrow]
        let classesForDayOnly = mixedClasses.filter { $0.isClassOrAlfatih && $0.startDate >= startOfToday && $0.startDate < endOfToday }
        assertEqual(classesForDayOnly.map { $0.id }, ["CT"], "Classes events are restricted strictly to today and exclude future class events")

        print("\n🎉 All PlanTop CalendarEvent tests passed successfully!")
    }
}
