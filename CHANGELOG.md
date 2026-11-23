# Changelog

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
