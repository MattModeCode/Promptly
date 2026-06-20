// RelativeTimeTests.swift — Tier A autonomous tests for RelativeTime (Feature #4 history view).
//
// Compile + run (x86_64 / Apple Intel):
//     arch -x86_64 swiftc \
//         -target x86_64-apple-macosx12.0 \
//         Promptly/RelativeTime.swift RelativeTimeTests.swift \
//         -o /tmp/RelativeTimeTests && /tmp/RelativeTimeTests
//
// Pure-function tests — no foreign app, no clipboard, no AX trust. Fixed `now`, never
// Date()/Date.now, so "yesterday"/"weekday"/"older" assertions are deterministic regardless
// of when the suite runs (CLAUDE.md honesty rule: never weaken an assertion to go green).

import Foundation

var passed = 0
var failed = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("  PASS: \(message)"); passed += 1 }
    else         { print("  FAIL: \(message)"); failed += 1 }
}

// Fixed reference "now": Friday 2026-06-19, 12:00:00 local time.
private func fixedNow() -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 19; c.hour = 12; c.minute = 0; c.second = 0
    c.timeZone = TimeZone.current
    return Calendar(identifier: .gregorian).date(from: c)!
}

private func minus(_ seconds: TimeInterval, from now: Date) -> Date {
    now.addingTimeInterval(-seconds)
}

func test_just_now() {
    print("\nTest — bucket 1, just now:")
    let now = fixedNow()
    check(RelativeTime.format(minus(0, from: now), now: now) == "just now", "0s ago")
    check(RelativeTime.format(minus(30, from: now), now: now) == "just now", "30s ago")
    check(RelativeTime.format(minus(59, from: now), now: now) == "just now", "59s ago is still just now, not 0m ago")
}

func test_minutes_boundary() {
    print("\nTest — bucket 1/2 boundary at 60s:")
    let now = fixedNow()
    check(RelativeTime.format(minus(60, from: now), now: now) == "1m ago", "60s ago is 1m ago")
    check(RelativeTime.format(minus(90, from: now), now: now) == "1m ago", "90s ago floors to 1m ago")
    check(RelativeTime.format(minus(180, from: now), now: now) == "3m ago", "180s ago is 3m ago")
    check(RelativeTime.format(minus(3599, from: now), now: now) == "59m ago", "3599s ago is 59m ago, just under the hour")
}

func test_hours_same_day() {
    print("\nTest — bucket 3, hours ago, same calendar day:")
    let now = fixedNow()
    check(RelativeTime.format(minus(3600, from: now), now: now) == "1h ago", "3600s ago is 1h ago")
    check(RelativeTime.format(minus(7200, from: now), now: now) == "2h ago", "7200s ago is 2h ago")
    // now is 12:00 local; 11h before is 01:00 same calendar day — still bucket 3, not yesterday.
    check(RelativeTime.format(minus(11 * 3600, from: now), now: now) == "11h ago", "11h ago is still today (01:00) — bucket 3, not yesterday")
}

func test_yesterday() {
    print("\nTest — bucket 4, yesterday relative to fixed now, including midnight boundary:")
    let now = fixedNow() // 2026-06-19 12:00
    // 13h before now crosses local midnight into 2026-06-18 23:00 — bucket 4, not bucket 3.
    check(RelativeTime.format(minus(13 * 3600, from: now), now: now) == "yesterday", "13h ago crosses midnight into yesterday (23:00 prior day)")

    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 18; c.hour = 9
    c.timeZone = TimeZone.current
    let yesterdayMorning = Calendar(identifier: .gregorian).date(from: c)!
    check(RelativeTime.format(yesterdayMorning, now: now) == "yesterday", "2026-06-18 09:00 is yesterday relative to fixed now")
}

func test_weekday_2_to_6_days() {
    print("\nTest — bucket 5, weekday name for 2-6 days back:")
    let now = fixedNow() // Friday 2026-06-19

    var c2 = DateComponents()
    c2.year = 2026; c2.month = 6; c2.day = 17; c2.hour = 9 // Wednesday, 2 days back
    c2.timeZone = TimeZone.current
    let twoDaysBack = Calendar(identifier: .gregorian).date(from: c2)!
    check(RelativeTime.format(twoDaysBack, now: now) == "Wed", "2 days back (Wed) shows weekday name (got \"\(RelativeTime.format(twoDaysBack, now: now))\")")

    var c6 = DateComponents()
    c6.year = 2026; c6.month = 6; c6.day = 13; c6.hour = 9 // Saturday, 6 days back
    c6.timeZone = TimeZone.current
    let sixDaysBack = Calendar(identifier: .gregorian).date(from: c6)!
    check(RelativeTime.format(sixDaysBack, now: now) == "Sat", "6 days back (Sat) shows weekday name (got \"\(RelativeTime.format(sixDaysBack, now: now))\")")
}

func test_seven_day_cutoff() {
    print("\nTest — bucket 5/6 boundary at the 7-day cutoff:")
    let now = fixedNow() // Friday 2026-06-19

    var c7 = DateComponents()
    c7.year = 2026; c7.month = 6; c7.day = 12; c7.hour = 9 // Friday, 7 days back
    c7.timeZone = TimeZone.current
    let sevenDaysBack = Calendar(identifier: .gregorian).date(from: c7)!
    check(RelativeTime.format(sevenDaysBack, now: now) == "Jun 12", "7 days back falls to month/day, not weekday (got \"\(RelativeTime.format(sevenDaysBack, now: now))\")")

    var c6 = DateComponents()
    c6.year = 2026; c6.month = 6; c6.day = 13; c6.hour = 9 // Saturday, 6 days back
    c6.timeZone = TimeZone.current
    let sixDaysBack = Calendar(identifier: .gregorian).date(from: c6)!
    check(RelativeTime.format(sixDaysBack, now: now) == "Sat", "6 days back is still weekday-name bucket (got \"\(RelativeTime.format(sixDaysBack, now: now))\")")
}

func test_seven_day_cutoff_uses_calendar_days_not_raw_seconds() {
    print("\nTest — 7-day cutoff is calendar-day distance, not raw elapsed seconds:")
    // now early in its day; date is 7 calendar days back but late in ITS day, so the raw
    // elapsed-seconds diff (~6.08 days) is under 7*86400 even though it's 7 calendar days back.
    var cNow = DateComponents()
    cNow.year = 2026; cNow.month = 6; cNow.day = 19; cNow.hour = 1
    cNow.timeZone = TimeZone.current
    let now = Calendar(identifier: .gregorian).date(from: cNow)!

    var cDate = DateComponents()
    cDate.year = 2026; cDate.month = 6; cDate.day = 12; cDate.hour = 23
    cDate.timeZone = TimeZone.current
    let date = Calendar(identifier: .gregorian).date(from: cDate)!

    let result = RelativeTime.format(date, now: now)
    check(result == "Jun 12", "7 calendar days back falls to month/day even though raw-second diff is < 7*86400 (got \"\(result)\")")
}

func test_older_month_day() {
    print("\nTest — bucket 6, older than 7 days, month + day, no year:")
    let now = fixedNow()

    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 12; c.hour = 8
    c.timeZone = TimeZone.current
    let date = Calendar(identifier: .gregorian).date(from: c)!
    check(RelativeTime.format(date, now: now) == "Jun 12", "older date formats as \"MMM d\" (got \"\(RelativeTime.format(date, now: now))\")")

    var cLastYear = DateComponents()
    cLastYear.year = 2025; cLastYear.month = 12; cLastYear.day = 25; cLastYear.hour = 8
    cLastYear.timeZone = TimeZone.current
    let lastYear = Calendar(identifier: .gregorian).date(from: cLastYear)!
    check(RelativeTime.format(lastYear, now: now) == "Dec 25", "no year in the string, even across year boundary (got \"\(RelativeTime.format(lastYear, now: now))\")")
}

@main
enum TestMain {
    static func main() {
        test_just_now()
        test_minutes_boundary()
        test_hours_same_day()
        test_yesterday()
        test_weekday_2_to_6_days()
        test_seven_day_cutoff()
        test_seven_day_cutoff_uses_calendar_days_not_raw_seconds()
        test_older_month_day()

        print("\n=== RelativeTime Tier A Results ===")
        print("\(passed) passed, \(failed) failed")
        print("Tier run: A (autonomous, pure functions, fixed `now` — deterministic regardless of wall clock).")
        exit(failed == 0 ? 0 : 1)
    }
}
