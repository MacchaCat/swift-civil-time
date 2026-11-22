# Changelog

## 0.1.0 (unreleased)

First release.

- `CivilTime`: `PlainDate`, `PlainTime`, `PlainDateTime`, `PlainYearMonth`,
  `PlainMonthDay`, `DatePeriod`, `Weekday` and `ISOWeekDate`, with calendar
  arithmetic, strict ISO 8601 parsing and formatting, and `Codable`.
  No dependencies and no Foundation.
- `CivilTimeFoundation`: conversions to and from `Date` in a `TimeZone`, with
  explicit handling of skipped and repeated wall-clock times; start and span
  of a day in a time zone; `DateComponents` conversions; display through
  `Date.FormatStyle`.
