import Foundation

@main
struct TestRunner {
    static func assertEqual(_ actual: String, _ expected: String, _ message: String) {
        if actual != expected {
            print("❌ FAIL: \(message)")
            print("   Expected: '\(expected)'")
            print("   Actual:   '\(actual)'")
            exit(1)
        } else {
            print("✅ PASS: \(message)")
        }
    }

    static func main() {
        print("Running TrackInfo tests...")

        // Test 1: User's actual Chrome tab title: "(1) Thor (Soundtrack Compilation) - YouTube"
        let track1 = TrackInfo(
            rawTitle: "(1) Thor (Soundtrack Compilation) - YouTube",
            url: "https://www.youtube.com/watch?v=yUySGJbf54g",
            browser: "Google Chrome"
        )
        assertEqual(track1.title, "Thor (Soundtrack Compilation)", "Strips notification count and - YouTube suffix")
        assertEqual(track1.browser, "Google Chrome", "Preserves browser name")

        // Test 2: Standard Artist - Song format
        let track2 = TrackInfo(
            rawTitle: "Hans Zimmer - Time (Inception OST) - YouTube",
            url: "https://www.youtube.com/watch?v=RxabV9hCWv8",
            browser: "Safari"
        )
        assertEqual(track2.title, "Time (Inception OST)", "Extracts song title from Artist - Title")
        assertEqual(track2.artist, "Hans Zimmer", "Extracts artist name")

        // Test 3: YouTube Music "Song • Artist" format
        let track3 = TrackInfo(
            rawTitle: "Starboy • The Weeknd, Daft Punk - YouTube Music",
            url: "https://music.youtube.com/watch?v=34Na4j8AVgA",
            browser: "Brave Browser"
        )
        assertEqual(track3.title, "Starboy", "Extracts YT Music song title")
        assertEqual(track3.artist, "The Weeknd, Daft Punk", "Extracts YT Music artist")

        // Test 4: Play glyph prefix
        let track4 = TrackInfo(
            rawTitle: "▶ Interstellar Main Theme - YouTube",
            url: "https://www.youtube.com/watch?v=UDVtMYqUAyw",
            browser: "Arc"
        )
        assertEqual(track4.title, "Interstellar Main Theme", "Strips play glyph")

        print("\n🎉 All TrackInfo tests passed successfully!")
    }
}
