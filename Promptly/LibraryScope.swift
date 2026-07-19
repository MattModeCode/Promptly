import Foundation

/// The Library window's (Stage 9) left-hand sidebar selection — which subset of the catalog
/// the middle list shows. Pure + Equatable so Tier A can test it directly, with no `NSView`
/// dependency.
enum LibraryScope: Equatable {
    case all
    case pinned
    case recent
    case folder(String)
}

extension LibraryScope {
    /// How many prompts `.recent` surfaces, top-N by frecency.
    static let recentLimit = 20

    /// Scope first, then the filter text composes on top via the same fuzzy match
    /// `PromptStore.filter` uses. `usage` is passed in (rather than reaching into a store) to
    /// keep this pure and Tier-A testable.
    static func filter(_ scope: LibraryScope,
                       prompts: [Prompt],
                       usage: [String: PromptUsage],
                       query: String,
                       now: Date = Date()) -> [Prompt] {
        let ranked = PromptStore.rank(prompts, usage: usage, now: now)
        let scoped: [Prompt]
        switch scope {
        case .all:
            scoped = ranked
        case .pinned:
            scoped = PromptStore.sortedByHotkey(ranked.filter { $0.pinned })
        case .recent:
            scoped = Array(ranked.prefix(recentLimit))
        case .folder(let name):
            scoped = ranked.filter { $0.folder == name }
        }
        return query.isEmpty ? scoped : PromptStore.fuzzyFilter(query, in: scoped)
    }

    /// The folder a drag-drop onto this sidebar row should move a prompt INTO, or nil when the
    /// row is a virtual scope with no backing folder. `.all` accepts a drop to root (""),
    /// `.folder(name)` into that folder; `.pinned`/`.recent` reject it (nil). Pure + Tier-A
    /// testable — the drop plumbing lives in the window controller.
    static func dropDestination(_ scope: LibraryScope) -> String? {
        switch scope {
        case .all: return ""
        case .folder(let name): return name
        case .pinned, .recent: return nil
        }
    }
}
