# swift-civil-time

Calendar dates and wall-clock times for Swift: a birthday, a due date, a
store's opening hours, a SQL `DATE` column. No time zone attached, no
dependencies, and exact ISO 8601 text.

```swift
import CivilTime

let due = PlainDate(year: 2024, month: 1, day: 31)!
due.adding(months: 1)                     // 2024-02-29
due.weekday                               // .wednesday
PlainDate("2024-02-30")                   // nil — not a real date

let opens = PlainTime(hour: 9, minute: 30)!
let meeting = due.at(opens)               // 2024-01-31T09:30:00
```

## Why

Foundation's `Date` is an *instant*, a point on the global timeline. Many values
in real programs are not instants. "My birthday is February 28" is the same day
in Tokyo and in New York. Store it as a `Date` and it has to pick a time of day
and a time zone, and it shifts by a day as soon as it is read somewhere else.

Swift has no type for these values, and the gap shows up in widely used
libraries:

- **swift-openapi-generator** generates OpenAPI `format: date` fields as
  `String`. The project chose that because neither the standard library
  nor Foundation has a date-only type, and they preferred not to invent one
  ([apple/swift-openapi-generator#136](https://github.com/apple/swift-openapi-generator/issues/136)).
- **PostgresNIO** encodes every `Date` as `timestamptz`, so writing one to a
  `DATE` column can store the previous day. The issue was closed with
  workarounds, one of them a hand-written `DateComponents` conformance
  ([vapor/postgres-nio#462](https://github.com/vapor/postgres-nio/issues/462)).
- A request to add local date and time types to Foundation is open. A
  swift-foundation contributor replied that `DateComponents` is designed for these
  cases, and that systems needing a stricter type can define their own
  ([swiftlang/swift-foundation#2002](https://github.com/swiftlang/swift-foundation/issues/2002)).

Other languages solved this long ago: Java's `LocalDate`, .NET's `DateOnly`,
Python's `datetime.date`, Go's `civil.Date`, Rust's `chrono::NaiveDate` and
`jiff::civil::Date`, and JavaScript's `Temporal.PlainDate`. This package brings
the same model to Swift and uses Temporal's names.

### Why not `DateComponents`?

`DateComponents` is a bag of optional fields. It is the right tool for asking a
`Calendar` questions, but not a value type for a date:

| | `DateComponents` | `PlainDate` |
|---|---|---|
| February 30 | accepted | `nil` |
| Compare, sort, use as a range | no | `Comparable`, `Strideable` |
| Add a month | needs a `Calendar` | `date.adding(months: 1)` |
| Codable form | `{"year":2024,"month":2,"day":29}` | `"2024-02-29"` |
| Equal values | can differ by calendar, time zone, unused fields | one representation per day |
| Size | 283 bytes | 6 bytes |
| Needs Foundation | yes | no |

## Types

| Type | Example | Use it for |
|---|---|---|
| `PlainDate` | `2024-02-29` | birthdays, due dates, holidays, SQL `DATE`, OpenAPI `format: date` |
| `PlainTime` | `09:30:00` | opening hours, alarms, SQL `TIME` |
| `PlainDateTime` | `2024-02-29T09:30:00` | local event times, SQL `TIMESTAMP` without time zone |
| `PlainYearMonth` | `2024-02` | billing periods, card expiry, monthly reports |
| `PlainMonthDay` | `--02-29` | recurring yearly dates |
| `DatePeriod` | `P1Y2M10D` | "1 year, 2 months and 10 days" |
| `Weekday` | `.monday` | ISO 8601 day of week |
| `ISOWeekDate` | `2025-W01-1` | ISO week numbering |

All of them are small `Sendable`, `Hashable`, `Comparable` value types. Every
value is valid by construction: the initializers check their input and
return `nil` for dates that do not exist.

## A short tour

```swift
import CivilTime

let date = PlainDate(year: 2024, month: 12, day: 30)!

// Calendar facts
date.weekday                  // .monday
date.dayOfYear                // 365
date.isoWeekDate              // 2025-W01-1
date.lastDayOfMonth           // 2024-12-31
date.next(.friday)            // 2025-01-03

// Arithmetic. Months clamp to the end of the month.
date.adding(days: 2)          // 2025-01-01
PlainDate(year: 2024, month: 2, day: 29)!.adding(years: 1)   // 2025-02-28

// Differences
let born = PlainDate(year: 1990, month: 6, day: 15)!
born.years(until: date)       // 34
born.period(until: date)      // P34Y6M15D
born.days(until: date)        // 12617

// Ranges of dates
for day in date...date.adding(days: 6) { print(day) }
(PlainDate("2024-01-01")!..<PlainDate("2025-01-01")!).count  // 366

// Text and Codable use ISO 8601
struct Event: Codable {
    var day: PlainDate          // "2024-12-30"
    var starts: PlainTime       // "18:30:00"
}
```

`period(until:)` always round-trips: `start.adding(start.period(until: end)) == end`
for any two dates, and all of the period's parts have the same sign.

## Working with `Date` and time zones

`CivilTimeFoundation` converts between civil values and Foundation's `Date`,
`TimeZone` and `DateComponents`:

```swift
import CivilTime
import CivilTimeFoundation

let tokyo = TimeZone(identifier: "Asia/Tokyo")!
let today = PlainDate.today(in: tokyo)
let now = PlainDateTime(Date(), in: tokyo)

let newYork = TimeZone(identifier: "America/New_York")!
let local = PlainDateTime(year: 2024, month: 11, day: 3, hour: 1, minute: 30)!
local.possibleDates(in: newYork)                        // two instants: 1:30 EDT and 1:30 EST
local.date(in: newYork)                                 // the earlier one
local.date(in: newYork, disambiguation: .later)         // the later one

PlainDate(year: 2024, month: 3, day: 10)!.dateInterval(in: newYork).duration  // 23 hours
```

When daylight saving time skips or repeats a wall-clock time, you choose the
result with `Disambiguation` (`.compatible`, `.earlier`, `.later`, as in
Temporal), or inspect every candidate with `possibleDates(in:)`. Edge cases
are tested against real time-zone history, including a midnight that never
happened (America/Santiago), a 30-minute shift (Australia/Lord_Howe) and a
whole day that was skipped (Pacific/Apia, 2011-12-30).

For display, use any `Date.FormatStyle`; the civil fields are shown as they
are, whatever the device's time zone:

```swift
PlainDate(year: 2024, month: 2, day: 29)!.formatted(date: .long)   // "February 29, 2024"
```

## Text formats

Parsing is strict on purpose, so bad data fails loudly instead of turning
into a wrong date:

- Dates are `YYYY-MM-DD` (RFC 3339 `full-date`). Years outside 0000–9999 use
  the ISO 8601 expanded form with a sign and six digits, such as `-000044-03-15`.
- Times are `HH:MM`, `HH:MM:SS` or `HH:MM:SS.fffffffff`, with at most nine
  fractional digits. A leap second `:60` reads as `:59`. `24:00` is rejected.
- Date-times join them with `T` (or `t`, or a space). Text with a UTC offset
  or `Z` is rejected: it names an instant, so parse it as a `Date` and convert.
- Only ASCII digits are accepted. Whitespace, missing zero padding, and
  invalid dates such as February 30 are rejected.

`try PlainDate(parsing:)` throws a `CivilTimeParseError` with the kind of
problem and its byte offset. `PlainDate(_:)` returns `nil`.

## Design notes

- **Calendar.** The proleptic Gregorian calendar of ISO 8601, for years
  -999,999 through 999,999. Year 0 is 1 BC. (Foundation's Gregorian calendar
  switches to Julian dates before October 1582; this package does not.)
- **Month arithmetic** clamps to the last day of the month: January 31 plus one
  month is February 29 or 28. Use `PlainMonthDay.date(inYear:ifMissing:)` when
  you need a different rule for February 29.
- **No leap seconds and no time zones** in the core. Every day has 86,400
  seconds. Time zones live in `CivilTimeFoundation`, which uses the system's
  time-zone database through `TimeZone`.
- **Out-of-range arithmetic traps**, like integer overflow. With a range of
  two million years, this only happens with corrupt or hostile input, so for
  amounts and instants that come from outside your program use the
  non-trapping forms, which return `nil`: `checkedAdding(...)` and
  `PlainDate(checking: date, in: zone)`. Parsing and decoding never trap.
- **Small and fast.** `PlainDate` is 6 bytes and `PlainTime` is 8. The core
  has no dependencies, imports no Foundation, and does all calendar math with
  a few integer operations.

### Performance

Nanoseconds per operation, lower is better. Measured on one machine (Apple
M4 Pro, macOS 27.3, release build), so treat the numbers as indicative. The
code is in [Benchmarks](Benchmarks/Sources/Benchmarks/main.swift); run it with
`swift run -c release --package-path Benchmarks`.

| Operation | swift-civil-time | Foundation |
|---|---:|---:|
| Parse `"2024-02-29"` | 86 | 254 (`Date.ISO8601FormatStyle`) |
| Format as `"2024-02-29"` | 14 | 88 (`Date.ISO8601FormatStyle`) |
| Add one month | 4 | 143 (`Calendar.date(byAdding:)`) |
| Calendar date of a `Date` in a time zone | 25 | 151 (`Calendar.dateComponents`) |

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/MacchaCat/swift-civil-time.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "CivilTime", package: "swift-civil-time"),
        // Only if you need Date / TimeZone conversions:
        .product(name: "CivilTimeFoundation", package: "swift-civil-time"),
    ]),
]
```

Requirements: Swift 6.0 or later. There is no minimum deployment target. The
few APIs that use `Duration` need macOS 13, iOS 16, tvOS 16 or watchOS 9, and
formatting with `Date.FormatStyle` needs macOS 12, iOS 15, tvOS 15 or
watchOS 8.

`CivilTime` uses only the Swift standard library, so it is meant to work
anywhere Swift does: Apple platforms, Linux, Windows, Android and WebAssembly.
It also compiles for 32-bit targets. Its `Codable` conformances are compiled
out under Embedded Swift, which has not been tested yet.

### Using it in a library

If your library exposes dates, depend on `CivilTime` only and put
`PlainDate` in your API. It adds no transitive dependencies and no
Foundation. For database drivers, `daysSinceEpoch` counts from 1970-01-01,
so a Postgres `DATE` (days since 2000-01-01) converts with
`PlainDate(daysSinceEpoch: Int(postgresDays) + 10_957)`.

## Status

The API is new and may still change before 1.0. CI runs the tests on Linux
(Swift 6.0–6.3, debug and release), Windows and macOS, and checks that the
`CivilTime` module stays free of Foundation.

## License

MIT. See [LICENSE](LICENSE).
