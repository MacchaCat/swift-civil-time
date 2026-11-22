import Testing
@testable import CivilTime

@Suite("Arithmetic")
struct ArithmeticTests {
    @Test("Adding days")
    func addingDays() {
        #expect(date(2024, 2, 28).adding(days: 1) == date(2024, 2, 29))
        #expect(date(2024, 2, 29).adding(days: 1) == date(2024, 3, 1))
        #expect(date(2024, 12, 31).adding(days: 1) == date(2025, 1, 1))
        #expect(date(2024, 1, 1).adding(days: -1) == date(2023, 12, 31))
        #expect(date(2024, 1, 15).adding(weeks: 2) == date(2024, 1, 29))
        #expect(date(2024, 1, 15).adding(weeks: 1, days: -1) == date(2024, 1, 21))
        #expect(date(1970, 1, 1).adding(days: 19_782) == date(2024, 2, 29))
        #expect(PlainDate.max.adding(days: 0) == .max)
        #expect(PlainDate.min.adding(days: CivilMath.maxEpochDay - CivilMath.minEpochDay) == .max)
    }

    @Test("Adding months clamps to the end of the month")
    func addingMonths() {
        #expect(date(2024, 1, 31).adding(months: 1) == date(2024, 2, 29))
        #expect(date(2023, 1, 31).adding(months: 1) == date(2023, 2, 28))
        #expect(date(2024, 1, 31).adding(months: 2) == date(2024, 3, 31))
        #expect(date(2024, 3, 31).adding(months: -1) == date(2024, 2, 29))
        #expect(date(2024, 5, 31).adding(months: 1) == date(2024, 6, 30))
        #expect(date(2024, 1, 31).adding(months: 1, days: 1) == date(2024, 3, 1))
        #expect(date(2024, 2, 29).adding(years: 1) == date(2025, 2, 28))
        #expect(date(2024, 2, 29).adding(years: 4) == date(2028, 2, 29))
        #expect(date(2024, 11, 15).adding(months: 2) == date(2025, 1, 15))
        #expect(date(2024, 1, 15).adding(months: -13) == date(2022, 12, 15))
        #expect(date(0, 1, 1).adding(months: -1) == date(-1, 12, 1))
        #expect(date(2024, 1, 15).adding(years: 1, months: 1) == date(2025, 2, 15))
        #expect(date(2024, 1, 15).adding(DatePeriod(years: 1, months: -1, days: 3)) == date(2024, 12, 18))
    }

    @Test("Adding months agrees with a component-wise definition")
    func addingMonthsProperty() {
        var generator = SplitMix64(seed: 10)
        var bad: [String] = []
        for _ in 0..<100_000 {
            let start = PlainDate.randomMostlyModern(using: &generator)
            let months = Int.random(in: -2400...2400, using: &generator)
            let result = start.adding(months: months)
            let index = start.year * 12 + start.month - 1 + months
            let year = Int((Double(index) / 12).rounded(.down))
            let month = index - year * 12 + 1
            let day = min(start.day, CivilMath.daysInMonth(year: year, month: month))
            if result != PlainDate(year: year, month: month, day: day), bad.count < 10 {
                bad.append("\(start) + \(months)M = \(result)")
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Periods between dates", arguments: [
        ((2024, 1, 15), (2025, 3, 1), (1, 1, 14)),
        ((2024, 1, 31), (2024, 2, 29), (0, 1, 0)),
        ((2024, 1, 31), (2024, 3, 1), (0, 1, 1)),
        ((2024, 1, 31), (2024, 2, 28), (0, 0, 28)),
        ((2024, 3, 31), (2024, 2, 29), (0, -1, 0)),
        ((2024, 3, 1), (2024, 1, 31), (0, -1, -1)),
        ((2000, 2, 29), (2025, 2, 28), (25, 0, 0)),
        ((2000, 2, 29), (2024, 2, 28), (23, 11, 30)),
        ((2024, 5, 5), (2024, 5, 5), (0, 0, 0)),
        ((2024, 5, 5), (2024, 5, 1), (0, 0, -4)),
        ((-1, 12, 31), (1, 1, 1), (1, 0, 1)),
    ])
    func periods(start: (Int, Int, Int), end: (Int, Int, Int), expected: (Int, Int, Int)) {
        let a = date(start.0, start.1, start.2)
        let b = date(end.0, end.1, end.2)
        let period = a.period(until: b)
        #expect(period == DatePeriod(years: expected.0, months: expected.1, days: expected.2))
        #expect(a.adding(period) == b)
    }

    @Test("A period always leads back to the end date, with one sign")
    func periodRoundTrip() {
        var generator = SplitMix64(seed: 11)
        var bad: [String] = []
        for _ in 0..<100_000 {
            let a = PlainDate.randomMostlyModern(using: &generator)
            let b: PlainDate
            if Bool.random(using: &generator) {
                b = PlainDate(daysSinceEpoch: a.daysSinceEpoch + Int.random(in: -800...800, using: &generator)) ?? a
            } else {
                b = PlainDate.randomMostlyModern(using: &generator)
            }
            let p = a.period(until: b)
            let signs = [p.years, p.months, p.days].filter { $0 != 0 }.map { $0 > 0 }
            let oneSign = Set(signs).count <= 1
            let monthsInRange = abs(p.months) < 12
            if a.adding(p) != b || !oneSign || !monthsInRange || a.months(until: b) != p.totalMonths {
                if bad.count < 10 { bad.append("\(a) → \(b): \(p)") }
            }
            // A whole month more would overshoot.
            if b > a, a.adding(months: p.totalMonths + 1) <= b, bad.count < 10 {
                bad.append("\(a) → \(b): \(p) is not maximal")
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Ages in whole years")
    func ages() {
        let born = date(1990, 6, 15)
        #expect(born.years(until: date(2024, 6, 14)) == 33)
        #expect(born.years(until: date(2024, 6, 15)) == 34)
        let leapling = date(2000, 2, 29)
        #expect(leapling.years(until: date(2023, 2, 27)) == 22)
        #expect(leapling.years(until: date(2023, 2, 28)) == 23)
        #expect(leapling.years(until: date(2024, 2, 28)) == 23)
        #expect(leapling.years(until: date(2024, 2, 29)) == 24)
        #expect(date(2024, 1, 1).days(until: date(2025, 1, 1)) == 366)
    }

    @Test("Time of day wraps around midnight")
    func timeArithmetic() {
        #expect(time(22, 0).adding(hours: 3) == time(1, 0))
        #expect(time(0, 15).adding(minutes: -30) == time(23, 45))
        #expect(time(12, 0).adding(seconds: 86_400 * 1000 + 1) == time(12, 0, 1))
        #expect(time(0, 0).adding(nanoseconds: -1) == .max)
        #expect(time(23, 59, 59, 999_999_999).adding(nanoseconds: 1) == .midnight)
        #expect(time(10, 0).adding(hours: Int.max) == time(10, 0).adding(hours: Int.max % 24))
        #expect(time(10, 0).adding(hours: Int.min).hour == (10 + Int.min % 24 + 24) % 24)
        #expect(time(10, 30).nanoseconds(until: time(9, 30)) == -3_600_000_000_000)
    }

    @Test("Date-times carry into the date")
    func dateTimeArithmetic() {
        let t = dateTime(2024, 1, 31, 22)
        #expect(t.adding(months: 1) == dateTime(2024, 2, 29, 22))
        #expect(t.adding(months: 1, hours: 3) == dateTime(2024, 3, 1, 1))
        #expect(t.adding(hours: -23) == dateTime(2024, 1, 30, 23))
        #expect(t.adding(minutes: 60 * 24 * 365) == dateTime(2025, 1, 30, 22))
        #expect(t.adding(seconds: -86_400 * 31) == dateTime(2023, 12, 31, 22))
        #expect(t.adding(nanoseconds: 7_200_000_000_000) == dateTime(2024, 2, 1, 0))
        #expect(dateTime(2024, 2, 29).adding(DatePeriod(years: 1)) == dateTime(2025, 2, 28))
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    @Test("Duration arithmetic")
    func durations() {
        let t = dateTime(2024, 3, 10, 1, 30)
        #expect(t.adding(.seconds(3600)) == dateTime(2024, 3, 10, 2, 30))
        #expect(t.adding(.seconds(-90_000)) == dateTime(2024, 3, 9, 0, 30))
        #expect(t.adding(.milliseconds(1500)).nanosecond == 500_000_000)
        #expect(t.adding(.milliseconds(-1500)) == PlainDateTime(year: 2024, month: 3, day: 10, hour: 1, minute: 29, second: 58, nanosecond: 500_000_000))
        #expect(t.duration(until: dateTime(2024, 3, 11, 1, 30)) == .seconds(86_400))
        #expect(dateTime(2024, 3, 11).duration(until: dateTime(2024, 3, 10, 23, 59, 59)) == .seconds(-1))
        #expect(time(23, 0).adding(.seconds(7200)) == time(1, 0))
        #expect(time(1, 0).duration(until: time(23, 0)) == .seconds(79_200))
        // Round trip for random pairs.
        var generator = SplitMix64(seed: 12)
        var bad = 0
        for _ in 0..<20_000 {
            let a = PlainDate.randomMostlyModern(using: &generator).at(PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!)
            let b = PlainDate.randomMostlyModern(using: &generator).at(PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!)
            if a.adding(a.duration(until: b)) != b { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("Seconds since the epoch")
    func secondsSinceEpoch() {
        #expect(dateTime(1970, 1, 1).secondsSinceEpoch == (0, 0))
        #expect(dateTime(2024, 2, 29, 12).secondsSinceEpoch.seconds == 1_709_208_000)
        #expect(PlainDateTime(secondsSinceEpoch: -1) == dateTime(1969, 12, 31, 23, 59, 59))
        #expect(PlainDateTime(secondsSinceEpoch: 0, nanoseconds: -1) == PlainDateTime(year: 1969, month: 12, day: 31, hour: 23, minute: 59, second: 59, nanosecond: 999_999_999))
        #expect(PlainDateTime(secondsSinceEpoch: 0, nanoseconds: 2_500_000_000) == PlainDateTime(year: 1970, month: 1, day: 1, second: 2, nanosecond: 500_000_000))
        #expect(PlainDateTime(secondsSinceEpoch: Int64.max) == nil)
        #expect(PlainDateTime(secondsSinceEpoch: Int64.min) == nil)
        var generator = SplitMix64(seed: 13)
        var bad = 0
        for _ in 0..<50_000 {
            let d = PlainDate.random(using: &generator).at(PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!)
            let (s, n) = d.secondsSinceEpoch
            if PlainDateTime(secondsSinceEpoch: s, nanoseconds: Int64(n)) != d { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("Checked arithmetic returns nil instead of trapping")
    func checkedArithmetic() throws {
        #expect(PlainDate.max.checkedAdding(days: 1) == nil)
        #expect(PlainDate.min.checkedAdding(days: -1) == nil)
        #expect(PlainDate.max.checkedAdding(months: 1) == nil)
        #expect(PlainDate.min.checkedAdding(years: -1) == nil)
        #expect(date(2024, 2, 29).checkedAdding(years: Int.max) == nil)
        #expect(date(2024, 2, 29).checkedAdding(months: Int.min) == nil)
        #expect(date(2024, 2, 29).checkedAdding(weeks: Int.max) == nil)
        #expect(date(2024, 2, 29).checkedAdding(weeks: 1, days: Int.max) == nil)
        #expect(date(2024, 2, 29).checkedAdding(years: 1) == date(2025, 2, 28))
        #expect(date(2024, 1, 31).checkedAdding(DatePeriod(months: 1, days: 1)) == date(2024, 3, 1))

        // A decoded period can be applied safely.
        let hostile = try DatePeriod(parsing: "P999999999999999Y")
        #expect(date(2024, 1, 1).checkedAdding(hostile) == nil)
        #expect(dateTime(2024, 1, 1).checkedAdding(hostile) == nil)

        #expect(PlainDateTime.max.checkedAdding(nanoseconds: 1) == nil)
        #expect(PlainDateTime.min.checkedAdding(hours: -1) == nil)
        #expect(dateTime(2024, 1, 1).checkedAdding(seconds: Int.max) == nil)
        #expect(dateTime(2024, 1, 1).checkedAdding(hours: 25) == dateTime(2024, 1, 2, 1))

        #expect(PlainYearMonth(year: 999_999, month: 12)!.checkedAdding(months: 1) == nil)
        #expect(PlainYearMonth(year: 2024, month: 1)!.checkedAdding(years: Int.max) == nil)
        #expect(PlainYearMonth(year: 2024, month: 1)!.checkedAdding(months: 13) == PlainYearMonth(year: 2025, month: 2))

        // Wherever the result is in range, checked and trapping arithmetic agree.
        var generator = SplitMix64(seed: 14)
        var bad = 0
        for _ in 0..<50_000 {
            let d = PlainDate.randomMostlyModern(using: &generator)
            let months = Int.random(in: -5000...5000, using: &generator)
            let days = Int.random(in: -500_000...500_000, using: &generator)
            guard let checked = d.checkedAdding(months: months, days: days) else {
                // Only far-away dates may leave the range.
                if abs(d.year) < 900_000 { bad += 1 }
                continue
            }
            if checked != d.adding(months: months, days: days) { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("Year-months")
    func yearMonths() {
        let february = PlainYearMonth(year: 2024, month: 2)!
        #expect(february.daysInMonth == 29)
        #expect(february.firstDay == date(2024, 2, 1))
        #expect(february.lastDay == date(2024, 2, 29))
        #expect(february.days.count == 29)
        #expect(february.day(30) == nil)
        #expect(february.adding(months: 11) == PlainYearMonth(year: 2025, month: 1))
        #expect(february.adding(years: -1, months: -2) == PlainYearMonth(year: 2022, month: 12))
        #expect(Array(february...february.adding(months: 2)).map(\.month) == [2, 3, 4])
        #expect(february.months(until: PlainYearMonth(year: 2023, month: 2)!) == -12)
        #expect(PlainYearMonth(year: 2024, month: 13) == nil)
        #expect(PlainYearMonth(year: 0, month: 1)!.adding(months: -1) == PlainYearMonth(year: -1, month: 12))
    }

    @Test("Month-days")
    func monthDays() {
        let leapDay = PlainMonthDay(month: 2, day: 29)!
        #expect(leapDay.isLeapDay)
        #expect(leapDay.date(inYear: 2024) == date(2024, 2, 29))
        #expect(leapDay.date(inYear: 2025) == nil)
        #expect(leapDay.date(inYear: 2025, ifMissing: .previousDay) == date(2025, 2, 28))
        #expect(leapDay.date(inYear: 2025, ifMissing: .nextDay) == date(2025, 3, 1))
        #expect(leapDay.date(inYear: 2024, ifMissing: .nextDay) == date(2024, 2, 29))
        #expect(PlainMonthDay(month: 2, day: 30) == nil)
        #expect(PlainMonthDay(month: 4, day: 31) == nil)
        #expect(PlainMonthDay(month: 12, day: 25)! > leapDay)
    }

    @Test("Period helpers")
    func periodHelpers() {
        let p = DatePeriod(years: 1, months: 14, days: 3)
        #expect(p.normalized == DatePeriod(years: 2, months: 2, days: 3))
        #expect(p.totalMonths == 26)
        #expect(-p == DatePeriod(years: -1, months: -14, days: -3))
        #expect(p + DatePeriod.weeks(1) == DatePeriod(years: 1, months: 14, days: 10))
        #expect(p - p == .zero)
        #expect(DatePeriod(months: 12) != DatePeriod(years: 1))
        #expect(DatePeriod(years: -1, months: -14).normalized == DatePeriod(years: -2, months: -2))
    }
}
