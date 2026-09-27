import Foundation
import AppKit

@main
struct QuickNotesTestsRunner {
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
        print("Running PlanTop QuickNotes unit tests...\n")

        // Test 1: Bold toggle applies font attribute directly (no raw asterisks)
        do {
            let tv = QuickNotesTextView()
            tv.isRichText = true
            tv.string = "PlanTop rocks"
            tv.setSelectedRange(NSRange(location: 8, length: 5)) // select "rocks"
            tv.toggleBold()
            assertEqual(tv.string, "PlanTop rocks", "Does NOT insert raw asterisks into text on bold toggle")
            
            // Check that "rocks" has bold font trait
            var hasBold = false
            tv.textStorage?.enumerateAttribute(.font, in: NSRange(location: 8, length: 5), options: []) { val, _, stop in
                if let font = val as? NSFont {
                    let isBold = font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.contains("Heavy") || font.fontName.contains("Black") || font.fontName.contains("Bold")
                    if isBold {
                        hasBold = true
                        stop.pointee = true
                    }
                }
            }
            assertTrue(hasBold, "Selected text 'rocks' has bold font applied directly")
            
            // Toggle again to unbold
            tv.toggleBold()
            assertEqual(tv.string, "PlanTop rocks", "Text remains clean on unbold toggle")
            var isUnbold = true
            tv.textStorage?.enumerateAttribute(.font, in: NSRange(location: 8, length: 5), options: []) { val, _, stop in
                if let font = val as? NSFont {
                    let isBold = font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.contains("Heavy") || font.fontName.contains("Black") || font.fontName.contains("Bold")
                    if isBold {
                        isUnbold = false
                        stop.pointee = true
                    }
                }
            }
            assertTrue(isUnbold, "Selected text 'rocks' has bold font removed on second toggle")
        }

        // Test 2: Italic toggle applies font attribute directly (no raw asterisks)
        do {
            let tv = QuickNotesTextView()
            tv.isRichText = true
            tv.string = "Focus mode"
            tv.setSelectedRange(NSRange(location: 0, length: 5)) // select "Focus"
            tv.toggleItalic()
            assertEqual(tv.string, "Focus mode", "Does NOT insert raw asterisks on italic toggle")
            
            var hasItalic = false
            tv.textStorage?.enumerateAttribute(.font, in: NSRange(location: 0, length: 5), options: []) { val, _, stop in
                if let font = val as? NSFont {
                    let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic) || font.fontName.contains("Oblique") || font.fontName.contains("Italic")
                    if isItalic {
                        hasItalic = true
                        stop.pointee = true
                    }
                }
            }
            assertTrue(hasItalic, "Selected text 'Focus' has italic font applied directly")
            
            // Toggle again to remove italic
            tv.toggleItalic()
            assertEqual(tv.string, "Focus mode", "Text remains clean on unitalic toggle")
        }

        // Test 3: Markdown conversion strips raw syntax and applies rich formatting
        do {
            let mdString = "**Hello** *World* and ~~strike~~"
            let rich = QuickNotesPanelView.convertMarkdownToRichText(mdString)
            let plain = rich.string
            
            assertTrue(!plain.contains("**"), "No ** asterisks in converted markdown")
            assertTrue(!plain.contains("~~"), "No ~~ tildes in converted markdown")
            assertEqual(plain, "Hello World and strike", "Markdown delimiters stripped cleanly: '\(plain)'")
            
            // Check bold on "Hello"
            let helloRange = (plain as NSString).range(of: "Hello")
            var helloIsBold = false
            rich.enumerateAttribute(.font, in: helloRange, options: []) { val, _, stop in
                if let font = val as? NSFont {
                    let isBold = font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.contains("Heavy") || font.fontName.contains("Bold")
                    if isBold {
                        helloIsBold = true
                        stop.pointee = true
                    }
                }
            }
            assertTrue(helloIsBold, "Converted 'Hello' has bold font attribute")
            
            // Check italic on "World"
            let worldRange = (plain as NSString).range(of: "World")
            var worldIsItalic = false
            rich.enumerateAttribute(.font, in: worldRange, options: []) { val, _, stop in
                if let font = val as? NSFont {
                    let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic) || font.fontName.contains("Oblique")
                    if isItalic {
                        worldIsItalic = true
                        stop.pointee = true
                    }
                }
            }
            assertTrue(worldIsItalic, "Converted 'World' has italic font attribute")
            
            // Check strikethrough on "strike"
            let strikeRange = (plain as NSString).range(of: "strike")
            var strikeHasAttr = false
            rich.enumerateAttribute(.strikethroughStyle, in: strikeRange, options: []) { val, _, stop in
                if let s = val as? Int, s == NSUnderlineStyle.single.rawValue {
                    strikeHasAttr = true
                    stop.pointee = true
                }
            }
            assertTrue(strikeHasAttr, "Converted 'strike' has strikethrough attribute")
        }

        // Test 4: Bullet points toggle
        do {
            let tv = QuickNotesTextView()
            tv.string = "First\nSecond\nThird"
            tv.setSelectedRange(NSRange(location: 0, length: (tv.string as NSString).length))
            tv.toggleBullet()
            assertEqual(tv.string, "- First\n- Second\n- Third", "Adds bullet prefixes to multiple lines")
            
            tv.toggleBullet()
            assertEqual(tv.string, "First\nSecond\nThird", "Removes bullet prefixes on second toggle")
        }

        // Test 5: Numbered points toggle
        do {
            let tv = QuickNotesTextView()
            tv.string = "Apple\nBanana\nCherry"
            tv.setSelectedRange(NSRange(location: 0, length: (tv.string as NSString).length))
            tv.toggleNumbered()
            assertEqual(tv.string, "1. Apple\n2. Banana\n3. Cherry", "Adds sequential numbered prefixes")
            
            tv.toggleNumbered()
            assertEqual(tv.string, "Apple\nBanana\nCherry", "Removes numbered prefixes on second toggle")
        }

        // Test 6: QuickNotesPanelView font size & setup
        do {
            let panel = QuickNotesPanelView()
            var foundTextView: QuickNotesTextView?
            for subview in panel.subviews {
                if let scroll = subview as? NSScrollView, let tv = scroll.documentView as? QuickNotesTextView {
                    foundTextView = tv
                }
            }
            assertTrue(foundTextView != nil, "QuickNotesPanelView contains a QuickNotesTextView")
            if let tv = foundTextView {
                assertEqual(tv.font?.pointSize ?? 0, 16.0, "Text view font size is enlarged to 16.0pt")
                assertTrue(tv.isRichText, "Text view is enabled for rich markdown display")
            }
        }

        // Test 7: Underline toggle applies underline style attribute
        do {
            let tv = QuickNotesTextView()
            tv.isRichText = true
            tv.string = "Underline me"
            tv.setSelectedRange(NSRange(location: 0, length: 9)) // select "Underline"
            tv.toggleUnderline()
            
            var hasUnderline = false
            tv.textStorage?.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: 9), options: []) { val, _, stop in
                if let s = val as? Int, s == NSUnderlineStyle.single.rawValue {
                    hasUnderline = true
                    stop.pointee = true
                }
            }
            assertTrue(hasUnderline, "Selected text has underline style attribute applied")
            
            // Toggle again to remove underline
            tv.toggleUnderline()
            var isUnunderlined = true
            tv.textStorage?.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: 9), options: []) { val, _, stop in
                if let s = val as? Int, s != 0 {
                    isUnunderlined = false
                    stop.pointee = true
                }
            }
            assertTrue(isUnunderlined, "Underline removed on second toggle")
        }

        // Test 8: Cmd+A Select All key equivalent in QuickNotesTextView
        do {
            let tv = QuickNotesTextView()
            tv.string = "The quick brown fox jumps over the lazy dog"
            tv.setSelectedRange(NSRange(location: 0, length: 0)) // cursor at start
            
            let cmdAEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )!
            let handled = tv.performKeyEquivalent(with: cmdAEvent)
            assertTrue(handled, "Cmd+A is handled by QuickNotesTextView")
            assertEqual(tv.selectedRange().length, (tv.string as NSString).length, "Cmd+A selects all text in QuickNotesTextView")
            
            // Test Cmd+U shortcut
            tv.setSelectedRange(NSRange(location: 4, length: 5)) // select "quick"
            let cmdUEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "u",
                charactersIgnoringModifiers: "u",
                isARepeat: false,
                keyCode: 32
            )!
            let handledU = tv.performKeyEquivalent(with: cmdUEvent)
            assertTrue(handledU, "Cmd+U is handled by QuickNotesTextView")
            
            var quickHasUnderline = false
            tv.textStorage?.enumerateAttribute(.underlineStyle, in: NSRange(location: 4, length: 5), options: []) { val, _, stop in
                if let s = val as? Int, s == NSUnderlineStyle.single.rawValue {
                    quickHasUnderline = true
                    stop.pointee = true
                }
            }
            assertTrue(quickHasUnderline, "Cmd+U successfully underlined selected word 'quick'")
        }
        
        // Test 10: Hover auto-focus and immediate typing activation
        do {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            let panel = QuickNotesPanelView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            win.contentView = panel
            win.makeKeyAndOrderFront(nil)
            
            // Before hover focus
            win.makeFirstResponder(nil)
            assertTrue(win.firstResponder != panel, "Initial first responder is not textView")
            
            // Hover activates focusForTyping immediately
            panel.focusForTyping()
            
            // Verify window's first responder is now the internal text view
            var foundTextView = false
            func checkSubviewForTextView(_ v: NSView) {
                if let tv = v as? QuickNotesTextView {
                    if win.firstResponder == tv {
                        foundTextView = true
                    }
                }
                for sub in v.subviews {
                    checkSubviewForTextView(sub)
                }
            }
            checkSubviewForTextView(panel)
            assertTrue(foundTextView, "Hover auto-focus immediately sets QuickNotesTextView as first responder without clicking")
        }

        print("\n🎉 All PlanTop QuickNotes tests passed successfully!")
    }
}
