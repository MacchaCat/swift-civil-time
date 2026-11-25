# Changelog

## 0.4.0 (unreleased)

- `CivilTimeFoundation`: `ZonedDateTime`, an exact instant together with its
  time zone and wall-clock time, like Temporal's `ZonedDateTime`.
  - Created from exact seconds and nanoseconds, from a `Date`, or from a
    `PlainDateTime` with a disambiguation, each with a non-trapping form;
    `withTimeZone(_:)` and `checkedWithTimeZone(_:)`; `startOfDay`.
  - `adding(_:disambiguation:)` and `checkedAdding(_:disambiguation:)` share
    their implementation with `Date.adding(_:in:)`.
  - `dateTimeDuration(until:)`, counted as Temporal's `until` does and
    always leading back to the same instant; `duration(until:)`.
  - RFC 9557 text (`2025-05-02T22:00:00+09:00[Asia/Tokyo]`; offsets with
    seconds, for historical local mean time, go beyond the RFC), with
    `OffsetPolicy` (`reject`, `prefer`, `use`, `ignore`) for offsets that do
    not match the time zone. `Codable` decodes with `prefer`.
  - Equality and hashing use the instant and the time zone: its identifier,
    or the exact offset of a fixed-offset zone.
- `CivilTimeParseError.Kind` gains `unknownTimeZone` and `offsetMismatch`.

## 0.3.0 (2026-11-25)

- `DatePeriod` is now `DateDuration`, and `PlainDate.period(until:)` is now
  `dateDuration(until:)`. The old names remain as deprecated aliases.
  Parse errors name the type `DateDuration`.
- `DateTimeDuration`: years, months and days plus hours, minutes, seconds and
  nanoseconds, with the full ISO 8601 duration form (`P1DT12H30M`,
  `PT1.5S`), `Codable`, `PlainDateTime.adding(_:)` and `checkedAdding(_:)`,
  and `PlainDateTime.dateTimeDuration(until:)`, which always round-trips.
  It converts from Swift's `Duration` on every platform, and back through
  `exactDuration` when it has no calendar units.
- `CivilTimeFoundation`: `Date.adding(_:in:disambiguation:)` and
  `checkedAdding(_:in:disambiguation:)` add a `DateTimeDuration` in a time
  zone, with calendar units on the wall clock and clock units as exact time,
  as in Temporal.

## 0.2.0 (2026-11-23)

- `PlainTimeRange`: a daily span of wall-clock time that may cross midnight,
  such as opening hours of 21:00–03:00, with `contains`, `overlaps`,
  occurrences on the calendar, and the text form `21:00:00/03:00:00`
  (an extended end such as `18:00/29:00` is accepted).
- `ExtendedTime`: clock readings past 24:00 counted from a reference day,
  as in Japan's 30-hour clock and GTFS timetables, with conversions to and
  from `PlainDateTime` and `PlainTimeRange`.
- `CivilTimeFoundation`: `Range<PlainDateTime>.dateInterval(in:)`, which maps
  both ends to the first instant the wall clock reaches them, so the interval
  is never reversed by a daylight-saving gap.

## 0.1.0 (2026-11-23)

First release.

- `CivilTime`: `PlainDate`, `PlainTime`, `PlainDateTime`, `PlainYearMonth`,
  `PlainMonthDay`, `DatePeriod`, `Weekday` and `ISOWeekDate`, with calendar
  arithmetic, strict ISO 8601 parsing and formatting, and `Codable`.
  `checkedAdding(...)` returns `nil` instead of trapping for amounts from
  untrusted input. No dependencies and no Foundation.
- `CivilTimeFoundation`: conversions to and from `Date` in a `TimeZone`
  (with non-trapping `init(checking:in:)` forms for untrusted input), with
  explicit handling of skipped and repeated wall-clock times; start and span
  of a day in a time zone; `DateComponents` conversions; display through
  `Date.FormatStyle`.
