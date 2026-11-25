public import CivilTime
public import Foundation

// MARK: - From an instant to a wall-clock value

extension PlainDateTime {
    /// The date and time a wall clock in `timeZone` shows at the instant `date`.
    ///
    /// ```swift
    /// let now = Date()
    /// PlainDateTime(now, in: TimeZone(identifier: "Asia/Tokyo")!)
    /// ```
    ///
    /// `Date` stores time as a `Double`, so for instants near the present the
    /// nanosecond field is accurate to about a quarter of a microsecond.
    ///
    /// - Precondition: `date` is finite and its year in `timeZone` is within
    ///   -999999…999999. For a `Date` from untrusted input, use
    ///   ``init(checking:in:)``.
    public init(_ date: Date, in timeZone: TimeZone) {
        guard let value = PlainDateTime(checking: date, in: timeZone) else {
            preconditionFailure("\(date) is outside the years PlainDateTime supports")
        }
        self = value
    }

    /// The date and time a wall clock in `timeZone` shows at the instant
    /// `date`, or `nil` if `date` is not finite or falls outside the years
    /// -999999…999999. Safe to use with untrusted input.
    public init?(checking date: Date, in timeZone: TimeZone) {
        guard let (seconds, nanoseconds) = _checkedSecondsAndNanoseconds(of: date) else { return nil }
        let offset = Int64(timeZone.secondsFromGMT(for: date))
        let (local, overflow) = seconds.addingReportingOverflow(offset)
        guard !overflow, let value = PlainDateTime(secondsSinceEpoch: local, nanoseconds: nanoseconds) else {
            return nil
        }
        self = value
    }

    /// The current date and time on a wall clock in `timeZone`.
    public static func now(in timeZone: TimeZone = .current) -> PlainDateTime {
        PlainDateTime(Date(), in: timeZone)
    }
}

extension PlainDate {
    /// The calendar date in `timeZone` at the instant `date`.
    ///
    /// ```swift
    /// let instant = Date(timeIntervalSince1970: 1_709_164_800)  // 2024-02-29T00:00:00Z
    /// PlainDate(instant, in: TimeZone(identifier: "UTC")!)                  // 2024-02-29
    /// PlainDate(instant, in: TimeZone(identifier: "America/Los_Angeles")!)  // 2024-02-28
    /// ```
    ///
    /// - Precondition: `date` is finite and its year in `timeZone` is within
    ///   -999999…999999. For a `Date` from untrusted input, use
    ///   ``init(checking:in:)``.
    public init(_ date: Date, in timeZone: TimeZone) {
        self = PlainDateTime(date, in: timeZone).date
    }

    /// The calendar date in `timeZone` at the instant `date`, or `nil` if
    /// `date` is not finite or falls outside the years -999999…999999. Safe
    /// to use with untrusted input.
    public init?(checking date: Date, in timeZone: TimeZone) {
        guard let dateTime = PlainDateTime(checking: date, in: timeZone) else { return nil }
        self = dateTime.date
    }

    /// Today's date in `timeZone`.
    ///
    /// Today depends on where you are: at 01:00 in Tokyo it is still
    /// yesterday in London. Pass the time zone the date belongs to — the
    /// user's, a store's, a server's — rather than relying on the default.
    public static func today(in timeZone: TimeZone = .current) -> PlainDate {
        PlainDate(Date(), in: timeZone)
    }
}

extension PlainTime {
    /// The time of day a wall clock in `timeZone` shows at the instant `date`.
    ///
    /// - Precondition: `date` is finite and its year in `timeZone` is within
    ///   -999999…999999. For a `Date` from untrusted input, use
    ///   ``init(checking:in:)``.
    public init(_ date: Date, in timeZone: TimeZone) {
        self = PlainDateTime(date, in: timeZone).time
    }

    /// The time of day a wall clock in `timeZone` shows at the instant `date`,
    /// or `nil` if `date` is not finite or falls outside the years
    /// -999999…999999. Safe to use with untrusted input.
    public init?(checking date: Date, in timeZone: TimeZone) {
        guard let dateTime = PlainDateTime(checking: date, in: timeZone) else { return nil }
        self = dateTime.time
    }

    /// The current time of day on a wall clock in `timeZone`.
    public static func now(in timeZone: TimeZone = .current) -> PlainTime {
        PlainTime(Date(), in: timeZone)
    }
}

// MARK: - From a wall-clock value to an instant

extension PlainDateTime {
    /// How to choose an instant for a wall-clock time that a time zone skips
    /// or repeats.
    ///
    /// When clocks spring forward, some wall-clock times never happen: in New
    /// York, 2024-03-10T02:30 does not exist. When clocks fall back, some
    /// happen twice: 2024-11-03T01:30 occurs once in daylight time and again
    /// an hour later in standard time. A disambiguation picks one instant in
    /// both cases. Use ``PlainDateTime/possibleDates(in:)`` to see every
    /// candidate instead, or to reject ambiguous input.
    ///
    /// The options match the `disambiguation` option of JavaScript's Temporal
    /// API and the default behavior of most calendar software.
    public struct Disambiguation: Sendable, Hashable, CustomStringConvertible {
        @usableFromInline let _code: UInt8

        init(_code: UInt8) { self._code = _code }

        /// For a repeated time, the earlier instant. For a skipped time, the
        /// instant that is as far after the transition as the time is into
        /// the gap — 02:30 in a 02:00→03:00 gap becomes 03:30.
        ///
        /// This is what `Calendar`, most operating systems and JavaScript's
        /// `Date` do. It is the default.
        public static let compatible = Disambiguation(_code: 0)

        /// The earlier instant. For a skipped time, the time read with the
        /// offset in effect after the gap — 02:30 in a 02:00→03:00 gap
        /// becomes 01:30 before the transition.
        public static let earlier = Disambiguation(_code: 1)

        /// The later instant. For a skipped time, the time read with the
        /// offset in effect before the gap — 02:30 in a 02:00→03:00 gap
        /// becomes 03:30 after the transition.
        public static let later = Disambiguation(_code: 2)

        public var description: String {
            switch _code {
            case 1: return "earlier"
            case 2: return "later"
            default: return "compatible"
            }
        }
    }

    /// The instant at which a wall clock in `timeZone` shows this date and
    /// time.
    ///
    /// Most wall-clock times happen exactly once. For a time skipped or
    /// repeated by a daylight-saving or other offset change, `disambiguation`
    /// chooses the instant; see ``Disambiguation``.
    ///
    /// ```swift
    /// let newYork = TimeZone(identifier: "America/New_York")!
    /// let skipped = PlainDateTime(year: 2024, month: 3, day: 10, hour: 2, minute: 30)!
    /// skipped.date(in: newYork)                          // 2024-03-10T03:30-04:00
    /// skipped.date(in: newYork, disambiguation: .earlier) // 2024-03-10T01:30-05:00
    /// ```
    public func date(in timeZone: TimeZone, disambiguation: Disambiguation = .compatible) -> Date {
        let (_, nanoseconds) = secondsSinceEpoch
        let utc = _utcSeconds(in: timeZone, disambiguation: disambiguation)
        return Date(timeIntervalSince1970: TimeInterval(utc) + TimeInterval(nanoseconds) / 1_000_000_000)
    }

    /// The whole UTC seconds since 1970 of this wall-clock time in
    /// `timeZone`, resolved with `disambiguation`. The nanoseconds of this
    /// date-time are not included.
    func _utcSeconds(in timeZone: TimeZone, disambiguation: Disambiguation) -> Int64 {
        let (local, _) = secondsSinceEpoch
        let candidates = Self._instants(local: local, in: timeZone)
        if let first = candidates.first, let last = candidates.last {
            return disambiguation == .later ? last : first
        }
        let before = Self._offset(of: timeZone, atUTC: local - _secondsPerDay)
        let after = Self._offset(of: timeZone, atUTC: local + _secondsPerDay)
        return disambiguation == .earlier ? local - after : local - before
    }

    /// Every instant at which a wall clock in `timeZone` shows this date and
    /// time, in order.
    ///
    /// The array has one element for most times, two for a time repeated
    /// when clocks fall back, and none for a time skipped when clocks spring
    /// forward. To accept only unambiguous input:
    ///
    /// ```swift
    /// let candidates = local.possibleDates(in: zone)
    /// guard candidates.count == 1 else { throw AmbiguousTimeError() }
    /// ```
    public func possibleDates(in timeZone: TimeZone) -> [Date] {
        let (local, nanoseconds) = secondsSinceEpoch
        return Self._instants(local: local, in: timeZone).map {
            Date(timeIntervalSince1970: TimeInterval($0) + TimeInterval(nanoseconds) / 1_000_000_000)
        }
    }

    /// UTC seconds whose wall-clock time in `timeZone` is `local`, ascending.
    static func _instants(local: Int64, in timeZone: TimeZone) -> [Int64] {
        // A transition near `local` happens within a day of it in UTC, so the
        // offsets a day before and a day after are the two candidates. The
        // offset at `local` itself catches zones with two transitions close
        // together.
        let offsets = [
            _offset(of: timeZone, atUTC: local - _secondsPerDay),
            _offset(of: timeZone, atUTC: local),
            _offset(of: timeZone, atUTC: local + _secondsPerDay),
        ]
        var result: [Int64] = []
        for offset in offsets {
            let utc = local - offset
            if _offset(of: timeZone, atUTC: utc) == offset && !result.contains(utc) {
                result.append(utc)
            }
        }
        result.sort()
        return result
    }

    static func _offset(of timeZone: TimeZone, atUTC seconds: Int64) -> Int64 {
        Int64(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))))
    }
}

extension PlainDateTime {
    /// The first instant at which a wall clock in `timeZone` shows this
    /// date-time or a later one.
    ///
    /// For an ordinary time this is the time itself. For a time shown twice,
    /// it is the first occurrence. For a time skipped by a gap, it is the
    /// transition at the end of the gap, when the clock jumps past it. Unlike
    /// ``date(in:disambiguation:)``, this mapping never reverses the order of
    /// two wall-clock times, so it is safe for both ends of a range.
    func _firstInstant(in timeZone: TimeZone) -> Date {
        let (local, nanoseconds) = secondsSinceEpoch
        if let first = Self._instants(local: local, in: timeZone).first {
            return Date(timeIntervalSince1970: TimeInterval(first) + TimeInterval(nanoseconds) / 1_000_000_000)
        }
        // The time is in a gap: find the first instant whose wall-clock time
        // is at or after it. That is the transition at the end of the gap.
        let before = Self._offset(of: timeZone, atUTC: local - _secondsPerDay)
        let after = Self._offset(of: timeZone, atUTC: local + _secondsPerDay)
        var low = local - Swift.max(before, after) - 1   // wall clock is before `local` here
        var high = local - Swift.min(before, after)      // and at or after it here
        while high - low > 1 {
            let middle = low + (high - low) / 2
            if middle + Self._offset(of: timeZone, atUTC: middle) >= local {
                high = middle
            } else {
                low = middle
            }
        }
        return Date(timeIntervalSince1970: TimeInterval(high))
    }
}

extension Range where Bound == PlainDateTime {
    /// The span of time this wall-clock range covers in `timeZone`.
    ///
    /// Each end becomes the first instant at which a wall clock in the time
    /// zone reaches it. Across a daylight-saving change, the interval is
    /// therefore longer or shorter than the wall-clock difference, as it is
    /// in real life:
    ///
    /// ```swift
    /// let newYork = TimeZone(identifier: "America/New_York")!
    /// let bar = PlainTimeRange(start: PlainTime("21:00")!, end: PlainTime("03:00")!)
    /// bar.occurrence(startingOn: PlainDate("2024-11-02")!).dateInterval(in: newYork).duration
    /// // 7 hours: clocks fell back during the night
    /// ```
    ///
    /// A time skipped by a gap maps to the end of the gap, so a range that
    /// lies entirely inside a gap gives an empty interval.
    public func dateInterval(in timeZone: TimeZone) -> DateInterval {
        let start = lowerBound._firstInstant(in: timeZone)
        let end = upperBound._firstInstant(in: timeZone)
        // The mapping keeps order, so `end >= start`; `max` only guards
        // against inconsistent time-zone data.
        return DateInterval(start: start, end: Swift.max(start, end))
    }
}

extension PlainDate {
    /// The first instant of this date in `timeZone`.
    ///
    /// This is usually midnight. In a time zone whose clocks skip midnight
    /// (for example, America/Santiago moves from 00:00 straight to 01:00 on
    /// the day daylight time starts), the day starts at the transition. For a
    /// date the time zone skips entirely — Pacific/Apia jumped from
    /// 2011-12-29 to 2011-12-31 — the result is the instant the next day
    /// starts, so the date's ``dateInterval(in:)`` is empty.
    public func startOfDay(in timeZone: TimeZone) -> Date {
        PlainDateTime(date: self, time: .midnight)._firstInstant(in: timeZone)
    }

    /// The span of time this date covers in `timeZone`, from its first
    /// instant to the first instant of the next day.
    ///
    /// The duration is usually 24 hours, but 23 or 25 hours (or another
    /// amount) on days when the offset changes, and zero for a date the time
    /// zone skips.
    public func dateInterval(in timeZone: TimeZone) -> DateInterval {
        DateInterval(start: startOfDay(in: timeZone), end: adding(days: 1).startOfDay(in: timeZone))
    }
}

// MARK: - Helpers

let _secondsPerDay: Int64 = 86_400

/// Splits a `Date` into whole seconds since 1970 and nanoseconds, rounding
/// the fraction to the nearest nanosecond, or returns `nil` if the `Date` is
/// not finite or its seconds do not fit in `Int64`.
func _checkedSecondsAndNanoseconds(of date: Date) -> (seconds: Int64, nanoseconds: Int64)? {
    let interval = date.timeIntervalSince1970
    guard interval.isFinite else { return nil }
    var whole = interval.rounded(.down)
    var nanoseconds = ((interval - whole) * 1_000_000_000).rounded()
    if nanoseconds >= 1_000_000_000 {
        nanoseconds -= 1_000_000_000
        whole += 1
    }
    guard let seconds = Int64(exactly: whole) else { return nil }
    return (seconds, Int64(nanoseconds))
}
