import CivilTime
import CivilTimeFoundation
import Foundation
import Testing

private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }
private func utc(_ text: String) -> Date { try! Date(text, strategy: .iso8601) }

@Suite("Adding durations in a time zone")
struct ZonedArithmeticTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    @Test("A day is not always 24 hours")
    func dayVersusHours() {
        let noon = PlainDateTime("2024-03-09T12:00")!.date(in: newYork)
        let nextDay = noon.adding(DateTimeDuration(days: 1), in: newYork)
        #expect(PlainDateTime(nextDay, in: newYork) == PlainDateTime("2024-03-10T12:00"))
        #expect(nextDay.timeIntervalSince(noon) == 23 * 3600)
        let dayOfHours = noon.adding(DateTimeDuration(hours: 24), in: newYork)
        #expect(PlainDateTime(dayOfHours, in: newYork) == PlainDateTime("2024-03-10T13:00"))
        #expect(dayOfHours.timeIntervalSince(nextDay) == 3600)
        // Calendar part first, then exact time.
        let both = noon.adding(DateTimeDuration(days: 1, hours: 1), in: newYork)
        #expect(PlainDateTime(both, in: newYork) == PlainDateTime("2024-03-10T13:00"))
    }

    @Test("Landing in a skipped hour uses the disambiguation")
    func intoGap() {
        let start = PlainDateTime("2024-03-09T02:30")!.date(in: newYork)
        let compatible = start.adding(DateTimeDuration(days: 1), in: newYork)
        #expect(compatible == utc("2024-03-10T07:30:00Z"))                      // 03:30 EDT
        let earlier = start.adding(DateTimeDuration(days: 1), in: newYork, disambiguation: .earlier)
        #expect(earlier == utc("2024-03-10T06:30:00Z"))                         // 01:30 EST
    }

    @Test("Landing in a repeated hour uses the disambiguation")
    func intoOverlap() {
        let start = PlainDateTime("2024-11-02T01:30")!.date(in: newYork)
        #expect(start.adding(DateTimeDuration(days: 1), in: newYork) == utc("2024-11-03T05:30:00Z"))                         // EDT
        #expect(start.adding(DateTimeDuration(days: 1), in: newYork, disambiguation: .later) == utc("2024-11-03T06:30:00Z")) // EST
    }

    @Test("Without calendar units, time stays exact, even in a repeated hour")
    func exactOnly() {
        let secondOneThirty = utc("2024-11-03T06:30:00Z")                       // 01:30 EST, the second one
        #expect(secondOneThirty.adding(DateTimeDuration(minutes: 10), in: newYork) == utc("2024-11-03T06:40:00Z"))
        #expect(secondOneThirty.adding(.zero, in: newYork) == secondOneThirty)
        #expect(secondOneThirty.adding(DateTimeDuration(seconds: -1, nanoseconds: -500_000_000), in: newYork)
                == utc("2024-11-03T06:30:00Z").addingTimeInterval(-1.5))
    }

    @Test("Months clamp on the wall clock")
    func months() {
        let start = PlainDateTime("2024-01-31T09:00")!.date(in: zone("Asia/Tokyo"))
        let result = start.adding(DateTimeDuration(months: 1), in: zone("Asia/Tokyo"))
        #expect(PlainDateTime(result, in: zone("Asia/Tokyo")) == PlainDateTime("2024-02-29T09:00"))
    }

    /// Days only, at noon (never in a gap), against Foundation's Calendar.
    /// Pacific/Apia is left out: across the day it skipped (2011-12-30),
    /// Calendar counts only days that happened there, while this package,
    /// like Temporal, counts calendar days. See `skippedDay`.
    @Test("Adding days agrees with Calendar", arguments: ["America/New_York", "Europe/London", "Australia/Lord_Howe"])
    func againstCalendar(identifier: String) {
        let timeZone = zone(identifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var state: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        var bad: [String] = []
        for _ in 0..<5_000 {
            let start = PlainDateTime(date: PlainDate("2000-01-01")!.adding(days: next(30 * 366)), time: .noon).date(in: timeZone)
            let days = next(400) - 200
            let ours = start.adding(DateTimeDuration(days: days), in: timeZone)
            let theirs = calendar.date(byAdding: .day, value: days, to: start)!
            if ours != theirs, bad.count < 5 { bad.append("\(start) + \(days)d: \(ours) vs \(theirs)") }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Calendar days across a skipped date")
    func skippedDay() {
        let apia = zone("Pacific/Apia")
        let start = PlainDateTime("2011-12-29T12:00")!.date(in: apia)
        // 2011-12-30 12:00 never happened there; .compatible moves it a day on.
        #expect(PlainDateTime(start.adding(DateTimeDuration(days: 1), in: apia), in: apia) == PlainDateTime("2011-12-31T12:00"))
        #expect(PlainDateTime(start.adding(DateTimeDuration(days: 2), in: apia), in: apia) == PlainDateTime("2011-12-31T12:00"))
        #expect(PlainDateTime(start.adding(DateTimeDuration(days: 3), in: apia), in: apia) == PlainDateTime("2012-01-01T12:00"))
        let autumn = PlainDateTime("2011-09-25T12:00")!.date(in: apia)
        #expect(PlainDateTime(autumn.adding(DateTimeDuration(days: 110), in: apia), in: apia) == PlainDateTime("2012-01-13T12:00"))
    }

    @Test("Untrusted input never traps")
    func untrusted() {
        let now = utc("2025-05-02T00:00:00Z")
        #expect(now.checkedAdding(DateTimeDuration(hours: .max), in: newYork) == nil)
        #expect(now.checkedAdding(DateTimeDuration(years: 2_000_000), in: newYork) == nil)
        #expect(Date(timeIntervalSince1970: .infinity).checkedAdding(DateTimeDuration(days: 1), in: newYork) == nil)
        #expect(Date(timeIntervalSince1970: .nan).checkedAdding(DateTimeDuration(minutes: 1), in: newYork) == nil)
        #expect(Date(timeIntervalSince1970: 1e300).checkedAdding(DateTimeDuration(days: 1), in: newYork) == nil)
        #expect(now.checkedAdding(DateTimeDuration("PT999999999999999H")!, in: newYork) != nil)
    }
}
