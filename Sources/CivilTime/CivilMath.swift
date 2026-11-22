// Proleptic Gregorian calendar arithmetic on plain integers.
//
// The day-number conversions follow Howard Hinnant's public-domain
// `days_from_civil` / `civil_from_days` algorithms
// (https://howardhinnant.github.io/date_algorithms.html), which are exact for
// every year this package supports.

@usableFromInline
enum CivilMath {
    /// The smallest year a civil value can hold (ISO 8601 expanded, six digits).
    @usableFromInline static let minYear = -999_999
    /// The largest year a civil value can hold (ISO 8601 expanded, six digits).
    @usableFromInline static let maxYear = 999_999

    /// Days since 1970-01-01 of -999999-01-01.
    @usableFromInline static let minEpochDay = -365_961_662
    /// Days since 1970-01-01 of +999999-12-31.
    @usableFromInline static let maxEpochDay = 364_522_971

    @usableFromInline static let secondsPerDay: Int64 = 86_400
    @usableFromInline static let nanosecondsPerSecond: Int64 = 1_000_000_000
    @usableFromInline static let nanosecondsPerDay: Int64 = 86_400 * 1_000_000_000

    @inlinable
    static func isValidYear(_ year: Int) -> Bool {
        year >= minYear && year <= maxYear
    }

    @inlinable
    static func isLeapYear(_ year: Int) -> Bool {
        // `%` truncates toward zero, but divisibility tests are sign-agnostic.
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    @inlinable
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    @inlinable
    static func daysInYear(_ year: Int) -> Int {
        isLeapYear(year) ? 366 : 365
    }

    /// Floor division (rounds toward negative infinity).
    @inlinable
    static func floorDivide(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
    }

    /// The non-negative remainder that matches ``floorDivide(_:_:)``.
    @inlinable
    static func floorModulo(_ a: Int, _ b: Int) -> Int {
        let r = a % b
        return (r != 0 && ((r < 0) != (b < 0))) ? r + b : r
    }

    @inlinable
    static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
    }

    @inlinable
    static func floorModulo(_ a: Int64, _ b: Int64) -> Int64 {
        let r = a % b
        return (r != 0 && ((r < 0) != (b < 0))) ? r + b : r
    }

    /// Days since 1970-01-01 for a valid proleptic Gregorian date.
    @inlinable
    static func epochDay(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = floorDivide(y, 400)
        let yearOfEra = y - era * 400                                         // [0, 399]
        let shiftedMonth = month > 2 ? month - 3 : month + 9                  // March = 0
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1                // [0, 365]
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear  // [0, 146096]
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The proleptic Gregorian date for a number of days since 1970-01-01.
    @inlinable
    static func civil(fromEpochDay epochDay: Int) -> (year: Int, month: Int, day: Int) {
        let z = epochDay + 719_468
        let era = floorDivide(z, 146_097)
        let dayOfEra = z - era * 146_097                                      // [0, 146096]
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153                          // [0, 11]
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1                // [1, 31]
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9  // [1, 12]
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    /// ISO weekday number (Monday = 1 … Sunday = 7) for a day since 1970-01-01.
    @inlinable
    static func isoWeekday(epochDay: Int) -> Int {
        // 1970-01-01 was a Thursday (4).
        floorModulo(epochDay + 3, 7) + 1
    }

    /// Days before the first day of `month` in a common year.
    @usableFromInline
    static let daysBeforeMonth: [Int] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

    @inlinable
    static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        daysBeforeMonth[month - 1] + day + (month > 2 && isLeapYear(year) ? 1 : 0)
    }

    /// Number of ISO weeks (52 or 53) in an ISO week-numbering year.
    @inlinable
    static func isoWeeksInYear(_ year: Int) -> Int {
        // A year has 53 weeks when it starts on a Thursday, or is a leap year
        // that starts on a Wednesday.
        let jan1 = isoWeekday(epochDay: epochDay(year: year, month: 1, day: 1))
        return jan1 == 4 || (jan1 == 3 && isLeapYear(year)) ? 53 : 52
    }
}
