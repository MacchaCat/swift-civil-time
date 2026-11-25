/// A time of day — hour, minute, second and nanosecond — with no date and no
/// time zone.
///
/// Use `PlainTime` for wall-clock times that repeat every day: opening hours,
/// an alarm, a daily reminder, a SQL `TIME` column.
///
/// ```swift
/// let opening = PlainTime(hour: 9, minute: 30)!
/// opening.adding(hours: 15)       // 00:30:00 — wraps past midnight
/// PlainTime("23:59:59.5")         // Optional(23:59:59.5)
/// PlainTime("24:00")              // nil
/// ```
///
/// Values run from 00:00:00 to 23:59:59.999999999. There are no leap seconds:
/// when parsing, a seconds field of `60` reads as `59`.
///
/// The text form is ISO 8601 extended format, `HH:MM:SS` followed by a
/// fraction only when the time has one, with trailing zeros removed:
/// `09:30:00`, `23:59:59.5`, `12:00:00.000001`.
public struct PlainTime: Sendable, Hashable, BitwiseCopyable {
    @usableFromInline let _nanosecondOfDay: Int64

    @inlinable
    init(_uncheckedNanosecondOfDay nanoseconds: Int64) {
        _nanosecondOfDay = nanoseconds
    }

    /// Creates a time of day, or returns `nil` if a component is out of range.
    ///
    /// - Parameters:
    ///   - hour: 0 to 23.
    ///   - minute: 0 to 59.
    ///   - second: 0 to 59.
    ///   - nanosecond: 0 to 999,999,999.
    @inlinable
    public init?(hour: Int, minute: Int, second: Int = 0, nanosecond: Int = 0) {
        guard hour >= 0, hour < 24, minute >= 0, minute < 60, second >= 0, second < 60,
              nanosecond >= 0, nanosecond < 1_000_000_000
        else { return nil }
        let seconds = Int64(hour * 3600 + minute * 60 + second)
        self.init(_uncheckedNanosecondOfDay: seconds * CivilMath.nanosecondsPerSecond + Int64(nanosecond))
    }

    /// Creates the time that is a number of nanoseconds after midnight, or
    /// returns `nil` unless the value is in `0 ..< 86_400_000_000_000`.
    @inlinable
    public init?(nanosecondsSinceMidnight: Int64) {
        guard nanosecondsSinceMidnight >= 0, nanosecondsSinceMidnight < CivilMath.nanosecondsPerDay
        else { return nil }
        self.init(_uncheckedNanosecondOfDay: nanosecondsSinceMidnight)
    }

    /// Creates the time that is a number of whole seconds after midnight, or
    /// returns `nil` unless the value is in `0 ..< 86_400`.
    @inlinable
    public init?(secondsSinceMidnight: Int) {
        guard secondsSinceMidnight >= 0, secondsSinceMidnight < 86_400 else { return nil }
        self.init(_uncheckedNanosecondOfDay: Int64(secondsSinceMidnight) * CivilMath.nanosecondsPerSecond)
    }

    /// The hour, from 0 to 23.
    @inlinable
    public var hour: Int { Int(_nanosecondOfDay / (3600 * CivilMath.nanosecondsPerSecond)) }

    /// The minute, from 0 to 59.
    @inlinable
    public var minute: Int { Int(_nanosecondOfDay / (60 * CivilMath.nanosecondsPerSecond) % 60) }

    /// The second, from 0 to 59.
    @inlinable
    public var second: Int { Int(_nanosecondOfDay / CivilMath.nanosecondsPerSecond % 60) }

    /// The fraction of the second, in nanoseconds, from 0 to 999,999,999.
    @inlinable
    public var nanosecond: Int { Int(_nanosecondOfDay % CivilMath.nanosecondsPerSecond) }

    /// The number of nanoseconds since midnight.
    @inlinable
    public var nanosecondsSinceMidnight: Int64 { _nanosecondOfDay }

    /// The number of whole seconds since midnight.
    @inlinable
    public var secondsSinceMidnight: Int { Int(_nanosecondOfDay / CivilMath.nanosecondsPerSecond) }

    /// 00:00:00, the start of the day.
    public static let midnight = PlainTime(_uncheckedNanosecondOfDay: 0)

    /// 12:00:00.
    public static let noon = PlainTime(_uncheckedNanosecondOfDay: 12 * 3600 * 1_000_000_000)

    /// 00:00:00, the earliest time of day.
    public static let min = PlainTime(_uncheckedNanosecondOfDay: 0)

    /// 23:59:59.999999999, the latest time of day.
    public static let max = PlainTime(_uncheckedNanosecondOfDay: 86_400 * 1_000_000_000 - 1)

    /// The time with the fraction of a second removed.
    @inlinable
    public var truncatedToSeconds: PlainTime {
        PlainTime(_uncheckedNanosecondOfDay: _nanosecondOfDay - _nanosecondOfDay % CivilMath.nanosecondsPerSecond)
    }
}

extension PlainTime: Comparable {
    @inlinable
    public static func < (lhs: PlainTime, rhs: PlainTime) -> Bool {
        lhs._nanosecondOfDay < rhs._nanosecondOfDay
    }
}

// MARK: - Arithmetic

extension PlainTime {
    /// Returns the time moved by an amount of hours, minutes, seconds and
    /// nanoseconds, wrapping around midnight.
    ///
    /// ```swift
    /// PlainTime(hour: 22, minute: 0)!.adding(hours: 3)     // 01:00:00
    /// PlainTime(hour: 0, minute: 15)!.adding(minutes: -30) // 23:45:00
    /// ```
    ///
    /// Use ``PlainDateTime/adding(years:months:weeks:days:hours:minutes:seconds:nanoseconds:)``
    /// to carry the overflow into the date.
    @inlinable
    public func adding(hours: Int = 0, minutes: Int = 0, seconds: Int = 0, nanoseconds: Int = 0) -> PlainTime {
        PlainTime(_uncheckedNanosecondOfDay: _offset(hours: hours, minutes: minutes, seconds: seconds, nanoseconds: nanoseconds).nanosecondOfDay)
    }

    /// Adds a time span to this time and returns the new time of day plus the
    /// number of days carried (negative when moving back past midnight).
    @inlinable
    func _offset(hours: Int, minutes: Int, seconds: Int, nanoseconds: Int)
        -> (days: Int, nanosecondOfDay: Int64)
    {
        // Split every component into whole days and a remainder first, so
        // that no intermediate product can overflow.
        let h = hours.quotientAndRemainder(dividingBy: 24)
        let m = minutes.quotientAndRemainder(dividingBy: 1440)
        let s = seconds.quotientAndRemainder(dividingBy: 86_400)
        let n = Int64(nanoseconds).quotientAndRemainder(dividingBy: CivilMath.nanosecondsPerDay)
        let partial: Int64 = _nanosecondOfDay
            + Int64(h.remainder) * 3600 * CivilMath.nanosecondsPerSecond
            + Int64(m.remainder) * 60 * CivilMath.nanosecondsPerSecond
            + Int64(s.remainder) * CivilMath.nanosecondsPerSecond
            + n.remainder
        let carry = CivilMath.floorDivide(partial, CivilMath.nanosecondsPerDay)
        let nanosecondOfDay = CivilMath.floorModulo(partial, CivilMath.nanosecondsPerDay)
        let (d1, o1) = h.quotient.addingReportingOverflow(m.quotient)
        let (d2, o2) = d1.addingReportingOverflow(s.quotient)
        let (d3, o3) = d2.addingReportingOverflow(Int(n.quotient))
        let (days, o4) = d3.addingReportingOverflow(Int(carry))
        precondition(!(o1 || o2 || o3 || o4), "time arithmetic overflowed")
        return (days, nanosecondOfDay)
    }

    /// The number of nanoseconds from this time to `other`, within the same
    /// day; negative if `other` is earlier.
    @inlinable
    public func nanoseconds(until other: PlainTime) -> Int64 {
        other._nanosecondOfDay - _nanosecondOfDay
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension PlainTime {
    /// Returns the time moved by `duration`, wrapping around midnight.
    /// Fractions below one nanosecond are dropped.
    @inlinable
    public func adding(_ duration: Duration) -> PlainTime {
        // Only the position within a day matters here, so drop whole days
        // first. That also keeps durations too long for Int64 seconds, and
        // values too large for `Int` on 32-bit platforms, out of the way.
        let wholeDays = (duration / 86_400).components.seconds
        let withinDays = duration - .seconds(86_400) * wholeDays
        let (seconds, nanoseconds) = _secondsAndNanoseconds(of: withinDays)!
        return PlainTime(_uncheckedNanosecondOfDay: _offset(
            hours: 0, minutes: 0, seconds: Int(seconds % 86_400), nanoseconds: Int(nanoseconds)
        ).nanosecondOfDay)
    }

    /// The time from this time to `other` within the same day; negative if
    /// `other` is earlier.
    @inlinable
    public func duration(until other: PlainTime) -> Duration {
        .nanoseconds(other._nanosecondOfDay - _nanosecondOfDay)
    }
}

/// Splits a duration into whole seconds and nanoseconds, dropping any
/// fraction of a nanosecond (rounding toward zero), or returns `nil` if the
/// whole seconds do not fit in `Int64`. (`Duration.components` traps then.)
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@inlinable
func _secondsAndNanoseconds(of duration: Duration) -> (seconds: Int64, nanoseconds: Int64)? {
    guard duration < .seconds(Int64.max), duration > .seconds(Int64.min) else { return nil }
    let components = duration.components
    return (components.seconds, components.attoseconds / 1_000_000_000)
}
