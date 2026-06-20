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

    /// Map fixed slots 1…9: manual pins claim their chosen number FIRST, then the frecency
    /// ordering fills whatever slots remain (Stage 8 hybrid). `pins` is the user's explicit
    /// slot→prompt map; `ranked` is the frecency ordering (which already folds in recency/time),
    /// so unpinned slots still "adapt by app/time" between opens. A pinned prompt never also
    /// appears in a frecency-filled slot (deduped by filename). Deterministic: identical
    /// (pins, ranked) → identical map — exactly what freezes positions within a single appearance.
    static func assign(pins: [Int: Prompt], ranked: [Prompt]) -> [Int: Prompt] {
        var map = pins
        let pinnedFiles = Set(pins.values.map { $0.filename })
        var fill = ranked.lazy.filter { !pinnedFiles.contains($0.filename) }.makeIterator()
        for slot in 1...slotCount where map[slot] == nil {
            if let prompt = fill.next() { map[slot] = prompt }
        }
        return map
    }
}
