// PromptStoreTests.swift — Tier A autonomous tests for the prompt store's pure logic.
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc -framework AppKit \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/PromptStore.swift PromptStoreTests.swift \
//         -o /tmp/PromptStoreTests && /tmp/PromptStoreTests
//
// Stage 5 (§6): the inverse-capture save path must produce well-formed markdown that the
// store re-reads identically — asserted as serialize→parse symmetry, no ~/Prompts touched.
// (Selection capture itself is Tier B — it needs a foreign app.)
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

func roundTrip(name: String, keywords: [String], body: String) -> Prompt? {
    let md = PromptStore.serialize(name: name, keywords: keywords, body: body)
    return PromptStore.parse(md, filename: "round-trip.md")
}

func test_basic_symmetry() {
    print("\nTest — serialize → parse round-trips name/keywords/body:")
    let p = roundTrip(name: "PR description", keywords: ["pr", "diff"], body: "Summarize the diff.")
    check(p?.name == "PR description", "name preserved (got \(p?.name ?? "nil"))")
    check(p?.keywords == ["pr", "diff"], "keywords preserved (got \(p?.keywords ?? []))")
    check(p?.body == "Summarize the diff.", "body preserved (got \(p?.body ?? "nil"))")
}

func test_multiline_and_tokens() {
    print("\nTest — multi-line body with tokens survives the round-trip:")
    let body = "Line one.\n\nLine two with {{clipboard}}\n{{cursor}}"
    let p = roundTrip(name: "Multi", keywords: [], body: body)
    check(p?.body == body, "multi-line + token body byte-identical (got \"\(p?.body ?? "nil")\")")
    check(p?.keywords == [], "no keywords → empty array")
}

func test_capture_like_payload() {
    print("\nTest — a captured-selection payload (Stage 5) round-trips:")
    // What the inverse-capture sheet would save: a pasted snippet as the body.
    let captured = "func paste() {\n    // selected from some editor\n}"
    let p = roundTrip(name: "Captured snippet", keywords: ["capture", "swift"], body: captured)
    check(p?.body == captured, "captured body preserved verbatim")
    check(p?.name == "Captured snippet", "title preserved")
}

func test_malformed_rejected() {
    print("\nTest — malformed markdown is rejected (nil), not crashed:")
    check(PromptStore.parse("no frontmatter here", filename: "a.md") == nil, "missing frontmatter → nil")
    check(PromptStore.parse("---\nname: X\n(no close)", filename: "b.md") == nil, "unclosed frontmatter → nil")
    check(PromptStore.parse("---\nkeywords: [x]\n---\nbody", filename: "c.md") == nil, "missing name → nil")
}

@main
enum TestMain {
    static func main() {
        test_basic_symmetry()
        test_multiline_and_tokens()
        test_capture_like_payload()
        test_malformed_rejected()

        print("\n=== Stage 5 Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous, pure serialize/parse). Tier B (capture in a real app) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
