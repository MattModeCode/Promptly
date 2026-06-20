// RelativeTime.swift — human-relative timestamp formatting for the history view (Feature #4).
//
// Pure function over its inputs (date, now) so it's deterministic to test — no Date()/Date.now
// inside. Locale-stable DateFormatters (en_US_POSIX + fixed dateFormat, never dateStyle) mirror
// TokenEngine.isoDate's construction for the same reason: independent of the user's locale/region.

import Foundation

enum RelativeTime {

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "MMM d"
        return f
    }()

    /// `date` is always in the past relative to `now` for this feature (diff assumed >= 0).
    static func format(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "just now"
        }
        if diff < 3600 {
            return "\(Int(diff / 60))m ago"
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return "\(Int(diff / 3600))h ago"
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        if calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        // Calendar-day distance, not raw elapsed seconds: a date 7 calendar days back late in
        // its day can be < 7*86400s away from an early-in-the-day `now`, and vice versa.
        let daysBack = calendar.dateComponents([.day],
                                                from: calendar.startOfDay(for: date),
                                                to: calendar.startOfDay(for: now)).day!
        if daysBack < 7 {
            return weekdayFormatter.string(from: date)
        }
        return monthDayFormatter.string(from: date)
    }
}
