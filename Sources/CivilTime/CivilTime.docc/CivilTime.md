# ``CivilTime``

Calendar dates and wall-clock times with no time zone attached.

## Overview

A *civil* value is what a calendar or a wall clock shows: February 29, 2024,
or 09:30. Unlike Foundation's `Date`, which is a point on the global timeline,
a civil value means the same thing everywhere. A birthday stored as a
``PlainDate`` never shifts by a day when it moves between devices, servers and
databases.

```swift
import CivilTime

let due = PlainDate(year: 2024, month: 1, day: 31)!
due.adding(months: 1)        // 2024-02-29
due.weekday                  // .wednesday
PlainDate("2024-02-30")      // nil
```

The module has no dependencies and does not import Foundation. Every type is a
small `Sendable`, `Hashable`, `Comparable` value that is valid by
construction, reads and writes ISO 8601 text, and encodes with `Codable` as
that text.

To convert to and from `Date` in a time zone, add the `CivilTimeFoundation`
module.

## Topics

### Essentials

- <doc:ChoosingADateType>
- ``PlainDate``
- ``PlainTime``
- ``PlainDateTime``

### Parts of a date

- ``PlainYearMonth``
- ``PlainMonthDay``
- ``Weekday``
- ``ISOWeekDate``

### Spans of the day

- ``PlainTimeRange``
- ``ExtendedTime``

### Amounts of calendar time

- ``DatePeriod``

### Text

- <doc:TextFormats>
- ``CivilTimeParseError``
