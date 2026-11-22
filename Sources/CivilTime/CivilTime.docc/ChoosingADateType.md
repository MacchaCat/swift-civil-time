# Choosing a type for a date

Pick the type that says what the value means, not how it is stored.

## Overview

Ask one question: *is this value a moment on the global timeline, or a label
on a calendar or a clock?*

A **moment** happens once for everyone at the same time, wherever they are:
when a payment was made, when a message was sent, when a token expires. Store
moments as Foundation's `Date` (or another instant type). Show them in the
viewer's time zone.

A **label** is read off a calendar or a clock and means the same text
everywhere: a birthday, a public holiday, the day an invoice is due, the time
a shop opens, the date in a passport. Store labels as civil values:

| Meaning | Type |
|---|---|
| A day on the calendar | ``PlainDate`` |
| A time on the clock, every day | ``PlainTime`` |
| A day and a clock time, with no place yet | ``PlainDateTime`` |
| A month of a year | ``PlainYearMonth`` |
| A day that recurs every year | ``PlainMonthDay`` |
| An amount like "3 months" | ``DatePeriod`` |

### Why not store a label as a `Date`?

A `Date` must be a specific instant, so storing "February 28" means picking a
time and a time zone, often midnight in the current zone. Another device in a
time zone further west reads that instant back as February 27. The bug is
invisible until a user travels or a server runs in UTC.

### Why not `DateComponents`?

`DateComponents` is a bag of optional fields meant for asking a `Calendar`
questions. It accepts February 30, is not `Comparable`, needs a calendar for
arithmetic, and two values for the same day can compare unequal. A
``PlainDate`` is always a real day and has exactly one representation for it.

### Events in a place

An event such as "the meeting starts at 09:00 in Tokyo on March 3" is a
``PlainDateTime`` plus a time zone. Keep both, and turn them into a `Date` with
`CivilTimeFoundation` when you need the instant. That way the event stays at
09:00 local time even if the zone's rules change before the meeting.
