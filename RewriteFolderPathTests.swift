// RewriteFolderPathTests.swift — Tier A autonomous tests for PromptStore.rewriteFolderPath, the
// pure folder-prefix rewrite behind a folder rename (the on-disk move lives in move(_:toFolder:)).
//
// Compile + run (native arm64):
//     swiftc -framework AppKit -target arm64-apple-macosx12.0 \
//         Promptly/PromptStore.swift RewriteFolderPathTests.swift \
//         -o /tmp/RewriteFolderPathTests && /tmp/RewriteFolderPathTests
//
// Pure string logic — no filesystem. Honesty rule (CLAUDE.md): never weaken an assertion to go
// green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

func test_nested_file_rewrites_folder_prefix() {
    print("\nTest — a nested file's folder prefix is rewritten, leaf preserved:")
    let out = PromptStore.rewriteFolderPath("Eng/foo.md", from: "Eng", to: "Backend")
    check(out == "Backend/foo.md", "Eng/foo.md → Backend/foo.md (got \(out))")
}

func test_root_file_unchanged() {
    print("\nTest — a root file (no folder) is returned unchanged:")
    let out = PromptStore.rewriteFolderPath("foo.md", from: "Eng", to: "Backend")
    check(out == "foo.md", "root file untouched (got \(out))")
}

func test_multi_segment_folder_matches_full_prefix() {
    print("\nTest — a multi-segment folder matches the FULL prefix, not just the first segment:")
    let out = PromptStore.rewriteFolderPath("a/b/foo.md", from: "a/b", to: "c")
    check(out == "c/foo.md", "a/b/foo.md → c/foo.md (got \(out))")
    // old "a" matches only the leading "a/" segment, leaving "b/foo.md" beneath the new folder.
    let partial = PromptStore.rewriteFolderPath("a/b/foo.md", from: "a", to: "c")
    check(partial == "c/b/foo.md", "old \"a\" rewrites only the \"a\" segment (got \(partial))")
}

func test_empty_new_moves_to_root() {
    print("\nTest — new == \"\" moves the file to root (drops the folder):")
    let out = PromptStore.rewriteFolderPath("Eng/foo.md", from: "Eng", to: "")
    check(out == "foo.md", "Eng/foo.md → foo.md at root (got \(out))")
}

func test_non_matching_prefix_unchanged() {
    print("\nTest — a path that doesn't start with old/ is returned unchanged:")
    let out = PromptStore.rewriteFolderPath("Other/foo.md", from: "Eng", to: "Backend")
    check(out == "Other/foo.md", "non-matching folder untouched (got \(out))")
    // The trailing slash guards the segment boundary: "Eng" must not match "Engineering/".
    let similar = PromptStore.rewriteFolderPath("Engineering/foo.md", from: "Eng", to: "Backend")
    check(similar == "Engineering/foo.md", "\"Eng\" does not match \"Engineering/\" (got \(similar))")
}

@main
enum TestMain {
    static func main() {
        test_nested_file_rewrites_folder_prefix()
        test_root_file_unchanged()
        test_multi_segment_folder_matches_full_prefix()
        test_empty_new_moves_to_root()
        test_non_matching_prefix_unchanged()

        print("\n=== rewriteFolderPath Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous; pure path rewrite). The on-disk folder rename that calls it")
        print("is exercised via move(_:toFolder:) and Tier B.")
        exit(failed == 0 ? 0 : 1)
    }
}
