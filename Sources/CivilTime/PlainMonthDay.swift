/// A day of the year without the year, such as February 29 or December 25.
///
/// Use it for birthdays, anniversaries and fixed-date holidays that recur
/// every year.
///
/// ```swift
/// let leapDay = PlainMonthDay(month: 2, day: 29)!
/// leapDay.date(inYear: 2024)                    // 2024-02-29
/// leapDay.date(inYear: 2025)                    // nil
/// leapDay.date(inYear: 2025, ifMissing: .previousDay)  // 2025-02-28
/// ```
///
/// The text form is the ISO 8601 / XML Schema `--MM-DD`, such as `--02-29`.
/// Parsing also accepts `MM-DD`.
public struct PlainMonthDay: Sendable, Hashable, BitwiseCopyable {
    @usableFromInline let _month: UInt8
    @usableFromInline let _day: UInt8

    @inlinable
    init(_uncheckedMonth month: Int, day: Int) {
        _month = UInt8(truncatingIfNeeded: month)
        _day = UInt8(truncatingIfNeeded: day)
    }

    /// Creates a month-day, or returns `nil` if the month never has that day.
    /// February 29 is allowed.
    @inlinable
    public init?(month: Int, day: Int) {
        // 2000 is a leap year, so February accepts the 29th.
        guard month >= 1, month <= 12, day >= 1, day <= CivilMath.daysInMonth(year: 2000, month: month)
        else { return nil }
        self.init(_uncheckedMonth: month, day: day)
    }

    /// The month, from 1 (January) to 12 (December).
    @inlinable public var month: Int { Int(_month) }

    /// The day of the month, starting at 1.
    @inlinable public var day: Int { Int(_day) }

    /// Whether this is February 29, which exists only in leap years.
    @inlinable
    public var isLeapDay: Bool { _month == 2 && _day == 29 }

    /// The date with this month and day in `year`, or `nil` if that year has
    /// no such day (February 29 in a common year) or is out of range.
    @inlinable
    public func date(inYear year: Int) -> PlainDate? {
        PlainDate(year: year, month: month, day: day)
    }

    /// The date with this month and day in `year`, using `rule` when the day
    /// does not exist that year (February 29 in a common year).
    ///
    /// - Precondition: `year` is within -999999…999999.
    @inlinable
    public func date(inYear year: Int, ifMissing rule: MissingDayRule) -> PlainDate {
        precondition(CivilMath.isValidYear(year), "year is out of range")
        if let date = PlainDate(year: year, month: month, day: day) { return date }
        let lastDay = PlainDate(_uncheckedYear: year, month: month, day: CivilMath.daysInMonth(year: year, month: month))
        return rule._nextDay ? lastDay.adding(days: 1) : lastDay
    }

    /// What to do when a month-day does not exist in a given year.
    ///
    /// Laws differ on when someone born on February 29 has a birthday in a
    /// common year, so the choice is yours.
    public struct MissingDayRule: Sendable, Hashable {
        @usableFromInline let _nextDay: Bool

        @inlinable
        init(_nextDay: Bool) { self._nextDay = _nextDay }

        /// Use the last day of the month: February 28 for February 29.
        public static let previousDay = MissingDayRule(_nextDay: false)

        /// Use the first day of the next month: March 1 for February 29.
        public static let nextDay = MissingDayRule(_nextDay: true)
    }
}

extension PlainMonthDay: Comparable {
    @inlinable
    public static func < (lhs: PlainMonthDay, rhs: PlainMonthDay) -> Bool {
        (lhs._month, lhs._day) < (rhs._month, rhs._day)
    }
}
