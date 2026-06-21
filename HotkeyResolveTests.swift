// HotkeyResolveTests.swift — Tier A autonomous tests for hotkey-conflict resolution.
// Covers PromptStore.resolveHotkeys (deterministic lowest-filename winner, conflict reporting,
// clean pass-through, no-hotkey-ignored) plus the parse-time range guard that keeps
// out-of-range hotkeys out of resolveHotkeys entirely, plus legacy `pin:` migration-on-read.
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc -framework AppKit \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/PromptStore.swift HotkeyResolveTests.swift \
//         -o /tmp/HotkeyResolveTests && /tmp/HotkeyResolveTests
//
// (PromptStore.swift supplies Prompt, HotkeyConflict, resolveHotkeys, parse.) Pure-function
// tests — no panel, no filesystem: resolution is deterministic and the range guard lives in
// parse, not in resolveHotkeys. Honesty rule (CLAUDE.md): never weaken an assertion to go
// green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

private func prompt(_ filename: String, hotkey: Int?) -> Prompt {
    Prompt(name: filename, keywords: [], body: "", filename: filename, hotkey: hotkey)
}

func test_deterministic_winner_on_conflict() {
    print("\nTest — two prompts on the same hotkey: lowest filename wins, one conflict recorded:")
    // Pass them in the "wrong" order to prove ordering comes from filename, not input order.
    let (hotkeys, conflicts) = PromptStore.resolveHotkeys([
        prompt("zebra.md", hotkey: 3),
        prompt("alpha.md", hotkey: 3),
    ])
    check(hotkeys[3]?.filename == "alpha.md", "slot 3 winner = lexicographically lowest (got \(hotkeys[3]?.filename ?? "nil"))")
    check(hotkeys.count == 1, "only slot 3 occupied (got \(hotkeys.count))")
    check(conflicts.count == 1, "exactly one conflict (got \(conflicts.count))")
    check(conflicts.first == HotkeyConflict(slot: 3, winner: "alpha.md", loser: "zebra.md"),
          "conflict attributes slot/winner/loser (got \(String(describing: conflicts.first)))")
}

func test_three_way_conflict() {
    print("\nTest — three prompts on one hotkey: one winner, two conflicts:")
    let (hotkeys, conflicts) = PromptStore.resolveHotkeys([
        prompt("c.md", hotkey: 5),
        prompt("a.md", hotkey: 5),
        prompt("b.md", hotkey: 5),
    ])
    check(hotkeys[5]?.filename == "a.md", "winner = lowest filename (got \(hotkeys[5]?.filename ?? "nil"))")
    check(hotkeys.count == 1, "only one slot occupied (got \(hotkeys.count))")
    check(conflicts.count == 2, "two losers → two conflicts (got \(conflicts.count))")
    check(conflicts.contains(HotkeyConflict(slot: 5, winner: "a.md", loser: "b.md")),
          "b.md recorded as loser to a.md")
    check(conflicts.contains(HotkeyConflict(slot: 5, winner: "a.md", loser: "c.md")),
          "c.md recorded as loser to a.md")
}

func test_non_conflicting_hotkeys_pass_through() {
    print("\nTest — distinct slots all survive, no conflicts:")
    let (hotkeys, conflicts) = PromptStore.resolveHotkeys([
        prompt("one.md", hotkey: 1),
        prompt("four.md", hotkey: 4),
        prompt("nine.md", hotkey: 9),
    ])
    check(hotkeys.count == 3, "all three hotkeyed (got \(hotkeys.count))")
    check(hotkeys[1]?.filename == "one.md", "slot 1 = one.md")
    check(hotkeys[4]?.filename == "four.md", "slot 4 = four.md")
    check(hotkeys[9]?.filename == "nine.md", "slot 9 = nine.md")
    check(conflicts.isEmpty, "no conflicts (got \(conflicts.count))")
}

func test_no_hotkey_ignored() {
    print("\nTest — prompts without a hotkey are ignored, only hotkeyed ones land in the map:")
    let (hotkeys, conflicts) = PromptStore.resolveHotkeys([
        prompt("hotkeyed.md", hotkey: 2),
        prompt("loose-a.md", hotkey: nil),
        prompt("loose-b.md", hotkey: nil),
    ])
    check(hotkeys.count == 1, "only the hotkeyed prompt is in the map (got \(hotkeys.count))")
    check(hotkeys[2]?.filename == "hotkeyed.md", "slot 2 = hotkeyed.md")
    check(conflicts.isEmpty, "no overlap → no conflicts (got \(conflicts.count))")
}

func test_out_of_range_hotkeys_rejected_at_parse() {
    print("\nTest — out-of-range / non-numeric hotkeys are dropped in parse, never reach resolveHotkeys:")
    func parsedHotkey(_ raw: String) -> Int?? {
        let md = "---\nname: P\nkeywords: []\nhotkey: \(raw)\n---\n\nbody"
        return PromptStore.parse(md, filename: "p.md").map { $0.hotkey }
    }
    check(parsedHotkey("15") == .some(nil), "hotkey 15 (above range) → hotkey nil (got \(String(describing: parsedHotkey("15"))))")
    check(parsedHotkey("0")  == .some(nil), "hotkey 0 (below range) → hotkey nil (got \(String(describing: parsedHotkey("0"))))")
    check(parsedHotkey("notanumber") == .some(nil), "hotkey notanumber → hotkey nil (got \(String(describing: parsedHotkey("notanumber"))))")
    check(parsedHotkey("4") == .some(4), "hotkey 4 (in range) → hotkey 4 (sanity, got \(String(describing: parsedHotkey("4"))))")
}

func test_legacy_pin_migrates_to_pinned_and_hotkey() {
    print("\nTest — a legacy `pin: 3` (pre-revamp frontmatter) parses as pinned=true, hotkey=3:")
    let md = "---\nname: Legacy\nkeywords: []\npin: 3\n---\n\nbody"
    let p = PromptStore.parse(md, filename: "legacy.md")
    check(p?.pinned == true, "legacy pin sets pinned=true (got \(String(describing: p?.pinned)))")
    check(p?.hotkey == 3, "legacy pin sets hotkey=3 (got \(String(describing: p?.hotkey)))")
}

@main
enum TestMain {
    static func main() {
        test_deterministic_winner_on_conflict()
        test_three_way_conflict()
        test_non_conflicting_hotkeys_pass_through()
        test_no_hotkey_ignored()
        test_out_of_range_hotkeys_rejected_at_parse()
        test_legacy_pin_migrates_to_pinned_and_hotkey()

        print("\n=== Hotkey-Resolve Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous; pure resolveHotkeys + parse range guard + legacy migration).")
        print("Tier B (a live conflict surfaced in the Library window) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
