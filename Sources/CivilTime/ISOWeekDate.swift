/// A date written as an ISO 8601 week date: week-numbering year, week and
/// weekday, such as `2025-W01-1` for Monday, December 30, 2024.
///
/// ISO weeks start on Monday, and week 1 is the week that contains the year's
/// first Thursday. The week-numbering ``year`` therefore differs from the
/// calendar year for a few days around New Year.
///
/// ```swift
/// let date = PlainDate(year: 2024, month: 12, day: 30)!
/// date.isoWeekDate              // 2025-W01-1
/// date.isoWeekDate.week         // 1
/// date.isoWeekDate.year         // 2025
/// ```
public struct ISOWeekDate: Sendable, Hashable, BitwiseCopyable {
    /// The ISO week-numbering year.
    public let year: Int
    /// The week of the year, from 1 to 52 or 53.
    public let week: Int
    /// The day of the week.
    public let weekday: Weekday

    /// Creates a week date, or returns `nil` if the year has no such week or
    /// the date would be outside the supported years.
    public init?(year: Int, week: Int, weekday: Weekday) {
        guard CivilMath.isValidYear(year), week >= 1, week <= CivilMath.isoWeeksInYear(year)
        else { return nil }
        self.year = year
        self.week = week
        self.weekday = weekday
        guard PlainDate(self) != nil else { return nil }
    }

    @usableFromInline
    init(_uncheckedYear year: Int, week: Int, weekday: Weekday) {
        self.year = year
        self.week = week
        self.weekday = weekday
    }

    /// The number of ISO weeks in a week-numbering year: 52 or 53.
    public static func weeksInYear(_ year: Int) -> Int {
        CivilMath.isoWeeksInYear(year)
    }
}

extension ISOWeekDate: CustomStringConvertible {
    /// The ISO 8601 extended form, such as `2025-W01-1`.
    public var description: String {
        _makeString(capacity: 16) { writer in
            writer.appendYear(year)
            writer.append(ascii: "-")
            writer.append(ascii: "W")
            writer.appendDigits(week, width: 2)
            writer.append(ascii: "-")
            writer.appendDigits(weekday.rawValue, width: 1)
        }
    }
}

extension PlainDate {
    /// The date as an ISO 8601 week date.
    public var isoWeekDate: ISOWeekDate {
        let weekday = self.weekday
        let week = (dayOfYear - weekday.rawValue + 10) / 7
        if week < 1 {
            let previousYear = year - 1
            return ISOWeekDate(
                _uncheckedYear: previousYear,
                week: CivilMath.isoWeeksInYear(previousYear),
                weekday: weekday
            )
        }
        if week > CivilMath.isoWeeksInYear(year) {
            return ISOWeekDate(_uncheckedYear: year + 1, week: 1, weekday: weekday)
        }
        return ISOWeekDate(_uncheckedYear: year, week: week, weekday: weekday)
    }

    /// Creates the date for an ISO 8601 week date, or returns `nil` if it is
    /// outside the supported years.
    public init?(_ weekDate: ISOWeekDate) {
        // Day 4 of January is always in week 1.
        let jan4 = CivilMath.epochDay(year: weekDate.year, month: 1, day: 4)
        let mondayOfWeek1 = jan4 - (CivilMath.isoWeekday(epochDay: jan4) - 1)
        self.init(daysSinceEpoch: mondayOfWeek1 + (weekDate.week - 1) * 7 + (weekDate.weekday.rawValue - 1))
    }
}
