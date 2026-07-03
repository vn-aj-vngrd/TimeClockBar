import AppKit
import XCTest
@testable import Time_Clock_Bar

final class HotkeyFormattingTests: XCTestCase {
    func testModifierLabelsUseStableOrder() {
        let modifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

        XCTAssertEqual(HotkeyFormatting.modifierLabel(modifiers), "⌃⌥⇧⌘")
    }

    func testKnownKeyLabels() {
        XCTAssertEqual(HotkeyFormatting.label(keyCode: 17, modifiers: []), "T")
        XCTAssertEqual(HotkeyFormatting.label(keyCode: 49, modifiers: []), "Space")
    }

    func testUnknownKeyLabelIncludesKeyCode() {
        XCTAssertEqual(HotkeyFormatting.label(keyCode: 999, modifiers: []), "Key 999")
    }

    func testDefaultHotkeyLabel() {
        XCTAssertEqual(
            HotkeyFormatting.label(keyCode: 17, modifiers: [.control, .option, .command]),
            "⌃⌥⌘T"
        )
    }
}
