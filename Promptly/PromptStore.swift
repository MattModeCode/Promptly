import Foundation
import AppKit

struct Prompt: Equatable {
    let name: String
    let keywords: [String]
    let body: String
    let filename: String
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
    private var fsSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private let defaults = UserDefaults(suiteName: "com.promptly.app")

    func load() {
        // Create ~/Prompts if needed
        try? FileManager.default.createDirectory(at: Self.promptsDir, withIntermediateDirectories: true)

        // Seed on first launch
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.promptsDir.path)) ?? []
        if files.filter({ $0.hasSuffix(".md") }).isEmpty {
            seedPrompts()
        }

        // Load all .md files
        var loaded: [Prompt] = []
        let mdFiles = (try? FileManager.default.contentsOfDirectory(at: Self.promptsDir,
            includingPropertiesForKeys: nil)) ?? []
        for url in mdFiles.filter({ $0.pathExtension == "md" }) {
            if let content = try? String(contentsOf: url, encoding: .utf8),
               let prompt = Self.parse(content, filename: url.lastPathComponent) {
                if loaded.contains(where: { $0.name == prompt.name }) {
                    print("[PromptStore] WARNING: duplicate name '\(prompt.name)' in \(url.lastPathComponent) — skipping")
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

    // MARK: - Mutation

    func save(name: String, keywords: [String], body: String, filename: String) {
        let fname = filename.isEmpty ? newSlug(for: name) : filename
        let url = Self.promptsDir.appendingPathComponent(fname)
        try? Self.serialize(name: name, keywords: keywords, body: body)
            .write(to: url, atomically: true, encoding: .utf8)
        load()
    }

    /// The on-disk markdown shape (frontmatter + body). Pure + static so the Stage 5 Tier A
    /// test can assert serialize→parse symmetry without touching ~/Prompts.
    static func serialize(name: String, keywords: [String], body: String) -> String {
        let kw = keywords.joined(separator: ", ")
        return "---\nname: \(name)\nkeywords: [\(kw)]\n---\n\n\(body)"
    }

    func delete(_ prompt: Prompt) {
        let url = Self.promptsDir.appendingPathComponent(prompt.filename)
        try? FileManager.default.removeItem(at: url)
        usage.removeValue(forKey: prompt.filename)
        persistUsage()
        load()
    }

    func startWatching() {
        let fd = open(Self.promptsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.load() }
        src.setCancelHandler { close(fd) }
        src.resume()
        fsSource = src
    }

    // MARK: - Private

    private func newSlug(for name: String) -> String {
        var base = name.lowercased()
            .components(separatedBy: .whitespaces).joined(separator: "-")
        base = String(base.filter { $0.isLetter || $0.isNumber || $0 == "-" })
        if base.isEmpty { base = "prompt" }
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: Self.promptsDir.path)) ?? []
        var candidate = base
        var n = 2
        while existing.contains(candidate + ".md") {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate + ".md"
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
        for line in frontmatterLines {
            if line.hasPrefix("name:") {
                name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("keywords:") {
                let raw = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
                let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                keywords = stripped.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        guard let n = name, !n.isEmpty else {
            print("[PromptStore] WARNING: missing 'name:' in \(filename) — skipping")
            return nil
        }
        return Prompt(name: n, keywords: keywords, body: body, filename: filename)
    }

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
