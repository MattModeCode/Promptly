// TokenEngineTests.swift — Tier A autonomous tests for the Stage 3 token engine.
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/TokenEngine.swift TokenEngineTests.swift \
//         -o /tmp/TokenEngineTests && /tmp/TokenEngineTests
//
// Pure-function tests — no foreign app, no clipboard, no AX trust (DESIGN §8, Stage 3 §6).
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

// A fixed reference date so the {{date}} assertion is deterministic.
private func fixedDate() -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 19; c.hour = 12
    c.timeZone = TimeZone.current
    return Calendar(identifier: .gregorian).date(from: c)!
}

func test_clipboard() {
    print("\nTest — {{clipboard}} substitution:")
    let e = TokenEngine.expand("before {{clipboard}} after", clipboard: "PASTED", now: fixedDate())
    check(e.text == "before PASTED after", "clipboard substituted (got \"\(e.text)\")")
    check(e.cursorOffset == nil, "no cursor → offset nil")
}

func test_clipboard_empty_warns() {
    print("\nTest — empty {{clipboard}} substitutes empty + warns (does not crash):")
    var warned = false
    let e = TokenEngine.expand("[{{clipboard}}]", clipboard: nil, now: fixedDate(),
                               warn: { _ in warned = true })
    check(e.text == "[]", "empty clipboard → empty substitution (got \"\(e.text)\")")
    check(warned, "warning fired for empty known token")
}

func test_date() {
    print("\nTest — {{date}} ISO 8601:")
    let now = fixedDate()
    let expected = TokenEngine.isoDate.string(from: now)
    let e = TokenEngine.expand("d={{date}}", clipboard: nil, now: now)
    check(e.text == "d=\(expected)", "date formatted ISO (got \"\(e.text)\", expected suffix \(expected))")
}

func test_unknown_literal() {
    print("\nTest — unknown tokens stay literal:")
    let e = TokenEngine.expand("keep {{whatever}} and {{clipboaord}}", clipboard: "x", now: fixedDate())
    check(e.text == "keep {{whatever}} and {{clipboaord}}", "typo'd/unknown tokens verbatim (got \"\(e.text)\")")
}

func test_cursor() {
    print("\nTest — {{cursor}} stripped, offset recorded:")
    let e = TokenEngine.expand("ab{{cursor}}cd", clipboard: nil, now: fixedDate())
    check(e.text == "abcd", "cursor token removed (got \"\(e.text)\")")
    check(e.cursorOffset == 2, "offset is char position before cursor (got \(e.cursorOffset.map(String.init) ?? "nil"))")
}

func test_cursor_after_substitution() {
    print("\nTest — {{cursor}} offset reflects substituted length:")
    // "XY" (2) then cursor → offset 2; trailing "!" after.
    let e = TokenEngine.expand("{{clipboard}}{{cursor}}!", clipboard: "XY", now: fixedDate())
    check(e.text == "XY!", "assembled text (got \"\(e.text)\")")
    check(e.cursorOffset == 2, "offset counts substituted clipboard (got \(e.cursorOffset.map(String.init) ?? "nil"))")
}

func test_cursor_first_only() {
    print("\nTest — only the first {{cursor}} is honored; all stripped:")
    let e = TokenEngine.expand("a{{cursor}}b{{cursor}}c", clipboard: nil, now: fixedDate())
    check(e.text == "abc", "both cursor tokens removed (got \"\(e.text)\")")
    check(e.cursorOffset == 1, "offset from FIRST cursor (got \(e.cursorOffset.map(String.init) ?? "nil"))")
}

func test_asks_passthrough() {
    print("\nTest — {{ask:…}} is left literal by expand (resolved earlier in Stage 4):")
    let e = TokenEngine.expand("Hi {{ask:name}}", clipboard: nil, now: fixedDate())
    check(e.text == "Hi {{ask:name}}", "ask token untouched by static expand (got \"\(e.text)\")")
}

@main
enum TestMain {
    static func main() {
        test_clipboard()
        test_clipboard_empty_warns()
        test_date()
        test_unknown_literal()
        test_cursor()
        test_cursor_after_substitution()
        test_cursor_first_only()
        test_asks_passthrough()

        print("\n=== Stage 3 Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous, pure functions). Tier B (real-app paste + caret) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
