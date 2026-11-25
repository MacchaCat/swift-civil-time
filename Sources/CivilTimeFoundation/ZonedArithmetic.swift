public import CivilTime
public import Foundation

extension Date {
    /// The instant a `DateTimeDuration` after this one, counting
    /// its calendar units on the wall clock of `timeZone`.
    ///
    /// This follows JavaScript's Temporal (`ZonedDateTime.add`):
    ///
    /// 1. The years, months and days are added to the date and time a wall
    ///    clock in `timeZone` shows at this instant, clamping the day to the
    ///    end of the month, and the result is turned back into an instant
    ///    with `disambiguation`.
    /// 2. The hours, minutes and seconds are then added as exact time.
    ///
    /// So "one day later" keeps the wall-clock time, while "24 hours later"
    /// does not when the clocks change in between:
    ///
    /// ```swift
    /// let newYork = TimeZone(identifier: "America/New_York")!
    /// let noon = PlainDateTime("2024-03-09T12:00")!.date(in: newYork)
    /// noon.adding(DateTimeDuration(days: 1), in: newYork)     // 2024-03-10 12:00 EDT, 23 hours later
    /// noon.adding(DateTimeDuration(hours: 24), in: newYork)   // 2024-03-10 13:00 EDT
    /// ```
    ///
    /// A duration without calendar units never goes through the wall clock,
    /// so a time in a repeated hour stays exactly where it is.
    ///
    /// Days are calendar days, as in Temporal. Across a date a time zone
    /// skipped entirely (Pacific/Apia skipped 2011-12-30), that date still
    /// counts, whereas Foundation's `Calendar.date(byAdding:)` counts only
    /// the days that happened there.
    ///
    /// For a duration or an instant from untrusted input, use
    /// ``checkedAdding(_:in:disambiguation:)``.
    ///
    /// - Precondition: The wall-clock result is within the years
    ///   -999999…999999 and the clock part fits in `Int64` seconds.
    public func adding(
        _ duration: DateTimeDuration,
        in timeZone: TimeZone,
        disambiguation: PlainDateTime.Disambiguation = .compatible
    ) -> Date {
        guard let result = checkedAdding(duration, in: timeZone, disambiguation: disambiguation) else {
            preconditionFailure("Date arithmetic is out of range")
        }
        return result
    }

    /// Like ``adding(_:in:disambiguation:)``, but returns `nil` instead of
    /// stopping the program when this instant is not finite, the wall-clock
    /// result is outside the years -999999…999999, or the clock part does
    /// not fit in `Int64` seconds. Safe to use with untrusted input.
    public func checkedAdding(
        _ duration: DateTimeDuration,
        in timeZone: TimeZone,
        disambiguation: PlainDateTime.Disambiguation = .compatible
    ) -> Date? {
        guard timeIntervalSince1970.isFinite,
              let (seconds, nanoseconds) = duration.clockSecondsAndNanoseconds
        else { return nil }
        var instant = self
        if duration.hasCalendarUnits {
            guard let local = PlainDateTime(checking: self, in: timeZone),
                  let moved = local.checkedAdding(duration.dateDuration)
            else { return nil }
            instant = moved.date(in: timeZone, disambiguation: disambiguation)
        }
        return instant.addingTimeInterval(TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000)
    }
}
