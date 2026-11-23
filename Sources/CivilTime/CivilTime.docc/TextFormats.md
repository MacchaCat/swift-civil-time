# Text formats

Every civil type reads and writes one ISO 8601 form, strictly.

## Overview

| Type | Written as | Also read |
|---|---|---|
| ``PlainDate`` | `2024-02-29`, `-000044-03-15` | `+002024-02-29` |
| ``PlainTime`` | `09:30:00`, `23:59:59.5` | `09:30`, `09:30:00,5`, `23:59:60` (as `23:59:59`) |
| ``PlainDateTime`` | `2024-02-29T09:30:00` | `t` or a space instead of `T` |
| ``PlainYearMonth`` | `2024-02` | |
| ``PlainMonthDay`` | `--02-29` | `02-29` |
| ``DatePeriod`` | `P1Y2M10D`, `P0D`, `-P1M`, `P1Y-2M` | `P2W` (as 14 days), `+P1D` |
| ``PlainTimeRange`` | `21:00:00/03:00:00` | `21:00/03:00`, an extended end such as `18:00/24:00` or `18:00/29:00` |
| ``ExtendedTime`` | `26:30:00`, `09:00:00` | `26:30`, hours of two to four digits |
| ``ISOWeekDate`` | `2025-W01-1` | (not parsed) |

These are the forms used by RFC 3339, JSON APIs, OpenAPI (`format: date`),
SQL databases and JavaScript's Temporal, so values round-trip through all of
them unchanged.

### What is rejected

Parsing fails, rather than guessing, for:

- dates that do not exist, such as `2023-02-29` or `2024-04-31`;
- missing zero padding (`2024-2-9`), basic format (`20240229`), or
  surrounding whitespace;
- digits other than ASCII `0`–`9`, such as full-width `２０２４`;
- `24:00`, minutes or seconds above their range, and more than nine
  fractional digits;
- a UTC offset, `Z`, or a bracketed time-zone name after a date-time. Such
  text names an instant; parse it as a `Date` and convert it with
  `CivilTimeFoundation`.

### Errors

`init(parsing:)` throws a ``CivilTimeParseError`` that names the problem and
its UTF-8 byte offset:

```swift
do {
    _ = try PlainDate(parsing: "2023-02-29")
} catch {
    print(error)  // Cannot parse "2023-02-29" as PlainDate: value out of range at offset 8
}
```

The `LosslessStringConvertible` initializer, `PlainDate("…")`, returns `nil`
instead.

### Codable

Each type encodes as a single string in its written form, regardless of the
encoder's date strategy, and decoding accepts only that form. Decoding
failures are reported as `DecodingError.dataCorrupted` with the parse error's
description.
