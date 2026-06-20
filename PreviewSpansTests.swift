// PreviewSpansTests.swift — Tier A autonomous tests for TokenEngine.spans(in:) (preview pane seam).
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/TokenEngine.swift PreviewSpansTests.swift \
//         -o /tmp/PreviewSpansTests && /tmp/PreviewSpansTests
//
// Pure-function tests — no foreign app, no clipboard, no AX trust (DESIGN §8).
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

func test_one_of_each_kind() {
    print("\nTest — one span per token kind, in document order, ranges cover the literal \"{{...}}\":")
    let body = "{{clipboard}} {{date}} {{cursor}} {{ask:name}}"
    let spans = TokenEngine.spans(in: body)
    check(spans.count == 4, "expected 4 spans (got \(spans.count))")
    guard spans.count == 4 else { return }
    let kinds = spans.map { $0.kind }
    check(kinds == [.clipboard, .date, .cursor, .ask], "kinds in document order (got \(kinds))")
    let texts = spans.map { String(body[$0.range]) }
    check(texts == ["{{clipboard}}", "{{date}}", "{{cursor}}", "{{ask:name}}"],
          "each range's substring equals the literal token (got \(texts))")
}

func test_unknown_token() {
    print("\nTest — unknown/typo'd token classified .unknown, still present:")
    let body = "keep {{whatever}} here"
    let spans = TokenEngine.spans(in: body)
    check(spans.count == 1, "expected 1 span (got \(spans.count))")
    guard let span = spans.first else { return }
    check(span.kind == .unknown, "typo'd token classified unknown (got \(span.kind))")
    check(String(body[span.range]) == "{{whatever}}", "range covers full literal (got \"\(String(body[span.range]))\")")
}

func test_plain_text_no_tokens() {
    print("\nTest — plain text with no tokens yields no spans:")
    let spans = TokenEngine.spans(in: "just plain text, no braces at all")
    check(spans.isEmpty, "expected [] (got \(spans.count) spans)")
}

func test_empty_ask_label_is_unknown() {
    print("\nTest — {{ask:}} with empty label classified .unknown (asks(in:) silently skips it too):")
    let body = "before {{ask:}} after"
    let spans = TokenEngine.spans(in: body)
    check(spans.count == 1, "expected 1 span (got \(spans.count))")
    guard let span = spans.first else { return }
    check(span.kind == .unknown, "empty-label ask classified unknown (got \(span.kind))")
    check(String(body[span.range]) == "{{ask:}}", "range covers full literal (got \"\(String(body[span.range]))\")")
}

func test_mixed_body_with_surrounding_text() {
    print("\nTest — tokens interspersed with plain text resolve correct ranges:")
    let body = "Hello {{clipboard}}, today is {{date}}."
    let spans = TokenEngine.spans(in: body)
    check(spans.count == 2, "expected 2 spans (got \(spans.count))")
    guard spans.count == 2 else { return }
    check(spans[0].kind == .clipboard, "first span clipboard (got \(spans[0].kind))")
    check(spans[1].kind == .date, "second span date (got \(spans[1].kind))")
    check(String(body[spans[0].range]) == "{{clipboard}}", "first range literal (got \"\(String(body[spans[0].range]))\")")
    check(String(body[spans[1].range]) == "{{date}}", "second range literal (got \"\(String(body[spans[1].range]))\")")
}

@main
enum TestMain {
    static func main() {
        test_one_of_each_kind()
        test_unknown_token()
        test_plain_text_no_tokens()
        test_empty_ask_label_is_unknown()
        test_mixed_body_with_surrounding_text()

        print("\n=== Preview Spans Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous, pure functions). No UI exercised — that's Task 2.")
        exit(failed == 0 ? 0 : 1)
    }
}
