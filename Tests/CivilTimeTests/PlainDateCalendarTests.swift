import Testing
@testable import CivilTime

@Suite("PlainDate: calendar math")
struct PlainDateCalendarTests {
    @Test("Known day numbers")
    func knownDayNumbers() {
        #expect(date(1970, 1, 1).daysSinceEpoch == 0)
        #expect(date(1969, 12, 31).daysSinceEpoch == -1)
        #expect(date(2000, 3, 1).daysSinceEpoch == 11_017)
        #expect(date(2024, 2, 29).daysSinceEpoch == 19_782)
        #expect(date(0, 1, 1).daysSinceEpoch == -719_528)
        #expect(date(-1, 12, 31).daysSinceEpoch == -719_529)
        // Postgres counts dates from 2000-01-01.
        #expect(date(2000, 1, 1).daysSinceEpoch == 10_957)
    }

    @Test("Range constants match the algorithm")
    func rangeConstants() {
        #expect(CivilMath.epochDay(year: -999_999, month: 1, day: 1) == CivilMath.minEpochDay)
        #expect(CivilMath.epochDay(year: 999_999, month: 12, day: 31) == CivilMath.maxEpochDay)
        #expect(PlainDate.min.daysSinceEpoch == CivilMath.minEpochDay)
        #expect(PlainDate.max.daysSinceEpoch == CivilMath.maxEpochDay)
        #expect(PlainDate(daysSinceEpoch: CivilMath.minEpochDay - 1) == nil)
        #expect(PlainDate(daysSinceEpoch: CivilMath.maxEpochDay + 1) == nil)
        #expect(PlainDate(daysSinceEpoch: Int.min) == nil)
        #expect(PlainDate(daysSinceEpoch: Int.max) == nil)
    }

    /// Walks the calendar one day at a time using only month lengths, and
    /// checks the closed-form conversion against it for 2 million days
    /// (about 5,500 years) around 1970.
    @Test("Day numbers agree with a day-by-day walk")
    func dayByDayWalk() {
        var mismatches: [String] = []
        for direction in [1, -1] {
            var (y, m, d) = (1970, 1, 1)
            for n in 0...1_000_000 {
                let epochDay = n * direction
                let fromDay = CivilMath.civil(fromEpochDay: epochDay)
                if fromDay != (y, m, d) || CivilMath.epochDay(year: y, month: m, day: d) != epochDay {
                    if mismatches.count < 10 { mismatches.append("\(epochDay): \(fromDay) vs \((y, m, d))") }
                }
                // Step the naive walker.
                if direction == 1 {
                    d += 1
                    if d > CivilMath.daysInMonth(year: y, month: m) { d = 1; m += 1 }
                    if m > 12 { m = 1; y += 1 }
                } else {
                    d -= 1
                    if d < 1 {
                        m -= 1
                        if m < 1 { m = 12; y -= 1 }
                        d = CivilMath.daysInMonth(year: y, month: m)
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("Day numbers round-trip across the whole supported range")
    func roundTripWholeRange() {
        var mismatches: [Int] = []
        var generator = SplitMix64(seed: 1)
        var samples = Array(CivilMath.minEpochDay ..< CivilMath.minEpochDay + 1000)
        samples += Array(CivilMath.maxEpochDay - 1000 ... CivilMath.maxEpochDay)
        for _ in 0..<200_000 {
            samples.append(Int.random(in: CivilMath.minEpochDay ... CivilMath.maxEpochDay, using: &generator))
        }
        for epochDay in samples {
            let date = PlainDate(daysSinceEpoch: epochDay)!
            let next = PlainDate(daysSinceEpoch: epochDay + 1)
            if date.daysSinceEpoch != epochDay
                || PlainDate(year: date.year, month: date.month, day: date.day) != date
                || (next != nil && !(date < next!)) {
                mismatches.append(epochDay)
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
    }

    @Test("Validation rejects dates that do not exist")
    func validation() {
        #expect(PlainDate(year: 2023, month: 2, day: 29) == nil)
        #expect(PlainDate(year: 2024, month: 2, day: 30) == nil)
        #expect(PlainDate(year: 2024, month: 4, day: 31) == nil)
        #expect(PlainDate(year: 2024, month: 0, day: 1) == nil)
        #expect(PlainDate(year: 2024, month: 13, day: 1) == nil)
        #expect(PlainDate(year: 2024, month: 1, day: 0) == nil)
        #expect(PlainDate(year: 1_000_000, month: 1, day: 1) == nil)
        #expect(PlainDate(year: -1_000_000, month: 12, day: 31) == nil)
        #expect(PlainDate(year: Int.max, month: 1, day: 1) == nil)
        #expect(PlainDate(year: 2024, month: 1, day: Int.min) == nil)
        #expect(PlainDate(year: 2024, month: 2, day: 29) != nil)
    }

    @Test("Leap years follow the Gregorian rule, including negative years",
          arguments: [
            (2024, true), (2023, false), (2000, true), (1900, false), (2100, false),
            (1600, true), (0, true), (-1, false), (-4, true), (-100, false), (-400, true),
          ])
    func leapYears(year: Int, isLeap: Bool) {
        #expect(date(year, 1, 1).isInLeapYear == isLeap)
        #expect(date(year, 1, 1).daysInYear == (isLeap ? 366 : 365))
        #expect((PlainDate(year: year, month: 2, day: 29) != nil) == isLeap)
    }

    @Test("Weekdays")
    func weekdays() {
        #expect(date(1970, 1, 1).weekday == .thursday)
        #expect(date(2024, 2, 29).weekday == .thursday)
        #expect(date(2000, 1, 1).weekday == .saturday)
        #expect(date(1900, 1, 1).weekday == .monday)
        #expect(date(0, 1, 1).weekday == .saturday)
        #expect(date(-1, 12, 31).weekday == .friday)
        // Consecutive days have consecutive weekdays, across the whole range.
        var generator = SplitMix64(seed: 2)
        var bad = 0
        for _ in 0..<50_000 {
            let d = PlainDate.random(using: &generator)
            guard d < .max else { continue }
            if d.adding(days: 1).weekday != d.weekday.advanced(by: 1) { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("Weekday helpers")
    func weekdayHelpers() {
        #expect(Weekday.sunday.advanced(by: 1) == .monday)
        #expect(Weekday.monday.advanced(by: -1) == .sunday)
        #expect(Weekday.wednesday.advanced(by: 7 * 1000 + 2) == .friday)
        #expect(Weekday.wednesday.advanced(by: -15) == .tuesday)
        #expect(Weekday.friday.days(until: .monday) == 3)
        #expect(Weekday.friday.days(until: .friday) == 0)
        #expect(Weekday(isoNumber: 7) == .sunday)
        #expect(Weekday(isoNumber: 0) == nil)
        #expect(Weekday.allCases.count == 7)
    }

    @Test("Day of year")
    func dayOfYear() {
        #expect(date(2024, 1, 1).dayOfYear == 1)
        #expect(date(2024, 3, 1).dayOfYear == 61)
        #expect(date(2023, 3, 1).dayOfYear == 60)
        #expect(date(2024, 12, 31).dayOfYear == 366)
        #expect(PlainDate(year: 2024, dayOfYear: 60) == date(2024, 2, 29))
        #expect(PlainDate(year: 2023, dayOfYear: 366) == nil)
        #expect(PlainDate(year: 2023, dayOfYear: 0) == nil)
        var generator = SplitMix64(seed: 3)
        var bad = 0
        for _ in 0..<50_000 {
            let d = PlainDate.random(using: &generator)
            if PlainDate(year: d.year, dayOfYear: d.dayOfYear) != d { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("ISO week dates", arguments: [
        ((2024, 12, 30), (2025, 1, Weekday.monday)),
        ((2021, 1, 3), (2020, 53, .sunday)),
        ((2026, 1, 1), (2026, 1, .thursday)),
        ((2020, 12, 31), (2020, 53, .thursday)),
        ((2008, 12, 29), (2009, 1, .monday)),
        ((2010, 1, 3), (2009, 53, .sunday)),
        ((2024, 2, 29), (2024, 9, .thursday)),
    ])
    func isoWeekDates(civil: (Int, Int, Int), week: (Int, Int, Weekday)) {
        let d = date(civil.0, civil.1, civil.2)
        let weekDate = d.isoWeekDate
        #expect(weekDate.year == week.0)
        #expect(weekDate.week == week.1)
        #expect(weekDate.weekday == week.2)
        #expect(PlainDate(weekDate) == d)
        #expect(ISOWeekDate(year: week.0, week: week.1, weekday: week.2).flatMap { PlainDate($0) } == d)
    }

    @Test("ISO week dates round-trip and are consecutive")
    func isoWeekRoundTrip() {
        var bad: [PlainDate] = []
        var previous = date(1799, 12, 31).isoWeekDate
        for d in date(1800, 1, 1)...date(2400, 12, 31) {
            let w = d.isoWeekDate
            let expectedNext: (Int, Int)
            if previous.weekday != .sunday {
                expectedNext = (previous.year, previous.week)
            } else if previous.week == ISOWeekDate.weeksInYear(previous.year) {
                expectedNext = (previous.year + 1, 1)
            } else {
                expectedNext = (previous.year, previous.week + 1)
            }
            if PlainDate(w) != d || (w.year, w.week) != expectedNext || w.weekday != d.weekday {
                if bad.count < 10 { bad.append(d) }
            }
            previous = w
        }
        #expect(bad.isEmpty, "\(bad)")
        #expect(ISOWeekDate(year: 2021, week: 53, weekday: .monday) == nil)
        #expect(ISOWeekDate(year: 2020, week: 53, weekday: .monday) != nil)
        #expect(ISOWeekDate(year: 2020, week: 0, weekday: .monday) == nil)
        #expect(date(2024, 12, 30).isoWeekDate.description == "2025-W01-1")
    }

    @Test("Moving to month and year boundaries")
    func boundaries() {
        let d = date(2024, 2, 14)
        #expect(d.firstDayOfMonth == date(2024, 2, 1))
        #expect(d.lastDayOfMonth == date(2024, 2, 29))
        #expect(d.firstDayOfYear == date(2024, 1, 1))
        #expect(d.lastDayOfYear == date(2024, 12, 31))
        #expect(d.daysInMonth == 29)
        #expect(d.quarter == 1)
        #expect(date(2024, 12, 1).quarter == 4)
        #expect(d.yearMonth == PlainYearMonth(year: 2024, month: 2))
        #expect(d.monthDay == PlainMonthDay(month: 2, day: 14))
    }

    @Test("Next and previous weekday")
    func nextAndPrevious() {
        let thursday = date(2024, 2, 29)
        #expect(thursday.next(.friday) == date(2024, 3, 1))
        #expect(thursday.next(.thursday) == date(2024, 3, 7))
        #expect(thursday.nextOrSame(.thursday) == thursday)
        #expect(thursday.nextOrSame(.monday) == date(2024, 3, 4))
        #expect(thursday.previous(.thursday) == date(2024, 2, 22))
        #expect(thursday.previous(.friday) == date(2024, 2, 23))
        #expect(thursday.previousOrSame(.thursday) == thursday)
        #expect(thursday.previousOrSame(.monday) == date(2024, 2, 26))
        for weekday in Weekday.allCases {
            #expect(thursday.next(weekday).weekday == weekday)
            #expect(thursday.previous(weekday).weekday == weekday)
            #expect((1...7).contains(thursday.days(until: thursday.next(weekday))))
            #expect((1...7).contains(thursday.previous(weekday).days(until: thursday)))
        }
    }

    @Test("Comparison and hashing")
    func comparison() {
        #expect(date(2024, 2, 29) < date(2024, 3, 1))
        #expect(date(-1, 12, 31) < date(0, 1, 1))
        #expect(date(-10, 6, 1) < date(-9, 1, 1))
        #expect(PlainDate.min < PlainDate.max)
        #expect(Set([date(2024, 1, 1), date(2024, 1, 1), date(2024, 1, 2)]).count == 2)
        var generator = SplitMix64(seed: 4)
        var bad = 0
        for _ in 0..<50_000 {
            let a = PlainDate.random(using: &generator)
            let b = PlainDate.randomMostlyModern(using: &generator)
            if (a < b) != (a.daysSinceEpoch < b.daysSinceEpoch) || (a == b) != (a.daysSinceEpoch == b.daysSinceEpoch) {
                bad += 1
            }
        }
        #expect(bad == 0)
    }

    @Test("Ranges of dates can be iterated")
    func ranges() {
        let days = Array(date(2024, 2, 27)...date(2024, 3, 2))
        #expect(days == [date(2024, 2, 27), date(2024, 2, 28), date(2024, 2, 29), date(2024, 3, 1), date(2024, 3, 2)])
        #expect((date(2024, 1, 1)..<date(2025, 1, 1)).count == 366)
        #expect(date(2024, 1, 1).distance(to: date(2023, 1, 1)) == -365)
        #expect(Array(stride(from: date(2024, 1, 1), to: date(2024, 1, 22), by: 7)).count == 3)
    }

    @Test("Memory layout stays compact")
    func layout() {
        #expect(MemoryLayout<PlainDate>.size == 6)
        #expect(MemoryLayout<PlainTime>.size == 8)
        #expect(MemoryLayout<PlainDateTime>.size <= 16)
        #expect(MemoryLayout<PlainYearMonth>.size == 5)
        #expect(MemoryLayout<PlainMonthDay>.size == 2)
    }
}
