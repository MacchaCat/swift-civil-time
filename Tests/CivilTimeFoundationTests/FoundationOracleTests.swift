import CivilTime
import CivilTimeFoundation
import Foundation
import Testing

/// Checks the calendar arithmetic against Foundation's own calendars for
/// every day from 1600 to 2400. Foundation's Gregorian calendar switches to
/// Julian dates before October 1582, so earlier years are covered by the
/// day-by-day walk in the core tests instead.
@Suite("Agreement with Foundation's calendars")
struct FoundationOracleTests {
    static let utc = TimeZone(secondsFromGMT: 0)!

    static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    static var iso8601: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = utc
        return calendar
    }

    @Test("Day numbers, weekdays, days of year and ISO weeks from 1600 to 2400")
    func everyDay() {
        let gregorian = Self.gregorian
        let iso = Self.iso8601
        var mismatches: [String] = []
        for day in PlainDate(year: 1600, month: 1, day: 1)!...PlainDate(year: 2400, month: 12, day: 31)! {
            let instant = Date(timeIntervalSince1970: TimeInterval(day.daysSinceEpoch) * 86_400)
            let c = gregorian.dateComponents([.year, .month, .day, .weekday], from: instant)
            let w = iso.dateComponents([.weekOfYear, .yearForWeekOfYear], from: instant)
            let foundationWeekday = (c.weekday! + 5) % 7 + 1   // Sunday = 1 → ISO 7
            let ordinal = gregorian.ordinality(of: .day, in: .year, for: instant)!
            if c.year != day.year || c.month != day.month || c.day != day.day
                || foundationWeekday != day.weekday.isoNumber
                || ordinal != day.dayOfYear
                || w.weekOfYear != day.isoWeekDate.week || w.yearForWeekOfYear != day.isoWeekDate.year
            {
                if mismatches.count < 10 { mismatches.append("\(day): \(c) \(w)") }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    /// Only days 1–28 are compared, which never need clamping. Older
    /// Foundation releases (seen on macOS 26, and in the swift-foundation
    /// shipped with Swift 6.0–6.3 on Linux and Windows) clamp some
    /// month-end dates to the wrong day when subtracting many months into
    /// February: 2014-05-31 minus 339 months gives 1986-03-01 instead of
    /// 1986-02-28. Clamping is checked against its definition in the core
    /// tests instead.
    @Test("Adding months agrees with Foundation")
    func addingMonths() {
        let gregorian = Self.gregorian
        var generator = SplitMix64(seed: 30)
        var mismatches: [String] = []
        let low = PlainDate(year: 1700, month: 1, day: 1)!.daysSinceEpoch
        let high = PlainDate(year: 2300, month: 12, day: 31)!.daysSinceEpoch
        for _ in 0..<20_000 {
            let start = PlainDate(daysSinceEpoch: Int.random(in: low...high, using: &generator))!
            let months = Int.random(in: -1200...1200, using: &generator)
            guard start.day <= 28 else { continue }
            let ours = start.adding(months: months)
            let instant = Date(timeIntervalSince1970: TimeInterval(start.daysSinceEpoch) * 86_400)
            let theirs = gregorian.date(byAdding: .month, value: months, to: instant)!
            if PlainDate(theirs, in: Self.utc) != ours, mismatches.count < 10 {
                mismatches.append("\(start) + \(months)M: \(ours) vs \(theirs)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("Day counts between dates match Foundation")
    func dayCounts() {
        let gregorian = Self.gregorian
        var generator = SplitMix64(seed: 31)
        var mismatches: [String] = []
        let low = PlainDate(year: 1700, month: 1, day: 1)!.daysSinceEpoch
        let high = PlainDate(year: 2300, month: 12, day: 31)!.daysSinceEpoch
        for _ in 0..<20_000 {
            let a = PlainDate(daysSinceEpoch: Int.random(in: low...high, using: &generator))!
            let b = PlainDate(daysSinceEpoch: Int.random(in: low...high, using: &generator))!
            let ia = Date(timeIntervalSince1970: TimeInterval(a.daysSinceEpoch) * 86_400)
            let ib = Date(timeIntervalSince1970: TimeInterval(b.daysSinceEpoch) * 86_400)
            let theirs = gregorian.dateComponents([.day], from: ia, to: ib).day!
            if theirs != a.days(until: b), mismatches.count < 10 {
                mismatches.append("\(a) → \(b)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }
}

@Suite("DateComponents and formatting")
struct DateComponentsTests {
    @Test("Date components, including years before 1 AD")
    func components() {
        let d = PlainDate(year: 2024, month: 2, day: 29)!
        #expect(d.dateComponents == DateComponents(year: 2024, month: 2, day: 29))
        #expect(PlainDate(DateComponents(year: 2024, month: 2, day: 29)) == d)
        #expect(PlainDate(DateComponents(year: 2023, month: 2, day: 29)) == nil)
        #expect(PlainDate(DateComponents(year: 2024, month: 2)) == nil)
        #expect(PlainDate(DateComponents(calendar: Calendar(identifier: .japanese), year: 6, month: 2, day: 29)) == nil)
        #expect(PlainDate(DateComponents(calendar: Calendar(identifier: .gregorian), year: 2024, month: 2, day: 29)) == d)

        let oneBC = PlainDate(year: 0, month: 6, day: 1)!
        #expect(oneBC.dateComponents == DateComponents(era: 0, year: 1, month: 6, day: 1))
        #expect(PlainDate(oneBC.dateComponents) == oneBC)
        #expect(PlainDate(DateComponents(era: 0, year: 44, month: 3, day: 15)) == PlainDate(year: -43, month: 3, day: 15))

        // Untrusted components must not crash the conversion.
        #expect(PlainDate(DateComponents(era: 0, year: Int.min, month: 1, day: 1)) == nil)
        #expect(PlainDate(DateComponents(era: 0, year: Int.max, month: 1, day: 1)) == nil)
        #expect(PlainDate(DateComponents(year: Int.max, month: Int.max, day: Int.max)) == nil)
        #expect(PlainTime(DateComponents(hour: Int.max, minute: Int.min, second: Int.max, nanosecond: Int.min)) == nil)

        let t = PlainTime(hour: 9, minute: 30, second: 15, nanosecond: 5)!
        #expect(t.dateComponents == DateComponents(hour: 9, minute: 30, second: 15, nanosecond: 5))
        #expect(PlainTime(t.dateComponents) == t)
        #expect(PlainTime(DateComponents(hour: 9)) == nil)
        #expect(PlainTime(DateComponents(hour: 9, minute: 5)) == PlainTime(hour: 9, minute: 5))

        let dt = d.at(t)
        #expect(PlainDateTime(dt.dateComponents) == dt)
        #expect(PlainYearMonth(year: 2024, month: 2)!.dateComponents == DateComponents(year: 2024, month: 2))
    }

    @Test("Formatting shows the civil fields in every device time zone")
    func formatting() {
        let d = PlainDate(year: 2024, month: 2, day: 29)!
        let locale = Locale(identifier: "en_US_POSIX")
        // A style that carries a far-away time zone must not shift the date.
        var style = Date.FormatStyle(date: .numeric, time: .omitted, locale: locale)
        style.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        #expect(d.formatted(style) == "2/29/2024")
        style.timeZone = TimeZone(identifier: "Pacific/Pago_Pago")!
        #expect(d.formatted(style) == "2/29/2024")

        let t = PlainTime(hour: 21, minute: 5)!
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        timeStyle.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(t.formatted(timeStyle).hasPrefix("9:05"))

        let dt = d.at(t)
        var both = Date.FormatStyle(date: .numeric, time: .shortened, locale: locale)
        both.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let text = dt.formatted(both)
        #expect(text.hasPrefix("2/29/2024") && text.contains("9:05"), "\(text)")
    }
}
