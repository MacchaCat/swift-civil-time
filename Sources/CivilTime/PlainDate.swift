/// A calendar date — year, month and day — with no time of day and no time zone.
///
/// Use `PlainDate` for values that mean a day on the calendar rather than a
/// moment in time: birthdays, due dates, holidays, billing days, a SQL `DATE`
/// column, an OpenAPI `format: date` field. A `PlainDate` reads the same in
/// every time zone, so it never shifts by a day when it travels between
/// devices, servers and databases.
///
/// ```swift
/// let birthday = PlainDate(year: 1990, month: 2, day: 28)!
/// birthday.weekday                       // .wednesday
/// birthday.adding(years: 30)             // 2020-02-28
/// PlainDate("2024-02-29")                // Optional(2024-02-29)
/// PlainDate("2023-02-29")                // nil — not a real date
/// ```
///
/// Dates use the proleptic Gregorian calendar, the calendar of ISO 8601, for
/// every year from -999999 to +999999. Year 0 is 1 BC, year -1 is 2 BC, and so
/// on. Every `PlainDate` value is a real date: the initializers check the
/// month and day, and arithmetic stops with a runtime error, like integer
/// overflow, if a result falls outside the supported years.
///
/// The text form is ISO 8601 / RFC 3339 `full-date`: `2024-02-29`. Years
/// outside 0000…9999 use the expanded form with a sign and six digits, such as
/// `+012024-02-29` or `-000044-03-15`.
public struct PlainDate: Sendable, Hashable, BitwiseCopyable {
    @usableFromInline let _year: Int32
    @usableFromInline let _month: UInt8
    @usableFromInline let _day: UInt8

    /// Creates a date without checking the components. Internal use only.
    @inlinable
    init(_uncheckedYear year: Int, month: Int, day: Int) {
        _year = Int32(truncatingIfNeeded: year)
        _month = UInt8(truncatingIfNeeded: month)
        _day = UInt8(truncatingIfNeeded: day)
    }

    /// Creates a date from its year, month and day, or returns `nil` if there
    /// is no such date.
    ///
    /// ```swift
    /// PlainDate(year: 2024, month: 2, day: 29)   // 2024-02-29
    /// PlainDate(year: 2023, month: 2, day: 29)   // nil
    /// PlainDate(year: 2024, month: 13, day: 1)   // nil
    /// ```
    ///
    /// - Parameters:
    ///   - year: The proleptic Gregorian year, from -999999 to 999999.
    ///     Year 0 is 1 BC.
    ///   - month: The month, from 1 (January) to 12 (December).
    ///   - day: The day of the month, starting at 1.
    @inlinable
    public init?(year: Int, month: Int, day: Int) {
        guard CivilMath.isValidYear(year),
              month >= 1, month <= 12,
              day >= 1, day <= CivilMath.daysInMonth(year: year, month: month)
        else { return nil }
        self.init(_uncheckedYear: year, month: month, day: day)
    }

    /// Creates the date that is a number of days after 1970-01-01, or returns
    /// `nil` if that date is outside the supported years.
    ///
    /// ```swift
    /// PlainDate(daysSinceEpoch: 0)       // 1970-01-01
    /// PlainDate(daysSinceEpoch: 19_782)  // 2024-02-29
    /// ```
    @inlinable
    public init?(daysSinceEpoch: Int) {
        guard daysSinceEpoch >= CivilMath.minEpochDay, daysSinceEpoch <= CivilMath.maxEpochDay
        else { return nil }
        let (year, month, day) = CivilMath.civil(fromEpochDay: daysSinceEpoch)
        self.init(_uncheckedYear: year, month: month, day: day)
    }

    /// Creates the date with the given day of the year, or returns `nil` if
    /// there is no such date.
    ///
    /// ```swift
    /// PlainDate(year: 2024, dayOfYear: 60)   // 2024-02-29
    /// PlainDate(year: 2023, dayOfYear: 366)  // nil
    /// ```
    @inlinable
    public init?(year: Int, dayOfYear: Int) {
        guard CivilMath.isValidYear(year),
              dayOfYear >= 1, dayOfYear <= CivilMath.daysInYear(year)
        else { return nil }
        self.init(daysSinceEpoch: CivilMath.epochDay(year: year, month: 1, day: 1) + dayOfYear - 1)
    }

    /// The year. Year 0 is 1 BC, year -1 is 2 BC, and so on.
    @inlinable public var year: Int { Int(_year) }

    /// The month, from 1 (January) to 12 (December).
    @inlinable public var month: Int { Int(_month) }

    /// The day of the month, starting at 1.
    @inlinable public var day: Int { Int(_day) }

    /// The number of days from 1970-01-01 to this date; negative before 1970.
    ///
    /// This is the same day number that Postgres, Arrow, Parquet and Avro
    /// use for dates, shifted only by their epoch.
    @inlinable
    public var daysSinceEpoch: Int {
        CivilMath.epochDay(year: year, month: month, day: day)
    }

    /// The earliest supported date, -999999-01-01.
    public static let min = PlainDate(_uncheckedYear: CivilMath.minYear, month: 1, day: 1)

    /// The latest supported date, +999999-12-31.
    public static let max = PlainDate(_uncheckedYear: CivilMath.maxYear, month: 12, day: 31)

    /// 1970-01-01, the day that ``daysSinceEpoch`` counts from.
    public static let unixEpoch = PlainDate(_uncheckedYear: 1970, month: 1, day: 1)
}

// MARK: - Comparing

extension PlainDate: Comparable {
    /// A single integer that orders dates the same way the calendar does.
    @inlinable
    var _sortKey: Int64 {
        Int64(_year) << 16 | Int64(_month) << 8 | Int64(_day)
    }

    @inlinable
    public static func == (lhs: PlainDate, rhs: PlainDate) -> Bool {
        lhs._year == rhs._year && lhs._month == rhs._month && lhs._day == rhs._day
    }

    @inlinable
    public static func < (lhs: PlainDate, rhs: PlainDate) -> Bool {
        lhs._sortKey < rhs._sortKey
    }
}

/// Dates are strideable by days, so ranges of dates can be iterated:
///
/// ```swift
/// for day in start...end { … }
/// (start..<end).count   // number of days
/// ```
extension PlainDate: Strideable {
    /// The number of days from this date to `other`.
    @inlinable
    public func distance(to other: PlainDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    /// The date `n` days after this one (or before, for a negative `n`).
    @inlinable
    public func advanced(by n: Int) -> PlainDate {
        adding(days: n)
    }
}

// MARK: - Calendar facts

extension PlainDate {
    /// The day of the week.
    @inlinable
    public var weekday: Weekday {
        Weekday(rawValue: CivilMath.isoWeekday(epochDay: daysSinceEpoch))!
    }

    /// The day of the year, from 1 (January 1) to 365 or 366.
    @inlinable
    public var dayOfYear: Int {
        CivilMath.dayOfYear(year: year, month: month, day: day)
    }

    /// Whether the date's year is a leap year in the Gregorian calendar.
    @inlinable
    public var isInLeapYear: Bool {
        CivilMath.isLeapYear(year)
    }

    /// The number of days in the date's month: 28, 29, 30 or 31.
    @inlinable
    public var daysInMonth: Int {
        CivilMath.daysInMonth(year: year, month: month)
    }

    /// The number of days in the date's year: 365 or 366.
    @inlinable
    public var daysInYear: Int {
        CivilMath.daysInYear(year)
    }

    /// The quarter of the year, from 1 (January–March) to 4 (October–December).
    @inlinable
    public var quarter: Int {
        (month - 1) / 3 + 1
    }

    /// The year and month of this date.
    @inlinable
    public var yearMonth: PlainYearMonth {
        PlainYearMonth(_uncheckedYear: year, month: month)
    }

    /// The month and day of this date, without the year — for example, a
    /// birthday or an anniversary.
    @inlinable
    public var monthDay: PlainMonthDay {
        PlainMonthDay(_uncheckedMonth: month, day: day)
    }

    /// The date at the given time of day.
    ///
    /// ```swift
    /// date.at(PlainTime(hour: 9, minute: 30)!)   // 2024-02-29T09:30:00
    /// ```
    @inlinable
    public func at(_ time: PlainTime) -> PlainDateTime {
        PlainDateTime(date: self, time: time)
    }
}

// MARK: - Moving around the calendar

extension PlainDate {
    /// The first day of this date's month.
    @inlinable
    public var firstDayOfMonth: PlainDate {
        PlainDate(_uncheckedYear: year, month: month, day: 1)
    }

    /// The last day of this date's month.
    @inlinable
    public var lastDayOfMonth: PlainDate {
        PlainDate(_uncheckedYear: year, month: month, day: daysInMonth)
    }

    /// January 1 of this date's year.
    @inlinable
    public var firstDayOfYear: PlainDate {
        PlainDate(_uncheckedYear: year, month: 1, day: 1)
    }

    /// December 31 of this date's year.
    @inlinable
    public var lastDayOfYear: PlainDate {
        PlainDate(_uncheckedYear: year, month: 12, day: 31)
    }

    /// The first date after this one that falls on `weekday`.
    ///
    /// If this date is already that weekday, the result is one week later.
    @inlinable
    public func next(_ weekday: Weekday) -> PlainDate {
        let delta = self.weekday.days(until: weekday)
        return adding(days: delta == 0 ? 7 : delta)
    }

    /// This date if it falls on `weekday`, otherwise the next date that does.
    @inlinable
    public func nextOrSame(_ weekday: Weekday) -> PlainDate {
        adding(days: self.weekday.days(until: weekday))
    }

    /// The last date before this one that falls on `weekday`.
    ///
    /// If this date is already that weekday, the result is one week earlier.
    @inlinable
    public func previous(_ weekday: Weekday) -> PlainDate {
        let delta = weekday.days(until: self.weekday)
        return adding(days: -(delta == 0 ? 7 : delta))
    }

    /// This date if it falls on `weekday`, otherwise the previous date that does.
    @inlinable
    public func previousOrSame(_ weekday: Weekday) -> PlainDate {
        adding(days: -weekday.days(until: self.weekday))
    }
}

// MARK: - Arithmetic

extension PlainDate {
    /// Returns the date moved by a number of years, months, weeks and days.
    ///
    /// Years and months are applied first, then weeks and days. When the
    /// target month is shorter than the starting day of the month, the day is
    /// clamped to the end of that month:
    ///
    /// ```swift
    /// let jan31 = PlainDate(year: 2024, month: 1, day: 31)!
    /// jan31.adding(months: 1)              // 2024-02-29
    /// jan31.adding(months: 1, days: 1)     // 2024-03-01
    /// PlainDate(year: 2024, month: 2, day: 29)!.adding(years: 1)   // 2025-02-28
    /// ```
    ///
    /// Pass negative values to move backward.
    ///
    /// The program stops with a runtime error, like integer overflow, if the
    /// result would be outside ``min``…``max``. When the amounts come from
    /// outside your program, such as a decoded ``DatePeriod``, use
    /// ``checkedAdding(years:months:weeks:days:)`` instead.
    ///
    /// - Precondition: The result is between ``min`` and ``max``.
    @inlinable
    public func adding(years: Int = 0, months: Int = 0, weeks: Int = 0, days: Int = 0) -> PlainDate {
        guard let result = checkedAdding(years: years, months: months, weeks: weeks, days: days) else {
            preconditionFailure("PlainDate arithmetic is out of range")
        }
        return result
    }

    /// Returns the date moved by a ``DatePeriod``: years and months first,
    /// clamping the day to the end of the month, then days.
    ///
    /// For a period from untrusted input, use ``checkedAdding(_:)``.
    ///
    /// - Precondition: The result is between ``min`` and ``max``.
    @inlinable
    public func adding(_ period: DatePeriod) -> PlainDate {
        adding(years: period.years, months: period.months, days: period.days)
    }

    /// Returns the date moved by a number of years, months, weeks and days,
    /// or `nil` if the result would be outside ``min``…``max``.
    ///
    /// This works exactly like ``adding(years:months:weeks:days:)`` but never
    /// stops the program, so it is safe to use with amounts from untrusted
    /// input.
    ///
    /// ```swift
    /// let period = try JSONDecoder().decode(DatePeriod.self, from: body)
    /// guard let due = start.checkedAdding(period) else { throw BadRequest() }
    /// ```
    @inlinable
    public func checkedAdding(years: Int = 0, months: Int = 0, weeks: Int = 0, days: Int = 0) -> PlainDate? {
        var result = self
        if years != 0 || months != 0 {
            let (yearMonths, o1) = years.multipliedReportingOverflow(by: 12)
            let (totalMonths, o2) = yearMonths.addingReportingOverflow(months)
            guard !o1, !o2, let moved = result._checkedAddingMonths(totalMonths) else { return nil }
            result = moved
        }
        if weeks != 0 || days != 0 {
            let (weekDays, o1) = weeks.multipliedReportingOverflow(by: 7)
            let (totalDays, o2) = weekDays.addingReportingOverflow(days)
            guard !o1, !o2, let moved = result._checkedAddingDays(totalDays) else { return nil }
            result = moved
        }
        return result
    }

    /// Returns the date moved by a ``DatePeriod``, or `nil` if the result would
    /// be outside ``min``…``max``. Safe to use with untrusted input.
    @inlinable
    public func checkedAdding(_ period: DatePeriod) -> PlainDate? {
        checkedAdding(years: period.years, months: period.months, days: period.days)
    }

    @inlinable
    func _checkedAddingDays(_ days: Int) -> PlainDate? {
        // Fast path: stay inside the current month.
        if days > -32 && days < 32 {
            let newDay = day + days
            if newDay >= 1 && newDay <= 28 {
                return PlainDate(_uncheckedYear: year, month: month, day: newDay)
            }
        }
        let (target, overflow) = daysSinceEpoch.addingReportingOverflow(days)
        guard !overflow else { return nil }
        return PlainDate(daysSinceEpoch: target)
    }

    @inlinable
    func _checkedAddingMonths(_ months: Int) -> PlainDate? {
        let (index, overflow) = (year * 12 + (month - 1)).addingReportingOverflow(months)
        guard !overflow else { return nil }
        let newYear = CivilMath.floorDivide(index, 12)
        let newMonth = CivilMath.floorModulo(index, 12) + 1
        guard CivilMath.isValidYear(newYear) else { return nil }
        let newDay = Swift.min(day, CivilMath.daysInMonth(year: newYear, month: newMonth))
        return PlainDate(_uncheckedYear: newYear, month: newMonth, day: newDay)
    }

    @inlinable
    func _addingMonths(_ months: Int) -> PlainDate {
        guard let result = _checkedAddingMonths(months) else {
            preconditionFailure("PlainDate arithmetic is out of range")
        }
        return result
    }

    /// The number of days from this date to `other`; negative if `other` is
    /// earlier.
    @inlinable
    public func days(until other: PlainDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    /// The years, months and days from this date to `other`.
    ///
    /// The result counts as many whole months as fit, then the remaining
    /// days. All three parts have the same sign, and adding the result back
    /// always lands on `other`:
    ///
    /// ```swift
    /// start.adding(start.period(until: end)) == end   // always true
    /// ```
    ///
    /// A month is counted when ``adding(years:months:weeks:days:)`` with that
    /// many months does not pass `other`. Because adding months clamps to the
    /// end of the month, January 31 to February 29 is one month:
    ///
    /// ```swift
    /// let jan31 = PlainDate(year: 2024, month: 1, day: 31)!
    /// jan31.period(until: PlainDate(year: 2024, month: 2, day: 29)!)  // P1M
    /// jan31.period(until: PlainDate(year: 2024, month: 3, day: 1)!)   // P1M1D
    /// ```
    @inlinable
    public func period(until other: PlainDate) -> DatePeriod {
        let months = _wholeMonths(until: other)
        let days = _addingMonths(months).days(until: other)
        return DatePeriod(years: months / 12, months: months % 12, days: days)
    }

    /// The number of whole months from this date to `other`, as counted by
    /// ``period(until:)``; negative if `other` is earlier.
    @inlinable
    public func months(until other: PlainDate) -> Int {
        _wholeMonths(until: other)
    }

    /// The number of whole years from this date to `other`, as counted by
    /// ``period(until:)``; negative if `other` is earlier.
    ///
    /// This is how old someone born on this date is on `other`. A person born
    /// on February 29 turns one year older on February 28 in common years.
    @inlinable
    public func years(until other: PlainDate) -> Int {
        _wholeMonths(until: other) / 12
    }

    @inlinable
    func _wholeMonths(until other: PlainDate) -> Int {
        var months = (other.year - year) * 12 + (other.month - month)
        if other >= self {
            if months > 0 && _addingMonths(months) > other { months -= 1 }
        } else {
            if months < 0 && _addingMonths(months) < other { months += 1 }
        }
        return months
    }
}
