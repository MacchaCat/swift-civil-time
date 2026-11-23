/// A clock reading counted from midnight of a reference day that may run past
/// 24:00, such as 26:30 for 02:30 the next morning.
///
/// Several conventions write times after midnight this way, so that a night
/// stays attached to the day it started on:
///
/// - Japan's 30-hour clock (30時間制), used in TV listings and for late-night
///   opening hours: a show at 25:30 airs at 01:30 after the listed day.
/// - Public-transit timetables in GTFS, where a trip that runs past midnight
///   lists times such as `25:35:00` relative to its service day.
///
/// ```swift
/// let show = ExtendedTime("25:30")!
/// show.hour                                    // 25
/// show.timeOfDay                               // 01:30:00
/// show.days                                    // 1
/// show.dateTime(on: PlainDate("2025-05-02")!)  // 2025-05-03T01:30:00
///
/// ExtendedTime(PlainDateTime("2025-05-03T02:00")!, relativeTo: PlainDate("2025-05-02")!)
/// // 26:00:00
/// ```
///
/// Extended times are ordered and never wrap, so Swift's own ranges work for
/// spans that cross midnight: `ExtendedTime("18:00")!..<ExtendedTime("29:00")!`
/// is a valid `Range<ExtendedTime>`.
///
/// Values run from 00:00:00 up to, but not including, 10000:00:00. The text
/// form is `HH:MM:SS`, with at least two hour digits and the fraction only
/// when there is one: `09:30:00`, `26:30:00`, `25:00:00.5`.
public struct ExtendedTime: Sendable, Hashable, BitwiseCopyable {
    /// Nanoseconds since midnight of the reference day, below 10,000 hours.
    @usableFromInline let _nanoseconds: Int64

    /// Hours are limited to four digits.
    @usableFromInline static let _hourLimit = 10_000

    @usableFromInline static let _nanosecondLimit: Int64 = 10_000 * 3600 * 1_000_000_000

    @inlinable
    init(_uncheckedNanoseconds nanoseconds: Int64) {
        _nanoseconds = nanoseconds
    }

    /// Creates an extended time, or returns `nil` if a component is out of
    /// range.
    ///
    /// - Parameters:
    ///   - hour: 0 to 9999. Values of 24 and above are on following days.
    ///   - minute: 0 to 59.
    ///   - second: 0 to 59.
    ///   - nanosecond: 0 to 999,999,999.
    @inlinable
    public init?(hour: Int, minute: Int, second: Int = 0, nanosecond: Int = 0) {
        guard hour >= 0, hour < Self._hourLimit, minute >= 0, minute < 60, second >= 0, second < 60,
              nanosecond >= 0, nanosecond < 1_000_000_000
        else { return nil }
        let seconds = Int64(hour) * 3600 + Int64(minute * 60 + second)
        self.init(_uncheckedNanoseconds: seconds * CivilMath.nanosecondsPerSecond + Int64(nanosecond))
    }

    /// The extended time that is a number of nanoseconds after midnight of the
    /// reference day, or `nil` if it is negative or 10,000 hours or more.
    @inlinable
    public init?(nanosecondsSinceMidnight nanoseconds: Int64) {
        guard nanoseconds >= 0, nanoseconds < Self._nanosecondLimit else { return nil }
        self.init(_uncheckedNanoseconds: nanoseconds)
    }

    /// The same clock reading on the reference day itself.
    @inlinable
    public init(_ time: PlainTime) {
        self.init(_uncheckedNanoseconds: time._nanosecondOfDay)
    }

    /// The reading of `dateTime` counted from midnight of `date`, or `nil` if
    /// `dateTime` is before that midnight or 10,000 hours or more after it.
    ///
    /// ```swift
    /// let broadcastDay = PlainDate("2025-05-02")!
    /// ExtendedTime(PlainDateTime("2025-05-03T01:30")!, relativeTo: broadcastDay)   // 25:30:00
    /// ```
    @inlinable
    public init?(_ dateTime: PlainDateTime, relativeTo date: PlainDate) {
        let days = Int64(dateTime.date.daysSinceEpoch) - Int64(date.daysSinceEpoch)
        guard days >= 0, days < Int64(Self._hourLimit / 24 + 1) else { return nil }
        self.init(nanosecondsSinceMidnight: days * CivilMath.nanosecondsPerDay + dateTime.time._nanosecondOfDay)
    }

    /// The hour, from 0 to 9999. Hours of 24 and above are on following days.
    @inlinable
    public var hour: Int { Int(_nanoseconds / (3600 * CivilMath.nanosecondsPerSecond)) }

    /// The minute, from 0 to 59.
    @inlinable
    public var minute: Int { Int(_nanoseconds / (60 * CivilMath.nanosecondsPerSecond) % 60) }

    /// The second, from 0 to 59.
    @inlinable
    public var second: Int { Int(_nanoseconds / CivilMath.nanosecondsPerSecond % 60) }

    /// The fraction of the second, in nanoseconds.
    @inlinable
    public var nanosecond: Int { Int(_nanoseconds % CivilMath.nanosecondsPerSecond) }

    /// The number of nanoseconds since midnight of the reference day.
    @inlinable
    public var nanosecondsSinceMidnight: Int64 { _nanoseconds }

    /// The number of whole days after the reference day: 0 before 24:00,
    /// 1 from 24:00 to 47:59, and so on.
    @inlinable
    public var days: Int { Int(_nanoseconds / CivilMath.nanosecondsPerDay) }

    /// The time a wall clock shows: 26:30 is 02:30.
    @inlinable
    public var timeOfDay: PlainTime {
        PlainTime(_uncheckedNanosecondOfDay: _nanoseconds % CivilMath.nanosecondsPerDay)
    }

    /// The date-time of this reading when the reference day is `date`.
    ///
    /// For a date from untrusted input, use ``checkedDateTime(on:)``.
    ///
    /// - Precondition: The result is no later than ``PlainDateTime/max``.
    @inlinable
    public func dateTime(on date: PlainDate) -> PlainDateTime {
        guard let result = checkedDateTime(on: date) else {
            preconditionFailure("ExtendedTime date-time is out of range")
        }
        return result
    }

    /// The date-time of this reading when the reference day is `date`, or
    /// `nil` if it would be later than ``PlainDateTime/max``. Safe to use with
    /// untrusted input.
    @inlinable
    public func checkedDateTime(on date: PlainDate) -> PlainDateTime? {
        guard let day = date.checkedAdding(days: days) else { return nil }
        return PlainDateTime(date: day, time: timeOfDay)
    }
}

extension ExtendedTime: Comparable {
    @inlinable
    public static func < (lhs: ExtendedTime, rhs: ExtendedTime) -> Bool {
        lhs._nanoseconds < rhs._nanoseconds
    }
}

extension Range where Bound == ExtendedTime {
    /// The wall-clock span of this range when the reference day is `date`.
    ///
    /// ```swift
    /// let lateShow = ExtendedTime("25:30")!..<ExtendedTime("26:00")!
    /// lateShow.occurrence(on: PlainDate("2025-05-02")!)
    /// // 2025-05-03T01:30:00..<2025-05-03T02:00:00
    /// ```
    ///
    /// For a date from untrusted input, use ``checkedOccurrence(on:)``.
    ///
    /// - Precondition: The result is no later than ``PlainDateTime/max``.
    @inlinable
    public func occurrence(on date: PlainDate) -> Range<PlainDateTime> {
        guard let result = checkedOccurrence(on: date) else {
            preconditionFailure("ExtendedTime range occurrence is out of range")
        }
        return result
    }

    /// The wall-clock span of this range when the reference day is `date`, or
    /// `nil` if it would run past ``PlainDateTime/max``. Safe to use with
    /// untrusted input.
    @inlinable
    public func checkedOccurrence(on date: PlainDate) -> Range<PlainDateTime>? {
        guard let lower = lowerBound.checkedDateTime(on: date),
              let upper = upperBound.checkedDateTime(on: date)
        else { return nil }
        return lower..<upper
    }
}

extension PlainTimeRange {
    /// The range written with extended hours: the start as a time on the
    /// first day, and the end counted on from it, past 24:00 when the range
    /// crosses midnight.
    ///
    /// ```swift
    /// let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)
    /// bar.extendedRange                  // 21:00:00..<27:00:00
    /// ```
    @inlinable
    public var extendedRange: Range<ExtendedTime> {
        ExtendedTime(_uncheckedNanoseconds: _start)..<ExtendedTime(_uncheckedNanoseconds: _start + _length)
    }

    /// Creates a daily range from a range of extended times, or returns `nil`
    /// if the range is empty or longer than 24 hours.
    ///
    /// The days of the bounds are dropped: 25:00..<27:00 becomes the daily
    /// range 01:00–03:00. Keep the `Range<ExtendedTime>` if you need to know
    /// which day each occurrence belongs to.
    @inlinable
    public init?(_ range: Range<ExtendedTime>) {
        let start = range.lowerBound._nanoseconds % CivilMath.nanosecondsPerDay
        self.init(
            start: PlainTime(_uncheckedNanosecondOfDay: start),
            lengthInNanoseconds: range.upperBound._nanoseconds - range.lowerBound._nanoseconds
        )
    }
}
