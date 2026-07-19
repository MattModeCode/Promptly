import Foundation

/// Pure, `now`-injectable relative-time formatting for the Library window's
/// `used N× · last used …` line (pulled forward from Stage 10 — see
/// docs/stages/STAGE-10-library-polish.md §5.5 for the bucket table).
enum RelativeTime {
    static func format(_ date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))h ago" }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let dayDiff = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if dayDiff == 1 { return "yesterday" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if elapsed < 7 * 86_400 {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    /// The Library window's usage line — `used N× · last used <relative>`. Composes the count
    /// with `format` so the relative-time bucket logic stays in one place (and one test surface).
    static func usageSummary(count: Int, lastUsed: Date, now: Date = Date()) -> String {
        "used \(count)× · last used \(format(lastUsed, now: now))"
    }
}
