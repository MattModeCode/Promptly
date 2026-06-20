// HistoryOrderTests.swift — Tier A autonomous tests for the history view's pure ordering logic.
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc -framework AppKit \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/PromptStore.swift HistoryOrderTests.swift \
//         -o /tmp/HistoryOrderTests && /tmp/HistoryOrderTests
//
// Feature #4: history view orders fired prompts by recency only (no decay/score math the way
// frecency has). Mirrors PromptStoreTests.swift's harness idiom exactly.
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

private func prompt(_ name: String, _ file: String) -> Prompt {
    Prompt(name: name, keywords: [], body: "", filename: file)
}

func test_historyOrder_excludes_unused() {
    print("\nTest — historyOrder excludes prompts with no usage entry:")
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let ps = [prompt("Used", "used.md"), prompt("Unused", "unused.md")]
    let usage: [String: PromptUsage] = [
        "used.md": PromptUsage(count: 1, lastUsed: now),
    ]
    let order = PromptStore.historyOrder(ps, usage: usage).map { $0.0.name }
    check(order == ["Used"], "unused prompt excluded entirely (got \(order))")
}

func test_historyOrder_orders_by_lastUsed_desc() {
    print("\nTest — historyOrder orders multiple used prompts by lastUsed descending:")
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let ps = [prompt("A", "a.md"), prompt("B", "b.md"), prompt("C", "c.md")]
    let usage: [String: PromptUsage] = [
        "a.md": PromptUsage(count: 1, lastUsed: now.addingTimeInterval(-7 * 86_400)),  // a week ago
        "b.md": PromptUsage(count: 1, lastUsed: now),                                   // now (most recent)
        "c.md": PromptUsage(count: 1, lastUsed: now.addingTimeInterval(-3600)),         // an hour ago
    ]
    let order = PromptStore.historyOrder(ps, usage: usage).map { $0.0.name }
    check(order == ["B", "C", "A"], "most recently used first (got \(order))")
}

func test_historyOrder_deterministic_tiebreak() {
    print("\nTest — historyOrder breaks exact lastUsed ties by original array index ascending:")
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    // B and C share the exact same lastUsed; B precedes C in the original prompts array.
    let ps = [prompt("A", "a.md"), prompt("B", "b.md"), prompt("C", "c.md")]
    let usage: [String: PromptUsage] = [
        "a.md": PromptUsage(count: 1, lastUsed: now.addingTimeInterval(-86_400)),
        "b.md": PromptUsage(count: 1, lastUsed: now),
        "c.md": PromptUsage(count: 1, lastUsed: now),
    ]
    let order = PromptStore.historyOrder(ps, usage: usage).map { $0.0.name }
    check(order == ["B", "C", "A"], "tied lastUsed broken by original index ascending (got \(order))")
}

func test_historyOrder_all_unused_returns_empty() {
    print("\nTest — an all-unused library returns [] (not seed order):")
    let ps = [prompt("first", "1.md"), prompt("second", "2.md"), prompt("third", "3.md")]
    let order = PromptStore.historyOrder(ps, usage: [:])
    check(order.isEmpty, "no fires at all → [] (got \(order.map { $0.0.name }))")
}

@main
enum TestMain {
    static func main() {
        test_historyOrder_excludes_unused()
        test_historyOrder_orders_by_lastUsed_desc()
        test_historyOrder_deterministic_tiebreak()
        test_historyOrder_all_unused_returns_empty()

        print("\n=== Task 3 (historyOrder) Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous; pure recency ordering). Tier B (history-mode UI, Task 5) is later.")
        exit(failed == 0 ? 0 : 1)
    }
}
