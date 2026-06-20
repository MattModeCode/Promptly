// HudAssignTests.swift — Tier A autonomous tests for the Stage 7 ⌥1–9 position assignment.
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc -framework AppKit \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/PromptStore.swift Promptly/HudRow.swift HudAssignTests.swift \
//         -o /tmp/HudAssignTests && /tmp/HudAssignTests
//
// (PromptStore.swift only supplies the Prompt type.) Pure-function tests — no panel, no keys
// (Stage 7 §6): 9 slots fill deterministically; same input → same map (the freeze rule).
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

private func prompt(_ name: String) -> Prompt {
    Prompt(name: name, keywords: [], body: "", filename: "\(name).md")
}

func test_fills_one_based_in_rank_order() {
    print("\nTest — slots 1…N fill in ranking order:")
    let ranked = (1...5).map { prompt("p\($0)") }
    let map = HudRow.assign(ranked)
    check(map.count == 5, "5 ranked → 5 slots (got \(map.count))")
    check(map[1]?.name == "p1", "slot 1 = top-ranked")
    check(map[5]?.name == "p5", "slot 5 = fifth")
    check(map[0] == nil, "no slot 0 (1-based)")
}

func test_caps_at_nine() {
    print("\nTest — never assigns more than 9 slots:")
    let ranked = (1...20).map { prompt("p\($0)") }
    let map = HudRow.assign(ranked)
    check(map.count == HudRow.slotCount, "capped at 9 (got \(map.count))")
    check(map[9]?.name == "p9", "slot 9 = ninth")
    check(map[10] == nil, "nothing past slot 9")
}

func test_fewer_than_nine() {
    print("\nTest — a small library fills only the slots it can:")
    let map = HudRow.assign([prompt("only"), prompt("two")])
    check(map.count == 2, "2 prompts → slots 1,2 (got \(map.count))")
    check(map[3] == nil, "slot 3 empty")
}

func test_deterministic_and_stable() {
    print("\nTest — identical input → identical map (the freeze rule — no live reshuffle):")
    let ranked = (1...9).map { prompt("p\($0)") }
    let a = HudRow.assign(ranked)
    let b = HudRow.assign(ranked)
    let same = (1...9).allSatisfy { a[$0]?.name == b[$0]?.name }
    check(same, "two assignments of the same ranking match slot-for-slot")
    // A *different* ranking (a reorder between opens) yields a different map — adaptation
    // happens only between appearances, never during one.
    let reordered = Array(ranked.reversed())
    let c = HudRow.assign(reordered)
    check(c[1]?.name == "p9", "a re-sorted ranking remaps slot 1 (between-open adaptation)")
}

@main
enum TestMain {
    static func main() {
        test_fills_one_based_in_rank_order()
        test_caps_at_nine()
        test_fewer_than_nine()
        test_deterministic_and_stable()

        print("\n=== Stage 7 Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous, pure assignment). Tier B (⌥3 stays ⌥3 for a whole")
        print("appearance; re-sort only between opens) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
