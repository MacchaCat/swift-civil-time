/// An amount of calendar time in years, months and days, such as
/// "1 year, 2 months and 10 days".
///
/// It is not a fixed length of time: one month can be 28 to 31 days, and its
/// effect depends on the date you add it to. Use it with
/// ``PlainDate/adding(_:)`` and ``PlainDate/dateDuration(until:)``. For
/// durations that also have hours, minutes and seconds, use
/// ``DateTimeDuration``; for an exact length of time, use Swift's `Duration`.
///
/// This type was called `DatePeriod` before version 0.3.0.
///
/// ```swift
/// let start = PlainDate(year: 2024, month: 1, day: 15)!
/// let p = DateDuration(months: 1, days: 10)
/// start.adding(p)                            // 2024-02-25
/// start.dateDuration(until: PlainDate(year: 2025, month: 3, day: 1)!)  // P1Y1M14D
/// ```
///
/// Equality compares the components, so `P12M` and `P1Y` are different values
/// even though they always move a date by the same amount.
///
/// The text form is an ISO 8601 duration with date components only: `P1Y2M10D`,
/// `P0D`, or `-P1M` when every component is negative or zero. A duration with
/// mixed signs puts the sign on each component, as `P1Y-2M`. Parsing also
/// accepts weeks (`P2W` reads as 14 days).
public struct DateDuration: Sendable, Hashable, BitwiseCopyable {
    /// The number of years.
    public var years: Int
    /// The number of months.
    public var months: Int
    /// The number of days.
    public var days: Int

    /// Creates a duration. Components may be negative.
    @inlinable
    public init(years: Int = 0, months: Int = 0, days: Int = 0) {
        self.years = years
        self.months = months
        self.days = days
    }

    /// A duration of whole weeks, stored as days.
    @inlinable
    public static func weeks(_ weeks: Int) -> DateDuration {
        DateDuration(days: weeks * 7)
    }

    /// The duration with no years, months or days.
    public static let zero = DateDuration()

    /// Whether every component is zero.
    @inlinable
    public var isZero: Bool { years == 0 && months == 0 && days == 0 }

    /// Years and months together, in months.
    @inlinable
    public var totalMonths: Int { years * 12 + months }

    /// The duration with every component's sign flipped.
    @inlinable
    public var negated: DateDuration {
        DateDuration(years: -years, months: -months, days: -days)
    }

    /// The duration with months of 12 or more moved into years, keeping the
    /// sign of the total: `P1Y14M` becomes `P2Y2M`. Days are unchanged.
    @inlinable
    public var normalized: DateDuration {
        let total = totalMonths
        return DateDuration(years: total / 12, months: total % 12, days: days)
    }

    @inlinable
    public static prefix func - (duration: DateDuration) -> DateDuration {
        duration.negated
    }

    @inlinable
    public static func + (lhs: DateDuration, rhs: DateDuration) -> DateDuration {
        DateDuration(years: lhs.years + rhs.years, months: lhs.months + rhs.months, days: lhs.days + rhs.days)
    }

    @inlinable
    public static func - (lhs: DateDuration, rhs: DateDuration) -> DateDuration {
        lhs + rhs.negated
    }
}

/// The name of ``DateDuration`` before version 0.3.0.
@available(*, deprecated, renamed: "DateDuration")
public typealias DatePeriod = DateDuration
