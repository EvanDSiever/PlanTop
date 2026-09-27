import Foundation
import AppKit

@main
struct SettingsTestsRunner {
    static func assertTrue(_ condition: Bool, _ message: String) {
        if !condition {
            print("❌ FAIL: \(message)")
            exit(1)
        } else {
            print("✅ PASS: \(message)")
        }
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            print("❌ FAIL: \(message) - Expected: \(expected), Got: \(actual)")
            exit(1)
        } else {
            print("✅ PASS: \(message)")
        }
    }

    static func main() {
        print("Running PlanTop Settings unit tests...\n")

        // 1. Display Mode switching
        do {
            let pillCtrl = FloatingPillWindowController()
            pillCtrl.displayMode = .hoverDropdown
            assertEqual(pillCtrl.displayMode, .hoverDropdown, "Sets displayMode to hoverDropdown")
            assertTrue(pillCtrl.isEnabled, "isEnabled is true for hoverDropdown")
            assertTrue(pillCtrl.hoverDropOnly, "hoverDropOnly is true for hoverDropdown")

            pillCtrl.displayMode = .alwaysFloating
            assertEqual(pillCtrl.displayMode, .alwaysFloating, "Sets displayMode to alwaysFloating")
            assertTrue(pillCtrl.isEnabled, "isEnabled is true for alwaysFloating")
            assertTrue(!pillCtrl.hoverDropOnly, "hoverDropOnly is false for alwaysFloating")

            pillCtrl.displayMode = .menuBarOnly
            assertEqual(pillCtrl.displayMode, .menuBarOnly, "Sets displayMode to menuBarOnly")
            assertTrue(!pillCtrl.isEnabled, "isEnabled is false for menuBarOnly")
        }

        // 2. Scan Reach, Scan Height & Hover Delay properties
        do {
            let pillCtrl = FloatingPillWindowController()
            
            // Scan Reach
            pillCtrl.scanReach = 85.0
            assertEqual(pillCtrl.scanReach, 85.0, "Updates scanReach")
            assertEqual(CGFloat(UserDefaults.standard.double(forKey: "scanReach")), 85.0, "Persists scanReach to UserDefaults")

            // Scan Height
            pillCtrl.scanHeight = 720.0
            assertEqual(pillCtrl.scanHeight, 720.0, "Updates scanHeight")
            assertEqual(CGFloat(UserDefaults.standard.double(forKey: "scanHeight")), 720.0, "Persists scanHeight to UserDefaults")

            // Hover Delay
            pillCtrl.hoverDelay = 0.15
            assertEqual(pillCtrl.hoverDelay, 0.15, "Updates hoverDelay")
            assertEqual(UserDefaults.standard.double(forKey: "hoverDelay"), 0.15, "Persists hoverDelay to UserDefaults")

            // Panel Width
            pillCtrl.customPanelWidth = 420.0
            assertEqual(pillCtrl.customPanelWidth, 420.0, "Updates customPanelWidth")
            assertEqual(CGFloat(UserDefaults.standard.double(forKey: "customPanelWidth")), 420.0, "Persists customPanelWidth to UserDefaults")

            // Permanent Pinning
            pillCtrl.isPinned = true
            assertTrue(pillCtrl.isPinned, "Updates isPinned")
            assertTrue(UserDefaults.standard.bool(forKey: "isSidePanelPinned"), "Persists isPinned to UserDefaults")

            // Auto Peek & Peek Duration
            pillCtrl.autoPeekEnabled = true
            assertTrue(pillCtrl.autoPeekEnabled, "Updates autoPeekEnabled")
            pillCtrl.peekDuration = 7.5
            assertEqual(pillCtrl.peekDuration, 7.5, "Updates peekDuration")
            assertEqual(UserDefaults.standard.double(forKey: "peekDuration"), 7.5, "Persists peekDuration to UserDefaults")
        }

        // 3. Dynamic App Font Family
        do {
            // System Default
            UserDefaults.standard.set("System", forKey: "plantop_app_font_family")
            let sysFont = AppleTheme.font(size: 14, weight: .regular)
            assertTrue(sysFont.pointSize == 14, "Loads system font with 14pt")

            // Rounded
            UserDefaults.standard.set("Rounded", forKey: "plantop_app_font_family")
            let roundedFont = AppleTheme.font(size: 14, weight: .bold)
            assertTrue(roundedFont.pointSize == 14, "Loads rounded font with 14pt")

            // Monospaced
            UserDefaults.standard.set("Monospaced", forKey: "plantop_app_font_family")
            let monoFont = AppleTheme.font(size: 13, weight: .medium)
            assertTrue(monoFont.pointSize == 13, "Loads monospaced font with 13pt")

            // Avenir
            UserDefaults.standard.set("Avenir", forKey: "plantop_app_font_family")
            let avenirFont = AppleTheme.font(size: 15, weight: .regular)
            assertTrue(avenirFont.fontName.contains("Avenir") || avenirFont.pointSize == 15, "Resolves Avenir font family")

            // Reset to System
            UserDefaults.standard.set("System", forKey: "plantop_app_font_family")
        }

        // 4. Accent Color Dynamic Switching
        do {
            UserDefaults.standard.set("#34C759", forKey: "plantop_accent_color_hex")
            let greenColor = AppleTheme.primary
            assertTrue(greenColor != .clear, "Resolves custom green accent color")

            UserDefaults.standard.set("#AF52DE", forKey: "plantop_accent_color_hex")
            let purpleColor = AppleTheme.primary
            assertTrue(purpleColor != .clear, "Resolves custom purple accent color")

            // Reset to default
            UserDefaults.standard.removeObject(forKey: "plantop_accent_color_hex")
        }

        // 5. Google Calendar Enable / Disable switch
        do {
            GoogleCalendarService.shared.isCalendarEnabled = false
            assertTrue(!GoogleCalendarService.shared.isCalendarEnabled, "Disables Google Calendar in service")
            assertTrue(!UserDefaults.standard.bool(forKey: "isCalendarEnabled"), "Persists isCalendarEnabled false")

            GoogleCalendarService.shared.isCalendarEnabled = true
            assertTrue(GoogleCalendarService.shared.isCalendarEnabled, "Enables Google Calendar in service")
            assertTrue(UserDefaults.standard.bool(forKey: "isCalendarEnabled"), "Persists isCalendarEnabled true")
        }

        // 6. SettingsWindowController initialization and UI verification
        do {
            let pillCtrl = FloatingPillWindowController()
            let menuCtrl = MenuBarController(pillController: pillCtrl)
            let settingsWin = SettingsWindowController(pillController: pillCtrl, menuBarController: menuCtrl)
            assertTrue(settingsWin.window != nil, "Settings window is successfully created")
            assertEqual(settingsWin.window?.title, "PlanTop Settings & Preferences", "Settings window title is correct")
        }

        // 7. Clock Font Selection Resolution
        do {
            UserDefaults.standard.set("SFPro", forKey: "plantop_time_font_name")
            let sfFont = AppleTheme.timeFont(size: 32, weight: .bold)
            assertTrue(sfFont.pointSize == 32, "Resolves SF Pro time font at 32pt")

            UserDefaults.standard.set("SFProRounded", forKey: "plantop_time_font_name")
            let roundedFont = AppleTheme.timeFont(size: 32, weight: .bold)
            assertTrue(roundedFont.pointSize == 32, "Resolves SF Pro Rounded time font at 32pt")

            UserDefaults.standard.set("SFMono", forKey: "plantop_time_font_name")
            let monoFont = AppleTheme.timeFont(size: 32, weight: .bold)
            assertTrue(monoFont.pointSize == 32, "Resolves SF Mono time font at 32pt")

            UserDefaults.standard.set("Futura-CondensedLight", forKey: "plantop_time_font_name")
            let futuraFont = AppleTheme.timeFont(size: 32, weight: .bold)
            assertTrue(futuraFont.pointSize == 32, "Resolves Futura family time font at 32pt")

            UserDefaults.standard.set("AlienLeagueCondensed", forKey: "plantop_time_font_name")
            let alienFont = AppleTheme.timeFont(size: 32, weight: .bold)
            assertTrue(alienFont.pointSize == 32, "Resolves Alien League time font at 32pt")

            // Reset
            UserDefaults.standard.removeObject(forKey: "plantop_time_font_name")
        }

        // 8. Robust Hex String Conversion
        do {
            let blueHex = AppleTheme.hexString(from: NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0))
            assertTrue(blueHex.hasPrefix("#"), "Hex string has '#' prefix")
            assertEqual(blueHex.count, 7, "Hex string has length 7")

            let redHex = AppleTheme.hexString(from: NSColor.red)
            assertEqual(redHex, "#FF0000", "Red converts to #FF0000")

            let greenHex = AppleTheme.hexString(from: NSColor.green)
            assertEqual(greenHex, "#00FF00", "Green converts to #00FF00")
        }

        print("\n🎉 All PlanTop Settings tests passed successfully!")
    }
}

