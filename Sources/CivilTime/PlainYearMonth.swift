/// A month of a particular year, such as February 2024, with no day.
///
/// Use it for billing periods, card expiry dates, monthly reports and
/// calendar pages.
///
/// ```swift
/// let february = PlainYearMonth(year: 2024, month: 2)!
/// february.daysInMonth                 // 29
/// february.lastDay                     // 2024-02-29
/// february.adding(months: 11)          // 2025-01
/// for month in february...february.adding(months: 2) { … }  // 2024-02, 2024-03, 2024-04
/// ```
///
/// The text form is ISO 8601 `YYYY-MM`, such as `2024-02`.
public struct PlainYearMonth: Sendable, Hashable, BitwiseCopyable {
    @usableFromInline let _year: Int32
    @usableFromInline let _month: UInt8

    @inlinable
    init(_uncheckedYear year: Int, month: Int) {
        _year = Int32(truncatingIfNeeded: year)
        _month = UInt8(truncatingIfNeeded: month)
    }

    /// Creates a year-month, or returns `nil` if the month is not 1…12 or the
    /// year is outside -999999…999999.
    @inlinable
    public init?(year: Int, month: Int) {
        guard CivilMath.isValidYear(year), month >= 1, month <= 12 else { return nil }
        self.init(_uncheckedYear: year, month: month)
    }

    /// The year. Year 0 is 1 BC.
    @inlinable public var year: Int { Int(_year) }

    /// The month, from 1 (January) to 12 (December).
    @inlinable public var month: Int { Int(_month) }

    /// The number of days in the month: 28, 29, 30 or 31.
    @inlinable
    public var daysInMonth: Int { CivilMath.daysInMonth(year: year, month: month) }

    /// Whether the year is a leap year in the Gregorian calendar.
    @inlinable
    public var isInLeapYear: Bool { CivilMath.isLeapYear(year) }

    /// The first day of the month.
    @inlinable
    public var firstDay: PlainDate { PlainDate(_uncheckedYear: year, month: month, day: 1) }

    /// The last day of the month.
    @inlinable
    public var lastDay: PlainDate { PlainDate(_uncheckedYear: year, month: month, day: daysInMonth) }

    /// Every day of the month, in order.
    @inlinable
    public var days: ClosedRange<PlainDate> { firstDay...lastDay }

    /// The given day of this month, or `nil` if the month has no such day.
    @inlinable
    public func day(_ day: Int) -> PlainDate? {
        PlainDate(year: year, month: month, day: day)
    }

    /// Returns the year-month moved by a number of years and months.
    ///
    /// For amounts from untrusted input, use ``checkedAdding(years:months:)``.
    ///
    /// - Precondition: The result is within the supported years.
    @inlinable
    public func adding(years: Int = 0, months: Int = 0) -> PlainYearMonth {
        guard let result = checkedAdding(years: years, months: months) else {
            preconditionFailure("PlainYearMonth arithmetic is out of range")
        }
        return result
    }

    /// Returns the year-month moved by a number of years and months, or `nil`
    /// if the result would be outside the supported years. Safe to use with
    /// untrusted input.
    @inlinable
    public func checkedAdding(years: Int = 0, months: Int = 0) -> PlainYearMonth? {
        let (yearMonths, o1) = years.multipliedReportingOverflow(by: 12)
        let (delta, o2) = yearMonths.addingReportingOverflow(months)
        let (index, o3) = _monthIndex.addingReportingOverflow(delta)
        guard !(o1 || o2 || o3) else { return nil }
        return PlainYearMonth(_monthIndex: index)
    }

    /// The number of months from this month to `other`.
    @inlinable
    public func months(until other: PlainYearMonth) -> Int {
        other._monthIndex - _monthIndex
    }

    /// Months since January of year 0.
    @inlinable
    var _monthIndex: Int { year * 12 + month - 1 }

    @inlinable
    init?(_monthIndex index: Int) {
        self.init(year: CivilMath.floorDivide(index, 12), month: CivilMath.floorModulo(index, 12) + 1)
    }
}

extension PlainYearMonth: Comparable {
    @inlinable
    public static func < (lhs: PlainYearMonth, rhs: PlainYearMonth) -> Bool {
        (lhs._year, lhs._month) < (rhs._year, rhs._month)
    }

    @inlinable
    public static func == (lhs: PlainYearMonth, rhs: PlainYearMonth) -> Bool {
        lhs._year == rhs._year && lhs._month == rhs._month
    }
}

/// Year-months are strideable by months.
extension PlainYearMonth: Strideable {
    @inlinable
    public func distance(to other: PlainYearMonth) -> Int {
        months(until: other)
    }

    @inlinable
    public func advanced(by n: Int) -> PlainYearMonth {
        adding(months: n)
    }
}
