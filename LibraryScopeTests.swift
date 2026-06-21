// LibraryScopeTests.swift — Tier A autonomous tests for the Library window's sidebar scope
// filter (Stage 9). Pure, no NSView, no filesystem.
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc -framework AppKit \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/PromptStore.swift Promptly/LibraryScope.swift LibraryScopeTests.swift \
//         -o /tmp/LibraryScopeTests && /tmp/LibraryScopeTests
//
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

private func prompt(_ name: String, filename: String? = nil, folder: String = "",
                    pinned: Bool = false, hotkey: Int? = nil) -> Prompt {
    Prompt(name: name, keywords: [], body: "", filename: filename ?? "\(name).md",
           folder: folder, pinned: pinned, hotkey: hotkey)
}

func test_all_returns_every_prompt() {
    print("\nTest — .all returns every prompt:")
    let prompts = [prompt("A"), prompt("B"), prompt("C")]
    let result = LibraryScope.filter(.all, prompts: prompts, usage: [:], query: "")
    check(result.count == 3, "all 3 prompts returned (got \(result.count))")
}

func test_pinned_returns_only_pinned() {
    print("\nTest — .pinned returns only prompts with pinned == true:")
    let prompts = [prompt("A", pinned: true), prompt("B", pinned: false), prompt("C", pinned: true)]
    let result = LibraryScope.filter(.pinned, prompts: prompts, usage: [:], query: "")
    check(result.count == 2, "only the 2 pinned prompts (got \(result.count))")
    check(result.allSatisfy { $0.pinned }, "every result is pinned")
    check(!result.contains { $0.name == "B" }, "the unpinned prompt is excluded")
}

func test_pinned_is_independent_of_hotkey() {
    print("\nTest — .pinned doesn't care whether a hotkey is set:")
    let prompts = [prompt("A", pinned: true, hotkey: nil), prompt("B", pinned: false, hotkey: 3)]
    let result = LibraryScope.filter(.pinned, prompts: prompts, usage: [:], query: "")
    check(result.count == 1, "only A (pinned, no hotkey) — B has a hotkey but isn't pinned (got \(result.count))")
    check(result.first?.name == "A", "A is the one pinned result")
}

func test_recent_orders_by_frecency_top_n() {
    print("\nTest — .recent orders by frecency (matches PromptStore.rank):")
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let prompts = [prompt("A"), prompt("B"), prompt("C")]
    let usage: [String: PromptUsage] = [
        "B.md": PromptUsage(count: 5, lastUsed: now.addingTimeInterval(-3600)),
        "A.md": PromptUsage(count: 1, lastUsed: now.addingTimeInterval(-30 * 86_400)),
    ]
    let result = LibraryScope.filter(.recent, prompts: prompts, usage: usage, query: "", now: now)
    check(result.map { $0.name } == ["B", "A", "C"], "frecency order, unused last (got \(result.map { $0.name }))")
}

func test_folder_returns_exact_match_only() {
    print("\nTest — .folder(\"X\") returns exactly that folder's prompts:")
    let prompts = [
        prompt("Eng1", folder: "Engineering"),
        prompt("Eng2", folder: "Engineering"),
        prompt("Root", folder: ""),
        prompt("Other", folder: "Writing"),
    ]
    let engineering = LibraryScope.filter(.folder("Engineering"), prompts: prompts, usage: [:], query: "")
    check(engineering.count == 2, "exactly the 2 Engineering prompts (got \(engineering.count))")
    check(engineering.allSatisfy { $0.folder == "Engineering" }, "every result is in Engineering")

    let root = LibraryScope.filter(.folder(""), prompts: prompts, usage: [:], query: "")
    check(root.count == 1, "folder(\"\") returns exactly the root prompt (got \(root.count))")
    check(root.first?.name == "Root", "the root prompt is Root")
}

func test_query_composes_on_top_of_scope() {
    print("\nTest — a non-empty query narrows WITHIN the scope, not the whole library:")
    let prompts = [
        prompt("Bug report", pinned: true),
        prompt("Cold outreach", pinned: true),
        prompt("Bug triage notes", pinned: false),   // matches "bug" but not pinned
    ]
    let result = LibraryScope.filter(.pinned, prompts: prompts, usage: [:], query: "bug")
    check(result.count == 1, "only the pinned prompt matching \"bug\" (got \(result.count))")
    check(result.first?.name == "Bug report", "the unpinned bug match is excluded by scope (got \(result.map { $0.name }))")
}

@main
enum TestMain {
    static func main() {
        test_all_returns_every_prompt()
        test_pinned_returns_only_pinned()
        test_pinned_is_independent_of_hotkey()
        test_recent_orders_by_frecency_top_n()
        test_folder_returns_exact_match_only()
        test_query_composes_on_top_of_scope()

        print("\n=== LibraryScope Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous; pure scope filtering). Tier B (sidebar selection driving")
        print("the real window) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
