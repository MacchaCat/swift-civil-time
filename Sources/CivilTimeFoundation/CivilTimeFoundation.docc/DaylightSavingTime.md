# Daylight saving time and other offset changes

How wall-clock times map to instants when a time zone's offset changes.

## Overview

Most wall-clock times happen exactly once in a time zone. Around an offset
change, two things can go wrong:

- **A gap.** When clocks spring forward, some times never happen. In New York
  on 2024-03-10, clocks went from 01:59:59 to 03:00:00, so 02:30 did not exist.
- **An overlap.** When clocks fall back, some times happen twice. In New York
  on 2024-11-03, 01:30 happened once in daylight time (UTC−4) and again an hour
  later in standard time (UTC−5).

Gaps and overlaps are not always one hour and not always at 02:00. Lord Howe
Island shifts by 30 minutes. Chile and Lebanon have skipped midnight itself,
so some days there begin at 01:00. Samoa skipped all of 2011-12-30 when it
moved across the date line.

### Choosing an instant

`PlainDateTime.date(in:disambiguation:)` always returns an instant. The
`disambiguation` argument decides what happens in a gap or an overlap:

| | Overlap (time happens twice) | Gap (time never happens) |
|---|---|---|
| `.compatible` (default) | the earlier instant | moved forward by the gap: 02:30 → 03:30 |
| `.earlier` | the earlier instant | moved back by the gap: 02:30 → 01:30 |
| `.later` | the later instant | moved forward by the gap: 02:30 → 03:30 |

`.compatible` matches `Calendar`, most operating systems and JavaScript's
`Date`. The three options are the same as the `disambiguation` option of
JavaScript's Temporal API.

### Seeing every candidate

`PlainDateTime.possibleDates(in:)` returns every instant that shows the given
wall-clock time: one for most times, two in an overlap, none in a gap. Use it
to reject ambiguous input, or to ask the user which one they meant:

```swift
let candidates = local.possibleDates(in: zone)
switch candidates.count {
case 1: schedule(at: candidates[0])
case 0: askUser("That time doesn't exist on this day.")
default: askUser("Did you mean the first or the second 1:30?")
}
```

### Days

`PlainDate.startOfDay(in:)` returns the first instant of a date, which is not
always midnight, and `PlainDate.dateInterval(in:)` returns the whole day. A
day can last 23, 23.5, 25 hours, or, for a date that was skipped entirely,
no time at all.

### Adding durations

`Date.adding(_:in:disambiguation:)` adds a `DateTimeDuration` in a time zone.
Its years, months and days move the wall-clock date, so the time of day stays
the same, and the result goes back to an instant with the given
disambiguation. Its hours, minutes and seconds are then added as exact time.
On the day clocks spring forward, adding one day to noon gives noon the next
day, 23 hours later, while adding 24 hours gives 13:00.

### Ranges

`Range<PlainDateTime>.dateInterval(in:)` turns a wall-clock range, such as an
occurrence of a `PlainTimeRange`, into a `DateInterval`. Each end becomes the
first instant at which the wall clock reaches it. Unlike converting the ends
one by one with `date(in:disambiguation:)`, this never puts the end before the
start: a range that lies entirely inside a gap, such as 02:30–03:00 on the
night clocks spring forward, becomes an empty interval at the transition.
