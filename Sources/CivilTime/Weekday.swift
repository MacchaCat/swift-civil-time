/// A day of the week, numbered as in ISO 8601 (Monday = 1 … Sunday = 7).
///
/// ```swift
/// PlainDate(year: 2024, month: 2, day: 29)!.weekday   // .thursday
/// Weekday.sunday.advanced(by: 1)                      // .monday
/// ```
///
/// Which days count as the weekend, and which day starts a week, depend on the
/// locale, so this type does not answer those questions. Foundation's
/// `Calendar` and `Locale` do.
public enum Weekday: Int, Sendable, Hashable, CaseIterable, BitwiseCopyable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    /// The ISO 8601 day number: Monday is 1 and Sunday is 7.
    @inlinable
    public var isoNumber: Int { rawValue }

    /// Creates a weekday from its ISO 8601 number (Monday = 1 … Sunday = 7).
    @inlinable
    public init?(isoNumber: Int) {
        self.init(rawValue: isoNumber)
    }

    /// The weekday `days` days after this one (or before, for a negative value).
    @inlinable
    public func advanced(by days: Int) -> Weekday {
        let offset = days % 7
        let number = (rawValue - 1 + offset + 7) % 7 + 1
        return Weekday(rawValue: number)!
    }

    /// The number of days from this weekday forward to `other`, in `0...6`.
    @inlinable
    public func days(until other: Weekday) -> Int {
        (other.rawValue - rawValue + 7) % 7
    }
}

extension Weekday: CustomStringConvertible {
    public var description: String {
        switch self {
        case .monday: return "monday"
        case .tuesday: return "tuesday"
        case .wednesday: return "wednesday"
        case .thursday: return "thursday"
        case .friday: return "friday"
        case .saturday: return "saturday"
        case .sunday: return "sunday"
        }
    }
}
