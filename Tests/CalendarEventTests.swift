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

        // Test 3: Class detector matching
        let classEvent1 = CalendarEvent(
            id: "3",
            title: "Class IEL - Advanced English",
            startDate: now.addingTimeInterval(7200),
            endDate: now.addingTimeInterval(10800),
            isAllDay: false
        )
        assertTrue(classEvent1.isClassOrAlfatih, "Matches default keyword 'Class IEL'")

        let classEvent2 = CalendarEvent(
            id: "4",
            title: "Alfatih Halaqah Session",
            startDate: now.addingTimeInterval(7200),
            endDate: now.addingTimeInterval(10800),
            isAllDay: false
        )
        assertTrue(classEvent2.isClassOrAlfatih, "Matches default keyword 'Alfatih'")

        let regularEvent = CalendarEvent(
            id: "5",
            title: "Grocery Shopping",
            startDate: now.addingTimeInterval(7200),
            endDate: now.addingTimeInterval(10800),
            isAllDay: false
        )
        assertTrue(!regularEvent.isClassOrAlfatih, "Regular event does not match class keywords")

        print("\n🎉 All PlanTop CalendarEvent tests passed successfully!")
    }
}
