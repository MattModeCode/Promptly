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
    /// Shows in the "pinned" section of the palette/Library — purely organizational, independent
    /// of `hotkey`. A prompt can be pinned with no hotkey, have a hotkey while unpinned, both, or
    /// neither.
    let pinned: Bool
    /// Explicit ⌘-number (1…9) or nil. Never auto-assigned by frecency — a hotkey only ever
    /// fires the prompt that explicitly declares it.
    let hotkey: Int?
    /// Optional one-line summary, shown in the Library list (Stage 8).
    let description: String?

    init(name: String, keywords: [String], body: String, filename: String,
         folder: String = "", pinned: Bool = false, hotkey: Int? = nil, description: String? = nil) {
        self.name = name
        self.keywords = keywords
        self.body = body
        self.filename = filename
        self.folder = folder
        self.pinned = pinned
        self.hotkey = hotkey
        self.description = description
    }

    /// UI alias — the frontmatter key stays `name` for back-compat, surfaced as "title".
    var title: String { name }
}

/// A hotkey collision surfaced at load: two files declared the same ⌘-number. Resolution is
/// deterministic (lowest filename wins) and NON-destructive — the loser's file is left untouched;
/// the Library window surfaces the conflict. Pure + Equatable so it is Tier-A testable.
struct HotkeyConflict: Equatable {
    let slot: Int
    let winner: String   // filename that keeps the slot
    let loser: String    // filename demoted to no-hotkey for assignment
}

/// Per-prompt usage for frecency ranking (Stage 6): how often and how recently it was used.
struct PromptUsage: Codable, Equatable {
    var count: Int
    var lastUsed: Date
}

final class PromptStore {
    static let promptsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Prompts")

    /// Defaults to the real `~/Prompts`; overridable so tests can point at a temp directory
    /// instead of ever touching the user's real library.
    let promptsDir: URL
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

    init(promptsDir: URL = PromptStore.promptsDir) {
        self.promptsDir = promptsDir
    }

    func load() {
        // Create ~/Prompts if needed
        try? FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)

        // Seed on first launch. Counts the whole tree (not just the top level), so a library
        // that lives entirely in subfolders is not mistaken for empty and re-seeded.
        var urls = markdownURLs()
        if urls.isEmpty {
            seedPrompts()
            urls = markdownURLs()
        }

        // Load all .md files (recursive). `filename` is the path relative to ~/Prompts, so a
        // subfolder prompt is keyed "Engineering/foo.md" and a root prompt stays "foo.md".
        var loaded: [Prompt] = []
        for url in urls {
            let rel = relativePath(of: url)
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
    private func markdownURLs() -> [URL] {
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
    func relativePath(of url: URL) -> String {
        // `url` comes from FileManager's enumerator, which returns the fully resolved path
        // (e.g. /var -> /private/var under macOS's top-level symlinks). `URL.resolvingSymlinksInPath()`
        // does NOT resolve /var//tmp/etc (Foundation special-cases them as already-canonical), so
        // comparing promptsDir.path directly against it silently fails the prefix check below and
        // every file falls back to its bare last path component, losing its folder entirely. Only
        // realpath(3) gives the same canonical form the enumerator uses.
        let base = Self.realPath(of: promptsDir)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        let full = url.path
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : url.lastPathComponent
    }

    private static func realPath(of url: URL) -> String {
        var buf = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buf) != nil else { return url.path }
        return String(cString: buf)
    }

    /// Folder = the parent directory of a relative path ("" for root, else "Engineering").
    static func folder(forRelativePath rel: String) -> String {
        let comps = rel.components(separatedBy: "/")
        return comps.count > 1 ? comps.dropLast().joined(separator: "/") : ""
    }

    func filter(_ query: String) -> [Prompt] {
        if query.isEmpty { return ranked() }
        return Self.fuzzyFilter(query, in: prompts)
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

    /// A single prompt's usage (count/lastUsed), for the Library window's (Stage 9) usage line.
    /// `nil` when never used.
    func usage(for filename: String) -> PromptUsage? { usage[filename] }

    /// Snapshot of all usage data, for `LibraryScope.filter` (Stage 9) to rank `.recent` by
    /// frecency without duplicating PromptStore's internal frecency-store access.
    var allUsage: [String: PromptUsage] { usage }

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

    // MARK: - Mutation

    func save(name: String, keywords: [String], body: String,
              folder: String = "", pinned: Bool = false, hotkey: Int? = nil, description: String? = nil,
              filename: String) {
        let fname = filename.isEmpty ? newSlug(for: name, in: folder) : filename
        let url = promptsDir.appendingPathComponent(fname)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.serialize(name: name, keywords: keywords, body: body,
                            pinned: pinned, hotkey: hotkey, description: description)
            .write(to: url, atomically: true, encoding: .utf8)
        suppressReloadUntil = Date().addingTimeInterval(0.3)
        load()
    }

    /// The on-disk markdown shape (frontmatter + body). Pure + static so the Tier A test can
    /// assert serialize→parse symmetry without touching ~/Prompts. `pinned`/`hotkey`/`description`
    /// are emitted only when present, so an unpinned/no-hotkey/undescribed file stays byte-clean
    /// (no spurious keys). `pinned` and `hotkey` are independent — either, both, or neither.
    static func serialize(name: String, keywords: [String], body: String,
                          pinned: Bool = false, hotkey: Int? = nil, description: String? = nil) -> String {
        let kw = keywords.joined(separator: ", ")
        var fm = "---\nname: \(name)\nkeywords: [\(kw)]"
        if pinned { fm += "\npinned: true" }
        if let hotkey = hotkey { fm += "\nhotkey: \(hotkey)" }
        if let description = description, !description.isEmpty { fm += "\ndescription: \(description)" }
        fm += "\n---\n\n\(body)"
        return fm
    }

    /// `~/Prompts/.trash` — dot-prefixed so `markdownURLs()`'s `.skipsHiddenFiles` already keeps
    /// it out of the library/HUD with no extra filtering.
    private var trashDir: URL { promptsDir.appendingPathComponent(".trash") }

    /// Soft delete: moves the file into `trashDir` instead of erasing it, so a mistaken delete is
    /// recoverable (manually, from Finder — there is no restore UI yet). The Library UI looks
    /// identical to a hard delete either way, since the file just leaves `prompts` either way.
    func delete(_ prompt: Prompt) {
        let url = promptsDir.appendingPathComponent(prompt.filename)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let destURL = trashDir.appendingPathComponent(uniqueTrashName(for: prompt.filename))
        try? FileManager.default.moveItem(at: url, to: destURL)
        usage.removeValue(forKey: prompt.filename)
        persistUsage()
        load()
    }

    /// Flattens a (possibly folder-prefixed) relative filename to a trash-safe leaf name, then
    /// applies the same numeric-suffix collision avoidance as `newSlug` — trash is a single flat
    /// directory, so two prompts from different folders (or two deletes over time) can share a
    /// leaf name even though they never collided in the live tree.
    private func uniqueTrashName(for relativePath: String) -> String {
        let leaf = (relativePath as NSString).lastPathComponent
        let base = (leaf as NSString).deletingPathExtension
        let ext = (leaf as NSString).pathExtension
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: trashDir.path)) ?? []
        var candidate = leaf
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(n).\(ext)"
            n += 1
        }
        return candidate
    }

    /// Moves a prompt's file into `folder` (Stage 9) and migrates its frecency usage key —
    /// without this, a reorganize would silently reset `used N×` history, since `filename` is
    /// the usage-dict key (see the doc comment on `Prompt.filename`).
    func move(_ prompt: Prompt, toFolder folder: String) {
        let newFilename = newSlug(for: baseName(of: prompt.filename), in: folder)
        let oldURL = promptsDir.appendingPathComponent(prompt.filename)
        let newURL = promptsDir.appendingPathComponent(newFilename)
        try? FileManager.default.createDirectory(
            at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: oldURL, to: newURL)
        if let u = usage[prompt.filename] {
            usage[newFilename] = u
            usage.removeValue(forKey: prompt.filename)
            persistUsage()
        }
        suppressReloadUntil = Date().addingTimeInterval(0.3)
        load()
    }

    /// Deletes a folder: every prompt inside is either soft-deleted (mirrors `delete`) or moved to
    /// `destination` (mirrors `move`, "" = root/General). Then removes the now-empty directory.
    func deleteFolder(_ folder: String, moveTo destination: String?) {
        let affected = prompts.filter { $0.folder == folder }
        for prompt in affected {
            if let destination {
                move(prompt, toFolder: destination)
            } else {
                delete(prompt)
            }
        }
        try? FileManager.default.removeItem(at: promptsDir.appendingPathComponent(folder))
    }

    /// The leaf filename (no directory, no extension) `newSlug` expects as its `name` input —
    /// reuses the existing slug minting so a move gets the same folder-scoped collision safety
    /// as a fresh save.
    private func baseName(of relativePath: String) -> String {
        let leaf = (relativePath as NSString).lastPathComponent
        return (leaf as NSString).deletingPathExtension
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
            [promptsDir.path] as CFArray,
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
        let dir = folder.isEmpty ? promptsDir : promptsDir.appendingPathComponent(folder)
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
        var pinned = false
        var hotkey: Int?
        var legacyPin: Int?
        var sawPinnedKey = false
        var sawHotkeyKey = false
        var description: String?
        for line in frontmatterLines {
            if line.hasPrefix("name:") {
                name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("keywords:") {
                let raw = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
                let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                keywords = stripped.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if line.hasPrefix("pinned:") {
                let raw = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                pinned = (raw == "true")
                sawPinnedKey = true
            } else if line.hasPrefix("hotkey:") {
                let raw = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                // Valid hotkey is 1…9. Out-of-range/garbage → no hotkey.
                if let v = Int(raw), hotkeySlots.contains(v) { hotkey = v }
                sawHotkeyKey = true
            } else if line.hasPrefix("pin:") {
                // Legacy (pre-revamp) frontmatter: `pin: N` meant both pinned AND hotkey N.
                // Migrated on read only — files are rewritten in the new two-key shape only when
                // next saved through the editor.
                let raw = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if let v = Int(raw), hotkeySlots.contains(v) { legacyPin = v }
            } else if line.hasPrefix("description:") {
                let raw = line.dropFirst(12).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { description = raw }
            }
        }
        if let legacy = legacyPin {
            if !sawHotkeyKey { hotkey = legacy }
            if !sawPinnedKey { pinned = true }
        }
        guard let n = name, !n.isEmpty else {
            print("[PromptStore] WARNING: missing 'name:' in \(filename) — skipping")
            return nil
        }
        return Prompt(name: n, keywords: keywords, body: body, filename: filename,
                      folder: folder(forRelativePath: filename), pinned: pinned, hotkey: hotkey,
                      description: description)
    }

    /// Valid ⌘-hotkey numbers (1...9).
    static let hotkeySlots = 1...9

    // MARK: - Hotkey resolution (pure, testable)

    /// Resolve declared hotkeys into a slot→prompt map. Deterministic: the lowest filename wins
    /// a contested slot; the loser is reported as a `HotkeyConflict` and treated as no-hotkey
    /// for assignment, with its file left UNTOUCHED (no silent rewrite at load). Pure so the
    /// Tier A test needs no filesystem. Independent of `pinned` — a hotkey conflict has nothing
    /// to do with which prompts are pinned.
    static func resolveHotkeys(_ prompts: [Prompt]) -> (hotkeys: [Int: Prompt], conflicts: [HotkeyConflict]) {
        var hotkeys: [Int: Prompt] = [:]
        var conflicts: [HotkeyConflict] = []
        for p in prompts.sorted(by: { $0.filename < $1.filename }) {
            guard let slot = p.hotkey else { continue }
            if let winner = hotkeys[slot] {
                conflicts.append(HotkeyConflict(slot: slot, winner: winner.filename, loser: p.filename))
            } else {
                hotkeys[slot] = p
            }
        }
        return (hotkeys, conflicts)
    }

    /// The current hotkey slot→prompt map (conflict winners only).
    func hotkeyAssignment() -> [Int: Prompt] { Self.resolveHotkeys(prompts).hotkeys }

    /// Orders prompts by ⌘-hotkey (1…9 ascending) first, then any without a hotkey, in their
    /// incoming relative order. Used for the pinned strip so ⌘1 always renders before ⌘2, etc. —
    /// a stable sort, since `sort(by:)` is not guaranteed stable but `Int?` comparisons here only
    /// ever differentiate hotkeyed-vs-not or distinct hotkey numbers (hotkeys are unique post-
    /// conflict-resolution), so ties never occur between two hotkeyed prompts.
    static func sortedByHotkey(_ prompts: [Prompt]) -> [Prompt] {
        prompts.sorted { lhs, rhs in
            switch (lhs.hotkey, rhs.hotkey) {
            case let (l?, r?): return l < r
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// Fuzzy-match + rank `prompts` against `query` (assumed non-empty). Pure and static so
    /// `LibraryScope.filter` (Stage 9) can reuse the exact same matching the palette uses,
    /// scoped to an arbitrary subset, without a `PromptStore` instance.
    static func fuzzyFilter(_ query: String, in prompts: [Prompt]) -> [Prompt] {
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

    private static func fuzzyScore(_ query: String, in text: String) -> Int? {
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
            let dest = promptsDir.appendingPathComponent(seed.lastPathComponent)
            try? FileManager.default.copyItem(at: seed, to: dest)
        }
    }
}
