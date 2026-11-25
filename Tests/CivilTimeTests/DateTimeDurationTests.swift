import Foundation
import Testing
@testable import CivilTime

@Suite("DateTimeDuration")
struct DateTimeDurationTests {
    @Test("Text round-trips", arguments: [
        ("P1DT12H30M", DateTimeDuration(days: 1, hours: 12, minutes: 30)),
        ("PT1.5S", DateTimeDuration(seconds: 1, nanoseconds: 500_000_000)),
        ("PT0S", DateTimeDuration.zero),
        ("-PT0.5S", DateTimeDuration(nanoseconds: -500_000_000)),
        ("-PT1.5S", DateTimeDuration(seconds: -1, nanoseconds: -500_000_000)),
        ("P1Y2M10DT2H30M5.25S", DateTimeDuration(years: 1, months: 2, days: 10, hours: 2, minutes: 30, seconds: 5, nanoseconds: 250_000_000)),
        ("P1DT-2H", DateTimeDuration(days: 1, hours: -2)),
        ("P1DT-0.5S", DateTimeDuration(days: 1, nanoseconds: -500_000_000)),
        ("PT0.000000001S", DateTimeDuration(nanoseconds: 1)),
        ("P1M", DateTimeDuration(months: 1)),
        ("PT1M", DateTimeDuration(minutes: 1)),
        ("PT90M", DateTimeDuration(minutes: 90)),
    ])
    func roundTrip(text: String, value: DateTimeDuration) throws {
        #expect(value.description == text)
        #expect(try DateTimeDuration(parsing: text) == value)
    }

    @Test("Other accepted spellings")
    func variants() throws {
        #expect(try DateTimeDuration(parsing: "PT-0.5S") == DateTimeDuration(nanoseconds: -500_000_000))
        #expect(try DateTimeDuration(parsing: "PT-1.5S") == DateTimeDuration(seconds: -1, nanoseconds: -500_000_000))
        #expect(try DateTimeDuration(parsing: "-PT-1S") == DateTimeDuration(seconds: 1))
        #expect(try DateTimeDuration(parsing: "PT1,5S") == DateTimeDuration(seconds: 1, nanoseconds: 500_000_000))
        #expect(try DateTimeDuration(parsing: "P2W") == DateTimeDuration(days: 14))
        #expect(try DateTimeDuration(parsing: "+P1D") == DateTimeDuration(days: 1))
        // Every form DateDuration writes is accepted, and means the same.
        for text in ["P1Y2M10D", "P0D", "-P1M", "P1Y-2M", "P400D", "-P1Y3D"] {
            #expect(try DateTimeDuration(parsing: text) == DateTimeDuration(DateDuration(parsing: text)), "\(text)")
        }
        // DateDuration still refuses time components.
        #expect(DateDuration("PT1H") == nil)
    }

    @Test("Rejected text", arguments: [
        "", "P", "PT", "P1DT", "1D", "P1H", "PT1D", "PT1.5H", "P1.5D", "PT1S1M", "PT1H1H", "P1M1Y",
        "PT1.S", "PT.5S", "PT1.1234567891S", "PT1234567890123456H", "P1DT1", "PT1HT1M", "p1d", "P1D ", "PT1H30",
    ])
    func rejected(text: String) {
        #expect(DateTimeDuration(text) == nil, "\(text)")
    }

    @Test("Seconds and their fraction share one sign")
    func normalization() {
        let half = DateTimeDuration(seconds: 1, nanoseconds: -500_000_000)
        #expect(half.seconds == 0 && half.nanoseconds == 500_000_000)
        #expect(half.description == "PT0.5S")
        let carried = DateTimeDuration(seconds: 1, nanoseconds: 2_500_000_000)
        #expect(carried.seconds == 3 && carried.nanoseconds == 500_000_000)
        let negative = DateTimeDuration(seconds: -1, nanoseconds: 500_000_000)
        #expect(negative.seconds == 0 && negative.nanoseconds == -500_000_000)
        #expect(DateTimeDuration(weeks: 2, days: 1).days == 15)
        // Equality compares components.
        #expect(DateTimeDuration(minutes: 90) != DateTimeDuration(hours: 1, minutes: 30))
    }

    @Test("Random values round-trip through text")
    func randomText() {
        var generator = SplitMix64(seed: 50)
        var bad: [String] = []
        for _ in 0..<50_000 {
            func r(_ limit: Int) -> Int { Int.random(in: -limit...limit, using: &generator) }
            let value = DateTimeDuration(
                years: Int.random(in: 0..<4, using: &generator) == 0 ? r(9_999) : 0,
                months: Int.random(in: 0..<3, using: &generator) == 0 ? r(500) : 0,
                days: Int.random(in: 0..<2, using: &generator) == 0 ? r(100_000) : 0,
                hours: Int64(Int.random(in: 0..<2, using: &generator) == 0 ? r(100_000) : 0),
                minutes: Int64(Int.random(in: 0..<2, using: &generator) == 0 ? r(10_000) : 0),
                seconds: Int64(Int.random(in: 0..<2, using: &generator) == 0 ? r(100_000) : 0),
                nanoseconds: Int64(Int.random(in: 0..<2, using: &generator) == 0 ? r(999_999_999) : 0))
            if DateTimeDuration(value.description) != value { bad.append(value.description) }
            if bad.count > 5 { break }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Adding to a date-time")
    func adding() {
        let start = PlainDateTime("2025-05-02T21:00")!
        #expect(start.adding(DateTimeDuration(days: 1, hours: 12, minutes: 30)) == PlainDateTime("2025-05-04T09:30"))
        #expect(PlainDateTime("2024-01-31T22:00")!.adding(DateTimeDuration(months: 1, hours: 3)) == PlainDateTime("2024-03-01T01:00"))
        #expect(start.adding(DateTimeDuration(nanoseconds: -1)) == PlainDateTime("2025-05-02T20:59:59.999999999"))
        #expect(start.adding(-DateTimeDuration(hours: 22)) == PlainDateTime("2025-05-01T23:00"))
        // The overloads written in 0.2.0 still resolve.
        #expect(start.adding(DateDuration(days: 1)) == PlainDateTime("2025-05-03T21:00"))
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            #expect(start.adding(.seconds(3600)) == PlainDateTime("2025-05-02T22:00"))
        }
        // Out of range or overflowing: nil, never a trap.
        #expect(PlainDateTime.max.checkedAdding(DateTimeDuration(nanoseconds: 1)) == nil)
        #expect(start.checkedAdding(DateTimeDuration(hours: .max)) == nil)
        #expect(start.checkedAdding(DateTimeDuration(seconds: .max, nanoseconds: 999_999_999)) == nil)
        #expect(start.checkedAdding(DateTimeDuration(years: .max)) == nil)
        #expect(start.checkedAdding(DateTimeDuration("PT999999999999999H")!) == nil)
    }

    @Test("Durations between date-times always lead back, with one sign")
    func until() {
        var generator = SplitMix64(seed: 51)
        var bad: [String] = []
        for i in 0..<100_000 {
            let a = PlainDate.randomMostlyModern(using: &generator)
                .at(PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!)
            let b: PlainDateTime
            switch i % 4 {
            case 0: b = a                                                                // same moment
            case 1: b = PlainDateTime(date: a.date, time: PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!)
            case 2: b = PlainDateTime(date: a.date.lastDayOfMonth, time: .midnight)     // month ends
            default:
                b = PlainDate.randomMostlyModern(using: &generator)
                    .at(PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!)
            }
            let d = a.dateTimeDuration(until: b)
            let parts = [Int64(d.years), Int64(d.months), Int64(d.days), d.hours, d.minutes, d.seconds, d.nanoseconds]
            let oneSign = Set(parts.filter { $0 != 0 }.map { $0 > 0 }).count <= 1
            if a.adding(d) != b || !oneSign || d.hours >= 24 || d.hours <= -24 {
                if bad.count < 10 { bad.append("\(a) → \(b): \(d)") }
            }
        }
        #expect(bad.isEmpty, "\(bad)")
        #expect(PlainDateTime("2024-01-31T22:00")!.dateTimeDuration(until: PlainDateTime("2024-03-01T01:00")!).description == "P1MT3H")
        #expect(PlainDateTime("2024-03-01T01:00")!.dateTimeDuration(until: PlainDateTime("2024-01-31T22:00")!).description == "-P1MT3H")
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    @Test("Conversions with Duration")
    func durations() {
        #expect(DateTimeDuration(.seconds(5400)) == DateTimeDuration(seconds: 5400))
        #expect(DateTimeDuration(.milliseconds(-1500)) == DateTimeDuration(seconds: -1, nanoseconds: -500_000_000))
        #expect(DateTimeDuration(hours: 1, minutes: 30).exactDuration == .seconds(5400))
        #expect(DateTimeDuration(nanoseconds: -500_000_000).exactDuration == .milliseconds(-500))
        #expect(DateTimeDuration(days: 1).exactDuration == nil)
        #expect(DateTimeDuration(hours: .max).exactDuration == nil)
        // Every Duration that fits in Int64 seconds converts, and round-trips.
        for duration in [Duration.seconds(Int64.max), .seconds(Int64.min), .nanoseconds(Int64.max), .zero, .seconds(-1) + .nanoseconds(1)] {
            #expect(DateTimeDuration(duration).exactDuration == duration)
        }
        // Longer than Int64 seconds: still converts, as whole hours.
        let huge = Duration.seconds(Int64.max) * 4 + .nanoseconds(7)
        let converted = DateTimeDuration(huge)
        #expect(converted.hours > 0 && converted.nanoseconds == 7 && converted.exactDuration == nil)
        #expect(DateTimeDuration(Duration.zero - huge).hours < 0)
        #expect(PlainTime.noon.adding(huge) == PlainTime.noon.adding(.seconds(Int64.max) * 4 + .nanoseconds(7) - .seconds(86_400) * 1_000))
        #expect(PlainTimeRange(start: .noon, length: huge) == nil)
        var generator = SplitMix64(seed: 52)
        var bad = 0
        for _ in 0..<10_000 {
            let d = Duration.seconds(Int64.random(in: -1_000_000_000_000...1_000_000_000_000, using: &generator))
                + .nanoseconds(Int64.random(in: -999_999_999...999_999_999, using: &generator))
            if DateTimeDuration(d).exactDuration != d { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("Codable")
    func codable() throws {
        struct Trip: Codable, Equatable { var stay: DateTimeDuration }
        let json = try JSONEncoder().encode(Trip(stay: DateTimeDuration(days: 2, hours: 3)))
        #expect(String(decoding: json, as: UTF8.self) == #"{"stay":"P2DT3H"}"#)
        #expect(try JSONDecoder().decode(Trip.self, from: json) == Trip(stay: DateTimeDuration(days: 2, hours: 3)))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Trip.self, from: Data(#"{"stay":"PT1.5H"}"#.utf8)) }
    }

    @available(*, deprecated)
    @Test("The 0.2.0 names still work")
    func deprecatedNames() {
        let p: DatePeriod = DatePeriod(months: 1)
        #expect(p == DateDuration(months: 1))
        let jan31 = PlainDate(year: 2024, month: 1, day: 31)!
        #expect(jan31.period(until: PlainDate(year: 2024, month: 3, day: 1)!) == DateDuration(months: 1, days: 1))
    }
}
