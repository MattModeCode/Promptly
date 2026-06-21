// RelativeTimeTests.swift — Tier A autonomous tests for RelativeTime.format (pulled forward
// from Stage 10 for the Library window's `used N× · last used …` usage line).
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc -target x86_64-apple-macosx12.0 \
//         Promptly/RelativeTime.swift RelativeTimeTests.swift \
//         -o /tmp/RelativeTimeTests && /tmp/RelativeTimeTests
//
// Pins a fixed `now` and walks every bucket boundary in docs/stages/STAGE-10-library-polish.md
// §5.5. Honesty rule (CLAUDE.md): never weaken an assertion to go green — fix the cause.

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

// Fixed reference instant, in the machine's LOCAL calendar/timezone — matching RelativeTime's
// own use of TimeZone.current, so day-boundary buckets ("yesterday", weekday) are exercised
// consistently regardless of which timezone the test happens to run in.
private let calendar = Calendar(identifier: .gregorian)
private let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 12))!

func test_just_now() {
    print("\nTest — under 60s → \"just now\":")
    check(RelativeTime.format(now.addingTimeInterval(-30), now: now) == "just now", "30s ago → just now")
    check(RelativeTime.format(now, now: now) == "just now", "0s ago → just now")
}

func test_minutes_ago() {
    print("\nTest — under 60m → \"Nm ago\":")
    check(RelativeTime.format(now.addingTimeInterval(-90), now: now) == "1m ago", "90s ago → 1m ago")
    check(RelativeTime.format(now.addingTimeInterval(-59 * 60), now: now) == "59m ago", "59m ago → 59m ago")
}

func test_hours_ago() {
    print("\nTest — under 24h → \"Nh ago\":")
    check(RelativeTime.format(now.addingTimeInterval(-2 * 3600), now: now) == "2h ago", "2h ago → 2h ago")
    check(RelativeTime.format(now.addingTimeInterval(-23 * 3600), now: now) == "23h ago", "23h ago → 23h ago")
}

func test_yesterday() {
    print("\nTest — same prior calendar day → \"yesterday\":")
    // now is 2026-06-16 12:00 (local); 1am on 2026-06-15 is calendar-two-days-back is NOT what
    // we want — pick a time on 2026-06-15 (the actual calendar-yesterday) that's >24h elapsed,
    // so the hours-ago bucket doesn't claim it first.
    let yesterdayLate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 1))!
    check(RelativeTime.format(yesterdayLate, now: now) == "yesterday",
          "calendar-yesterday → yesterday (got \(RelativeTime.format(yesterdayLate, now: now)))")
}

func test_weekday_under_a_week() {
    print("\nTest — under 7 days (and not yesterday) → the weekday name:")
    let threeDaysAgo = now.addingTimeInterval(-3 * 86_400)
    let expected = { () -> String in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f.string(from: threeDaysAgo)
    }()
    check(RelativeTime.format(threeDaysAgo, now: now) == expected, "3d ago → \(expected) (got \(RelativeTime.format(threeDaysAgo, now: now)))")
}

func test_short_date_at_a_week_or_more() {
    print("\nTest — 7 days or more → a short date:")
    let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
    let expected = { () -> String in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: tenDaysAgo)
    }()
    check(RelativeTime.format(tenDaysAgo, now: now) == expected, "10d ago → \(expected) (got \(RelativeTime.format(tenDaysAgo, now: now)))")
}

@main
enum TestMain {
    static func main() {
        test_just_now()
        test_minutes_ago()
        test_hours_ago()
        test_yesterday()
        test_weekday_under_a_week()
        test_short_date_at_a_week_or_more()

        print("\n=== RelativeTime Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous; pure bucket formatting). Tier B (the usage line reading")
        print("naturally in the real Library window) is the author's.")
        exit(failed == 0 ? 0 : 1)
    }
}
