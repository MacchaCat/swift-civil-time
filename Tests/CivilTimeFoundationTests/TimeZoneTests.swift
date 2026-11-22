import CivilTime
import CivilTimeFoundation
import Foundation
import Testing

private func zone(_ identifier: String) -> TimeZone {
    TimeZone(identifier: identifier)!
}

private func utc(_ text: String) -> Date {
    try! Date(text, strategy: .iso8601)
}

private func dateTime(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> PlainDateTime {
    PlainDateTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second)!
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> PlainDate {
    PlainDate(year: year, month: month, day: day)!
}

@Suite("Time zones")
struct TimeZoneTests {
    @Test("An instant falls on different dates in different zones")
    func instantToDate() {
        let instant = utc("2024-02-29T00:00:00Z")
        #expect(PlainDate(instant, in: zone("UTC")) == date(2024, 2, 29))
        #expect(PlainDate(instant, in: zone("America/Los_Angeles")) == date(2024, 2, 28))
        #expect(PlainDate(instant, in: zone("Asia/Tokyo")) == date(2024, 2, 29))
        #expect(PlainDateTime(instant, in: zone("Asia/Kolkata")) == dateTime(2024, 2, 29, 5, 30))
        #expect(PlainTime(instant, in: zone("Asia/Kathmandu")) == PlainTime(hour: 5, minute: 45))
        #expect(PlainDateTime(utc("1969-12-31T23:59:59Z"), in: zone("UTC")) == dateTime(1969, 12, 31, 23, 59, 59))
    }

    @Test("Dates from untrusted input convert without trapping")
    func checkedConversions() {
        let tokyo = zone("Asia/Tokyo")
        for bad in [Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: -.infinity),
                    Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: 1e300),
                    Date(timeIntervalSince1970: -1e300), Date(timeIntervalSince1970: 9.3e18),
                    Date(timeIntervalSince1970: 1e15)] {
            #expect(PlainDateTime(checking: bad, in: tokyo) == nil)
            #expect(PlainDate(checking: bad, in: tokyo) == nil)
            #expect(PlainTime(checking: bad, in: tokyo) == nil)
        }
        let instant = utc("2024-02-29T00:00:00Z")
        #expect(PlainDateTime(checking: instant, in: tokyo) == dateTime(2024, 2, 29, 9))
        #expect(PlainDate(checking: .distantFuture, in: tokyo) == PlainDate(.distantFuture, in: tokyo))
        #expect(PlainDate(checking: .distantPast, in: tokyo) == PlainDate(.distantPast, in: tokyo))
    }

    @Test("Fractional seconds survive the trip through Date to microsecond precision")
    func fractions() {
        let local = PlainDateTime(year: 2024, month: 2, day: 29, hour: 12, nanosecond: 123_456_000)!
        let instant = local.date(in: zone("Europe/Paris"))
        let back = PlainDateTime(instant, in: zone("Europe/Paris"))
        #expect(back.date == local.date)
        #expect(abs(back.time.nanosecondsSinceMidnight - local.time.nanosecondsSinceMidnight) < 1_000)
        let beforeEpoch = PlainDateTime(Date(timeIntervalSince1970: -0.25), in: zone("UTC"))
        #expect(beforeEpoch == PlainDateTime(year: 1969, month: 12, day: 31, hour: 23, minute: 59, second: 59, nanosecond: 750_000_000))
    }

    @Test("Ordinary times have exactly one instant")
    func unambiguous() {
        let local = dateTime(2024, 7, 1, 12)
        #expect(local.possibleDates(in: zone("America/New_York")) == [utc("2024-07-01T16:00:00Z")])
        for disambiguation in [PlainDateTime.Disambiguation.compatible, .earlier, .later] {
            #expect(local.date(in: zone("America/New_York"), disambiguation: disambiguation) == utc("2024-07-01T16:00:00Z"))
        }
    }

    @Test("A skipped time in New York (spring forward)")
    func newYorkGap() {
        let newYork = zone("America/New_York")
        let skipped = dateTime(2024, 3, 10, 2, 30)
        #expect(skipped.possibleDates(in: newYork).isEmpty)
        #expect(skipped.date(in: newYork) == utc("2024-03-10T07:30:00Z"))                         // 03:30 EDT
        #expect(skipped.date(in: newYork, disambiguation: .later) == utc("2024-03-10T07:30:00Z"))
        #expect(skipped.date(in: newYork, disambiguation: .earlier) == utc("2024-03-10T06:30:00Z")) // 01:30 EST
        #expect(PlainDateTime(skipped.date(in: newYork), in: newYork) == dateTime(2024, 3, 10, 3, 30))
        #expect(date(2024, 3, 10).dateInterval(in: newYork).duration == 23 * 3600)
    }

    @Test("A repeated time in New York (fall back)")
    func newYorkOverlap() {
        let newYork = zone("America/New_York")
        let repeated = dateTime(2024, 11, 3, 1, 30)
        #expect(repeated.possibleDates(in: newYork) == [utc("2024-11-03T05:30:00Z"), utc("2024-11-03T06:30:00Z")])
        #expect(repeated.date(in: newYork) == utc("2024-11-03T05:30:00Z"))
        #expect(repeated.date(in: newYork, disambiguation: .earlier) == utc("2024-11-03T05:30:00Z"))
        #expect(repeated.date(in: newYork, disambiguation: .later) == utc("2024-11-03T06:30:00Z"))
        #expect(date(2024, 11, 3).dateInterval(in: newYork).duration == 25 * 3600)
    }

    @Test("Lord Howe Island shifts by 30 minutes")
    func lordHowe() {
        let lordHowe = zone("Australia/Lord_Howe")
        // 2024-04-07 02:00 (+11) became 01:30 (+10:30): 01:30–02:00 happens twice.
        let repeated = dateTime(2024, 4, 7, 1, 45)
        let candidates = repeated.possibleDates(in: lordHowe)
        #expect(candidates.count == 2)
        #expect(candidates.count == 2 && candidates[1].timeIntervalSince(candidates[0]) == 1800)
        // 2024-10-06 02:00 (+10:30) became 02:30 (+11): 02:00–02:30 never happens.
        let skipped = dateTime(2024, 10, 6, 2, 15)
        #expect(skipped.possibleDates(in: lordHowe).isEmpty)
        #expect(PlainDateTime(skipped.date(in: lordHowe), in: lordHowe) == dateTime(2024, 10, 6, 2, 45))
        #expect(PlainDateTime(skipped.date(in: lordHowe, disambiguation: .earlier), in: lordHowe) == dateTime(2024, 10, 6, 1, 45))
        #expect(date(2024, 10, 6).dateInterval(in: lordHowe).duration == 23.5 * 3600)
    }

    @Test("Santiago skips midnight when daylight time starts")
    func santiagoMidnightGap() {
        let santiago = zone("America/Santiago")
        let day = date(2024, 9, 8)
        // Clocks went from 00:00 (-04) straight to 01:00 (-03).
        #expect(day.at(.midnight).possibleDates(in: santiago).isEmpty)
        let start = day.startOfDay(in: santiago)
        #expect(start == utc("2024-09-08T04:00:00Z"))
        #expect(PlainDateTime(start, in: santiago) == dateTime(2024, 9, 8, 1, 0))
        #expect(PlainDate(start.addingTimeInterval(-1), in: santiago) == date(2024, 9, 7))
        #expect(day.dateInterval(in: santiago).duration == 23 * 3600)
        // In April clocks went from 00:00 (-03) back to 23:00 (-04) the day
        // before, so 23:30 on April 6 happened twice.
        #expect(dateTime(2024, 4, 6, 23, 30).possibleDates(in: santiago).count == 2)
        #expect(date(2024, 4, 6).dateInterval(in: santiago).duration == 25 * 3600)
        #expect(date(2024, 4, 7).startOfDay(in: santiago) == utc("2024-04-07T04:00:00Z"))
    }

    @Test("Samoa skipped all of 2011-12-30")
    func samoaSkippedDay() throws {
        let apia = zone("Pacific/Apia")
        // Check the system time-zone data has the change before relying on it.
        try #require(PlainDate(utc("2011-12-30T09:59:59Z"), in: apia) == date(2011, 12, 29))
        try #require(PlainDate(utc("2011-12-30T10:00:00Z"), in: apia) == date(2011, 12, 31))

        let missing = date(2011, 12, 30)
        #expect(missing.at(.noon).possibleDates(in: apia).isEmpty)
        #expect(missing.startOfDay(in: apia) == utc("2011-12-30T10:00:00Z"))
        #expect(missing.startOfDay(in: apia) == date(2011, 12, 31).startOfDay(in: apia))
        #expect(missing.dateInterval(in: apia).duration == 0)
        #expect(PlainDateTime(missing.at(.noon).date(in: apia), in: apia) == dateTime(2011, 12, 31, 12))
        #expect(PlainDateTime(missing.at(.noon).date(in: apia, disambiguation: .earlier), in: apia) == dateTime(2011, 12, 29, 12))
        #expect(date(2011, 12, 29).dateInterval(in: apia).duration == 24 * 3600)
    }

    /// Every hour for ten years in several zones: the wall-clock time of an
    /// instant must lead back to that instant.
    @Test("Instants round-trip through wall-clock times", arguments: [
        "America/New_York", "Europe/London", "Australia/Lord_Howe", "America/Santiago",
        "Asia/Tokyo", "Pacific/Apia", "Asia/Tehran", "Africa/Casablanca",
    ])
    func roundTrip(identifier: String) {
        let timeZone = zone(identifier)
        var bad: [String] = []
        let start = utc("2010-01-01T00:00:00Z").timeIntervalSince1970
        for hour in 0 ..< 24 * 366 * 10 {
            // Every hour, plus an odd number of minutes so that half-hour
            // transitions are crossed too.
            let instant = Date(timeIntervalSince1970: start + Double(hour) * 3600 + Double(hour % 4) * 15 * 60)
            let local = PlainDateTime(instant, in: timeZone)
            let candidates = local.possibleDates(in: timeZone)
            let resolved = local.date(in: timeZone)
            let ok = candidates.contains(instant)
                && (resolved == instant || (candidates.count == 2 && candidates[1] == instant))
            if !ok, bad.count < 5 {
                bad.append("\(instant) → \(local) → \(candidates)")
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Every date starts on that date", arguments: ["America/Santiago", "America/Havana", "Asia/Beirut", "Pacific/Apia", "Europe/Berlin"])
    func startOfDay(identifier: String) {
        let timeZone = zone(identifier)
        var bad: [PlainDate] = []
        for day in date(2000, 1, 1)...date(2025, 12, 31) {
            let start = day.startOfDay(in: timeZone)
            let interval = day.dateInterval(in: timeZone)
            let startsOnDay = PlainDate(start, in: timeZone) == day
            let previousIsEarlier = PlainDate(start.addingTimeInterval(-1), in: timeZone) < day
            let skipped = interval.duration == 0
            if !(previousIsEarlier && (startsOnDay || skipped)), bad.count < 5 {
                bad.append(day)
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }
}
