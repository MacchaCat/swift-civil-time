public import CivilTime
public import Foundation

// Localized display through Foundation's `Date.FormatStyle`. The civil value
// is turned into an instant in UTC and formatted with the style's time zone
// set to UTC, so the fields shown are exactly the civil value's fields,
// whatever the device's time zone.

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension PlainDate {
    /// The date formatted for display with a `Date.FormatStyle`.
    ///
    /// ```swift
    /// let date = PlainDate(year: 2024, month: 2, day: 29)!
    /// date.formatted(.dateTime.year().month(.wide).day())   // "February 29, 2024" (en_US)
    /// ```
    ///
    /// The style's time zone is replaced with UTC; its locale and calendar
    /// are kept. Time fields in the style show midnight.
    public func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = _utc
        return _utcInstant.formatted(style)
    }

    /// The date formatted for display in one of the standard lengths, such
    /// as "Feb 29, 2024" for `.abbreviated` in English.
    public func formatted(date length: Date.FormatStyle.DateStyle = .abbreviated) -> String {
        formatted(Date.FormatStyle(date: length, time: .omitted))
    }

    /// Midnight UTC on this date.
    var _utcInstant: Date {
        Date(timeIntervalSince1970: TimeInterval(daysSinceEpoch) * 86_400)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension PlainTime {
    /// The time formatted for display with a `Date.FormatStyle`.
    ///
    /// ```swift
    /// PlainTime(hour: 21, minute: 5)!.formatted(.dateTime.hour().minute())   // "9:05 PM" (en_US)
    /// ```
    ///
    /// The style's time zone is replaced with UTC; its locale is kept. Date
    /// fields in the style show 1970-01-01.
    public func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = _utc
        return Date(timeIntervalSince1970: TimeInterval(nanosecondsSinceMidnight) / 1_000_000_000).formatted(style)
    }

    /// The time formatted for display in one of the standard lengths, such
    /// as "9:05 PM" for `.shortened` in English.
    public func formatted(time length: Date.FormatStyle.TimeStyle = .shortened) -> String {
        formatted(Date.FormatStyle(date: .omitted, time: length))
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension PlainDateTime {
    /// The date-time formatted for display with a `Date.FormatStyle`.
    ///
    /// The style's time zone is replaced with UTC; its locale and calendar
    /// are kept. A time-zone field in the style would show UTC, so leave it
    /// out.
    public func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = _utc
        let instant = date._utcInstant.addingTimeInterval(TimeInterval(time.nanosecondsSinceMidnight) / 1_000_000_000)
        return instant.formatted(style)
    }

    /// The date-time formatted for display in standard lengths, such as
    /// "Feb 29, 2024 at 9:05 PM" in English.
    public func formatted(
        date dateLength: Date.FormatStyle.DateStyle = .abbreviated,
        time timeLength: Date.FormatStyle.TimeStyle = .shortened
    ) -> String {
        formatted(Date.FormatStyle(date: dateLength, time: timeLength))
    }
}

private let _utc = TimeZone(secondsFromGMT: 0)!
