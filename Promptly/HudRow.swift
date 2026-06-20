// HudRow.swift — Stage 7 adaptive ⌥1–9 position assignment (pure).
//
// "A keyboard, not a piano" (FEATURES §7): fixed 9 positions, always in the same place;
// only the CONTENT reorders, by what you actually use. The number is the constant the hand
// learns — the label under it changes between opens, never during one.
//
// This is the load-bearing rule: assignment is computed once at present-time and held
// CONSTANT until dismiss (like the screen in invariant 4). Same input → same map; no live
// reshuffle. Pure + UI-free so the Tier A test needs no panel.

import Foundation

enum HudRow {
    static let slotCount = 9

    /// Map fixed slots 1…9 to the top prompts in ranking order. `ranked` is the frecency
    /// ordering (which already folds in recency/time), so the row "adapts by app/time" between
    /// opens simply by being recomputed from a fresh ranking each present. Deterministic:
    /// identical `ranked` → identical map, which is exactly what freezes positions within a
    /// single appearance.
    static func assign(_ ranked: [Prompt]) -> [Int: Prompt] {
        var map: [Int: Prompt] = [:]
        for (i, prompt) in ranked.prefix(slotCount).enumerated() {
            map[i + 1] = prompt
        }
        return map
    }
}
