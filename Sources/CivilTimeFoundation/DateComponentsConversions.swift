public import CivilTime
public import Foundation

// Foundation's Gregorian calendar counts years with an era (1 BC is era 0,
// year 1), while ISO 8601 counts year 0 as 1 BC. These conversions translate
// between the two. Foundation's Gregorian calendar also switches to the
// Julian calendar for dates before October 15, 1582, so components for
// earlier dates name a different day there than here.

extension PlainDate {
    /// Creates a date from the `year`, `month` and `day` of `components`, or
    /// returns `nil` if any of them is missing or they do not form a valid
    /// date.
    ///
    /// An `era` of 0 (BC) is honored. Components that name a calendar other
    /// than the Gregorian or ISO 8601 calendar are rejected, because their
    /// fields mean different days.
    public init?(_ components: DateComponents) {
        if let calendar = components.calendar,
           calendar.identifier != .gregorian && calendar.identifier != .iso8601 {
            return nil
        }
        guard let year = components.year, let month = components.month, let day = components.day
        else { return nil }
        var isoYear = year
        if components.era == 0 {
            // 1 BC is year 0. Overflow-checked, because the components may
            // come from untrusted input.
            let (converted, overflow) = 1.subtractingReportingOverflow(year)
            guard !overflow else { return nil }
            isoYear = converted
        }
        self.init(year: isoYear, month: month, day: day)
    }

    /// The date as `DateComponents` with `year`, `month` and `day` set (and
    /// `era` for years before 1), and no calendar or time zone.
    public var dateComponents: DateComponents {
        var components = DateComponents()
        if year >= 1 {
            components.year = year
        } else {
            components.era = 0
            components.year = 1 - year
        }
        components.month = month
        components.day = day
        return components
    }
}

extension PlainTime {
    /// Creates a time from the `hour` and `minute` of `components`, plus
    /// `second` and `nanosecond` when present, or returns `nil` if the hour
    /// or minute is missing or a value is out of range.
    public init?(_ components: DateComponents) {
        guard let hour = components.hour, let minute = components.minute else { return nil }
        self.init(hour: hour, minute: minute, second: components.second ?? 0, nanosecond: components.nanosecond ?? 0)
    }

    /// The time as `DateComponents` with `hour`, `minute`, `second` and
    /// `nanosecond` set.
    public var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
    }
}

extension PlainDateTime {
    /// Creates a date-time from the date and time fields of `components`, or
    /// returns `nil` if a required field is missing or the values are not
    /// valid. The date fields follow `PlainDate.init(_:)` and the time fields
    /// follow `PlainTime.init(_:)`.
    public init?(_ components: DateComponents) {
        guard let date = PlainDate(components), let time = PlainTime(components) else { return nil }
        self.init(date: date, time: time)
    }

    /// The date-time as `DateComponents` with the date and time fields set,
    /// and no calendar or time zone.
    public var dateComponents: DateComponents {
        var components = date.dateComponents
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        return components
    }
}

extension PlainYearMonth {
    /// The year-month as `DateComponents` with `year` and `month` set (and
    /// `era` for years before 1).
    public var dateComponents: DateComponents {
        var components = firstDay.dateComponents
        components.day = nil
        return components
    }
}
