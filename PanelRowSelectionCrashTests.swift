// PanelRowSelectionCrashTests.swift — Tier A regression for the palette-present crash surfaced by
// hotkey rebinding.
//
// The crash (two identical .ips reports): -[NSTableRowView viewAtColumn:] raises NSRangeException
// when the row has no column views. AppKit sets `isSelected` during *static* row configuration
// (_setPropertiesForRowView:atRow:isStatic:) BEFORE it installs the column views — a path taken when
// the palette relayouts (resizePanel → setFrame) while Promptly is the active app, e.g. right after
// the "Rebind Hotkey…" window called NSApplication.activate. PromptRowView.isSelected.didSet called
// view(atColumn: 0) unguarded → unhandled ObjC exception → the app crashed the instant the palette
// opened. It read as "the rebound hotkey crashes it" but was independent of the combo.
//
// This test toggles isSelected on a bare PromptRowView (zero columns), reproducing that exact state.
//   Pre-fix:  the process traps in objc_exception_throw before the PASS line prints (exit != 0).
//   Post-fix: the numberOfColumns guard returns early, PASS prints, exit 0.
// Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.
//
// Compile + run (native arm64) — all app sources except main.swift, which owns the @main entry point
// (HotkeyCaptureWindow.swift only *mentions* main.swift symbols in a comment, so excluding it is safe):
//   swiftc -framework AppKit -framework Carbon -framework ApplicationServices \
//       -target arm64-apple-macosx12.0 \
//       $(ls Promptly/*.swift | grep -v '/main\.swift$') PanelRowSelectionCrashTests.swift \
//       -o /tmp/PanelRowSelectionCrashTests && /tmp/PanelRowSelectionCrashTests

import AppKit

@main
enum TestMain {
    static func main() {
        // A row view with zero column views — exactly the state during static row configuration.
        let row = PromptRowView(frame: NSRect(x: 0, y: 0, width: 560, height: 38))
        guard row.numberOfColumns == 0 else {
            print("  FAIL: test premise broken — a bare row view unexpectedly has \(row.numberOfColumns) columns")
            exit(1)
        }

        // Pre-fix: view(atColumn: 0) fires here → NSRangeException → SIGTRAP. Post-fix: guard returns.
        // didSet runs on every assignment, so both transitions exercise the guarded path.
        row.isSelected = true
        row.isSelected = false

        print("  PASS: PromptRowView.isSelected toggled with no column views — no exception")
        print("\n=== Panel row-selection crash Tier A Results ===")
        print("1 passed, 0 failed")
        print("Tier run: A (autonomous; reproduces the exact throw site headlessly).")
        print("Tier B (press a rebound hotkey → palette opens without crashing) is the author's.")
        exit(0)
    }
}
