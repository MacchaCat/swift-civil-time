# Changelog

## 0.1.0 (unreleased)

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
