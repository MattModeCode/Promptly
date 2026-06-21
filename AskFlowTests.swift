// AskFlowTests.swift — Tier A autonomous tests for the Stage 4 {{ask:label}} state machine.
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/TokenEngine.swift AskFlowTests.swift \
//         -o /tmp/AskFlowTests && /tmp/AskFlowTests
//
// Pure model tests — no UI (Stage 4 §6). The panel owns keystrokes + surface; AskFlow owns
// only "which label is active, collect answers in order, assemble the final body."
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

func test_no_asks_is_nil() {
    print("\nTest — a body with no asks yields nil (caller pastes directly):")
    check(AskFlow(body: "plain prompt with {{clipboard}}") == nil, "no ask tokens → nil flow")
}

func test_discovers_in_order() {
    print("\nTest — asks discovered in document order:")
    let flow = AskFlow(body: "Hi {{ask:name}}, re {{ask:project}} ({{ask:date}})")
    check(flow?.labels == ["name", "project", "date"], "labels in order (got \(flow?.labels ?? []))")
    check(flow?.progress.total == 3, "total count = 3")
    check(flow?.currentLabel == "name", "first active label = name")
}

func test_advance_collects_and_completes() {
    print("\nTest — ↵/⇥ advance in order, collect answers, complete on the last:")
    var flow = AskFlow(body: "Hi {{ask:name}}, re {{ask:project}}.")!
    check(flow.progress == (1, 2), "starts at 1 of 2")
    let more1 = flow.advance(with: "Sam")
    check(more1, "advancing the first ask → more remain")
    check(flow.progress == (2, 2), "now 2 of 2")
    check(flow.currentLabel == "project", "active label advanced to project")
    let more2 = flow.advance(with: "Promptly")
    check(!more2, "advancing the last ask → complete")
    check(flow.isComplete, "isComplete true after last answer")
    let final = flow.finalText(body: "Hi {{ask:name}}, re {{ask:project}}.")
    check(final == "Hi Sam, re Promptly.", "final substitution composes answers (got \"\(final)\")")
}

func test_final_keeps_static_tokens() {
    print("\nTest — final text fills asks but leaves static tokens for expand():")
    var flow = AskFlow(body: "{{ask:greeting}} — {{clipboard}} {{cursor}}")!
    _ = flow.advance(with: "Hello")
    let final = flow.finalText(body: "{{ask:greeting}} — {{clipboard}} {{cursor}}")
    check(final == "Hello — {{clipboard}} {{cursor}}", "static tokens preserved (got \"\(final)\")")
}

func test_reset_cancels_whole_expansion() {
    print("\nTest — esc/reset clears all answers and returns to the first ask:")
    var flow = AskFlow(body: "{{ask:a}} {{ask:b}} {{ask:c}}")!
    _ = flow.advance(with: "1")
    _ = flow.advance(with: "2")
    check(flow.progress == (3, 3), "advanced to 3 of 3")
    flow.reset()
    check(flow.progress == (1, 3) && !flow.isComplete, "reset → back to 1 of 3, not complete")
    check(flow.answers.isEmpty, "reset clears collected answers")
}

func test_empty_answer_allowed() {
    print("\nTest — an empty answer is allowed (substitutes empty):")
    var flow = AskFlow(body: "[{{ask:opt}}]")!
    _ = flow.advance(with: "")
    let final = flow.finalText(body: "[{{ask:opt}}]")
    check(final == "[]", "empty answer substitutes empty (got \"\(final)\")")
}

@main
enum TestMain {
    static func main() {
        test_no_asks_is_nil()
        test_discovers_in_order()
        test_advance_collects_and_completes()
        test_final_keeps_static_tokens()
        test_reset_cancels_whole_expansion()
        test_empty_answer_allowed()

        print("\n=== Stage 4 Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous, pure model). Tier B (panel never jumps; esc mid-flow) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
