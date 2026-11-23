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

@Suite("Time ranges in time zones")
struct TimeRangeZoneTests {
    let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)

    @Test("A night out lasts as long as the clocks say")
    func nightsAcrossChanges() {
        let newYork = zone("America/New_York")
        // An ordinary night: 6 hours.
        #expect(bar.occurrence(startingOn: PlainDate("2024-07-05")!).dateInterval(in: newYork).duration == 6 * 3600)
        // Clocks fell back at 02:00 on 2024-11-03: 7 hours.
        #expect(bar.occurrence(startingOn: PlainDate("2024-11-02")!).dateInterval(in: newYork).duration == 7 * 3600)
        // Clocks sprang forward at 02:00 on 2024-03-10: 5 hours.
        let short = bar.occurrence(startingOn: PlainDate("2024-03-09")!).dateInterval(in: newYork)
        #expect(short.duration == 5 * 3600)
        #expect(short.start == utc("2024-03-10T02:00:00Z"))
        #expect(short.end == utc("2024-03-10T07:00:00Z"))
    }

    @Test("A range inside a gap becomes an empty interval at the transition")
    func rangeInsideGap() {
        let newYork = zone("America/New_York")
        let skipped = PlainDateTime("2024-03-10T02:30")!..<PlainDateTime("2024-03-10T03:00")!
        let interval = skipped.dateInterval(in: newYork)
        #expect(interval.duration == 0)
        #expect(interval.start == utc("2024-03-10T07:00:00Z"))   // 03:00 EDT
        // Ends inside the gap, starts before it.
        let into = PlainDateTime("2024-03-10T01:30")!..<PlainDateTime("2024-03-10T02:30")!
        #expect(into.dateInterval(in: newYork).duration == 30 * 60)
    }

    @Test("A range that starts in a repeated hour starts at its first occurrence")
    func rangeInOverlap() {
        let newYork = zone("America/New_York")
        let late = PlainDateTime("2024-11-03T01:30")!..<PlainDateTime("2024-11-03T02:30")!
        let interval = late.dateInterval(in: newYork)
        #expect(interval.start == utc("2024-11-03T05:30:00Z"))   // 01:30 EDT
        #expect(interval.end == utc("2024-11-03T07:30:00Z"))     // 02:30 EST
    }

    @Test("Samoa's skipped day and Lord Howe's half hour")
    func unusualZones() throws {
        let apia = zone("Pacific/Apia")
        try #require(PlainDate(utc("2011-12-30T10:00:00Z"), in: apia) == PlainDate("2011-12-31"))
        // The night of 2011-12-29 ran straight into 2011-12-31.
        let night = bar.occurrence(startingOn: PlainDate("2011-12-29")!).dateInterval(in: apia)
        #expect(night.start == utc("2011-12-30T07:00:00Z"))
        #expect(night.end == utc("2011-12-30T10:00:00Z"))         // the jump to 2011-12-31 00:00
        let lordHowe = zone("Australia/Lord_Howe")
        #expect(bar.occurrence(startingOn: PlainDate("2024-10-05")!).dateInterval(in: lordHowe).duration == 5.5 * 3600)
        #expect(bar.occurrence(startingOn: PlainDate("2024-04-06")!).dateInterval(in: lordHowe).duration == 6.5 * 3600)
    }

    /// Random wall-clock ranges in zones with changes: never reversed, and
    /// equal to the plain conversion whenever both ends are unambiguous.
    @Test("Intervals keep their order", arguments: ["America/New_York", "America/Santiago", "Australia/Lord_Howe", "Pacific/Apia", "Asia/Beirut"])
    func ordering(identifier: String) {
        let timeZone = zone(identifier)
        var state: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        let first = PlainDate("2010-01-01")!
        var bad: [String] = []
        for _ in 0..<20_000 {
            let start = PlainDateTime(date: first.adding(days: next(16 * 366)),
                                      time: PlainTime(secondsSinceMidnight: next(86_400 / 60) * 60)!)
            let end = start.adding(minutes: 1 + next(48 * 60))
            let interval = (start..<end).dateInterval(in: timeZone)
            let starts = start.possibleDates(in: timeZone)
            let ends = end.possibleDates(in: timeZone)
            let plain = starts.count == 1 && ends.count == 1
            if interval.end < interval.start
                || (plain && (interval.start != starts[0] || interval.end != ends[0])) {
                if bad.count < 5 { bad.append("\(start)..<\(end)") }
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Is it open now?")
    func openNow() {
        let tokyo = zone("Asia/Tokyo")
        let instant = utc("2025-05-02T16:30:00Z")                  // 01:30 in Tokyo on Saturday
        #expect(bar.contains(PlainTime(instant, in: tokyo)))
        let tonight = bar.occurrence(containing: PlainDateTime(instant, in: tokyo))!
        #expect(tonight.lowerBound == PlainDateTime("2025-05-02T21:00")!)
        #expect(tonight.dateInterval(in: tokyo).contains(instant))
    }
}
