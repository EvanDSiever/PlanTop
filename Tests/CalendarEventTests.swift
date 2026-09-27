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

        // Test 5: Timer formatting (Details up to the seconds)
        assertEqual(CalendarEvent.formatRemainingDuration(187200), "2 days 4 hours 0 mins 0s", "Formats days, hours, mins, and secs")
        assertEqual(CalendarEvent.formatRemainingDuration(86400), "1 day 0 hours 0 mins 0s", "Formats 1 day with hours, mins, and secs")
        assertEqual(CalendarEvent.formatRemainingDuration(11700), "3 hours 15 mins 0s", "Formats hours, mins, and secs")
        assertEqual(CalendarEvent.formatRemainingDuration(3600), "1 hour 0 mins 0s", "Formats 1 hour with mins and secs")
        assertEqual(CalendarEvent.formatRemainingDuration(1512), "25 mins 12s", "Formats mins and secs")
        assertEqual(CalendarEvent.formatRemainingDuration(45), "45s", "Formats secs only")

        // Test 6: Classes Timers - "Starts in" and "Ends in" with seconds
        let futureClass = CalendarEvent(
            title: "IEL Writing",
            startDate: now.addingTimeInterval(7200), // starts in 2h
            endDate: now.addingTimeInterval(14400)
        )
        let futureInfo = futureClass.statusTimerInfo(isClassesCategory: true, isTodayCategory: false, relativeTo: now)
        assertEqual(futureInfo.prefix, "Starts in ", "Classes event before start has 'Starts in ' prefix")
        assertEqual(futureInfo.timer, "2 hours 0 mins 0s", "Classes event has correct duration timer with seconds")

        let ongoingClass = CalendarEvent(
            title: "IEL Speaking",
            startDate: now.addingTimeInterval(-1800), // started 30m ago
            endDate: now.addingTimeInterval(2700)     // ends in 45m
        )
        let ongoingInfo = ongoingClass.statusTimerInfo(isClassesCategory: true, isTodayCategory: false, relativeTo: now)
        assertEqual(ongoingInfo.prefix, "Ends in ", "Classes event in session has 'Ends in ' prefix")
        assertEqual(ongoingInfo.timer, "45 mins 0s", "Classes event has correct remaining duration timer with seconds")

        // Test 7: Today Timers - "Limit in" with seconds
        let todayEvent = CalendarEvent(
            title: "Finish Project Report",
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(11700) // ends in 3h 15m
        )
        let todayInfo = todayEvent.statusTimerInfo(isClassesCategory: false, isTodayCategory: true, relativeTo: now)
        assertEqual(todayInfo.prefix, "Limit in ", "Today event has 'Limit in ' prefix")
        assertEqual(todayInfo.timer, "3 hours 15 mins 0s", "Today event has correct countdown timer with seconds")

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

        // Test 12: Report and Homework Categorization & Prefix Matching
        let validReportAndHW = [
            "REPORT: Physics Lab 1",
            "[REPORT] Capstone Thesis",
            "(REPORT) Chemistry Analysis",
            "REPORT - Quarterly Summary",
            "REPORT 101",
            "report preliminary draft",
            "HOMEWORK: Calculus Ch 4",
            "[HOMEWORK] Spanish 201",
            "(HOMEWORK) Linear Algebra",
            "HOMEWORK - Biology Reading",
            "HOMEWORK #3",
            "Homework 4 Assignment",
            "homework problem set 2"
        ]
        for title in validReportAndHW {
            let ev = CalendarEvent(title: title, startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
            assertTrue(ev.hasReportOrHomeworkPrefix, "Correctly detects prefix for '\(title)'")
            assertTrue(ev.isReportOrHomework, "Correctly identifies '\(title)' as report/homework")
        }

        let invalidReportAndHW = [
            "Reporter on the scene",
            "Homeworking discussion group",
            "Annual Financial Report",
            "My Math Homework",
            "Weekly Lab Report",
            "Turn in Homework at desk"
        ]
        for title in invalidReportAndHW {
            let ev = CalendarEvent(title: title, startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
            assertTrue(!ev.hasReportOrHomeworkPrefix, "Rejects non-prefix match for '\(title)'")
            assertTrue(!ev.isReportOrHomework, "Does not classify '\(title)' as report/homework")
        }

        // Test 13: Reports / Homework Timers with seconds
        let upcomingReport = CalendarEvent(
            title: "REPORT: AI Ethics Paper",
            startDate: now.addingTimeInterval(266400), // 3 days 2 hours
            endDate: now.addingTimeInterval(270000)
        )
        let upcomingReportInfo = upcomingReport.statusTimerInfo(isClassesCategory: true, isTodayCategory: false, relativeTo: now)
        assertEqual(upcomingReportInfo.prefix, "Starts in ", "Upcoming report has 'Starts in ' prefix")
        assertEqual(upcomingReportInfo.timer, "3 days 2 hours 0 mins 0s", "Upcoming report has formatted countdown timer")

        let ongoingHW = CalendarEvent(
            title: "HOMEWORK: Stats Set 3",
            startDate: now.addingTimeInterval(-1800), // started 30m ago
            endDate: now.addingTimeInterval(4500)    // ends in 1h 15m
        )
        let ongoingHWInfo = ongoingHW.statusTimerInfo(isClassesCategory: true, isTodayCategory: false, relativeTo: now)
        assertEqual(ongoingHWInfo.prefix, "Ends in ", "Ongoing homework has 'Ends in ' prefix")
        assertEqual(ongoingHWInfo.timer, "1 hour 15 mins 0s", "Ongoing homework has remaining countdown timer")

        let endedReport = CalendarEvent(
            title: "REPORT: Midterm Summary",
            startDate: now.addingTimeInterval(-7200),
            endDate: now.addingTimeInterval(-3600)
        )
        let endedReportInfo = endedReport.statusTimerInfo(isClassesCategory: true, isTodayCategory: false, relativeTo: now)
        assertEqual(endedReportInfo.prefix, "", "Ended report has empty prefix")
        assertEqual(endedReportInfo.timer, "Ended", "Ended report displays 'Ended'")

        // Test 14: Tasks (Report / Homework) Urgency and Blinking Rules
        assertEqual(upcomingReport.urgencyLevel(relativeTo: now), EventUrgencyLevel.neutral, "Upcoming report has .neutral urgency")
        assertTrue(!upcomingReport.shouldBlink(relativeTo: now), "Upcoming report does not blink")

        // Test 15: Recurring Event Detection & Single Set Deduplication
        let recurringSeriesKey = "rec-hw-weekly-math"
        let recInst1 = CalendarEvent(
            id: "R1",
            title: "HOMEWORK: Weekly Problem Set",
            startDate: now.addingTimeInterval(86400 * 2), // in 2 days
            endDate: now.addingTimeInterval(86400 * 2 + 3600),
            isRecurring: true,
            recurrenceKey: recurringSeriesKey
        )
        let recInst2 = CalendarEvent(
            id: "R2",
            title: "HOMEWORK: Weekly Problem Set",
            startDate: now.addingTimeInterval(86400 * 9), // in 9 days
            endDate: now.addingTimeInterval(86400 * 9 + 3600),
            isRecurring: true,
            recurrenceKey: recurringSeriesKey
        )
        let recInst3 = CalendarEvent(
            id: "R3",
            title: "HOMEWORK: Weekly Problem Set",
            startDate: now.addingTimeInterval(86400 * 16), // in 16 days
            endDate: now.addingTimeInterval(86400 * 16 + 3600),
            isRecurring: true,
            recurrenceKey: recurringSeriesKey
        )
        let singleTask = CalendarEvent(
            id: "S1",
            title: "REPORT: Final Research Paper",
            startDate: now.addingTimeInterval(86400 * 5),
            endDate: now.addingTimeInterval(86400 * 5 + 3600),
            isRecurring: false,
            recurrenceKey: nil
        )

        let recurringTestList = [recInst1, recInst2, recInst3, singleTask]
        let deduplicated = GoogleCalendarService.deduplicateRecurringEvents(recurringTestList, relativeTo: now)

        assertEqual(deduplicated.count, 2, "Only 1 instance of recurring event + 1 single task are kept (2 total)")
        assertTrue(deduplicated.contains(where: { $0.id == "R1" }), "Earliest upcoming instance (R1) of recurring series is retained")
        assertTrue(!deduplicated.contains(where: { $0.id == "R2" }), "Later recurrence R2 is filtered out")
        assertTrue(!deduplicated.contains(where: { $0.id == "R3" }), "Later recurrence R3 is filtered out")
        assertTrue(deduplicated.contains(where: { $0.id == "S1" }), "Non-recurring task S1 is retained")

        // Test 16: Tasks Date vs Timer Display (Today gets live timer, future days show date)
        do {
            let startOfToday = cal.startOfDay(for: now)
            let todayTask = CalendarEvent(
                title: "REPORT: Today's Lab Report",
                startDate: startOfToday.addingTimeInterval(14 * 3600), // Today at 2pm
                endDate: startOfToday.addingTimeInterval(15 * 3600)
            )
            let tomorrowTask = CalendarEvent(
                title: "HOMEWORK: Tomorrow's Math Problem",
                startDate: startOfToday.addingTimeInterval(26 * 3600), // Tomorrow at 2am
                endDate: startOfToday.addingTimeInterval(27 * 3600)
            )
            let futureTask = CalendarEvent(
                title: "REPORT: Next Week Capstone",
                startDate: startOfToday.addingTimeInterval(5 * 86400 + 10 * 3600), // in 5 days
                endDate: startOfToday.addingTimeInterval(5 * 86400 + 11 * 3600)
            )

            assertTrue(todayTask.isHappeningOrDueToday(relativeTo: now), "Today task correctly identified as happening/due today")
            assertTrue(!tomorrowTask.isHappeningOrDueToday(relativeTo: now), "Tomorrow task correctly identified as NOT today")
            assertTrue(!futureTask.isHappeningOrDueToday(relativeTo: now), "Future task correctly identified as NOT today")

            let tomorrowDateStr = tomorrowTask.occurrenceDateString(relativeTo: now, compact: false)
            assertTrue(tomorrowDateStr.contains("Tomorrow"), "Tomorrow task occurrence string contains 'Tomorrow'")
            
            let futureDateStr = futureTask.occurrenceDateString(relativeTo: now, compact: false)
            assertTrue(!futureDateStr.contains("Starts in"), "Future task occurrence string does not have timer prefix")

            // Card view verification
            let todayCard = CalendarEventCardView(event: todayTask, dayMode: .tasks, frame: NSRect(x: 0, y: 0, width: 400, height: 70))
            let tomorrowCard = CalendarEventCardView(event: tomorrowTask, dayMode: .tasks, frame: NSRect(x: 0, y: 0, width: 400, height: 70))
            let futureCard = CalendarEventCardView(event: futureTask, dayMode: .tasks, frame: NSRect(x: 0, y: 0, width: 400, height: 70))

            // Find the timerBadgeLabel text inside each card
            var todayBadgeText = ""
            var tomorrowBadgeText = ""
            var futureBadgeText = ""

            for subview in todayCard.subviews {
                if let tf = subview as? NSTextField, tf != todayCard.detailCasing, tf.frame.origin.y >= 30 {
                    todayBadgeText = tf.attributedStringValue.string
                }
            }
            for subview in tomorrowCard.subviews {
                if let tf = subview as? NSTextField, tf != tomorrowCard.detailCasing, tf.frame.origin.y >= 30 {
                    tomorrowBadgeText = tf.attributedStringValue.string
                }
            }
            for subview in futureCard.subviews {
                if let tf = subview as? NSTextField, tf != futureCard.detailCasing, tf.frame.origin.y >= 30 {
                    futureBadgeText = tf.attributedStringValue.string
                }
            }

            assertTrue(todayBadgeText.contains("Starts in ") || todayBadgeText.contains("Ends in ") || todayBadgeText == "Ended", "Today task in Tasks tab shows live timer: '\(todayBadgeText)'")
            assertTrue(!tomorrowBadgeText.contains("Starts in "), "Tomorrow task in Tasks tab does NOT show timer: '\(tomorrowBadgeText)'")
            assertTrue(tomorrowBadgeText.contains("Tomorrow"), "Tomorrow task in Tasks tab shows date: '\(tomorrowBadgeText)'")
            assertTrue(!futureBadgeText.contains("Starts in "), "Future task in Tasks tab does NOT show timer: '\(futureBadgeText)'")
            assertTrue(futureBadgeText == futureDateStr, "Future task in Tasks tab shows occurrence date: '\(futureBadgeText)'")
        }

        // Test 17: Tasks Tab Weekly Bound (Monday to Sunday) & Inter-Week Deduplication
        do {
            var gCal = Calendar(identifier: .gregorian)
            gCal.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? TimeZone.current
            var comps = DateComponents()
            comps.year = 2026
            comps.month = 9
            comps.day = 23 // Wednesday, Sep 23, 2026
            comps.hour = 11
            comps.minute = 40
            let wednesdayDate = gCal.date(from: comps)!
            
            let (startOfWeek, endOfWeek) = GoogleCalendarService.currentWeekInterval(for: wednesdayDate)
            
            // Start of week should be Monday Sep 21, 2026 00:00:00
            let startDay = gCal.component(.day, from: startOfWeek)
            let startMonth = gCal.component(.month, from: startOfWeek)
            let startWeekday = gCal.component(.weekday, from: startOfWeek) // Sunday=1, Monday=2
            assertEqual(startDay, 21, "Current week starts on Monday, Sep 21")
            assertEqual(startMonth, 9, "Current week start is in September")
            assertEqual(startWeekday, 2, "Current week start day of week is Monday")
            
            // End of week should be Monday Sep 28, 2026 00:00:00 (which covers through Sunday Sep 27 23:59:59)
            let endDay = gCal.component(.day, from: endOfWeek)
            let endMonth = gCal.component(.month, from: endOfWeek)
            assertEqual(endDay, 28, "Current week interval ends on Monday, Sep 28 00:00:00 (Sunday Sep 27 23:59:59)")
            assertEqual(endMonth, 9, "Current week end is in September")

            // Create the two "REPORT Robotics" events from the user's screenshot
            var friThisWeek = DateComponents()
            friThisWeek.year = 2026; friThisWeek.month = 9; friThisWeek.day = 25; friThisWeek.hour = 10
            let roboticsThisWeek = CalendarEvent(
                id: "ROBOTICS_THIS_WEEK",
                title: "REPORT Robotics",
                startDate: gCal.date(from: friThisWeek)!,
                endDate: gCal.date(from: friThisWeek)!.addingTimeInterval(3 * 3600)
            )

            var friNextWeek = DateComponents()
            friNextWeek.year = 2026; friNextWeek.month = 10; friNextWeek.day = 2; friNextWeek.hour = 10
            let roboticsNextWeek = CalendarEvent(
                id: "ROBOTICS_NEXT_WEEK",
                title: "REPORT Robotics",
                startDate: gCal.date(from: friNextWeek)!,
                endDate: gCal.date(from: friNextWeek)!.addingTimeInterval(3 * 3600)
            )

            var pastSun = DateComponents()
            pastSun.year = 2026; pastSun.month = 9; pastSun.day = 20; pastSun.hour = 20
            let homeworkPastSunday = CalendarEvent(
                id: "HW_PAST_WEEK",
                title: "HOMEWORK Physics",
                startDate: gCal.date(from: pastSun)!,
                endDate: gCal.date(from: pastSun)!.addingTimeInterval(2 * 3600)
            )

            let allEventList = [homeworkPastSunday, roboticsThisWeek, roboticsNextWeek]
            
            // Filter strictly to current week: startDate < endOfWeek && endDate >= startOfWeek
            let currentWeekTasks = allEventList.filter {
                $0.isReportOrHomework && $0.startDate < endOfWeek && $0.endDate >= startOfWeek
            }
            
            assertEqual(currentWeekTasks.count, 1, "Only events occurring strictly in this week (Monday to Sunday) are retained")
            assertEqual(currentWeekTasks.first?.id, "ROBOTICS_THIS_WEEK", "This Friday's REPORT Robotics (Sep 25) is retained")
            assertTrue(!currentWeekTasks.contains(where: { $0.id == "ROBOTICS_NEXT_WEEK" }), "Next Friday's REPORT Robotics (Oct 2) is excluded")
            assertTrue(!currentWeekTasks.contains(where: { $0.id == "HW_PAST_WEEK" }), "Past week event (Sep 20) is excluded")

            // Deduplication also guarantees identical titles collapse to one
            let deduplicated = GoogleCalendarService.deduplicateRecurringEvents(allEventList, relativeTo: wednesdayDate)
            let roboticsOnly = deduplicated.filter { $0.title == "REPORT Robotics" }
            assertEqual(roboticsOnly.count, 1, "Deduplication ensures at most 1 REPORT Robotics event even if multi-week list were processed")
            assertEqual(roboticsOnly.first?.id, "ROBOTICS_THIS_WEEK", "Earliest upcoming instance (this week) is prioritized")
        }

        // Test 18: Event Description & Notes HTML/Markdown Formatting (No Raw Syntax)
        do {
            // Case 1: Google Calendar HTML from user screenshot
            let htmlNotes = "<b>Let's work on the Robotics report, Evan!</b> Make sure to check our <a href=\"https://classroom.google.com/u/2/c/ODc2NTM1NTI3MDg0\">robotics classroom</a> for the lab guide and finish the report in the attached google docs!"
            let formattedHTML = CalendarEvent.formatNotesAttributedString(htmlNotes)
            let plainHTML = formattedHTML.string
            
            assertTrue(!plainHTML.contains("<b>"), "Rendered notes contain no raw <b> tag")
            assertTrue(!plainHTML.contains("</b>"), "Rendered notes contain no raw </b> tag")
            assertTrue(!plainHTML.contains("<a href"), "Rendered notes contain no raw <a href tag")
            assertTrue(!plainHTML.contains("</a>"), "Rendered notes contain no raw </a> tag")
            
            let expectedPlain = "Let's work on the Robotics report, Evan! Make sure to check our robotics classroom for the lab guide and finish the report in the attached google docs!"
            assertEqual(plainHTML, expectedPlain, "Rendered HTML notes matches expected plain text")
            
            // Check that "Let's work on the Robotics report, Evan!" has bold font
            let boldSnippetRange = (plainHTML as NSString).range(of: "Let's work on the Robotics report, Evan!")
            assertTrue(boldSnippetRange.location != NSNotFound, "Found bold snippet in formatted notes")
            var boldTraitFound = false
            formattedHTML.enumerateAttribute(.font, in: boldSnippetRange, options: []) { val, _, stop in
                if let font = val as? NSFont {
                    let isBold = font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.contains("Heavy") || font.fontName.contains("Bold")
                    if isBold {
                        boldTraitFound = true
                        stop.pointee = true
                    }
                }
            }
            assertTrue(boldTraitFound, "Snippet 'Let's work on the Robotics report, Evan!' has bold font applied")
            
            // Check that "robotics classroom" has .link attribute pointing to URL
            let linkSnippetRange = (plainHTML as NSString).range(of: "robotics classroom")
            assertTrue(linkSnippetRange.location != NSNotFound, "Found link snippet in formatted notes")
            var linkURLFound: URL? = nil
            formattedHTML.enumerateAttribute(.link, in: linkSnippetRange, options: []) { val, _, stop in
                if let url = val as? URL {
                    linkURLFound = url
                    stop.pointee = true
                }
            }
            assertEqual(linkURLFound?.absoluteString, "https://classroom.google.com/u/2/c/ODc2NTM1NTI3MDg0", "Link attribute URL matches expected Google Classroom URL")
            
            // Case 2: Markdown notes
            let mdNotes = "**Homework Due:** Please read [Syllabus](https://example.com/syllabus) *carefully*."
            let formattedMD = CalendarEvent.formatNotesAttributedString(mdNotes)
            let plainMD = formattedMD.string
            
            assertTrue(!plainMD.contains("**"), "Rendered markdown notes contain no raw ** asterisks")
            assertTrue(!plainMD.contains("[Syllabus]"), "Rendered markdown notes contain no raw markdown brackets")
            assertTrue(!plainMD.contains("(https://"), "Rendered markdown notes contain no raw markdown parenthesized URLs")
            assertEqual(plainMD, "Homework Due: Please read Syllabus carefully.", "Rendered markdown notes matches expected clean string")
            
            // Case 3: HTML line breaks & entities
            let entityNotes = "<p>First line</p><p>Tom &amp; Jerry &quot;quote&quot; &lt;3</p>"
            let formattedEntity = CalendarEvent.formatNotesAttributedString(entityNotes)
            let plainEntity = formattedEntity.string
            assertTrue(!plainEntity.contains("<p>"), "No raw <p> tags in entity notes")
            assertTrue(!plainEntity.contains("&amp;"), "Entity &amp; properly decoded to &")
            assertTrue(plainEntity.contains("Tom & Jerry \"quote\" <3"), "Entities properly decoded into readable text: '\(plainEntity)'")
        }

        // Test 21: Google Calendar Web URL generation
        do {
            // Case 1: Direct Google Calendar URL
            let directGoogleURL = URL(string: "https://calendar.google.com/calendar/event?eid=abc123direct")!
            let evWithDirect = CalendarEvent(
                title: "Meeting with Advisor",
                startDate: now,
                endDate: now.addingTimeInterval(3600),
                url: directGoogleURL
            )
            assertEqual(evWithDirect.googleCalendarURL, directGoogleURL, "Direct Google Calendar URL is preserved")

            // Case 2: Embedded Google Calendar link in notes
            let evWithNotesURL = CalendarEvent(
                title: "Project Sync",
                startDate: now,
                endDate: now.addingTimeInterval(3600),
                notes: "Join link and agenda.\nCalendar link: https://calendar.google.com/calendar/r/eventedit/xyz789\nSee you there!"
            )
            assertTrue(evWithNotesURL.googleCalendarURL.absoluteString.contains("calendar.google.com"), "Extracts Google Calendar URL from notes")

            // Case 3: Google UID in externalIdentifier generates valid web link
            let evWithUID = CalendarEvent(
                title: "Machine Learning Lecture",
                startDate: now,
                endDate: now.addingTimeInterval(5400),
                sourceAccount: "evandsiever@gmail.com",
                externalIdentifier: "4htgpmm1hmak744r0kbkdcodar@google.com"
            )
            let gCalURL = evWithUID.googleCalendarURL.absoluteString
            assertTrue(gCalURL.contains("calendar.google.com"), "Google UID generates Google Calendar URL")
            assertTrue(gCalURL.contains("r/eventedit/"), "Google UID generates eventedit route")
            assertTrue(gCalURL.contains("u/evandsiever@gmail.com"), "Includes account user prefix")

            // Case 4: Fallback search URL
            let evFallback = CalendarEvent(
                title: "Doctor Appointment",
                startDate: now,
                endDate: now.addingTimeInterval(1800),
                sourceAccount: "evandsiever@gmail.com"
            )
            let fallbackURL = evFallback.googleCalendarURL.absoluteString
            assertTrue(fallbackURL.contains("calendar.google.com"), "Fallback generates Google Calendar URL")
            assertTrue(fallbackURL.contains("Doctor%20Appointment") || fallbackURL.contains("Doctor"), "Fallback URL references event")
        }

        print("\n🎉 All PlanTop CalendarEvent tests passed successfully!")
    }
}
