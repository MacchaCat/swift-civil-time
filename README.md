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
| `PlainTimeRange` | `21:00:00/03:00:00` | daily spans such as opening hours, including ones past midnight |
| `ExtendedTime` | `26:30:00` | times past 24:00, as in Japan's 30-hour clock and GTFS timetables |
| `DateDuration` | `P1Y2M10D` | "1 year, 2 months and 10 days" |
| `DateTimeDuration` | `P1DT12H30M` | the same plus hours, minutes and seconds |
| `ZonedDateTime` | `2025-05-02T22:00:00+09:00[Asia/Tokyo]` | a moment in a place: flights, meetings (in `CivilTimeFoundation`) |
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
born.dateDuration(until: date)  // P34Y6M15D
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

`dateDuration(until:)` always round-trips: `start.adding(start.dateDuration(until: end)) == end`
for any two dates, and all of the duration's parts have the same sign.

## Durations

There are three kinds of duration, for three kinds of question:

| Type | Example | Length |
|---|---|---|
| `DateDuration` | `P1Y2M10D` | depends on the date: a month is 28 to 31 days |
| `DateTimeDuration` | `P1DT12H30M` | calendar part as above, plus an exact clock part |
| Swift's `Duration` | `.seconds(5400)` | always exact |

```swift
let stay = DateTimeDuration(days: 1, hours: 12, minutes: 30)
PlainDateTime("2025-05-02T21:00")!.adding(stay)              // 2025-05-04T09:30:00

let start = PlainDateTime("2024-01-31T22:00")!
start.dateTimeDuration(until: PlainDateTime("2024-03-01T01:00")!)   // P1MT3H

DateTimeDuration("PT1.5S")!.exactDuration                    // .milliseconds(1500)
DateTimeDuration(days: 1).exactDuration                      // nil: a day is not always 24 hours
DateTimeDuration(.seconds(90))                               // PT90S
```

The text form is the full ISO 8601 duration, with fractional seconds to the
nanosecond. Equality compares the components, so `PT90M` and `PT1H30M` are
different values even though they last equally long. `DateDuration` was
called `DatePeriod` before 0.3.0; the old name still works but is deprecated.

## Ranges of dates and times

Every type is `Comparable`, so Swift's own `Range` and `ClosedRange` work for
spans of time, with `contains`, `overlaps` and `clamped(to:)`. `PlainDate` and
`PlainYearMonth` are also `Strideable`, so their ranges can be counted and
iterated.

```swift
// A vacation, including both ends
let vacation = PlainDate("2025-05-01")!...PlainDate("2025-05-14")!
vacation.count                                     // 14
vacation.contains(PlainDate("2025-05-14")!)        // true
for day in vacation where day.weekday == .saturday { print(day) }  // 2025-05-03, 2025-05-10

// Business hours
let businessHours = PlainTime("09:00")!..<PlainTime("18:00")!
businessHours.contains(PlainTime("17:59")!)        // true
businessHours.contains(PlainTime("18:00")!)        // false

// A delivery window spanning several days
let delivery = PlainDateTime("2025-05-01T18:00")!..<PlainDateTime("2025-05-03T12:00")!
let slot = PlainDateTime("2025-05-03T11:00")!..<PlainDateTime("2025-05-03T13:00")!
delivery.overlaps(slot)                            // true
slot.clamped(to: delivery)                         // 2025-05-03T11:00:00..<2025-05-03T12:00:00

// Months
let secondQuarter = PlainYearMonth(year: 2025, month: 4)!...PlainYearMonth(year: 2025, month: 6)!
secondQuarter.map(\.daysInMonth)                   // [30, 31, 30]
PlainYearMonth(year: 2024, month: 2)!.days         // 2024-02-01...2024-02-29
```

### Past midnight

A `Range` needs its lower bound first, so opening hours that cross midnight,
such as 21:00–03:00, can't be a `Range<PlainTime>`. Use `PlainTimeRange`, a
span on the 24-hour clock that may wrap:

```swift
let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)
bar.contains(PlainTime("01:30")!)                          // true
bar.crossesMidnight                                        // true
bar.occurrence(startingOn: PlainDate("2025-05-02")!)       // 2025-05-02T21:00:00..<2025-05-03T03:00:00
bar.occurrence(containing: PlainDateTime("2025-05-03T01:30")!)   // the same Friday-night occurrence
PlainTimeRange("18:00/24:00")                              // 18:00 until midnight
```

Some schedules write times after midnight as 25:00, 26:00 and so on, to keep a
night attached to the day it started: Japan's 30-hour clock (30時間制) in TV
listings and late-night opening hours, and GTFS public-transit timetables.
`ExtendedTime` reads and writes them, and since extended times never wrap,
Swift's own ranges work:

```swift
let lateShow = ExtendedTime("25:30")!..<ExtendedTime("26:00")!
lateShow.occurrence(on: PlainDate("2025-05-02")!)          // 2025-05-03T01:30:00..<2025-05-03T02:00:00

PlainTimeRange("18:00/29:00")                              // 18:00 until 05:00
bar.extendedRange                                          // 21:00:00..<27:00:00
```

With `CivilTimeFoundation`, any `Range<PlainDateTime>` becomes a `DateInterval`
in a time zone. A night when the clocks change is an hour shorter or longer,
and a range that falls entirely in a skipped hour becomes empty instead of
crashing:

```swift
let newYork = TimeZone(identifier: "America/New_York")!
bar.occurrence(startingOn: PlainDate("2024-11-02")!).dateInterval(in: newYork).duration   // 7 hours
```

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

To add a duration to an instant in a time zone, the calendar part follows
the wall clock and the clock part is exact, as in JavaScript's Temporal. One
day later keeps the time of day; 24 hours later does not when the clocks
change:

```swift
let noon = PlainDateTime("2024-03-09T12:00")!.date(in: newYork)
noon.adding(DateTimeDuration(days: 1), in: newYork)     // 2024-03-10 12:00, 23 hours later
noon.adding(DateTimeDuration(hours: 24), in: newYork)   // 2024-03-10 13:00
```

`ZonedDateTime` keeps an instant, its time zone and the wall-clock time
together, like Temporal's `ZonedDateTime`. Its text form follows RFC 9557,
as Temporal does:

```swift
let tokyo = TimeZone(identifier: "Asia/Tokyo")!
let departure = ZonedDateTime(PlainDateTime("2025-05-02T22:00")!, in: tokyo)
departure.description              // "2025-05-02T22:00:00+09:00[Asia/Tokyo]"

let arrival = departure.adding(DateTimeDuration(hours: 10, minutes: 5))
    .withTimeZone(TimeZone(identifier: "America/Los_Angeles")!)
arrival.dateTime                   // 2025-05-02T16:05:00, local time on arrival

let parsed = try ZonedDateTime(parsing: "2024-11-03T01:30:00-05:00[America/New_York]")
parsed.utcOffset                   // -18000: the second 01:30, in standard time
```

The UTC offset in a string picks between the two occurrences of a repeated
time. When it no longer matches the time zone's rules, parsing rejects it by
default, while decoding keeps the wall-clock time, so stored values survive
rule changes. `dateTimeDuration(until:)` counts calendar units on the wall
clock and the rest as exact time, the way Temporal's `until` does, and always
leads back to the same instant. UTC offsets with seconds, which only
historical local mean time needs, go beyond RFC 9557, so other parsers may
reject them.

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
    .package(url: "https://github.com/MacchaCat/swift-civil-time.git", from: "0.4.0"),
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
