// TokenEngine.swift — pure token substitution (DESIGN §8 token grammar).
//
// Deliberately separate from PasteCore.swift (which stays verbatim from the spike):
// tokens are new app logic that rides on top of the proven paste path, never inside it.
// Everything here is a pure function over its inputs so the Tier A tests need no foreign
// app, no clipboard, no AX trust.
//
// Grammar (DESIGN §8 / the seed "token cheatsheet"):
//   {{clipboard}}  — clipboard contents at paste time
//   {{date}}       — today's date, ISO 8601 (yyyy-MM-dd)
//   {{cursor}}     — caret position after paste (precise on the B path; end-of-text on A)
//   {{ask:label}}  — interactive fill-in (Stage 4; parsed here, resolved by AskFlow)
// Unknown tokens stay LITERAL so a typo is visible. Empty known tokens substitute empty
// with a logged warning.

import Foundation
import os.log

private let tokenLog = OSLog(subsystem: "com.promptly.app", category: "tokens")

/// Result of expanding a prompt body. `cursorOffset` is a UTF-16 code-unit offset into
/// `text` (matching what `kAXSelectedTextRange` expects), or nil when there is no
/// `{{cursor}}`. Only the FIRST `{{cursor}}` is honored; any later ones are also stripped.
struct TokenExpansion: Equatable {
    let text: String
    let cursorOffset: Int?
}

/// One discovered `{{ask:label}}` token, in document order (Stage 4).
struct AskToken: Equatable {
    let label: String
}

/// One discovered `{{…}}` token in a prompt body, for the preview pane (Stage 9). Pure,
/// UI-free data — the panel maps `kind` to attributes; `range` covers the full literal
/// token including its braces, matching what `raw` captures in `expand`/`fillAsks`.
struct TokenSpan: Equatable {
    enum Kind: Equatable { case clipboard, date, cursor, ask, unknown }
    let range: Range<String.Index>
    let kind: Kind
}

enum TokenEngine {

    /// ISO-8601 calendar date (yyyy-MM-dd), locale-stable so it's deterministic to test.
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Static-token expansion (Stage 3)

    /// Substitute static tokens at paste time. `{{ask:...}}` is left UNTOUCHED here — it is
    /// resolved interactively (Stage 4) BEFORE this runs, so by the time a body reaches
    /// `expand` any asks are already filled in. Unknown tokens stay literal.
    static func expand(_ body: String,
                       clipboard: String?,
                       now: Date,
                       warn: (String) -> Void = TokenEngine.defaultWarn) -> TokenExpansion {
        var result = ""
        var cursorOffset: Int? = nil
        let chars = Array(body)
        let n = chars.count
        var i = 0
        while i < n {
            if chars[i] == "{", i + 1 < n, chars[i + 1] == "{",
               let close = closingBraces(chars, from: i + 2) {
                let inner = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespaces)
                let raw = String(chars[i..<(close + 2)])    // the literal "{{…}}"
                switch resolveStatic(inner, clipboard: clipboard, now: now, warn: warn) {
                case .text(let s):
                    result += s
                case .cursor:
                    if cursorOffset == nil { cursorOffset = result.utf16.count }
                case .literal:
                    result += raw
                }
                i = close + 2
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return TokenExpansion(text: result, cursorOffset: cursorOffset)
    }

    // MARK: - Ask discovery (Stage 4)

    /// All `{{ask:label}}` tokens in document order. Empty labels (`{{ask:}}`) are skipped.
    static func asks(in body: String) -> [AskToken] {
        var out: [AskToken] = []
        let chars = Array(body)
        let n = chars.count
        var i = 0
        while i < n {
            if chars[i] == "{", i + 1 < n, chars[i + 1] == "{",
               let close = closingBraces(chars, from: i + 2) {
                let inner = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespaces)
                if inner.hasPrefix("ask:") {
                    let label = String(inner.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    if !label.isEmpty { out.append(AskToken(label: label)) }
                }
                i = close + 2
                continue
            }
            i += 1
        }
        return out
    }

    // MARK: - Preview spans (Stage 9)

    /// Every `{{…}}` token in `body`, in document order, classified by kind — the pure seam
    /// the preview pane's cell maps to attributes (dim/emphasize the whole `{{…}}` chip).
    /// Unknown/malformed tokens are still included, classified `.unknown` — "unknown" means
    /// classified as such, not excluded from the list. Plain text with no tokens yields `[]`.
    static func spans(in body: String) -> [TokenSpan] {
        var out: [TokenSpan] = []
        let chars = Array(body)
        let n = chars.count
        var i = 0
        while i < n {
            if chars[i] == "{", i + 1 < n, chars[i + 1] == "{",
               let close = closingBraces(chars, from: i + 2) {
                let inner = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespaces)
                let kind: TokenSpan.Kind
                switch inner {
                case "clipboard": kind = .clipboard
                case "date": kind = .date
                case "cursor": kind = .cursor
                default:
                    if inner.hasPrefix("ask:"),
                       !String(inner.dropFirst(4)).trimmingCharacters(in: .whitespaces).isEmpty {
                        kind = .ask
                    } else {
                        kind = .unknown
                    }
                }
                let start = body.index(body.startIndex, offsetBy: i)
                let end = body.index(body.startIndex, offsetBy: close + 2)
                out.append(TokenSpan(range: start..<end, kind: kind))
                i = close + 2
                continue
            }
            i += 1
        }
        return out
    }

    /// Substitute `{{ask:label}}` tokens with collected answers (by document order). The
    /// first occurrence of each successive ask consumes the next answer. Static tokens are
    /// left alone here — `expand` handles them afterward. Unknown / non-ask tokens stay literal.
    static func fillAsks(_ body: String, answers: [String]) -> String {
        var result = ""
        var answerIdx = 0
        let chars = Array(body)
        let n = chars.count
        var i = 0
        while i < n {
            if chars[i] == "{", i + 1 < n, chars[i + 1] == "{",
               let close = closingBraces(chars, from: i + 2) {
                let inner = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespaces)
                let raw = String(chars[i..<(close + 2)])
                if inner.hasPrefix("ask:"),
                   !String(inner.dropFirst(4)).trimmingCharacters(in: .whitespaces).isEmpty {
                    if answerIdx < answers.count { result += answers[answerIdx]; answerIdx += 1 }
                    // If we run out of answers, drop the token (leave empty) rather than paste it.
                } else {
                    result += raw   // not an ask token → preserve verbatim for `expand`
                }
                i = close + 2
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    // MARK: - Private

    private enum Resolved { case text(String); case cursor; case literal }

    private static func resolveStatic(_ inner: String, clipboard: String?, now: Date,
                                      warn: (String) -> Void) -> Resolved {
        switch inner {
        case "clipboard":
            let v = clipboard ?? ""
            if v.isEmpty { warn("{{clipboard}} expanded empty — clipboard had no text") }
            return .text(v)
        case "date":
            return .text(isoDate.string(from: now))
        case "cursor":
            return .cursor
        default:
            // ask:label tokens are resolved before expand(); anything else is unknown → literal.
            return .literal
        }
    }

    /// Index of the `{` in the first `}}` at or after `from`, or nil if none. (Returns the
    /// index of the first closing brace, so the caller adds 2 to skip past `}}`.)
    private static func closingBraces(_ chars: [Character], from: Int) -> Int? {
        var j = from
        while j + 1 < chars.count {
            if chars[j] == "}", chars[j + 1] == "}" { return j }
            j += 1
        }
        return nil
    }

    static func defaultWarn(_ s: String) {
        os_log("token: %{public}@", log: tokenLog, type: .info, s)
    }
}

// MARK: - AskFlow (Stage 4) — pure state machine for interactive {{ask:label}} fill-in

/// Drives the in-place fill-in flow for a prompt's `{{ask:label}}` tokens. Pure and
/// UI-free so the Tier A tests need no panel: the `PanelController` owns the keystrokes
/// and the surface; this owns only "which label is active, collect answers in order,
/// assemble the final body." A prompt with no asks yields `nil` (caller pastes directly).
struct AskFlow: Equatable {
    let labels: [String]
    private(set) var answers: [String] = []
    private(set) var index: Int = 0

    /// nil when the body contains no `{{ask:…}}` tokens.
    init?(body: String) {
        let toks = TokenEngine.asks(in: body)
        guard !toks.isEmpty else { return nil }
        labels = toks.map { $0.label }
    }

    var currentLabel: String { labels[min(index, labels.count - 1)] }
    /// 1-based position for a quiet "k of N" indicator.
    var progress: (current: Int, total: Int) { (min(index + 1, labels.count), labels.count) }
    var isComplete: Bool { index >= labels.count }

    /// Record the current answer and advance. ↵ and Tab both call this. Returns true while
    /// more asks remain, false once the last answer has been collected (caller then pastes).
    mutating func advance(with answer: String) -> Bool {
        guard !isComplete else { return false }
        answers.append(answer)
        index += 1
        return !isComplete
    }

    /// esc cancels the WHOLE expansion (FEATURES §7) — reset to the first ask, no answers.
    mutating func reset() {
        answers.removeAll()
        index = 0
    }

    /// The prompt body with every ask replaced by its collected answer (static tokens are
    /// left for `expand` to resolve afterward).
    func finalText(body: String) -> String {
        TokenEngine.fillAsks(body, answers: answers)
    }
}
