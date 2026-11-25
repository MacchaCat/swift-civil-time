public import CivilTime
public import Foundation

/// An exact moment together with the time zone it is seen in, such as
/// 2025-05-02T22:00:00+09:00[Asia/Tokyo].
///
/// It is the counterpart of JavaScript's `Temporal.ZonedDateTime`: a
/// `Date`-like instant, a `TimeZone`, and the wall-clock date and time they
/// give. Use it for things that happen at a moment *in a place*: a flight's
/// departure, a meeting, a log entry you want to show in local time.
///
/// ```swift
/// let tokyo = TimeZone(identifier: "Asia/Tokyo")!
/// let departure = ZonedDateTime(PlainDateTime("2025-05-02T22:00")!, in: tokyo)
/// departure.description                         // "2025-05-02T22:00:00+09:00[Asia/Tokyo]"
///
/// let arrival = departure.adding(DateTimeDuration(hours: 10, minutes: 5))
///     .withTimeZone(TimeZone(identifier: "America/Los_Angeles")!)
/// arrival.dateTime                              // 2025-05-02T16:05:00 local time
/// ```
///
/// - The instant is kept to the nanosecond, independent of `Date`'s
///   floating-point precision.
/// - Equality compares the instant and the time zone (its identifier, or the
///   offset of a fixed-offset zone), so the same moment in two time zones
///   gives two different values. Compare ``date`` to compare moments only;
///   that is also how to sort.
/// - The time zone is fixed when the value is created: a value made with
///   `TimeZone.current` keeps that zone even if the device's zone changes.
///
/// The text form follows RFC 9557, as Temporal does:
/// `2025-05-02T22:00:00+09:00[Asia/Tokyo]`. A fixed-offset time zone is
/// written as an offset, `[+09:00]`. Offsets with seconds, which only
/// historical local mean time needs (Monrovia used -00:44:30 until 1972),
/// are written as `-00:44:30`; RFC 9557 allows only hours and minutes, so
/// other parsers may reject such strings.
public struct ZonedDateTime: Sendable, Hashable {
    /// The time zone.
    public let timeZone: TimeZone
    /// The instant, as whole seconds since 1970-01-01T00:00:00Z.
    public let secondsSince1970: Int64
    /// The fraction of the second, in nanoseconds, from 0 to 999,999,999.
    public let nanoseconds: Int32
    /// The date and time a wall clock in ``timeZone`` shows at this instant.
    public let dateTime: PlainDateTime
    /// The offset from UTC at this instant, in seconds east (for example
    /// 32,400 for +09:00).
    public let utcOffset: Int

    /// Creates a value from an exact instant, given as seconds and
    /// nanoseconds since 1970-01-01T00:00:00Z, or returns `nil` if its
    /// wall-clock date and time in `timeZone` is outside the supported years.
    ///
    /// Nanoseconds outside 0..<1,000,000,000 are carried into the seconds.
    public init?(secondsSince1970 seconds: Int64, nanoseconds: Int64 = 0, in timeZone: TimeZone) {
        self.init(seconds: seconds, nanoseconds: nanoseconds, timeZone: timeZone)
    }

    init?(seconds: Int64, nanoseconds: Int64, timeZone: TimeZone) {
        // Carry the nanoseconds into whole seconds, rounding down, so that
        // the fraction is in 0..<1,000,000,000.
        let carried = nanoseconds.quotientAndRemainder(dividingBy: 1_000_000_000)
        let borrow: Int64 = carried.remainder < 0 ? 1 : 0
        let fraction = carried.remainder + borrow * 1_000_000_000
        let (shifted, o1) = seconds.addingReportingOverflow(carried.quotient)
        let (whole, o2) = shifted.subtractingReportingOverflow(borrow)
        // Far outside the supported years, do not ask the time zone at all.
        guard !o1, !o2, whole >= Self._earliestSecond, whole <= Self._latestSecond else { return nil }
        let zone = Self._fixed(timeZone)
        let offset = zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(whole)))
        let (local, o3) = whole.addingReportingOverflow(Int64(offset))
        guard !o3, let wall = PlainDateTime(secondsSinceEpoch: local, nanoseconds: fraction) else { return nil }
        self.timeZone = zone
        self.secondsSince1970 = whole
        self.nanoseconds = Int32(fraction)
        self.dateTime = wall
        self.utcOffset = offset
    }

    /// Instants more than a day beyond the supported wall-clock range.
    static let _earliestSecond = PlainDateTime.min.secondsSinceEpoch.seconds - 86_400
    static let _latestSecond = PlainDateTime.max.secondsSinceEpoch.seconds + 86_400

    /// Whether `timeZone` is a fixed offset from UTC, such as one made with
    /// `TimeZone(secondsFromGMT:)`, rather than a named zone.
    static func _isFixedOffset(_ timeZone: TimeZone) -> Bool {
        let identifier = timeZone.identifier
        return identifier.hasPrefix("GMT+") || identifier.hasPrefix("GMT-")
    }

    /// The same zone, no longer following the device's settings. Fixed-offset
    /// zones are kept as they are: their identifiers are only accurate to the
    /// minute, so rebuilding one could change its offset.
    static func _fixed(_ timeZone: TimeZone) -> TimeZone {
        if _isFixedOffset(timeZone) { return timeZone }
        return TimeZone(identifier: timeZone.identifier) ?? timeZone
    }

    /// What equality compares for the time zone: the identifier of a named
    /// zone, or the exact offset of a fixed-offset zone.
    var _zoneKey: String {
        Self._isFixedOffset(timeZone) ? _formatUTCOffset(timeZone.secondsFromGMT()) : timeZone.identifier
    }

    /// The instant `date` seen in `timeZone`.
    ///
    /// For a `Date` from untrusted input, use ``init(checking:in:)``.
    ///
    /// - Precondition: `date` is finite and its wall-clock year in
    ///   `timeZone` is within -999999…999999.
    public init(_ date: Date, in timeZone: TimeZone) {
        guard let value = ZonedDateTime(checking: date, in: timeZone) else {
            preconditionFailure("\(date) is outside the years ZonedDateTime supports")
        }
        self = value
    }

    /// The instant `date` seen in `timeZone`, or `nil` if `date` is not
    /// finite or its wall-clock year is outside -999999…999999. Safe to use
    /// with untrusted input.
    public init?(checking date: Date, in timeZone: TimeZone) {
        guard let (seconds, nanoseconds) = _checkedSecondsAndNanoseconds(of: date) else { return nil }
        self.init(seconds: seconds, nanoseconds: nanoseconds, timeZone: timeZone)
    }

    /// The instant at which a wall clock in `timeZone` shows `dateTime`.
    ///
    /// A wall-clock time that the time zone skips or repeats is resolved with
    /// `disambiguation`; see ``CivilTime/PlainDateTime/Disambiguation``. In a
    /// skipped hour the result's ``dateTime`` is therefore not `dateTime`.
    ///
    /// - Precondition: The resolved wall-clock time is within the supported
    ///   years. Only a time within hours of +999999-12-31T24:00 can fail.
    public init(
        _ dateTime: PlainDateTime,
        in timeZone: TimeZone,
        disambiguation: PlainDateTime.Disambiguation = .compatible
    ) {
        guard let value = ZonedDateTime(checking: dateTime, in: timeZone, disambiguation: disambiguation) else {
            preconditionFailure("\(dateTime) is outside the years ZonedDateTime supports")
        }
        self = value
    }

    /// Like ``init(_:in:disambiguation:)-(PlainDateTime,_,_)``, but returns
    /// `nil` instead of stopping the program when the resolved wall-clock
    /// time falls outside the supported years.
    public init?(
        checking dateTime: PlainDateTime,
        in timeZone: TimeZone,
        disambiguation: PlainDateTime.Disambiguation = .compatible
    ) {
        let zone = Self._fixed(timeZone)
        let utc = dateTime._utcSeconds(in: zone, disambiguation: disambiguation)
        self.init(seconds: utc, nanoseconds: Int64(dateTime.nanosecond), timeZone: zone)
    }

    /// The current moment in `timeZone`.
    public static func now(in timeZone: TimeZone = .current) -> ZonedDateTime {
        ZonedDateTime(Date(), in: timeZone)
    }

    /// The instant as a Foundation `Date`, whose `Double` storage keeps about
    /// a quarter of a microsecond of precision near the present.
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(secondsSince1970) + TimeInterval(nanoseconds) / 1_000_000_000)
    }

    /// The wall-clock date.
    public var plainDate: PlainDate { dateTime.date }

    /// The wall-clock time of day.
    public var plainTime: PlainTime { dateTime.time }

    /// The same instant seen in another time zone.
    ///
    /// - Precondition: The wall-clock year in `timeZone` is within the
    ///   supported years. Only an instant within a day of the ends of the
    ///   range can fail; use ``checkedWithTimeZone(_:)`` for untrusted input.
    public func withTimeZone(_ timeZone: TimeZone) -> ZonedDateTime {
        guard let value = checkedWithTimeZone(timeZone) else {
            preconditionFailure("ZonedDateTime is outside the supported years in \(timeZone.identifier)")
        }
        return value
    }

    /// The same instant seen in another time zone, or `nil` if its
    /// wall-clock year there is outside the supported years.
    public func checkedWithTimeZone(_ timeZone: TimeZone) -> ZonedDateTime? {
        ZonedDateTime(seconds: secondsSince1970, nanoseconds: Int64(nanoseconds), timeZone: timeZone)
    }

    /// The first moment of this value's wall-clock date in its time zone.
    /// This is usually midnight; see `PlainDate.startOfDay(in:)`.
    public var startOfDay: ZonedDateTime {
        let start = PlainDateTime(date: plainDate, time: .midnight)._firstInstant(in: timeZone)
        // The start of a supported date is on that date in the same zone, so
        // it is always in range.
        return ZonedDateTime(checking: start, in: timeZone)!
    }

    public static func == (lhs: ZonedDateTime, rhs: ZonedDateTime) -> Bool {
        lhs.secondsSince1970 == rhs.secondsSince1970 && lhs.nanoseconds == rhs.nanoseconds
            && lhs._zoneKey == rhs._zoneKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(secondsSince1970)
        hasher.combine(nanoseconds)
        hasher.combine(_zoneKey)
    }
}

// MARK: - Arithmetic

extension ZonedDateTime {
    /// Returns the moment a `DateTimeDuration` later, counting
    /// its calendar units on the wall clock and its clock units as exact
    /// time, as `Date.adding(_:in:disambiguation:)` and Temporal do.
    ///
    /// ```swift
    /// let newYork = TimeZone(identifier: "America/New_York")!
    /// let noon = ZonedDateTime(PlainDateTime("2024-03-09T12:00")!, in: newYork)
    /// noon.adding(DateTimeDuration(days: 1)).dateTime     // 2024-03-10T12:00 (23 hours later)
    /// noon.adding(DateTimeDuration(hours: 24)).dateTime   // 2024-03-10T13:00
    /// ```
    ///
    /// For a duration from untrusted input, use
    /// ``checkedAdding(_:disambiguation:)``.
    ///
    /// - Precondition: The result is within the supported years.
    public func adding(
        _ duration: DateTimeDuration,
        disambiguation: PlainDateTime.Disambiguation = .compatible
    ) -> ZonedDateTime {
        guard let value = checkedAdding(duration, disambiguation: disambiguation) else {
            preconditionFailure("ZonedDateTime arithmetic is out of range")
        }
        return value
    }

    /// Like ``adding(_:disambiguation:)``, but returns `nil` instead of
    /// stopping the program when the result is out of range. Safe to use with
    /// untrusted input.
    public func checkedAdding(
        _ duration: DateTimeDuration,
        disambiguation: PlainDateTime.Disambiguation = .compatible
    ) -> ZonedDateTime? {
        guard let (seconds, nanos) = Self._adding(
            duration, toSeconds: secondsSince1970, nanoseconds: Int64(nanoseconds),
            wallClock: dateTime, in: timeZone, disambiguation: disambiguation
        ) else { return nil }
        return ZonedDateTime(seconds: seconds, nanoseconds: nanos, timeZone: timeZone)
    }

    /// The shared implementation of zoned addition, on exact instants.
    static func _adding(
        _ duration: DateTimeDuration,
        toSeconds seconds: Int64, nanoseconds: Int64,
        wallClock: PlainDateTime, in timeZone: TimeZone,
        disambiguation: PlainDateTime.Disambiguation
    ) -> (seconds: Int64, nanoseconds: Int64)? {
        guard let (clockSeconds, clockNanos) = duration.clockSecondsAndNanoseconds else { return nil }
        var start = (seconds: seconds, nanoseconds: nanoseconds)
        if duration.hasCalendarUnits {
            guard let moved = wallClock.checkedAdding(duration.dateDuration) else { return nil }
            start = (moved._utcSeconds(in: timeZone, disambiguation: disambiguation), Int64(moved.nanosecond))
        }
        let (total, overflow) = start.seconds.addingReportingOverflow(clockSeconds)
        guard !overflow else { return nil }
        return (total, start.nanoseconds + clockNanos)
    }

    /// The years, months, days, hours, minutes, seconds and nanoseconds from
    /// this moment to `other`, counted the way Temporal's
    /// `ZonedDateTime.until` does with years as the largest unit.
    ///
    /// The calendar part is counted on the wall clock of this value's time
    /// zone, and the rest is exact time. All components have the same sign,
    /// and with the default `.compatible` disambiguation adding the result
    /// back lands on the same instant:
    ///
    /// ```swift
    /// start.adding(start.dateTimeDuration(until: end)).date == end.date   // always true
    /// ```
    ///
    /// When `other` is in another time zone it is first converted into this
    /// value's zone. If no calendar count fits (only possible at the ends of
    /// the supported range), the result is exact time in hours, minutes and
    /// seconds.
    public func dateTimeDuration(until other: ZonedDateTime) -> DateTimeDuration {
        let start = (secondsSince1970, Int64(nanoseconds))
        let end = (other.secondsSince1970, Int64(other.nanoseconds))
        if start == end { return .zero }
        let sign: Int64 = end > start ? 1 : -1
        let exact = Self._exactDuration(from: start, to: end)
        guard let target = other.checkedWithTimeZone(timeZone) else { return exact }

        // How far apart the two times of day are, ignoring the date.
        let timeOfDay = target.plainTime.nanosecondsSinceMidnight - plainTime.nanosecondsSinceMidnight
        var correction = timeOfDay != 0 && (timeOfDay < 0) == (sign > 0) ? 1 : 0
        let maxCorrection = sign > 0 ? 2 : 1
        while correction <= maxCorrection {
            guard let intermediateDate = target.plainDate.checkedAdding(days: -correction * Int(sign)) else { break }
            let intermediate = PlainDateTime(date: intermediateDate, time: plainTime)
            let instant = (intermediate._utcSeconds(in: timeZone, disambiguation: .compatible), Int64(intermediate.nanosecond))
            let rest = Self._exactDuration(from: instant, to: end)
            let restSign = rest.seconds != 0 ? rest.seconds.signum() : rest.nanoseconds.signum()
            if restSign != -sign {
                let calendar = plainDate.dateDuration(until: intermediateDate)
                // With no calendar part, adding the result back is exact time
                // from this instant, so the answer must be the exact time too,
                // not time from the wall clock re-read (which can pick the
                // other occurrence of a repeated hour).
                if calendar.isZero { return exact }
                let parts = [Int64(calendar.years), Int64(calendar.months), Int64(calendar.days)].filter { $0 != 0 }
                guard parts.allSatisfy({ $0.signum() == sign }) else { return exact }
                return DateTimeDuration(
                    years: calendar.years, months: calendar.months, days: calendar.days,
                    hours: rest.hours, minutes: rest.minutes, seconds: rest.seconds, nanoseconds: rest.nanoseconds
                )
            }
            correction += 1
        }
        return exact
    }

    /// The exact time between two instants, in hours, minutes, seconds and
    /// nanoseconds.
    static func _exactDuration(from start: (Int64, Int64), to end: (Int64, Int64)) -> DateTimeDuration {
        let seconds = end.0 - start.0
        let nanoseconds = end.1 - start.1
        let normalized = DateTimeDuration(seconds: seconds, nanoseconds: nanoseconds)
        let total = normalized.seconds
        return DateTimeDuration(
            hours: total / 3600, minutes: total / 60 % 60, seconds: total % 60, nanoseconds: normalized.nanoseconds
        )
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension ZonedDateTime {
    /// The exact time from this moment to `other`; negative if `other` is
    /// earlier.
    public func duration(until other: ZonedDateTime) -> Duration {
        .seconds(other.secondsSince1970 - secondsSince1970) + .nanoseconds(Int64(other.nanoseconds) - Int64(nanoseconds))
    }
}

// MARK: - Text

extension ZonedDateTime {
    /// What to do when a string's UTC offset does not match its time zone at
    /// that wall-clock time, as Temporal's `offset` option.
    ///
    /// Offsets stop matching when a time zone's rules change after the
    /// string was written, or when two systems use different time-zone data.
    public struct OffsetPolicy: Sendable, Hashable, CustomStringConvertible {
        let _code: UInt8

        /// Throw `CivilTimeParseError.Kind.offsetMismatch`. The
        /// default for ``ZonedDateTime/init(parsing:offsetPolicy:)``.
        public static let reject = OffsetPolicy(_code: 0)
        /// Use the offset when it matches; otherwise keep the wall-clock time
        /// and resolve it in the time zone with `.compatible`. Used when
        /// decoding, so that data written under older rules still loads.
        public static let prefer = OffsetPolicy(_code: 1)
        /// Always use the offset: keep the exact instant, even if its
        /// wall-clock time in the time zone then differs from the string's.
        public static let use = OffsetPolicy(_code: 2)
        /// Ignore the offset: keep the wall-clock time and resolve it with
        /// `.compatible`.
        public static let ignore = OffsetPolicy(_code: 3)

        public var description: String {
            ["reject", "prefer", "use", "ignore"][Int(_code)]
        }
    }

    /// Parses an RFC 9557 date-time with a time zone, such as
    /// `2025-05-02T22:00:00+09:00[Asia/Tokyo]`.
    ///
    /// - The date and time are read as by `PlainDateTime.init(parsing:)`.
    /// - The UTC offset (`+09:00`, `-05:00`, `+00:19:32`, or `Z`) is optional.
    ///   `Z` means the date-time is UTC and is always used as the exact
    ///   instant. A numeric offset picks between the two occurrences of a
    ///   repeated wall-clock time; when it does not match the time zone,
    ///   `offsetPolicy` decides. An offset written without seconds matches
    ///   if it equals the zone's offset rounded to the minute.
    /// - Without an offset, a skipped or repeated wall-clock time is resolved
    ///   with `.compatible`.
    /// - The time zone in brackets is an IANA name (`[Asia/Tokyo]`) or an
    ///   offset (`[+09:00]`), optionally marked critical (`[!Asia/Tokyo]`).
    ///   Other annotations, such as calendars (`[u-ca=japanese]`), are
    ///   rejected.
    ///
    /// - Throws: `CivilTimeParseError`, including
    ///   `.unknownTimeZone` and `.offsetMismatch`.
    public init(parsing text: some StringProtocol, offsetPolicy: OffsetPolicy = .reject) throws(CivilTimeParseError) {
        let parts = try _parseZonedText(text)
        let zone: TimeZone
        if let seconds = parts.zoneOffset {
            guard let fixed = TimeZone(secondsFromGMT: seconds) else {
                throw CivilTimeParseError(kind: .unknownTimeZone, input: text, offset: parts.zonePosition, typeName: "ZonedDateTime")
            }
            zone = fixed
        } else {
            guard let named = TimeZone(identifier: parts.zone) else {
                throw CivilTimeParseError(kind: .unknownTimeZone, input: text, offset: parts.zonePosition, typeName: "ZonedDateTime")
            }
            zone = named
        }
        let local = parts.dateTime.secondsSinceEpoch.seconds
        let nanos = Int64(parts.dateTime.nanosecond)
        var utc: Int64
        if let offset = parts.offset, parts.isUTC || offsetPolicy == .use {
            utc = local - Int64(offset)
        } else if let offset = parts.offset, offsetPolicy != .ignore {
            let matching = PlainDateTime._instants(local: local, in: zone).first { candidate in
                let actual = Int(local - candidate)
                return parts.offsetHasSeconds ? actual == offset : Self._roundedToMinute(actual) == offset
            }
            if let matching {
                utc = matching
            } else if offsetPolicy == .prefer {
                utc = parts.dateTime._utcSeconds(in: zone, disambiguation: .compatible)
            } else {
                throw CivilTimeParseError(kind: .offsetMismatch, input: text, offset: parts.offsetPosition, typeName: "ZonedDateTime")
            }
        } else {
            utc = parts.dateTime._utcSeconds(in: zone, disambiguation: .compatible)
        }
        guard let value = ZonedDateTime(seconds: utc, nanoseconds: nanos, timeZone: zone) else {
            throw CivilTimeParseError(kind: .valueOutOfRange, input: text, offset: 0, typeName: "ZonedDateTime")
        }
        self = value
    }

    static func _roundedToMinute(_ seconds: Int) -> Int {
        let minutes = (Double(seconds) / 60).rounded(.toNearestOrAwayFromZero)
        return Int(minutes) * 60
    }

    /// The time zone as written between the brackets: its identifier, or an
    /// offset such as `+09:00` for a fixed-offset zone.
    var _zoneAnnotation: String { _zoneKey }
}

extension ZonedDateTime: CustomStringConvertible, LosslessStringConvertible {
    /// The RFC 9557 form, such as `2025-05-02T22:00:00+09:00[Asia/Tokyo]`.
    public var description: String {
        dateTime.description + _formatUTCOffset(utcOffset) + "[" + _zoneAnnotation + "]"
    }

    /// Parses an RFC 9557 date-time with a time zone, rejecting offsets that
    /// do not match, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? ZonedDateTime(parsing: description) else { return nil }
        self = value
    }
}

extension ZonedDateTime: Codable {
    /// Decodes a string such as `"2025-05-02T22:00:00+09:00[Asia/Tokyo]"`
    /// with the ``OffsetPolicy/prefer`` policy, so that values stored before
    /// a time zone changed its rules still decode, keeping their wall-clock
    /// time.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do {
            self = try ZonedDateTime(parsing: text, offsetPolicy: .prefer)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: error.description)
        }
    }

    /// Encodes the value as its RFC 9557 string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
