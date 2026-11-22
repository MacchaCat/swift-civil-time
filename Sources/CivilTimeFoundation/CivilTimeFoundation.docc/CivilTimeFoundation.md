# ``CivilTimeFoundation``

Convert civil dates and times to and from Foundation's `Date`, `TimeZone` and
`DateComponents`.

## Overview

A civil value becomes a moment in time only in a place. This module connects
the two worlds:

```swift
import CivilTime
import CivilTimeFoundation

let tokyo = TimeZone(identifier: "Asia/Tokyo")!
let today = PlainDate.today(in: tokyo)
let meeting = PlainDateTime(year: 2025, month: 3, day: 3, hour: 9)!
let instant = meeting.date(in: tokyo)
PlainDateTime(instant, in: TimeZone(identifier: "Europe/London")!)  // 2025-03-03T00:00:00
```

Conversions use the system's time-zone database through `TimeZone`. Wall-clock
times that a time zone skips or repeats are resolved explicitly; see
<doc:DaylightSavingTime>.

## Topics

### Articles

- <doc:DaylightSavingTime>
