import Foundation
import Testing
@testable import CivilTime

private func range(_ start: String, _ end: String) -> PlainTimeRange {
    PlainTimeRange(start: PlainTime(start)!, end: PlainTime(end)!)
}

private let minutesPerDay = 1440

/// A brute-force model: the set of minutes of the day a minute-aligned range
/// covers.
private func minuteSet(start: Int, length: Int) -> [Bool] {
    var covered = [Bool](repeating: false, count: minutesPerDay)
    for i in 0..<length { covered[(start + i) % minutesPerDay] = true }
    return covered
}

private func minuteRange(start: Int, length: Int) -> PlainTimeRange {
    PlainTimeRange(
        start: PlainTime(secondsSinceMidnight: start * 60)!,
        lengthInNanoseconds: Int64(length) * 60_000_000_000
    )!
}

@Suite("PlainTimeRange")
struct PlainTimeRangeTests {
    @Test("Construction, wrapping and the whole day")
    func construction() {
        let office = range("09:00", "18:00")
        #expect(office.start == PlainTime("09:00"))
        #expect(office.end == PlainTime("18:00"))
        #expect(office.lengthInNanoseconds == 9 * 3_600_000_000_000)
        #expect(!office.crossesMidnight && !office.isAllDay)

        let bar = range("21:00", "03:00")
        #expect(bar.lengthInNanoseconds == 6 * 3_600_000_000_000)
        #expect(bar.crossesMidnight)

        let untilMidnight = range("18:00", "00:00")
        #expect(untilMidnight.lengthInNanoseconds == 6 * 3_600_000_000_000)
        #expect(!untilMidnight.crossesMidnight)
        #expect(untilMidnight.contains(PlainTime.max))
        #expect(!untilMidnight.contains(.midnight))

        let roundTheClock = range("06:00", "06:00")
        #expect(roundTheClock.isAllDay && roundTheClock.crossesMidnight)
        #expect(roundTheClock.end == PlainTime("06:00"))
        #expect(PlainTimeRange.allDay.isAllDay && !PlainTimeRange.allDay.crossesMidnight)
        #expect(range("00:00", "00:00") == .allDay)

        #expect(PlainTimeRange(start: .noon, lengthInNanoseconds: 0) == nil)
        #expect(PlainTimeRange(start: .noon, lengthInNanoseconds: -1) == nil)
        #expect(PlainTimeRange(start: .noon, lengthInNanoseconds: 86_400_000_000_001) == nil)
        #expect(PlainTimeRange(start: .noon, lengthInNanoseconds: 86_400_000_000_000)?.isAllDay == true)

        #expect(PlainTimeRange(PlainTime("09:00")!..<PlainTime("18:00")!) == office)
        #expect(PlainTimeRange(PlainTime("09:00")!..<PlainTime("09:00")!) == nil)
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    @Test("Duration-based API")
    func durations() {
        let bar = range("21:00", "03:00")
        #expect(bar.length == .seconds(6 * 3600))
        #expect(PlainTimeRange(start: PlainTime("21:00")!, length: .seconds(6 * 3600)) == bar)
        #expect(PlainTimeRange(start: .noon, length: .zero) == nil)
        #expect(PlainTimeRange(start: .noon, length: .seconds(86_401)) == nil)
        #expect(PlainTimeRange(start: .noon, length: .seconds(Int64.max)) == nil)
    }

    /// Every minute-aligned range against a bitmap of the minutes it covers.
    @Test("contains, overlaps and crossesMidnight agree with a minute bitmap")
    func bitmapOracle() {
        var generator = SplitMix64(seed: 40)
        func randomRange() -> (start: Int, length: Int) {
            // Bias towards the edge cases: whole day, ending at midnight, one minute.
            switch Int.random(in: 0..<10, using: &generator) {
            case 0: return (Int.random(in: 0..<minutesPerDay, using: &generator), minutesPerDay)
            case 1:
                let start = Int.random(in: 0..<minutesPerDay, using: &generator)
                return (start, minutesPerDay - start)
            case 2: return (Int.random(in: 0..<minutesPerDay, using: &generator), 1)
            default:
                return (Int.random(in: 0..<minutesPerDay, using: &generator),
                        Int.random(in: 1...minutesPerDay, using: &generator))
            }
        }
        var bad: [String] = []
        for _ in 0..<2_000 {
            let a = randomRange()
            let model = minuteSet(start: a.start, length: a.length)
            let subject = minuteRange(start: a.start, length: a.length)
            for minute in 0..<minutesPerDay {
                if subject.contains(PlainTime(secondsSinceMidnight: minute * 60)!) != model[minute] {
                    bad.append("\(subject) contains minute \(minute)")
                    break
                }
            }
            if subject.crossesMidnight != (a.start + a.length > minutesPerDay) {
                bad.append("\(subject) crossesMidnight")
            }
            for _ in 0..<20 {
                let b = randomRange()
                let other = minuteSet(start: b.start, length: b.length)
                let expected = (0..<minutesPerDay).contains { model[$0] && other[$0] }
                let otherRange = minuteRange(start: b.start, length: b.length)
                if subject.overlaps(otherRange) != expected || otherRange.overlaps(subject) != expected {
                    bad.append("\(subject) overlaps \(otherRange)")
                }
            }
            if bad.count > 5 { break }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Occurrences on the calendar")
    func occurrences() throws {
        let bar = range("21:00", "03:00")
        let friday = PlainDate("2025-05-02")!
        #expect(bar.occurrence(startingOn: friday) == PlainDateTime("2025-05-02T21:00")!..<PlainDateTime("2025-05-03T03:00")!)
        #expect(bar.occurrence(containing: PlainDateTime("2025-05-03T01:30")!) == bar.occurrence(startingOn: friday))
        #expect(bar.occurrence(containing: PlainDateTime("2025-05-02T21:00")!) == bar.occurrence(startingOn: friday))
        #expect(bar.occurrence(containing: PlainDateTime("2025-05-03T03:00")!) == nil)
        #expect(bar.occurrence(containing: PlainDateTime("2025-05-03T12:00")!) == nil)

        let untilMidnight = range("18:00", "00:00")
        #expect(untilMidnight.occurrence(startingOn: friday).upperBound == PlainDateTime("2025-05-03T00:00")!)

        let roundTheClock = range("06:00", "06:00")
        #expect(roundTheClock.occurrence(containing: PlainDateTime("2025-05-03T05:59")!)?.lowerBound == PlainDateTime("2025-05-02T06:00")!)
        #expect(roundTheClock.occurrence(containing: PlainDateTime("2025-05-03T06:00")!)?.lowerBound == PlainDateTime("2025-05-03T06:00")!)

        // At the ends of the supported range, the checked forms return nil.
        #expect(bar.checkedOccurrence(startingOn: .max) == nil)
        #expect(range("09:00", "18:00").checkedOccurrence(startingOn: .max) != nil)
        #expect(bar.occurrence(containing: PlainDateTime(date: .min, time: PlainTime("01:00")!)) == nil)
        #expect(bar.occurrence(containing: PlainDateTime(date: .max, time: PlainTime("22:00")!)) == nil)

        // Property: an occurrence that contains a moment starts at the range's
        // start and lasts its length.
        var generator = SplitMix64(seed: 41)
        var bad = 0
        for _ in 0..<20_000 {
            let r = minuteRange(start: Int.random(in: 0..<minutesPerDay, using: &generator),
                                length: Int.random(in: 1...minutesPerDay, using: &generator))
            let moment = PlainDate.randomMostlyModern(using: &generator)
                .at(PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!)
            let found = r.occurrence(containing: moment)
            if r.contains(moment.time) {
                guard let found else { bad += 1; continue }
                let lengthOK = found.lowerBound.wallNanoseconds(until: found.upperBound) == r.lengthInNanoseconds
                if !found.contains(moment) || found.lowerBound.time != r.start || !lengthOK { bad += 1 }
            } else if found != nil {
                bad += 1
            }
        }
        #expect(bad == 0)
    }

    @Test("Text form")
    func text() throws {
        #expect(range("21:00", "03:00").description == "21:00:00/03:00:00")
        #expect(try PlainTimeRange(parsing: "21:00/03:00") == range("21:00", "03:00"))
        #expect(try PlainTimeRange(parsing: "09:00:00/18:00:00.5") == PlainTimeRange(start: PlainTime("09:00")!, end: PlainTime("18:00:00.5")!))
        #expect(try PlainTimeRange(parsing: "06:00/06:00").isAllDay)
        #expect(try PlainTimeRange(parsing: "00:00/24:00") == .allDay)
        #expect(try PlainTimeRange(parsing: "18:00/24:00") == range("18:00", "00:00"))
        #expect(try PlainTimeRange(parsing: "18:00/24:00:00.000") == range("18:00", "00:00"))
        // The 30-hour clock.
        #expect(try PlainTimeRange(parsing: "18:00/29:00") == range("18:00", "05:00"))
        #expect(try PlainTimeRange(parsing: "21:00/27:00") == range("21:00", "03:00"))
        #expect(try PlainTimeRange(parsing: "05:00/29:00").isAllDay)

        let failures: [(String, CivilTimeParseError.Kind, Int)] = [
            ("21:00-03:00", .invalidFormat, 5),
            ("21:00 03:00", .invalidFormat, 5),
            ("21:00/", .invalidFormat, 6),
            ("24:00/03:00", .valueOutOfRange, 0),
            ("21:00/03:00Z", .unexpectedTimeZone, 11),
            ("02:00/27:00", .valueOutOfRange, 6),
            ("18:00/24:60", .valueOutOfRange, 9),
            ("18:00/10000:00", .valueOutOfRange, 6),
            ("21:00/3:00", .invalidFormat, 6),
        ]
        for (input, kind, offset) in failures {
            #expect(throws: CivilTimeParseError(kind: kind, input: input, offset: offset, typeName: "PlainTimeRange")) {
                try PlainTimeRange(parsing: input)
            }
        }

        // Random round trips, and random bytes never trap.
        var generator = SplitMix64(seed: 42)
        var bad = 0
        for _ in 0..<20_000 {
            let r = PlainTimeRange(
                start: PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!,
                lengthInNanoseconds: Int64.random(in: 1...86_400_000_000_000, using: &generator))!
            if PlainTimeRange(r.description) != r { bad += 1 }
            let noise = String(decoding: (0..<Int.random(in: 0..<20, using: &generator)).map { _ in
                UInt8.random(in: 0x20...0x3A, using: &generator)
            }, as: UTF8.self)
            _ = PlainTimeRange(noise)
            _ = ExtendedTime(noise)
        }
        #expect(bad == 0)

        let json = try JSONEncoder().encode([range("21:00", "03:00")])
        #expect(try JSONDecoder().decode([PlainTimeRange].self, from: json) == [range("21:00", "03:00")])
    }
}

@Suite("ExtendedTime")
struct ExtendedTimeTests {
    @Test("Hours past 24 fall on following days")
    func basics() throws {
        let show = ExtendedTime("25:30")!
        #expect(show.hour == 25 && show.minute == 30 && show.days == 1)
        #expect(show.timeOfDay == PlainTime("01:30"))
        #expect(show.description == "25:30:00")
        #expect(show.dateTime(on: PlainDate("2025-05-02")!) == PlainDateTime("2025-05-03T01:30")!)
        #expect(ExtendedTime("09:15")!.dateTime(on: PlainDate("2025-05-02")!) == PlainDateTime("2025-05-02T09:15")!)
        #expect(ExtendedTime("48:00")!.days == 2)
        #expect(ExtendedTime(PlainTime("09:15")!) == ExtendedTime("09:15"))
        #expect(ExtendedTime("26:00")! > ExtendedTime("23:59:59.9")!)

        let day = PlainDate("2025-05-02")!
        #expect(ExtendedTime(PlainDateTime("2025-05-03T02:00")!, relativeTo: day) == ExtendedTime("26:00"))
        #expect(ExtendedTime(PlainDateTime("2025-05-02T00:00")!, relativeTo: day) == ExtendedTime("00:00"))
        #expect(ExtendedTime(PlainDateTime("2025-05-01T23:59")!, relativeTo: day) == nil)
        #expect(ExtendedTime(PlainDateTime("2026-05-01T00:00")!, relativeTo: day)?.hour == 8736)
        #expect(ExtendedTime(PlainDateTime("2027-01-01T00:00")!, relativeTo: day) == nil)

        #expect(ExtendedTime(hour: 9999, minute: 59, second: 59, nanosecond: 999_999_999) != nil)
        #expect(ExtendedTime(hour: 10_000, minute: 0) == nil)
        #expect(ExtendedTime(hour: -1, minute: 0) == nil)
        #expect(ExtendedTime(hour: 1, minute: 60) == nil)
        #expect(ExtendedTime(nanosecondsSinceMidnight: -1) == nil)
        #expect(ExtendedTime("9999:59:59.999999999")!.hour == 9999)
        #expect(ExtendedTime("10000:00") == nil)
        #expect(ExtendedTime("1:00") == nil)
        #expect(ExtendedTime("25:60") == nil)
        #expect(ExtendedTime("25:30Z") == nil)
        #expect(ExtendedTime("25:00:60") == ExtendedTime("25:00:59"))
        #expect(ExtendedTime("29:59:59")!.checkedDateTime(on: .max) == nil)
    }

    @Test("Day boundaries are exact")
    func dayBoundaries() {
        let day = PlainDate("2025-05-02")!
        let lastMoment = ExtendedTime(nanosecondsSinceMidnight: 86_400_000_000_000 - 1)!
        #expect(lastMoment.days == 0 && lastMoment.hour == 23)
        #expect(lastMoment.dateTime(on: day) == PlainDateTime(date: day, time: .max))
        let nextMidnight = ExtendedTime(nanosecondsSinceMidnight: 86_400_000_000_000)!
        #expect(nextMidnight.days == 1 && nextMidnight.hour == 24 && nextMidnight.timeOfDay == .midnight)
        #expect(nextMidnight.dateTime(on: day) == PlainDateTime("2025-05-03T00:00")!)
        #expect(ExtendedTime("47:59:59.999999999")!.days == 1)
        #expect(ExtendedTime("48:00")!.dateTime(on: day) == PlainDateTime("2025-05-04T00:00")!)

        // Round trip through a date-time, for random readings and dates.
        var generator = SplitMix64(seed: 44)
        var bad = 0
        for _ in 0..<20_000 {
            let e = ExtendedTime(nanosecondsSinceMidnight: Int64.random(in: 0..<(72 * 3_600_000_000_000), using: &generator))!
            let d = PlainDate.randomMostlyModern(using: &generator)
            guard d < PlainDate.max.adding(days: -3) else { continue }
            let dt = e.dateTime(on: d)
            if ExtendedTime(dt, relativeTo: d) != e || e.days != e.hour / 24 || dt.time != e.timeOfDay { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("Ranges of extended times, as in TV listings and timetables")
    func ranges() throws {
        let broadcastDay = PlainDate("2025-05-02")!
        let lateShow = ExtendedTime("25:30")!..<ExtendedTime("26:00")!
        #expect(lateShow.occurrence(on: broadcastDay) == PlainDateTime("2025-05-03T01:30")!..<PlainDateTime("2025-05-03T02:00")!)
        #expect(lateShow.checkedOccurrence(on: .max) == nil)

        let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)
        #expect(bar.extendedRange == ExtendedTime("21:00")!..<ExtendedTime("27:00")!)
        #expect(PlainTimeRange(bar.extendedRange) == bar)
        #expect(PlainTimeRange(ExtendedTime("25:00")!..<ExtendedTime("27:00")!) == PlainTimeRange(start: PlainTime("01:00")!, end: PlainTime("03:00")!))
        #expect(PlainTimeRange(ExtendedTime("05:00")!..<ExtendedTime("29:00")!)?.isAllDay == true)
        #expect(PlainTimeRange(ExtendedTime("05:00")!..<ExtendedTime("29:01")!) == nil)
        #expect(PlainTimeRange(ExtendedTime("05:00")!..<ExtendedTime("05:00")!) == nil)
        #expect(PlainTimeRange.allDay.extendedRange == ExtendedTime("00:00")!..<ExtendedTime("24:00")!)

        // Every daily range round-trips through its extended form.
        var generator = SplitMix64(seed: 43)
        var bad = 0
        for _ in 0..<20_000 {
            let r = PlainTimeRange(
                start: PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!,
                lengthInNanoseconds: Int64.random(in: 1...86_400_000_000_000, using: &generator))!
            let extended = r.extendedRange
            if PlainTimeRange(extended) != r || extended.lowerBound.days != 0
                || (extended.upperBound.days > 0) != (r.crossesMidnight || r.end == .midnight) {
                bad += 1
            }
            let e = ExtendedTime(nanosecondsSinceMidnight: Int64.random(in: 0..<(48 * 3_600_000_000_000), using: &generator))!
            if ExtendedTime(e.description) != e { bad += 1 }
        }
        #expect(bad == 0)

        struct Stop: Codable, Equatable { var departure: ExtendedTime }
        let json = try JSONEncoder().encode(Stop(departure: ExtendedTime("25:35")!))
        #expect(String(decoding: json, as: UTF8.self) == #"{"departure":"25:35:00"}"#)
        #expect(try JSONDecoder().decode(Stop.self, from: json) == Stop(departure: ExtendedTime("25:35")!))
    }
}

private extension PlainDateTime {
    /// Wall-clock nanoseconds from `self` to `other`, counting 24-hour days.
    func wallNanoseconds(until other: PlainDateTime) -> Int64 {
        Int64(other.date.daysSinceEpoch - date.daysSinceEpoch) * 86_400_000_000_000
            + other.time.nanosecondsSinceMidnight - time.nanosecondsSinceMidnight
    }
}
