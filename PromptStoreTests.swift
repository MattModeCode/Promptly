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

// ---------------------------------------------------------------------------
// Stage 6 — frecency ranking (pure functions; no store/DB).
// ---------------------------------------------------------------------------

private func prompt(_ name: String, _ file: String) -> Prompt {
    Prompt(name: name, keywords: [], body: "", filename: file)
}

func test_frecency_score_basics() {
    print("\nTest — frecencyScore: unused scores 0; recency and frequency both raise it:")
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    check(PromptStore.frecencyScore(count: 0, lastUsed: now, now: now) == 0, "count 0 → score 0")

    let hourAgo = now.addingTimeInterval(-3600)
    let weekAgo = now.addingTimeInterval(-7 * 86_400)
    let recent = PromptStore.frecencyScore(count: 3, lastUsed: hourAgo, now: now)
    let stale  = PromptStore.frecencyScore(count: 3, lastUsed: weekAgo, now: now)
    check(recent > stale, "same count, more recent → higher (\(recent) > \(stale))")

    let many = PromptStore.frecencyScore(count: 10, lastUsed: hourAgo, now: now)
    check(many > recent, "same recency, higher count → higher (\(many) > \(recent))")
}

func test_sorted_by_hotkey() {
    print("\nTest — sortedByHotkey orders ⌘1…⌘9 ascending, unhotkeyed last in incoming order:")
    let p1 = Prompt(name: "Three", keywords: [], body: "", filename: "three.md", pinned: true, hotkey: 3)
    let p2 = Prompt(name: "One", keywords: [], body: "", filename: "one.md", pinned: true, hotkey: 1)
    let p3 = Prompt(name: "NoKeyA", keywords: [], body: "", filename: "a.md", pinned: true)
    let p4 = Prompt(name: "Two", keywords: [], body: "", filename: "two.md", pinned: true, hotkey: 2)
    let p5 = Prompt(name: "NoKeyB", keywords: [], body: "", filename: "b.md", pinned: true)
    let order = PromptStore.sortedByHotkey([p1, p2, p3, p4, p5]).map { $0.name }
    check(order == ["One", "Two", "Three", "NoKeyA", "NoKeyB"],
          "hotkeyed prompts ascend by number, unhotkeyed ones keep their incoming order (got \(order))")
}

func test_rank_orders_by_frecency() {
    print("\nTest — rank orders by frecency:")
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let ps = [prompt("A", "a.md"), prompt("B", "b.md"), prompt("C", "c.md")]
    let usage: [String: PromptUsage] = [
        "a.md": PromptUsage(count: 2, lastUsed: now.addingTimeInterval(-30 * 86_400)),  // old, few
        "b.md": PromptUsage(count: 5, lastUsed: now.addingTimeInterval(-3600)),         // recent, many
        // c.md unused
    ]
    let order = PromptStore.rank(ps, usage: usage, now: now).map { $0.name }
    check(order.first == "B", "most recent+frequent ranks first (got \(order))")
    check(order.last == "C", "unused ranks last (got \(order))")
}

func test_rank_cold_start_keeps_seed_order() {
    print("\nTest — empty usage degrades to loaded (seed) order, stably:")
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let ps = [prompt("first", "1.md"), prompt("second", "2.md"), prompt("third", "3.md")]
    let order = PromptStore.rank(ps, usage: [:], now: now).map { $0.name }
    check(order == ["first", "second", "third"], "cold start preserves load order (got \(order))")
}

// ---------------------------------------------------------------------------
// Stage 8 — folders, manual pins, descriptions (pure serialize/parse + folder derivation).
// ---------------------------------------------------------------------------

func roundTripFull(name: String, keywords: [String], body: String,
                   pinned: Bool = false, hotkey: Int? = nil, description: String? = nil,
                   filename: String = "round-trip.md") -> (md: String, prompt: Prompt?) {
    let md = PromptStore.serialize(name: name, keywords: keywords, body: body,
                                   pinned: pinned, hotkey: hotkey, description: description)
    return (md, PromptStore.parse(md, filename: filename))
}

func test_pinned_round_trips() {
    print("\nTest — pinned survives serialize → parse, independent of hotkey:")
    let (md, p) = roundTripFull(name: "Bug repro", keywords: ["bug"], body: "Steps:", pinned: true)
    check(md.contains("pinned: true"), "serialized frontmatter carries pinned (got \"\(md)\")")
    check(p?.pinned == true, "parsed pinned == true (got \(String(describing: p?.pinned)))")
    check(p?.hotkey == nil, "no hotkey set → nil (got \(String(describing: p?.hotkey)))")
    check(p?.name == "Bug repro", "name still preserved alongside pinned")
}

func test_hotkey_round_trips_without_pinned() {
    print("\nTest — a hotkey survives serialize → parse without implying pinned:")
    let (md, p) = roundTripFull(name: "Bug repro", keywords: ["bug"], body: "Steps:", hotkey: 5)
    check(md.contains("hotkey: 5"), "serialized frontmatter carries the hotkey (got \"\(md)\")")
    check(p?.hotkey == 5, "parsed hotkey == 5 (got \(String(describing: p?.hotkey)))")
    check(p?.pinned == false, "hotkey alone does not imply pinned (got \(String(describing: p?.pinned)))")
}

func test_description_round_trips() {
    print("\nTest — a description survives serialize → parse:")
    let desc = "Structured repro for filing issues"
    let (md, p) = roundTripFull(name: "Bug repro", keywords: [], body: "Steps:", description: desc)
    check(md.contains("description: \(desc)"), "serialized frontmatter carries the description")
    check(p?.description == desc, "parsed description matches exactly (got \(p?.description ?? "nil"))")
}

func test_pinned_and_hotkey_and_description_together() {
    print("\nTest — pinned, hotkey, AND description round-trip together in one file:")
    let desc = "Structured repro for filing issues"
    let (_, p) = roundTripFull(name: "Bug repro", keywords: ["bug", "issue"],
                               body: "Steps:\n1. …", pinned: true, hotkey: 7, description: desc)
    check(p?.pinned == true, "pinned == true (got \(String(describing: p?.pinned)))")
    check(p?.hotkey == 7, "hotkey == 7 (got \(String(describing: p?.hotkey)))")
    check(p?.description == desc, "description preserved (got \(p?.description ?? "nil"))")
    check(p?.keywords == ["bug", "issue"], "keywords preserved (got \(p?.keywords ?? []))")
}

func test_absent_keys_stay_nil_and_byte_clean() {
    print("\nTest — no pinned/hotkey/description → no spurious keys, parsed back as nil/false:")
    let md = PromptStore.serialize(name: "Plain", keywords: ["x"], body: "Body.")
    check(!md.contains("pinned:"), "no spurious 'pinned:' key in markdown (got \"\(md)\")")
    check(!md.contains("hotkey:"), "no spurious 'hotkey:' key in markdown (got \"\(md)\")")
    check(!md.contains("description:"), "no spurious 'description:' key in markdown (got \"\(md)\")")
    let p = PromptStore.parse(md, filename: "plain.md")
    check(p?.pinned == false, "absent pinned parses back as false (got \(String(describing: p?.pinned)))")
    check(p?.hotkey == nil, "absent hotkey parses back as nil (got \(String(describing: p?.hotkey)))")
    check(p?.description == nil, "absent description parses back as nil (got \(p?.description ?? "nil"))")
}

func test_folder_derivation() {
    print("\nTest — folder(forRelativePath:) derives the parent directory:")
    check(PromptStore.folder(forRelativePath: "foo.md") == "", "root prompt → \"\" (got \"\(PromptStore.folder(forRelativePath: "foo.md"))\")")
    check(PromptStore.folder(forRelativePath: "Engineering/foo.md") == "Engineering",
          "one level → \"Engineering\" (got \"\(PromptStore.folder(forRelativePath: "Engineering/foo.md"))\")")
    check(PromptStore.folder(forRelativePath: "A/B/foo.md") == "A/B",
          "nested → \"A/B\" (got \"\(PromptStore.folder(forRelativePath: "A/B/foo.md"))\")")
}

func test_flat_root_prompt_keeps_usage_key() {
    print("\nTest — a flat root prompt keeps its bare-filename usage key (back-compat):")
    let md = PromptStore.serialize(name: "Legacy", keywords: [], body: "Body.")
    let p = PromptStore.parse(md, filename: "foo.md")
    check(p?.filename == "foo.md", "filename unchanged, not prefixed (got \(p?.filename ?? "nil"))")
    check(p?.folder == "", "root prompt → empty folder (got \(p?.folder ?? "nil"))")
}

// ---------------------------------------------------------------------------
// Stage 9 — PromptStore.move(_:toFolder:): rewrites the relative filename across
// folders, migrates the frecency usage key, and stays collision-safe. Uses a real
// temp ~/Prompts-shaped directory (move touches the filesystem), cleaned up after.
// ---------------------------------------------------------------------------

private func withTempPromptsDir(_ body: (URL) -> Void) {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("PromptStoreMoveTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    body(tmp)
}

func test_move_rewrites_relative_filename() {
    print("\nTest — move(_:toFolder:) rewrites the relative filename into the target folder:")
    withTempPromptsDir { dir in
        let store = PromptStore(promptsDir: dir)
        store.load()
        store.save(name: "Foo", keywords: [], body: "Body.", filename: "")
        store.load()
        guard let p = store.prompts.first(where: { $0.name == "Foo" }) else {
            check(false, "setup: prompt should exist after save+load"); return
        }
        check(p.filename == "foo.md", "sanity: starts at root (got \(p.filename))")
        store.move(p, toFolder: "Engineering")
        guard let moved = store.prompts.first(where: { $0.name == "Foo" }) else {
            check(false, "moved prompt should still be findable after move"); return
        }
        check(moved.filename == "Engineering/foo.md", "filename rewritten into the folder (got \(moved.filename))")
        check(moved.folder == "Engineering", "folder updated (got \(moved.folder))")
        check(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Engineering/foo.md").path),
              "file physically present at the new path")
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("foo.md").path),
              "file no longer present at the old path")
    }
}

func test_move_migrates_usage_key() {
    print("\nTest — move(_:toFolder:) migrates the usage/frecency key, not just the file:")
    withTempPromptsDir { dir in
        let store = PromptStore(promptsDir: dir)
        store.load()
        store.save(name: "Foo", keywords: [], body: "Body.", filename: "")
        store.load()
        guard let p = store.prompts.first(where: { $0.name == "Foo" }) else {
            check(false, "setup: prompt should exist after save+load"); return
        }
        store.recordUse(of: p)
        store.recordUse(of: p)
        store.move(p, toFolder: "Engineering")
        guard store.prompts.first(where: { $0.name == "Foo" }) != nil else {
            check(false, "moved prompt should still be findable after move"); return
        }
        let ranked = store.ranked()
        check(ranked.first?.filename == "Engineering/foo.md",
              "usage history survived the move — still ranks first (got \(ranked.first?.filename ?? "nil"))")
    }
}

func test_move_is_collision_safe_per_folder() {
    print("\nTest — moving into a folder that already has a same-named file doesn't clobber it:")
    withTempPromptsDir { dir in
        let store = PromptStore(promptsDir: dir)
        store.load()
        // Pre-place a file directly at Engineering/foo.md, bypassing save()'s slug minting —
        // its `name` is deliberately different from the prompt we're about to move (load()
        // rejects two prompts with the same display name as duplicates); only its FILENAME
        // collides, which is the actual thing newSlug must guard against.
        let engineeringDir = dir.appendingPathComponent("Engineering")
        try! FileManager.default.createDirectory(at: engineeringDir, withIntermediateDirectories: true)
        try! PromptStore.serialize(name: "Existing", keywords: [], body: "Existing in Engineering.")
            .write(to: engineeringDir.appendingPathComponent("foo.md"), atomically: true, encoding: .utf8)
        store.save(name: "Foo", keywords: [], body: "Root copy to be moved.", filename: "")
        store.load()
        guard let rootFoo = store.prompts.first(where: { $0.filename == "foo.md" }) else {
            check(false, "setup: root foo.md should exist"); return
        }
        store.move(rootFoo, toFolder: "Engineering")
        let engineeringFiles = store.prompts.filter { $0.folder == "Engineering" }
        check(engineeringFiles.count == 2, "both files land in Engineering, neither clobbered (got \(engineeringFiles.count))")
        check(engineeringFiles.contains { $0.filename == "Engineering/foo.md" }, "the pre-existing file keeps its name")
        check(engineeringFiles.contains { $0.filename == "Engineering/foo-2.md" }, "the moved file gets a collision-safe slug (got \(engineeringFiles.map { $0.filename }))")
    }
}

// ---------------------------------------------------------------------------
// Soft delete: delete(_:) moves the file into a hidden trash folder instead of
// removing it, so a mistaken delete is recoverable. Same withTempPromptsDir
// harness as the move tests above (delete touches the filesystem too).
// ---------------------------------------------------------------------------

func test_delete_moves_to_trash_not_removed() {
    print("\nTest — delete(_:) moves the file into .trash instead of erasing it:")
    withTempPromptsDir { dir in
        let store = PromptStore(promptsDir: dir)
        store.load()
        store.save(name: "Foo", keywords: [], body: "Body.", filename: "")
        store.load()
        guard let p = store.prompts.first(where: { $0.name == "Foo" }) else {
            check(false, "setup: prompt should exist after save+load"); return
        }
        store.delete(p)
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("foo.md").path),
              "original file no longer at its old path")
        check(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".trash/foo.md").path),
              "file recoverable under .trash")
        check(!store.prompts.contains(where: { $0.name == "Foo" }), "deleted prompt no longer listed")
    }
}

func test_delete_does_not_reappear_after_reload() {
    print("\nTest — a trashed file stays hidden across a fresh load() (skipsHiddenFiles):")
    withTempPromptsDir { dir in
        let store = PromptStore(promptsDir: dir)
        store.load()
        store.save(name: "Foo", keywords: [], body: "Body.", filename: "")
        store.load()
        guard let p = store.prompts.first(where: { $0.name == "Foo" }) else {
            check(false, "setup: prompt should exist after save+load"); return
        }
        store.delete(p)
        let reloaded = PromptStore(promptsDir: dir)
        reloaded.load()
        check(!reloaded.prompts.contains(where: { $0.name == "Foo" }),
              "a fresh store load also doesn't see the trashed file")
    }
}

func test_delete_is_collision_safe_in_trash() {
    print("\nTest — deleting two prompts that each land on foo.md doesn't clobber the earlier trashed copy:")
    withTempPromptsDir { dir in
        let store = PromptStore(promptsDir: dir)
        store.load()
        store.save(name: "Foo", keywords: [], body: "First version.", filename: "")
        store.load()
        guard let first = store.prompts.first(where: { $0.name == "Foo" }) else {
            check(false, "setup: first prompt should exist after save+load"); return
        }
        store.delete(first)

        store.save(name: "Foo", keywords: [], body: "Second version.", filename: "")
        store.load()
        guard let second = store.prompts.first(where: { $0.name == "Foo" }) else {
            check(false, "setup: second prompt should exist after save+load"); return
        }
        check(second.filename == "foo.md", "second save reuses foo.md now that the first is trashed (got \(second.filename))")
        store.delete(second)

        let trashDir = dir.appendingPathComponent(".trash")
        let trashed = ((try? FileManager.default.contentsOfDirectory(atPath: trashDir.path)) ?? []).sorted()
        check(trashed == ["foo-2.md", "foo.md"], "both deletes land under distinct trash names (got \(trashed))")
        let firstContent = try? String(contentsOf: trashDir.appendingPathComponent("foo.md"), encoding: .utf8)
        let secondContent = try? String(contentsOf: trashDir.appendingPathComponent("foo-2.md"), encoding: .utf8)
        check(firstContent?.contains("First version.") == true, "foo.md in trash still holds the first delete's content")
        check(secondContent?.contains("Second version.") == true, "foo-2.md in trash holds the second delete's content")
    }
}

@main
enum TestMain {
    static func main() {
        test_basic_symmetry()
        test_multiline_and_tokens()
        test_capture_like_payload()
        test_malformed_rejected()
        test_frecency_score_basics()
        test_sorted_by_hotkey()
        test_rank_orders_by_frecency()
        test_rank_cold_start_keeps_seed_order()
        test_pinned_round_trips()
        test_hotkey_round_trips_without_pinned()
        test_description_round_trips()
        test_pinned_and_hotkey_and_description_together()
        test_absent_keys_stay_nil_and_byte_clean()
        test_folder_derivation()
        test_flat_root_prompt_keeps_usage_key()
        test_move_rewrites_relative_filename()
        test_move_migrates_usage_key()
        test_move_is_collision_safe_per_folder()
        test_delete_moves_to_trash_not_removed()
        test_delete_does_not_reappear_after_reload()
        test_delete_is_collision_safe_in_trash()

        print("\n=== Stage 5 + 6 + 8 + 9 + 10 Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous; pure serialize/parse + frecency). Tier B (capture in a")
        print("real app; a week of use confirming ordering) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
