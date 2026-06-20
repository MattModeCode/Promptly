import Foundation
import AppKit
import CoreServices   // FSEventStream — recursive watch over ~/Prompts and its subfolders

struct Prompt: Equatable {
    let name: String
    let keywords: [String]
    let body: String
    /// Path RELATIVE to ~/Prompts ("foo.md" or "Engineering/foo.md"). It is the usage/frecency
    /// key, the dedup key, and the file locator — so a folder move must migrate the usage key.
    let filename: String
    /// Derived from the file's parent directory: "" for a root prompt, else "Engineering".
    /// Never serialized to frontmatter — the directory IS the folder (Stage 8).
    let folder: String
    /// Manually pinned ⌥-number (1…9) or nil. Pins claim their slot first; frecency fills the rest.
    let pinnedSlot: Int?
    /// Optional one-line summary, shown in the Library list (Stage 8).
    let description: String?

    init(name: String, keywords: [String], body: String, filename: String,
         folder: String = "", pinnedSlot: Int? = nil, description: String? = nil) {
        self.name = name
        self.keywords = keywords
        self.body = body
        self.filename = filename
        self.folder = folder
        self.pinnedSlot = pinnedSlot
        self.description = description
    }

    /// UI alias — the frontmatter key stays `name` for back-compat, surfaced as "title".
    var title: String { name }
}

/// A pin collision surfaced at load: two files declared the same ⌥-number. Resolution is
/// deterministic (lowest filename wins) and NON-destructive — the loser's file is left untouched;
/// the Library window surfaces the conflict. Pure + Equatable so it is Tier-A testable.
struct PinConflict: Equatable {
    let slot: Int
    let winner: String   // filename that keeps the slot
    let loser: String    // filename demoted to unpinned for assignment
}

/// Per-prompt usage for frecency ranking (Stage 6): how often and how recently it was used.
struct PromptUsage: Codable, Equatable {
    var count: Int
    var lastUsed: Date
}

final class PromptStore {
    static let promptsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Prompts")

    private(set) var prompts: [Prompt] = []
    private var usage: [String: PromptUsage] = [:]
    private var eventStream: FSEventStreamRef?
    /// Suppress the FSEvents reload triggered by our OWN save/delete writes (load() already ran
    /// directly), so an in-app edit doesn't double-reload. Brief window; external edits still fire.
    private var suppressReloadUntil: Date = .distantPast
    private let defaults = UserDefaults(suiteName: "com.promptly.app")

    /// Fired at the end of every load() so the Library window (Stage 9) can refresh. Optional —
    /// no subscriber in Stage 8.
    var onReload: (() -> Void)?

    func load() {
        // Create ~/Prompts if needed
        try? FileManager.default.createDirectory(at: Self.promptsDir, withIntermediateDirectories: true)

        // Seed on first launch. Counts the whole tree (not just the top level), so a library
        // that lives entirely in subfolders is not mistaken for empty and re-seeded.
        var urls = Self.markdownURLs()
        if urls.isEmpty {
            seedPrompts()
            urls = Self.markdownURLs()
        }

        // Load all .md files (recursive). `filename` is the path relative to ~/Prompts, so a
        // subfolder prompt is keyed "Engineering/foo.md" and a root prompt stays "foo.md".
        var loaded: [Prompt] = []
        for url in urls {
            let rel = Self.relativePath(of: url)
            if let content = try? String(contentsOf: url, encoding: .utf8),
               let prompt = Self.parse(content, filename: rel) {
                if loaded.contains(where: { $0.name == prompt.name }) {
                    print("[PromptStore] WARNING: duplicate name '\(prompt.name)' in \(rel) — skipping")
                } else {
                    loaded.append(prompt)
                }
            }
        }
        prompts = loaded

        // Restore usage. Prefer the Stage-6 frecency store; migrate the Stage-1 recency dict
        // (a bare last-used timestamp) to count=1 if that's all we have.
        if let data = defaults?.data(forKey: "usage"),
           let decoded = try? JSONDecoder().decode([String: PromptUsage].self, from: data) {
            usage = decoded
        } else if let stored = defaults?.dictionary(forKey: "lastUsed") as? [String: Double] {
            usage = stored.mapValues { PromptUsage(count: 1, lastUsed: Date(timeIntervalSince1970: $0)) }
        }

        onReload?()
    }

    /// Every `.md` under ~/Prompts (recursive), in a stable path order so load order is
    /// deterministic (frecency cold-start and dedup both lean on it).
    private static func markdownURLs() -> [URL] {
        let en = FileManager.default.enumerator(
            at: promptsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var urls: [URL] = []
        while let u = en?.nextObject() as? URL {
            if u.pathExtension == "md" { urls.append(u) }
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// Path of `url` relative to ~/Prompts (e.g. "Engineering/foo.md").
    static func relativePath(of url: URL) -> String {
        let base = promptsDir.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        let full = url.path
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : url.lastPathComponent
    }

    /// Folder = the parent directory of a relative path ("" for root, else "Engineering").
    static func folder(forRelativePath rel: String) -> String {
        let comps = rel.components(separatedBy: "/")
        return comps.count > 1 ? comps.dropLast().joined(separator: "/") : ""
    }

    func filter(_ query: String) -> [Prompt] {
        if query.isEmpty { return ranked() }
        let q = query.lowercased()
        return prompts
            .compactMap { p -> (Prompt, Int)? in
                let score = fuzzyScore(q, in: p.name.lowercased())
                    ?? fuzzyScore(q, in: p.keywords.joined(separator: " ").lowercased())
                guard let s = score else { return nil }
                return (p, s)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    func recordUse(of prompt: Prompt) {
        var u = usage[prompt.filename] ?? PromptUsage(count: 0, lastUsed: .distantPast)
        u.count += 1
        u.lastUsed = Date()
        usage[prompt.filename] = u
        persistUsage()
    }

    /// Library ordered by frecency (Stage 6). Cold start / never-used prompts fall back to the
    /// loaded (seed) order, so a fresh history is never empty (PRD §8 / Stage 6 §4).
    func ranked(now: Date = Date()) -> [Prompt] {
        Self.rank(prompts, usage: usage, now: now)
    }

    private func persistUsage() {
        if let data = try? JSONEncoder().encode(usage) { defaults?.set(data, forKey: "usage") }
    }

    // MARK: - Frecency (pure, testable — Stage 6 §6)

    /// Usage-weighted recency. Frequency (count) scaled by an exponential recency decay
    /// (3-day half-life): a prompt reached for often AND recently ranks highest, a stale one
    /// fades, and an unused prompt (count 0) scores 0. The judgment is never user-tuned
    /// (PRD principle 2) — it just gets quietly better at predicting the next prompt.
    static func frecencyScore(count: Int, lastUsed: Date, now: Date) -> Double {
        guard count > 0 else { return 0 }
        let halfLifeDays = 3.0
        let ageDays = max(0, now.timeIntervalSince(lastUsed) / 86_400)
        return Double(count) * pow(2.0, -ageDays / halfLifeDays)
    }

    /// Rank prompts by frecency, breaking ties by original (loaded) order so an all-unused
    /// library degrades cleanly to seed order. Pure so the Tier A test needs no store/DB.
    static func rank(_ prompts: [Prompt], usage: [String: PromptUsage], now: Date) -> [Prompt] {
        prompts.enumerated()
            .map { idx, p -> (Prompt, Double, Int) in
                let score = usage[p.filename].map {
                    frecencyScore(count: $0.count, lastUsed: $0.lastUsed, now: now)
                } ?? 0
                return (p, score, idx)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map { $0.0 }
    }

    // MARK: - History (pure, testable — Feature #4)

    /// Usage (fire) history ordered by recency. Only prompts with a usage entry are included
    /// (no usage ⇒ never fired ⇒ not history). Pure so the Tier A test needs no store.
    static func historyOrder(_ prompts: [Prompt], usage: [String: PromptUsage]) -> [(Prompt, Date)] {
        prompts.enumerated()
            .compactMap { idx, p -> (Prompt, Date, Int)? in
                guard let u = usage[p.filename] else { return nil }
                return (p, u.lastUsed, idx)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map { ($0.0, $0.1) }
    }

    func history() -> [(Prompt, Date)] {
        Self.historyOrder(prompts, usage: usage)
    }

    /// Fuzzy search restricted to the history subset (Feature #4) — typing in history mode
    /// filters what you've actually fired, never the full library. Empty query preserves
    /// recency order.
    func filterHistory(_ query: String) -> [Prompt] {
        if query.isEmpty { return history().map { $0.0 } }
        let usedFilenames = Set(usage.keys)
        return filter(query).filter { usedFilenames.contains($0.filename) }
    }

    // MARK: - Mutation

    func save(name: String, keywords: [String], body: String,
              folder: String = "", pinnedSlot: Int? = nil, description: String? = nil,
              filename: String) {
        let fname = filename.isEmpty ? newSlug(for: name, in: folder) : filename
        let url = Self.promptsDir.appendingPathComponent(fname)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.serialize(name: name, keywords: keywords, body: body,
                            pin: pinnedSlot, description: description)
            .write(to: url, atomically: true, encoding: .utf8)
        suppressReloadUntil = Date().addingTimeInterval(0.3)
        load()
    }

    /// The on-disk markdown shape (frontmatter + body). Pure + static so the Tier A test can
    /// assert serialize→parse symmetry without touching ~/Prompts. `pin`/`description` are emitted
    /// only when present, so an unpinned/undescribed file stays byte-clean (no spurious keys).
    static func serialize(name: String, keywords: [String], body: String,
                          pin: Int? = nil, description: String? = nil) -> String {
        let kw = keywords.joined(separator: ", ")
        var fm = "---\nname: \(name)\nkeywords: [\(kw)]"
        if let pin = pin { fm += "\npin: \(pin)" }
        if let description = description, !description.isEmpty { fm += "\ndescription: \(description)" }
        fm += "\n---\n\n\(body)"
        return fm
    }

    func delete(_ prompt: Prompt) {
        let url = Self.promptsDir.appendingPathComponent(prompt.filename)
        try? FileManager.default.removeItem(at: url)
        usage.removeValue(forKey: prompt.filename)
        persistUsage()
        load()
    }

    /// Watch the whole ~/Prompts tree (subfolders included) via FSEvents. The single-fd
    /// DispatchSource used through Stage 7 only saw the top level; folders (Stage 8) need a
    /// recursive watch. Events are coalesced (~200ms) and reload on the main thread.
    func startWatching() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            Unmanaged<PromptStore>.fromOpaque(info).takeUnretainedValue().handleFSEvent()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [Self.promptsDir.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,  // latency seconds — coalesce a burst (e.g. a multi-file move) into one reload
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return }
        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    private func handleFSEvent() {
        if Date() < suppressReloadUntil { return }   // our own save/delete already reloaded
        load()
    }

    deinit {
        if let s = eventStream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }

    // MARK: - Private

    /// A unique relative path for a new prompt, scoped to its target folder so "foo" can exist
    /// in two folders. Returns e.g. "foo.md" (root) or "Engineering/foo.md".
    private func newSlug(for name: String, in folder: String) -> String {
        var base = name.lowercased()
            .components(separatedBy: .whitespaces).joined(separator: "-")
        base = String(base.filter { $0.isLetter || $0.isNumber || $0 == "-" })
        if base.isEmpty { base = "prompt" }
        let dir = folder.isEmpty ? Self.promptsDir : Self.promptsDir.appendingPathComponent(folder)
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var candidate = base
        var n = 2
        while existing.contains(candidate + ".md") {
            candidate = "\(base)-\(n)"
            n += 1
        }
        let leaf = candidate + ".md"
        return folder.isEmpty ? leaf : "\(folder)/\(leaf)"
    }

    static func parse(_ content: String, filename: String) -> Prompt? {
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else {
            print("[PromptStore] WARNING: missing frontmatter in \(filename) — skipping")
            return nil
        }
        var endIdx = -1
        for i in 1..<lines.count {
            if lines[i] == "---" { endIdx = i; break }
        }
        guard endIdx > 0 else {
            print("[PromptStore] WARNING: unclosed frontmatter in \(filename) — skipping")
            return nil
        }
        let frontmatterLines = Array(lines[1..<endIdx])
        let body = lines[(endIdx+1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var name: String?
        var keywords: [String] = []
        var pin: Int?
        var description: String?
        for line in frontmatterLines {
            if line.hasPrefix("name:") {
                name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("keywords:") {
                let raw = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
                let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                keywords = stripped.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if line.hasPrefix("pin:") {
                let raw = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                // Valid pin is 1…9 (mirrors HudRow.slotCount). Out-of-range/garbage → unpinned.
                if let v = Int(raw), pinSlots.contains(v) { pin = v }
            } else if line.hasPrefix("description:") {
                let raw = line.dropFirst(12).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { description = raw }
            }
        }
        guard let n = name, !n.isEmpty else {
            print("[PromptStore] WARNING: missing 'name:' in \(filename) — skipping")
            return nil
        }
        return Prompt(name: n, keywords: keywords, body: body, filename: filename,
                      folder: folder(forRelativePath: filename), pinnedSlot: pin, description: description)
    }

    /// Valid ⌥-pin numbers. Mirrors `HudRow.slotCount` (9); kept here so PromptStore stays free of
    /// a HudRow dependency (its Tier-A test compiles PromptStore alone).
    static let pinSlots = 1...9

    // MARK: - Pinning (pure, testable — Stage 8)

    /// Resolve declared pins into a slot→prompt map. Deterministic: the lowest filename wins a
    /// contested slot; the loser is reported as a `PinConflict` and treated as unpinned for
    /// assignment, with its file left UNTOUCHED (no silent rewrite at load). Pure so the Tier A
    /// test needs no filesystem.
    static func resolvePins(_ prompts: [Prompt]) -> (pins: [Int: Prompt], conflicts: [PinConflict]) {
        var pins: [Int: Prompt] = [:]
        var conflicts: [PinConflict] = []
        for p in prompts.sorted(by: { $0.filename < $1.filename }) {
            guard let slot = p.pinnedSlot else { continue }
            if let winner = pins[slot] {
                conflicts.append(PinConflict(slot: slot, winner: winner.filename, loser: p.filename))
            } else {
                pins[slot] = p
            }
        }
        return (pins, conflicts)
    }

    /// The current pinned slot→prompt map (conflict winners only).
    func pinnedAssignment() -> [Int: Prompt] { Self.resolvePins(prompts).pins }

    private func fuzzyScore(_ query: String, in text: String) -> Int? {
        var qi = query.startIndex
        var score = 0
        var lastMatchIdx = text.startIndex
        for ci in text.indices {
            if qi == query.endIndex { break }
            if text[ci] == query[qi] {
                // Earlier matches score higher; consecutive bonus
                let gap = text.distance(from: lastMatchIdx, to: ci)
                score += max(10 - gap, 1)
                lastMatchIdx = ci
                qi = query.index(after: qi)
            }
        }
        return qi == query.endIndex ? score : nil
    }

    private func seedPrompts() {
        // Look for seed prompts bundled in the app
        guard let bundleURL = Bundle.main.url(forResource: "SeedPrompts", withExtension: nil,
                                               subdirectory: nil) else { return }
        let seeds = (try? FileManager.default.contentsOfDirectory(at: bundleURL,
            includingPropertiesForKeys: nil)) ?? []
        for seed in seeds.filter({ $0.pathExtension == "md" }) {
            let dest = Self.promptsDir.appendingPathComponent(seed.lastPathComponent)
            try? FileManager.default.copyItem(at: seed, to: dest)
        }
    }
}
