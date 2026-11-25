/// A span of wall-clock time that repeats every day and may run past
/// midnight, such as opening hours of 21:00–03:00.
///
/// Swift's `Range<PlainTime>` works for spans within one day, such as
/// 09:00..<18:00, but it cannot wrap: its lower bound must come first. A
/// `PlainTimeRange` is a span on the 24-hour clock instead, so it can start in
/// the evening and end the next morning.
///
/// ```swift
/// let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)
/// bar.contains(PlainTime("01:30")!)      // true
/// bar.contains(PlainTime("12:00")!)      // false
/// bar.crossesMidnight                    // true
///
/// let friday = PlainDate("2025-05-02")!
/// bar.occurrence(startingOn: friday)     // 2025-05-02T21:00:00..<2025-05-03T03:00:00
/// bar.occurrence(containing: PlainDateTime("2025-05-03T01:30")!)
///                                        // the same Friday-night occurrence
/// ```
///
/// The start is included and the end is not. A range is never empty: it lasts
/// more than zero and at most 24 hours. When the start and the end are the
/// same time, the range covers the whole day.
///
/// The text form is an ISO 8601 interval of two times, `21:00:00/03:00:00`.
/// Parsing also accepts an end written with extended hours, so `18:00/24:00`
/// reads as 18:00 until midnight and `18:00/29:00` (Japan's 30-hour clock) as
/// 18:00 until 05:00. ``extendedRange`` gives the same view in code.
///
/// To turn an occurrence into instants in a time zone, use
/// `Range<PlainDateTime>.dateInterval(in:)` from `CivilTimeFoundation`.
public struct PlainTimeRange: Sendable, Hashable, BitwiseCopyable {
    /// Nanoseconds from midnight to the start.
    @usableFromInline let _start: Int64
    /// Length in nanoseconds, in `1 ... nanosecondsPerDay`.
    @usableFromInline let _length: Int64

    @inlinable
    init(_uncheckedStart start: Int64, length: Int64) {
        _start = start
        _length = length
    }

    /// Creates the range from `start` up to, but not including, `end`.
    ///
    /// When `end` is earlier than `start`, the range runs past midnight into
    /// the next day. When `end` equals `start`, the range covers the whole day.
    ///
    /// ```swift
    /// PlainTimeRange(start: PlainTime("09:00")!, end: PlainTime("18:00")!)   // 9 hours
    /// PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)   // 6 hours, past midnight
    /// PlainTimeRange(start: PlainTime("18:00")!, end: .midnight)             // until midnight
    /// PlainTimeRange(start: PlainTime("06:00")!, end: PlainTime("06:00")!)   // all day
    /// ```
    @inlinable
    public init(start: PlainTime, end: PlainTime) {
        let difference = CivilMath.floorModulo(
            end._nanosecondOfDay - start._nanosecondOfDay, CivilMath.nanosecondsPerDay
        )
        self.init(
            _uncheckedStart: start._nanosecondOfDay,
            length: difference == 0 ? CivilMath.nanosecondsPerDay : difference
        )
    }

    /// Creates a range from its start and its length in nanoseconds, or
    /// returns `nil` unless the length is more than zero and at most 24 hours.
    @inlinable
    public init?(start: PlainTime, lengthInNanoseconds length: Int64) {
        guard length > 0, length <= CivilMath.nanosecondsPerDay else { return nil }
        self.init(_uncheckedStart: start._nanosecondOfDay, length: length)
    }

    /// Creates a range with the same bounds as a `Range<PlainTime>`, or
    /// returns `nil` if the range is empty.
    @inlinable
    public init?(_ range: Range<PlainTime>) {
        guard !range.isEmpty else { return nil }
        self.init(start: range.lowerBound, end: range.upperBound)
    }

    /// The whole day, starting at midnight.
    public static let allDay = PlainTimeRange(_uncheckedStart: 0, length: 86_400 * 1_000_000_000)

    /// The first moment of the range, which is included.
    @inlinable
    public var start: PlainTime {
        PlainTime(_uncheckedNanosecondOfDay: _start)
    }

    /// The moment the range ends, which is not included. For a range that
    /// covers the whole day, this equals ``start``.
    @inlinable
    public var end: PlainTime {
        PlainTime(_uncheckedNanosecondOfDay: (_start + _length) % CivilMath.nanosecondsPerDay)
    }

    /// The length of the range in nanoseconds: more than zero and at most
    /// 24 hours.
    @inlinable
    public var lengthInNanoseconds: Int64 { _length }

    /// Whether the range covers all 24 hours of the day.
    @inlinable
    public var isAllDay: Bool { _length == CivilMath.nanosecondsPerDay }

    /// Whether the range continues past midnight into the next day.
    ///
    /// A range that ends exactly at midnight, such as 18:00–00:00, does not
    /// cross it.
    @inlinable
    public var crossesMidnight: Bool { _start + _length > CivilMath.nanosecondsPerDay }

    /// Whether `time` falls within the range.
    @inlinable
    public func contains(_ time: PlainTime) -> Bool {
        _offset(of: time) < _length
    }

    /// Whether the two ranges share at least one moment of the day.
    @inlinable
    public func overlaps(_ other: PlainTimeRange) -> Bool {
        // Two spans on a circle overlap exactly when one of them starts
        // inside the other.
        contains(other.start) || other.contains(start)
    }

    /// Nanoseconds from the start forward to `time`, in `0 ..< 24 hours`.
    @inlinable
    func _offset(of time: PlainTime) -> Int64 {
        CivilMath.floorModulo(time._nanosecondOfDay - _start, CivilMath.nanosecondsPerDay)
    }
}

// MARK: - Occurrences on the calendar

extension PlainTimeRange {
    /// The occurrence of the range that starts on `date`, as wall-clock
    /// date-times.
    ///
    /// ```swift
    /// let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)
    /// bar.occurrence(startingOn: PlainDate("2025-05-02")!)
    /// // 2025-05-02T21:00:00..<2025-05-03T03:00:00
    /// ```
    ///
    /// For a date from untrusted input, use ``checkedOccurrence(startingOn:)``.
    ///
    /// - Precondition: The occurrence ends no later than
    ///   ``PlainDateTime/max``.
    @inlinable
    public func occurrence(startingOn date: PlainDate) -> Range<PlainDateTime> {
        guard let occurrence = checkedOccurrence(startingOn: date) else {
            preconditionFailure("PlainTimeRange occurrence is out of range")
        }
        return occurrence
    }

    /// The occurrence of the range that starts on `date`, or `nil` if it
    /// would run past ``PlainDateTime/max``. Safe to use with untrusted input.
    @inlinable
    public func checkedOccurrence(startingOn date: PlainDate) -> Range<PlainDateTime>? {
        let lower = PlainDateTime(date: date, time: start)
        guard let upper = lower._checkedAdding(nanoseconds: _length) else { return nil }
        return lower..<upper
    }

    /// The occurrence of the range that contains `dateTime`, or `nil` if
    /// `dateTime` is outside the range.
    ///
    /// For a range that crosses midnight, a time after midnight belongs to the
    /// occurrence that started the evening before:
    ///
    /// ```swift
    /// let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)
    /// bar.occurrence(containing: PlainDateTime("2025-05-03T01:30")!)
    /// // 2025-05-02T21:00:00..<2025-05-03T03:00:00
    /// bar.occurrence(containing: PlainDateTime("2025-05-03T12:00")!)   // nil
    /// ```
    ///
    /// The result is also `nil` if the occurrence would extend beyond
    /// ``PlainDateTime/min`` or ``PlainDateTime/max``, so this is safe to use
    /// with untrusted input.
    @inlinable
    public func occurrence(containing dateTime: PlainDateTime) -> Range<PlainDateTime>? {
        let offset = _offset(of: dateTime.time)
        guard offset < _length,
              let lower = dateTime._checkedAdding(nanoseconds: -offset),
              let upper = lower._checkedAdding(nanoseconds: _length)
        else { return nil }
        return lower..<upper
    }
}

extension PlainDateTime {
    /// Adds a nanosecond amount with 64-bit arithmetic, returning `nil` when
    /// the result is out of range.
    @inlinable
    func _checkedAdding(nanoseconds: Int64) -> PlainDateTime? {
        _checkedAdding(seconds: 0, nanoseconds: nanoseconds)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension PlainTimeRange {
    /// Creates a range from its start and its length, or returns `nil` unless
    /// the length is more than zero and at most 24 hours. Fractions below one
    /// nanosecond are dropped.
    @inlinable
    public init?(start: PlainTime, length: Duration) {
        guard let (seconds, nanoseconds) = _secondsAndNanoseconds(of: length) else { return nil }
        let (scaled, o1) = seconds.multipliedReportingOverflow(by: CivilMath.nanosecondsPerSecond)
        let (total, o2) = scaled.addingReportingOverflow(nanoseconds)
        guard !o1, !o2 else { return nil }
        self.init(start: start, lengthInNanoseconds: total)
    }

    /// The length of the range: more than zero and at most 24 hours.
    @inlinable
    public var length: Duration {
        .nanoseconds(_length)
    }
}
