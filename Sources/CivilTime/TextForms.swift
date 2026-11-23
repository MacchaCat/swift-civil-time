// ISO 8601 text forms for every civil type: `description` writes them,
// `init?(_:)` and `init(parsing:)` read them.
//
// The grammar is deliberately strict. Each type reads exactly the form it
// writes, plus the few variants that ISO 8601 and RFC 3339 allow for that
// form (noted on each type). Surrounding whitespace, UTC offsets, `Z`, and
// non-ASCII digits are rejected.

// MARK: - Grammar pieces

extension _Scanner {
    /// `YYYY`, or `±YYYYYY` for expanded years.
    @inlinable
    mutating func year() -> _ParseResult<Int> {
        let start = position
        if let sign = peek(), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
            position += 1
            guard let value = digits(exactly: 6) else { return .failure(.invalidFormat, offset: position) }
            // ISO 8601 forbids "-000000"; year zero is written "0000" or "+000000".
            if sign == UInt8(ascii: "-") && value == 0 { return .failure(.invalidFormat, offset: start) }
            return .success(sign == UInt8(ascii: "-") ? -value : value)
        }
        guard let value = digits(exactly: 4) else { return .failure(.invalidFormat, offset: position) }
        return .success(value)
    }

    @inlinable
    mutating func expect(_ byte: UInt8) -> _ParseResult<Void> {
        consume(byte) ? .success(()) : .failure(.invalidFormat, offset: position)
    }

    @inlinable
    mutating func twoDigits() -> _ParseResult<(value: Int, offset: Int)> {
        let offset = position
        guard let value = digits(exactly: 2) else { return .failure(.invalidFormat, offset: position) }
        return .success((value, offset))
    }

    /// `YYYY-MM-DD`.
    @inlinable
    mutating func date() -> _ParseResult<PlainDate> {
        let yearOffset = position
        let year: Int
        switch self.year() {
        case .success(let value): year = value
        case .failure(let kind, let offset): return .failure(kind, offset: offset)
        }
        guard consume(UInt8(ascii: "-")) else { return .failure(.invalidFormat, offset: position) }
        guard case .success(let month) = twoDigits() else { return .failure(.invalidFormat, offset: position) }
        guard consume(UInt8(ascii: "-")) else { return .failure(.invalidFormat, offset: position) }
        guard case .success(let day) = twoDigits() else { return .failure(.invalidFormat, offset: position) }
        guard CivilMath.isValidYear(year) else { return .failure(.valueOutOfRange, offset: yearOffset) }
        guard month.value >= 1, month.value <= 12 else { return .failure(.valueOutOfRange, offset: month.offset) }
        guard let date = PlainDate(year: year, month: month.value, day: day.value) else {
            return .failure(.valueOutOfRange, offset: day.offset)
        }
        return .success(date)
    }

    /// `HH:MM`, `HH:MM:SS`, or `HH:MM:SS.fffffffff` (a comma may replace the
    /// dot; one to nine fractional digits). A seconds value of 60 reads as 59.
    @inlinable
    mutating func time() -> _ParseResult<PlainTime> {
        guard case .success(let hour) = twoDigits() else { return .failure(.invalidFormat, offset: position) }
        guard consume(UInt8(ascii: ":")) else { return .failure(.invalidFormat, offset: position) }
        guard case .success(let minute) = twoDigits() else { return .failure(.invalidFormat, offset: position) }
        var second = (value: 0, offset: position)
        var nanosecond = 0
        if consume(UInt8(ascii: ":")) {
            guard case .success(let s) = twoDigits() else { return .failure(.invalidFormat, offset: position) }
            second = s
            if consume(UInt8(ascii: ".")) || consume(UInt8(ascii: ",")) {
                let fractionOffset = position
                let run = digitRunLength()
                guard run > 0 else { return .failure(.invalidFormat, offset: position) }
                guard run <= 9 else { return .failure(.tooManyFractionalDigits, offset: fractionOffset) }
                let fraction = digits(maxCount: 9)!
                var scaled = fraction.value
                for _ in fraction.count ..< 9 { scaled *= 10 }
                nanosecond = scaled
            }
        }
        guard hour.value <= 23 else { return .failure(.valueOutOfRange, offset: hour.offset) }
        guard minute.value <= 59 else { return .failure(.valueOutOfRange, offset: minute.offset) }
        guard second.value <= 60 else { return .failure(.valueOutOfRange, offset: second.offset) }
        // There are no leap seconds in civil arithmetic; 23:59:60 reads as 23:59:59.
        let clampedSecond = Swift.min(second.value, 59)
        return .success(PlainTime(hour: hour.value, minute: minute.value, second: clampedSecond, nanosecond: nanosecond)!)
    }

    /// `YYYY-MM-DDTHH:MM:SS`, with `T`, `t` or a space between date and time.
    @inlinable
    mutating func dateTime() -> _ParseResult<PlainDateTime> {
        let date: PlainDate
        switch self.date() {
        case .success(let value): date = value
        case .failure(let kind, let offset): return .failure(kind, offset: offset)
        }
        guard consume(UInt8(ascii: "T")) || consume(UInt8(ascii: "t")) || consume(UInt8(ascii: " ")) else {
            return .failure(.invalidFormat, offset: position)
        }
        switch time() {
        case .success(let time): return .success(PlainDateTime(date: date, time: time))
        case .failure(let kind, let offset): return .failure(kind, offset: offset)
        }
    }
}

// MARK: - PlainDate

extension PlainDate: CustomStringConvertible, LosslessStringConvertible {
    /// The ISO 8601 form, such as `2024-02-29` or `-000044-03-15`.
    public var description: String {
        _makeString(capacity: 16) { writer in
            writer.appendYear(year)
            writer.append(ascii: "-")
            writer.appendDigits(month, width: 2)
            writer.append(ascii: "-")
            writer.appendDigits(day, width: 2)
        }
    }

    /// Parses an ISO 8601 date such as `2024-02-29`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? PlainDate(parsing: description) else { return nil }
        self = value
    }

    /// Parses an ISO 8601 / RFC 3339 `full-date`: `YYYY-MM-DD`, or
    /// `±YYYYYY-MM-DD` for years outside 0000…9999.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "PlainDate") { $0.date() }
    }
}

// MARK: - PlainTime

extension PlainTime: CustomStringConvertible, LosslessStringConvertible {
    /// The ISO 8601 form, such as `09:30:00` or `23:59:59.5`.
    public var description: String {
        _makeString(capacity: 20) { writer in
            writer.appendDigits(hour, width: 2)
            writer.append(ascii: ":")
            writer.appendDigits(minute, width: 2)
            writer.append(ascii: ":")
            writer.appendDigits(second, width: 2)
            writer.appendFraction(nanoseconds: nanosecond)
        }
    }

    /// Parses an ISO 8601 time such as `09:30` or `23:59:59.5`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? PlainTime(parsing: description) else { return nil }
        self = value
    }

    /// Parses an ISO 8601 time of day in extended format: `HH:MM`,
    /// `HH:MM:SS`, or `HH:MM:SS.fffffffff` (a comma may replace the dot).
    ///
    /// The fraction may have one to nine digits. A seconds value of `60`
    /// (a leap second) reads as `59`. `24:00` is rejected.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "PlainTime", endsWithTime: true) { $0.time() }
    }
}

// MARK: - PlainDateTime

extension PlainDateTime: CustomStringConvertible, LosslessStringConvertible {
    /// The ISO 8601 form, such as `2024-02-29T09:30:00`.
    public var description: String {
        _makeString(capacity: 40) { writer in
            writer.appendYear(year)
            writer.append(ascii: "-")
            writer.appendDigits(month, width: 2)
            writer.append(ascii: "-")
            writer.appendDigits(day, width: 2)
            writer.append(ascii: "T")
            writer.appendDigits(hour, width: 2)
            writer.append(ascii: ":")
            writer.appendDigits(minute, width: 2)
            writer.append(ascii: ":")
            writer.appendDigits(second, width: 2)
            writer.appendFraction(nanoseconds: nanosecond)
        }
    }

    /// Parses an ISO 8601 date-time such as `2024-02-29T09:30:00`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? PlainDateTime(parsing: description) else { return nil }
        self = value
    }

    /// Parses an ISO 8601 / RFC 3339 date-time without an offset:
    /// a date as in ``PlainDate/init(parsing:)``, then `T` (or `t`, or a
    /// space), then a time as in ``PlainTime/init(parsing:)``.
    ///
    /// Text with a UTC offset or `Z` is rejected with
    /// ``CivilTimeParseError/Kind/unexpectedTimeZone``: it names an instant,
    /// not a wall-clock time.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "PlainDateTime", endsWithTime: true) { $0.dateTime() }
    }
}

// MARK: - PlainYearMonth

extension PlainYearMonth: CustomStringConvertible, LosslessStringConvertible {
    /// The ISO 8601 form, such as `2024-02`.
    public var description: String {
        _makeString(capacity: 12) { writer in
            writer.appendYear(year)
            writer.append(ascii: "-")
            writer.appendDigits(month, width: 2)
        }
    }

    /// Parses an ISO 8601 year and month such as `2024-02`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? PlainYearMonth(parsing: description) else { return nil }
        self = value
    }

    /// Parses an ISO 8601 year and month: `YYYY-MM`, or `±YYYYYY-MM`.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "PlainYearMonth") { scanner in
            let year: Int
            switch scanner.year() {
            case .success(let value): year = value
            case .failure(let kind, let offset): return .failure(kind, offset: offset)
            }
            guard scanner.consume(UInt8(ascii: "-")) else { return .failure(.invalidFormat, offset: scanner.position) }
            guard case .success(let month) = scanner.twoDigits() else {
                return .failure(.invalidFormat, offset: scanner.position)
            }
            guard let value = PlainYearMonth(year: year, month: month.value) else {
                return .failure(.valueOutOfRange, offset: month.offset)
            }
            return .success(value)
        }
    }
}

// MARK: - PlainMonthDay

extension PlainMonthDay: CustomStringConvertible, LosslessStringConvertible {
    /// The ISO 8601 form, such as `--02-29`.
    public var description: String {
        _makeString(capacity: 8) { writer in
            writer.append(ascii: "-")
            writer.append(ascii: "-")
            writer.appendDigits(month, width: 2)
            writer.append(ascii: "-")
            writer.appendDigits(day, width: 2)
        }
    }

    /// Parses a month and day such as `--02-29` or `02-29`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? PlainMonthDay(parsing: description) else { return nil }
        self = value
    }

    /// Parses a month and day: `--MM-DD` (ISO 8601, XML Schema) or `MM-DD`.
    /// February 29 is accepted.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "PlainMonthDay") { scanner in
            if scanner.consume(UInt8(ascii: "-")) {
                guard scanner.consume(UInt8(ascii: "-")) else {
                    return .failure(.invalidFormat, offset: scanner.position)
                }
            }
            guard case .success(let month) = scanner.twoDigits() else {
                return .failure(.invalidFormat, offset: scanner.position)
            }
            guard scanner.consume(UInt8(ascii: "-")) else { return .failure(.invalidFormat, offset: scanner.position) }
            guard case .success(let day) = scanner.twoDigits() else {
                return .failure(.invalidFormat, offset: scanner.position)
            }
            guard month.value >= 1, month.value <= 12 else { return .failure(.valueOutOfRange, offset: month.offset) }
            guard let value = PlainMonthDay(month: month.value, day: day.value) else {
                return .failure(.valueOutOfRange, offset: day.offset)
            }
            return .success(value)
        }
    }
}

// MARK: - DatePeriod

extension DatePeriod: CustomStringConvertible, LosslessStringConvertible {
    /// The ISO 8601 duration form, such as `P1Y2M10D`, `P0D`, `-P1M`, or
    /// `P1Y-2M` when the components have mixed signs.
    public var description: String {
        if isZero { return "P0D" }
        let allNonPositive = years <= 0 && months <= 0 && days <= 0
        return _makeString(capacity: 72) { writer in
            if allNonPositive { writer.append(ascii: "-") }
            writer.append(ascii: "P")
            for (value, unit) in [(years, "Y"), (months, "M"), (days, "D")] as [(Int, Unicode.Scalar)] where value != 0 {
                if value < 0 && !allNonPositive { writer.append(ascii: "-") }
                writer.appendDigits(value.magnitude, width: 1)
                writer.append(ascii: unit)
            }
        }
    }

    /// Parses an ISO 8601 date duration such as `P1Y2M10D`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? DatePeriod(parsing: description) else { return nil }
        self = value
    }

    /// Parses an ISO 8601 duration with date components only.
    ///
    /// Components appear in the order years (`Y`), months (`M`), weeks (`W`)
    /// and days (`D`), each at most once, and at least one must be present.
    /// A leading `-` negates the whole period; a component may also carry its
    /// own sign (`P1Y-2M`). Weeks are stored as days. Time components
    /// (`PT1H`) are rejected.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "DatePeriod") { scanner in
            var negateAll = false
            if scanner.consume(UInt8(ascii: "-")) {
                negateAll = true
            } else {
                _ = scanner.consume(UInt8(ascii: "+"))
            }
            guard scanner.consume(UInt8(ascii: "P")) else { return .failure(.invalidFormat, offset: scanner.position) }
            let units: [UInt8] = [UInt8(ascii: "Y"), UInt8(ascii: "M"), UInt8(ascii: "W"), UInt8(ascii: "D")]
            var values = [0, 0, 0, 0]
            var nextUnit = 0
            var sawComponent = false
            while !scanner.isAtEnd {
                var negative = false
                if scanner.consume(UInt8(ascii: "-")) {
                    negative = true
                } else {
                    _ = scanner.consume(UInt8(ascii: "+"))
                }
                let numberOffset = scanner.position
                let run = scanner.digitRunLength()
                guard run > 0 else { return .failure(.invalidFormat, offset: scanner.position) }
                guard run <= 15 else { return .failure(.valueOutOfRange, offset: numberOffset) }
                // Accumulate in Int64 so that this also works where Int has
                // 32 bits, then check that the value fits.
                var magnitude: Int64 = 0
                for _ in 0..<run {
                    magnitude = magnitude * 10 + Int64(scanner.bytes[scanner.position] &- 0x30)
                    scanner.position += 1
                }
                guard let unitByte = scanner.peek(),
                      let unitIndex = units.firstIndex(of: unitByte),
                      unitIndex >= nextUnit
                else { return .failure(.invalidFormat, offset: scanner.position) }
                guard let number = Int(exactly: negative ? -magnitude : magnitude) else {
                    return .failure(.valueOutOfRange, offset: numberOffset)
                }
                scanner.position += 1
                values[unitIndex] = number
                nextUnit = unitIndex + 1
                sawComponent = true
            }
            guard sawComponent else { return .failure(.invalidFormat, offset: scanner.position) }
            let (weekDays, o1) = values[2].multipliedReportingOverflow(by: 7)
            let (days, o2) = weekDays.addingReportingOverflow(values[3])
            guard !o1 && !o2 else { return .failure(.valueOutOfRange, offset: 0) }
            var period = DatePeriod(years: values[0], months: values[1], days: days)
            if negateAll { period = period.negated }
            return .success(period)
        }
    }
}

// MARK: - ExtendedTime

extension _Scanner {
    /// `HH:MM`, `HH:MM:SS` or `HH:MM:SS.fffffffff`, where the hour has two to
    /// four digits and may be 24 or more. A seconds value of 60 reads as 59.
    @inlinable
    mutating func extendedTime() -> _ParseResult<ExtendedTime> {
        let hourOffset = position
        let run = digitRunLength()
        guard run >= 2 else { return .failure(.invalidFormat, offset: position) }
        guard run <= 4 else { return .failure(.valueOutOfRange, offset: hourOffset) }
        let hour = digits(maxCount: 4)!.value
        guard consume(UInt8(ascii: ":")) else { return .failure(.invalidFormat, offset: position) }
        guard case .success(let minute) = twoDigits() else { return .failure(.invalidFormat, offset: position) }
        var second = (value: 0, offset: position)
        var nanosecond = 0
        if consume(UInt8(ascii: ":")) {
            guard case .success(let s) = twoDigits() else { return .failure(.invalidFormat, offset: position) }
            second = s
            if consume(UInt8(ascii: ".")) || consume(UInt8(ascii: ",")) {
                let fractionOffset = position
                let fractionRun = digitRunLength()
                guard fractionRun > 0 else { return .failure(.invalidFormat, offset: position) }
                guard fractionRun <= 9 else { return .failure(.tooManyFractionalDigits, offset: fractionOffset) }
                let fraction = digits(maxCount: 9)!
                var scaled = fraction.value
                for _ in fraction.count ..< 9 { scaled *= 10 }
                nanosecond = scaled
            }
        }
        guard minute.value <= 59 else { return .failure(.valueOutOfRange, offset: minute.offset) }
        guard second.value <= 60 else { return .failure(.valueOutOfRange, offset: second.offset) }
        return .success(ExtendedTime(
            hour: hour, minute: minute.value, second: Swift.min(second.value, 59), nanosecond: nanosecond
        )!)
    }
}

extension ExtendedTime: CustomStringConvertible, LosslessStringConvertible {
    /// The text form, such as `26:30:00` or `09:00:00.5`.
    public var description: String {
        _makeString(capacity: 24) { writer in
            writer.appendDigits(hour, width: 2)
            writer.append(ascii: ":")
            writer.appendDigits(minute, width: 2)
            writer.append(ascii: ":")
            writer.appendDigits(second, width: 2)
            writer.appendFraction(nanoseconds: nanosecond)
        }
    }

    /// Parses an extended time such as `26:30` or `25:00:00`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? ExtendedTime(parsing: description) else { return nil }
        self = value
    }

    /// Parses an extended time: `HH:MM`, `HH:MM:SS` or `HH:MM:SS.fffffffff`,
    /// where the hour has two to four digits and may be 24 or more.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "ExtendedTime", endsWithTime: true) { $0.extendedTime() }
    }
}

// MARK: - PlainTimeRange

extension PlainTimeRange: CustomStringConvertible, LosslessStringConvertible {
    /// The ISO 8601 interval form, such as `21:00:00/03:00:00`.
    public var description: String {
        start.description + "/" + end.description
    }

    /// Parses a range such as `21:00/03:00` or `18:00/29:00`, or returns `nil`.
    public init?(_ description: String) {
        guard let value = try? PlainTimeRange(parsing: description) else { return nil }
        self = value
    }

    /// Parses an interval of two times: a start time as in
    /// ``PlainTime/init(parsing:)``, `/`, and an end time.
    ///
    /// The end is read like the start, so when it is earlier than the start
    /// the range runs past midnight, and when they are equal the range covers
    /// the whole day: `21:00/03:00`, `06:00/06:00`.
    ///
    /// The end may also be written with extended hours, as
    /// ``ExtendedTime`` does, to show that it falls on the next day:
    /// `18:00/24:00` ends at midnight, and `18:00/29:00` (the 30-hour clock)
    /// ends at 05:00. An extended end must come after the start and at most
    /// 24 hours later.
    ///
    /// - Throws: ``CivilTimeParseError`` describing the first problem.
    public init(parsing text: some StringProtocol) throws(CivilTimeParseError) {
        self = try _parse(text, as: "PlainTimeRange", endsWithTime: true) { scanner in
            let start: PlainTime
            switch scanner.time() {
            case .success(let value): start = value
            case .failure(let kind, let offset): return .failure(kind, offset: offset)
            }
            guard scanner.consume(UInt8(ascii: "/")) else { return .failure(.invalidFormat, offset: scanner.position) }
            let endOffset = scanner.position
            let end: ExtendedTime
            switch scanner.extendedTime() {
            case .success(let value): end = value
            case .failure(let kind, let offset): return .failure(kind, offset: offset)
            }
            guard end.days > 0 else {
                return .success(PlainTimeRange(start: start, end: end.timeOfDay))
            }
            // An end of 24:00 or later is counted from the start's day.
            guard let range = PlainTimeRange(
                start: start,
                lengthInNanoseconds: end.nanosecondsSinceMidnight - start.nanosecondsSinceMidnight
            ) else { return .failure(.valueOutOfRange, offset: endOffset) }
            return .success(range)
        }
    }
}
