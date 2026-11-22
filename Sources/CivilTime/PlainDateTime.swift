/// A date and a time of day with no time zone, such as 2024-02-29T09:30.
///
/// A `PlainDateTime` is what a calendar and a wall clock show together. It is
/// not a moment in time until you say where: the same `PlainDateTime` happens
/// at different instants in Tokyo and in New York. Use it for local event
/// times, a SQL `TIMESTAMP` (without time zone) column, or as the input to a
/// time-zone conversion.
///
/// ```swift
/// let start = PlainDateTime(year: 2024, month: 3, day: 10, hour: 1, minute: 30)!
/// start.adding(hours: 1)          // 2024-03-10T02:30:00
/// start.date.weekday              // .sunday
/// ```
///
/// Arithmetic here is calendar arithmetic: every day has exactly 24 hours.
/// Converting to an instant in a time zone that observes daylight saving time
/// is done with `CivilTimeFoundation`, which states how skipped and repeated
/// wall-clock times are resolved.
///
/// The text form is ISO 8601 / RFC 3339 without an offset:
/// `2024-02-29T09:30:00`. Parsing also accepts a lowercase `t` or a space
/// between the date and the time.
public struct PlainDateTime: Sendable, Hashable, BitwiseCopyable {
    /// The calendar date.
    public var date: PlainDate
    /// The time of day.
    public var time: PlainTime

    /// Creates a date-time from a date and a time of day.
    @inlinable
    public init(date: PlainDate, time: PlainTime) {
        self.date = date
        self.time = time
    }

    /// Creates a date-time from its components, or returns `nil` if they do
    /// not form a valid date and time.
    @inlinable
    public init?(
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0, nanosecond: Int = 0
    ) {
        guard let date = PlainDate(year: year, month: month, day: day),
              let time = PlainTime(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
        else { return nil }
        self.init(date: date, time: time)
    }

    @inlinable public var year: Int { date.year }
    @inlinable public var month: Int { date.month }
    @inlinable public var day: Int { date.day }
    @inlinable public var hour: Int { time.hour }
    @inlinable public var minute: Int { time.minute }
    @inlinable public var second: Int { time.second }
    @inlinable public var nanosecond: Int { time.nanosecond }

    /// The earliest supported date-time, -999999-01-01T00:00:00.
    public static let min = PlainDateTime(date: .min, time: .min)

    /// The latest supported date-time, +999999-12-31T23:59:59.999999999.
    public static let max = PlainDateTime(date: .max, time: .max)

    /// The number of seconds from 1970-01-01T00:00:00 to this date-time,
    /// counting every day as 86,400 seconds, plus the remaining nanoseconds.
    ///
    /// This is the "local" counterpart of a Unix timestamp: it treats the
    /// date-time as if it were in UTC.
    @inlinable
    public var secondsSinceEpoch: (seconds: Int64, nanoseconds: Int32) {
        let seconds = Int64(date.daysSinceEpoch) * CivilMath.secondsPerDay
            + Int64(time.secondsSinceMidnight)
        return (seconds, Int32(time.nanosecond))
    }

    /// Creates the date-time that is a number of seconds and nanoseconds after
    /// 1970-01-01T00:00:00, counting every day as 86,400 seconds, or returns
    /// `nil` if it is outside the supported years.
    ///
    /// `nanoseconds` may be negative or exceed one second; it is carried into
    /// the seconds.
    @inlinable
    public init?(secondsSinceEpoch seconds: Int64, nanoseconds: Int64 = 0) {
        let n = nanoseconds.quotientAndRemainder(dividingBy: CivilMath.nanosecondsPerSecond)
        let (totalSeconds, overflow) = seconds.addingReportingOverflow(n.quotient)
        guard !overflow else { return nil }
        var days = CivilMath.floorDivide(totalSeconds, CivilMath.secondsPerDay)
        var nanosecondOfDay = CivilMath.floorModulo(totalSeconds, CivilMath.secondsPerDay)
            * CivilMath.nanosecondsPerSecond + n.remainder
        if nanosecondOfDay < 0 {
            days -= 1
            nanosecondOfDay += CivilMath.nanosecondsPerDay
        } else if nanosecondOfDay >= CivilMath.nanosecondsPerDay {
            days += 1
            nanosecondOfDay -= CivilMath.nanosecondsPerDay
        }
        guard days >= Int64(CivilMath.minEpochDay), days <= Int64(CivilMath.maxEpochDay),
              let date = PlainDate(daysSinceEpoch: Int(days))
        else { return nil }
        self.init(date: date, time: PlainTime(_uncheckedNanosecondOfDay: nanosecondOfDay))
    }
}

extension PlainDateTime: Comparable {
    @inlinable
    public static func < (lhs: PlainDateTime, rhs: PlainDateTime) -> Bool {
        lhs.date != rhs.date ? lhs.date < rhs.date : lhs.time < rhs.time
    }
}

// MARK: - Arithmetic

extension PlainDateTime {
    /// Returns the date-time moved by calendar and clock amounts.
    ///
    /// The date part moves first, as in
    /// ``PlainDate/adding(years:months:weeks:days:)``: years and months clamp
    /// the day to the end of the month, then weeks and days are added. The
    /// time part is then added with exactly 24 hours in every day, carrying
    /// into the date as needed.
    ///
    /// ```swift
    /// let t = PlainDateTime(year: 2024, month: 1, day: 31, hour: 22)!
    /// t.adding(months: 1)             // 2024-02-29T22:00:00
    /// t.adding(months: 1, hours: 3)   // 2024-03-01T01:00:00
    /// ```
    ///
    /// - Precondition: The result is between ``min`` and ``max``.
    @inlinable
    public func adding(
        years: Int = 0, months: Int = 0, weeks: Int = 0, days: Int = 0,
        hours: Int = 0, minutes: Int = 0, seconds: Int = 0, nanoseconds: Int = 0
    ) -> PlainDateTime {
        var newDate = date.adding(years: years, months: months, weeks: weeks, days: days)
        let offset = time._offset(hours: hours, minutes: minutes, seconds: seconds, nanoseconds: nanoseconds)
        if offset.days != 0 {
            newDate = newDate.adding(days: offset.days)
        }
        return PlainDateTime(date: newDate, time: PlainTime(_uncheckedNanosecondOfDay: offset.nanosecondOfDay))
    }

    /// Returns the date-time moved by a ``DatePeriod``.
    ///
    /// - Precondition: The result is between ``min`` and ``max``.
    @inlinable
    public func adding(_ period: DatePeriod) -> PlainDateTime {
        PlainDateTime(date: date.adding(period), time: time)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension PlainDateTime {
    /// Returns the date-time moved by `duration`, with exactly 24 hours in
    /// every day. Fractions below one nanosecond are dropped.
    ///
    /// - Precondition: The result is between ``min`` and ``max``.
    @inlinable
    public func adding(_ duration: Duration) -> PlainDateTime {
        let (seconds, nanoseconds) = _secondsAndNanoseconds(of: duration)
        let (days, remainder) = seconds.quotientAndRemainder(dividingBy: CivilMath.secondsPerDay)
        guard let wholeDays = Int(exactly: days) else {
            preconditionFailure("PlainDateTime arithmetic is out of range")
        }
        return adding(days: wholeDays, seconds: Int(remainder), nanoseconds: Int(nanoseconds))
    }

    /// The time from this date-time to `other`, counting every day as
    /// exactly 24 hours; negative if `other` is earlier.
    @inlinable
    public func duration(until other: PlainDateTime) -> Duration {
        let days = Int64(other.date.daysSinceEpoch - date.daysSinceEpoch)
        return .seconds(days * CivilMath.secondsPerDay)
            + .nanoseconds(other.time._nanosecondOfDay - time._nanosecondOfDay)
    }
}
