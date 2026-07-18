// HotkeyDisplayTests.swift — Tier A autonomous tests for HotkeyManager's pure display/modifier
// mapping (keycode + Carbon modifier bits → glyph string, and NSEvent flags → Carbon bits).
//
// Compile + run (native arm64):
//     swiftc -framework AppKit -target arm64-apple-macosx12.0 \
//         Promptly/HotkeyManager.swift HotkeyDisplayTests.swift \
//         -o /tmp/HotkeyDisplayTests && /tmp/HotkeyDisplayTests
//
// Pure functions — no event tap, no hotkey registration. Honesty rule (CLAUDE.md): never weaken
// an assertion to go green — fix the cause.

import AppKit
import Carbon

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

func test_option_space_is_the_palette_hotkey() {
    print("\nTest — ⌥Space (keycode 49, optionKey) renders as \"⌥Space\":")
    let s = HotkeyManager.displayString(keyCode: 49, modifiers: UInt32(optionKey))
    check(s == "⌥Space", "keycode 49 + optionKey → ⌥Space (got \(s))")
}

func test_letter_with_modifiers_uses_canonical_order() {
    print("\nTest — a letter + multiple modifiers renders glyphs in canonical ⌃⌥⇧⌘ order:")
    // Bits OR'd shift-then-command; the output must still be ⇧ before ⌘, then the key.
    let s = HotkeyManager.displayString(keyCode: 40, modifiers: UInt32(shiftKey | cmdKey))
    check(s == "⇧⌘K", "keycode 40 + ⇧⌘ → ⇧⌘K (got \(s))")
}

func test_unknown_keycode_falls_back_visibly() {
    print("\nTest — an unmapped keycode falls back to key<code> rather than blank:")
    let s = HotkeyManager.displayString(keyCode: 999, modifiers: 0)
    check(s == "key999", "unknown keycode → key999 (got \(s))")
}

func test_carbonModifiers_round_trips_through_displayString() {
    print("\nTest — carbonModifiers(from:) maps NSEvent flags to Carbon bits, round-tripping:")
    let cocoa: NSEvent.ModifierFlags = [.command, .shift]
    let bits = HotkeyManager.carbonModifiers(from: cocoa)
    check(bits == UInt32(cmdKey | shiftKey), "⌘⇧ flags → cmdKey|shiftKey bits (got \(bits))")
    // Round-trip: those same bits render back to the glyphs displayString produces.
    let rendered = HotkeyManager.displayString(keyCode: 40, modifiers: bits)
    check(rendered == "⇧⌘K", "the mapped bits render ⇧⌘K (got \(rendered))")
}

@main
enum TestMain {
    static func main() {
        test_option_space_is_the_palette_hotkey()
        test_letter_with_modifiers_uses_canonical_order()
        test_unknown_keycode_falls_back_visibly()
        test_carbonModifiers_round_trips_through_displayString()

        print("\n=== HotkeyManager display Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous; pure keycode/modifier mapping). The live global hotkey")
        print("registration is Tier B (it needs a real event tap).")
        exit(failed == 0 ? 0 : 1)
    }
}
