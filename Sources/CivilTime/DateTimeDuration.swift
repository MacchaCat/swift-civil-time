/// An amount of calendar and clock time, such as "1 day, 12 hours and 30
/// minutes" (`P1DT12H30M`).
///
/// It combines a ``DateDuration`` (years, months and days, whose length
/// depends on the date) with an exact clock part (hours, minutes, seconds
/// and nanoseconds). Add it to a ``PlainDateTime``, or, with
/// `CivilTimeFoundation`, to a `Date` in a time zone.
///
/// ```swift
/// let stay = DateTimeDuration(days: 1, hours: 12, minutes: 30)
/// stay.description                                       // "P1DT12H30M"
/// PlainDateTime("2025-05-02T21:00")!.adding(stay)        // 2025-05-04T09:30:00
/// DateTimeDuration("PT1.5S")?.nanoseconds                // 500000000
/// ```
///
/// - For an exact length of time with no calendar units, Swift's `Duration`
///   is the right type. It converts to a `DateTimeDuration` with
///   ``init(_:)-(Duration)``, and back with ``exactDuration``.
/// - Equality compares the components, so `PT90M` and `PT1H30M` are
///   different values even though they last equally long.
/// - Components may have different signs, as in ``DateDuration``.
///
/// The text form is an ISO 8601 duration: `P1Y2M10DT2H30M5.25S`, or `PT0S`
/// for zero. When every component is negative or zero it is written with a
/// leading sign, as `-PT0.5S`; with mixed signs each component carries its
/// own, as `P1DT-2H`. Parsing also accepts weeks (`P2W`, read as 14 days)
/// and a comma before the fraction. Only seconds may have a fraction, with
/// up to nine digits.
public struct DateTimeDuration: Sendable, Hashable, BitwiseCopyable {
    /// The number of years.
    public let years: Int
    /// The number of months.
    public let months: Int
    /// The number of days.
    public let days: Int
    /// The number of hours.
    public let hours: Int64
    /// The number of minutes.
    public let minutes: Int64
    /// The number of whole seconds.
    public let seconds: Int64
    /// The fraction of a second, in nanoseconds: less than one second in
    /// magnitude, and never of the opposite sign to ``seconds``.
    public let nanoseconds: Int64

    /// Creates a duration. Components may be negative.
    ///
    /// Weeks are stored as days. Nanoseconds of a second or more are carried
    /// into ``seconds``.
    ///
    /// - Precondition: The days, and the seconds after carrying, fit their
    ///   types.
    @inlinable
    public init(
        years: Int = 0, months: Int = 0, weeks: Int = 0, days: Int = 0,
        hours: Int64 = 0, minutes: Int64 = 0, seconds: Int64 = 0, nanoseconds: Int64 = 0
    ) {
        let (weekDays, o1) = weeks.multipliedReportingOverflow(by: 7)
        let (totalDays, o2) = weekDays.addingReportingOverflow(days)
        precondition(!o1 && !o2, "DateTimeDuration days overflowed")
        let carried = nanoseconds.quotientAndRemainder(dividingBy: 1_000_000_000)
        let (totalSeconds, o3) = seconds.addingReportingOverflow(carried.quotient)
        precondition(!o3, "DateTimeDuration seconds overflowed")
        var s = totalSeconds
        var n = carried.remainder
        // Give the seconds and the fraction one sign. Both steps move the
        // seconds toward zero, so they cannot overflow.
        if s > 0 && n < 0 {
            s -= 1
            n += 1_000_000_000
        } else if s < 0 && n > 0 {
            s += 1
            n -= 1_000_000_000
        }
        self.years = years
        self.months = months
        self.days = totalDays
        self.hours = hours
        self.minutes = minutes
        self.seconds = s
        self.nanoseconds = n
    }

    /// The duration with the same years, months and days, and no clock part.
    @inlinable
    public init(_ duration: DateDuration) {
        self.init(years: duration.years, months: duration.months, days: duration.days)
    }

    /// The duration with no time at all, written `PT0S`.
    public static let zero = DateTimeDuration()

    /// The years, months and days.
    @inlinable
    public var dateDuration: DateDuration {
        DateDuration(years: years, months: months, days: days)
    }

    /// Whether every component is zero.
    @inlinable
    public var isZero: Bool {
        years == 0 && months == 0 && days == 0 && hours == 0 && minutes == 0 && seconds == 0 && nanoseconds == 0
    }

    /// Whether the duration has years, months or days, whose length depends
    /// on the date and, in a time zone, on daylight saving time.
    @inlinable
    public var hasCalendarUnits: Bool { years != 0 || months != 0 || days != 0 }

    /// The clock part as whole seconds and nanoseconds, or `nil` if the
    /// duration has calendar units or the total does not fit in `Int64`
    /// seconds.
    ///
    /// This is ``exactDuration`` for systems without Swift's `Duration`.
    @inlinable
    public var exactSecondsAndNanoseconds: (seconds: Int64, nanoseconds: Int64)? {
        guard !hasCalendarUnits else { return nil }
        return clockSecondsAndNanoseconds
    }

    /// The hours, minutes and seconds as whole seconds plus nanoseconds, or
    /// `nil` if they do not fit in `Int64` seconds. Calendar units are
    /// ignored.
    @inlinable
    public var clockSecondsAndNanoseconds: (seconds: Int64, nanoseconds: Int64)? {
        let (h, o1) = hours.multipliedReportingOverflow(by: 3600)
        let (m, o2) = minutes.multipliedReportingOverflow(by: 60)
        let (hm, o3) = h.addingReportingOverflow(m)
        let (total, o4) = hm.addingReportingOverflow(seconds)
        guard !(o1 || o2 || o3 || o4) else { return nil }
        return (total, nanoseconds)
    }

    /// The duration with every component's sign flipped.
    @inlinable
    public var negated: DateTimeDuration {
        DateTimeDuration(
            years: -years, months: -months, days: -days,
            hours: -hours, minutes: -minutes, seconds: -seconds, nanoseconds: -nanoseconds
        )
    }

    @inlinable
    public static prefix func - (duration: DateTimeDuration) -> DateTimeDuration {
        duration.negated
    }

    /// The component-wise sum.
    @inlinable
    public static func + (lhs: DateTimeDuration, rhs: DateTimeDuration) -> DateTimeDuration {
        DateTimeDuration(
            years: lhs.years + rhs.years, months: lhs.months + rhs.months, days: lhs.days + rhs.days,
            hours: lhs.hours + rhs.hours, minutes: lhs.minutes + rhs.minutes,
            seconds: lhs.seconds + rhs.seconds, nanoseconds: lhs.nanoseconds + rhs.nanoseconds
        )
    }

    /// The component-wise difference.
    @inlinable
    public static func - (lhs: DateTimeDuration, rhs: DateTimeDuration) -> DateTimeDuration {
        lhs + rhs.negated
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension DateTimeDuration {
    /// The duration with the seconds and nanoseconds of an exact `Duration`
    /// and no calendar units. Fractions below one nanosecond are dropped.
    ///
    /// This conversion always succeeds. A `Duration` too long for `Int64`
    /// seconds (more than about 292 billion years) is stored as whole hours
    /// plus the remaining seconds.
    @inlinable
    public init(_ duration: Duration) {
        if let (seconds, nanoseconds) = _secondsAndNanoseconds(of: duration) {
            self.init(seconds: seconds, nanoseconds: nanoseconds)
        } else {
            let hours = (duration / 3600).components.seconds
            let (seconds, nanoseconds) = _secondsAndNanoseconds(of: duration - .seconds(3600) * hours)!
            self.init(hours: hours, seconds: seconds, nanoseconds: nanoseconds)
        }
    }

    /// The duration as an exact `Duration`, or `nil` if it has years, months
    /// or days (a day is not always 24 hours in a time zone) or is too long.
    ///
    /// ```swift
    /// DateTimeDuration(hours: 1, minutes: 30).exactDuration   // .seconds(5400)
    /// DateTimeDuration(days: 1).exactDuration                 // nil
    /// ```
    @inlinable
    public var exactDuration: Duration? {
        guard let (seconds, nanoseconds) = exactSecondsAndNanoseconds else { return nil }
        return .seconds(seconds) + .nanoseconds(nanoseconds)
    }
}

// MARK: - Date-times

extension PlainDateTime {
    /// Returns the date-time moved by a ``DateTimeDuration``.
    ///
    /// The years and months move first, clamping the day to the end of the
    /// month, then the days, then the clock part, with exactly 24 hours in
    /// every day, as ``adding(years:months:weeks:days:hours:minutes:seconds:nanoseconds:)``
    /// does.
    ///
    /// For a duration from untrusted input, use ``checkedAdding(_:)-(DateTimeDuration)``.
    ///
    /// - Precondition: The result is between ``min`` and ``max``.
    @inlinable
    public func adding(_ duration: DateTimeDuration) -> PlainDateTime {
        guard let result = checkedAdding(duration) else {
            preconditionFailure("PlainDateTime arithmetic is out of range")
        }
        return result
    }

    /// Returns the date-time moved by a ``DateTimeDuration``, or `nil` if the
    /// result would be outside ``min``…``max``. Safe to use with untrusted
    /// input.
    @inlinable
    public func checkedAdding(_ duration: DateTimeDuration) -> PlainDateTime? {
        guard let moved = date.checkedAdding(years: duration.years, months: duration.months, days: duration.days),
              let (seconds, nanoseconds) = duration.clockSecondsAndNanoseconds
        else { return nil }
        return PlainDateTime(date: moved, time: time)._checkedAdding(seconds: seconds, nanoseconds: nanoseconds)
    }

    /// The years, months, days, hours, minutes, seconds and nanoseconds from
    /// this date-time to `other`.
    ///
    /// The calendar part counts as in ``PlainDate/dateDuration(until:)`` and
    /// the clock part is less than a day. All components have the same sign,
    /// and adding the result back always lands on `other`:
    ///
    /// ```swift
    /// start.adding(start.dateTimeDuration(until: end)) == end   // always true
    /// ```
    @inlinable
    public func dateTimeDuration(until other: PlainDateTime) -> DateTimeDuration {
        var endDate = other.date
        var clock = other.time._nanosecondOfDay - time._nanosecondOfDay
        if other > self && clock < 0 {
            endDate = endDate.adding(days: -1)
            clock += CivilMath.nanosecondsPerDay
        } else if other < self && clock > 0 {
            endDate = endDate.adding(days: 1)
            clock -= CivilMath.nanosecondsPerDay
        }
        let calendar = date.dateDuration(until: endDate)
        let hours = clock / (3600 * CivilMath.nanosecondsPerSecond)
        let minutes = clock / (60 * CivilMath.nanosecondsPerSecond) % 60
        let seconds = clock / CivilMath.nanosecondsPerSecond % 60
        return DateTimeDuration(
            years: calendar.years, months: calendar.months, days: calendar.days,
            hours: hours, minutes: minutes, seconds: seconds,
            nanoseconds: clock % CivilMath.nanosecondsPerSecond
        )
    }

    /// Adds whole seconds and nanoseconds with 64-bit arithmetic throughout,
    /// returning `nil` instead of trapping when the result is out of range.
    @inlinable
    func _checkedAdding(seconds: Int64, nanoseconds: Int64) -> PlainDateTime? {
        let carried = nanoseconds.quotientAndRemainder(dividingBy: CivilMath.nanosecondsPerSecond)
        let (totalSeconds, overflow) = seconds.addingReportingOverflow(carried.quotient)
        guard !overflow else { return nil }
        let wholeDays = CivilMath.floorDivide(totalSeconds, CivilMath.secondsPerDay)
        let secondOfDay = CivilMath.floorModulo(totalSeconds, CivilMath.secondsPerDay)
        let partial = time._nanosecondOfDay + secondOfDay * CivilMath.nanosecondsPerSecond + carried.remainder
        let (days, o2) = wholeDays.addingReportingOverflow(CivilMath.floorDivide(partial, CivilMath.nanosecondsPerDay))
        guard !o2, let dayCount = Int(exactly: days), let newDate = date.checkedAdding(days: dayCount) else { return nil }
        return PlainDateTime(
            date: newDate,
            time: PlainTime(_uncheckedNanosecondOfDay: CivilMath.floorModulo(partial, CivilMath.nanosecondsPerDay))
        )
    }
}
