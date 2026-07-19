#!/bin/bash
# test.sh — compile + run the Tier A (autonomous) test suite, native arm64.
#
# Each test file is a standalone executable defining its own @main runner, so they must be built
# and run ONE AT A TIME (they'd collide if linked together). Tier B — the 5-app cross-app paste
# matrix in docs/TASKS.md — needs a human and real Accessibility grants and is NOT run here.
#
# PasteProbeTests SKIPS its AX-gated checks (and still exits 0) when Accessibility is not granted
# to the test binary, so a green run here proves typecheck + clipboard round-trip + the clobber-ban
# decision table, but NOT the full read-back path — that needs Tier B.
#
# Usage:  ./scripts/test.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/promptly-tests.XXXXXX)"
TARGET="arm64-apple-macosx12.0"
pass=0; fail=0; failed_names=()

run_test() { # $1 = test file (repo-root), $2 = extra frameworks, $3.. = Promptly/ source files
  local test="$1"; shift
  local fw="$1"; shift
  local name; name="$(basename "$test" .swift)"
  local srcs=(); local s; for s in "$@"; do srcs+=("$ROOT/Promptly/$s"); done
  printf "→ %-22s " "$name"
  if ! swiftc $fw -target "$TARGET" "${srcs[@]}" "$ROOT/$test" -o "$TMP/$name" >"$TMP/$name.build.log" 2>&1; then
    echo "BUILD FAIL"; sed 's/^/    /' "$TMP/$name.build.log" | head -25
    fail=$((fail+1)); failed_names+=("$name (build)"); return
  fi
  if "$TMP/$name" >"$TMP/$name.run.log" 2>&1; then
    local skips; skips="$(grep -c -i 'SKIP' "$TMP/$name.run.log" 2>/dev/null)" || true
    if [ "${skips:-0}" -gt 0 ] 2>/dev/null; then echo "PASS ($skips skipped)"; else echo "PASS"; fi
    pass=$((pass+1))
  else
    local rc=$?; echo "FAIL (exit $rc)"; sed 's/^/    /' "$TMP/$name.run.log" | tail -25
    fail=$((fail+1)); failed_names+=("$name")
  fi
}

echo "== Promptly Tier A test suite (native arm64) =="
run_test TokenEngineTests.swift   ""                                                 TokenEngine.swift
run_test AskFlowTests.swift       ""                                                 TokenEngine.swift
run_test PreviewSpansTests.swift  ""                                                 TokenEngine.swift
run_test RelativeTimeTests.swift  ""                                                 RelativeTime.swift
run_test PromptStoreTests.swift   "-framework AppKit"                                PromptStore.swift
run_test HistoryOrderTests.swift  "-framework AppKit"                                PromptStore.swift
run_test RewriteFolderPathTests.swift "-framework AppKit"                            PromptStore.swift
run_test HotkeyResolveTests.swift "-framework AppKit"                                PromptStore.swift
run_test HotkeyDisplayTests.swift "-framework AppKit"                                HotkeyManager.swift
run_test LibraryScopeTests.swift  "-framework AppKit"                                PromptStore.swift LibraryScope.swift
run_test PasteProbeTests.swift    "-framework AppKit -framework ApplicationServices" PasteCore.swift
# Palette-present crash regression. PromptRowView lives in PanelController, which pulls in the whole
# UI module, so this links every source except main.swift (which owns the @main entry point).
run_test PanelRowSelectionCrashTests.swift "-framework AppKit -framework Carbon -framework ApplicationServices" \
  Capture.swift HotkeyCaptureWindow.swift HotkeyManager.swift LibraryScope.swift LibraryWindowController.swift \
  Palette.swift PanelController.swift PasteCore.swift PasteService.swift PromptStore.swift RelativeTime.swift \
  ThemedControls.swift TokenEngine.swift
echo "== $pass passed, $fail failed =="

if [ "$fail" -ne 0 ]; then printf 'FAILED: %s\n' "${failed_names[@]}"; exit 1; fi
rm -rf "$TMP"
