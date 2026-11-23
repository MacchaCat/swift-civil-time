// Every civil type encodes as its ISO 8601 string, so JSON looks like
// {"birthday": "1990-02-28", "opens": "09:30:00"} with any encoder settings,
// and decoding rejects anything else.
//
// Embedded Swift has no Codable, so these conformances exist only in full
// Swift.

#if !hasFeature(Embedded)

@inlinable
func _decodeISO8601<Value>(
    from decoder: any Decoder,
    _ parse: (String) throws(CivilTimeParseError) -> Value
) throws -> Value {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    do {
        return try parse(text)
    } catch {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: error.description)
    }
}

@inlinable
func _encodeISO8601(_ text: String, to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(text)
}

extension PlainDate: Codable {
    /// Decodes a date from an ISO 8601 string such as `"2024-02-29"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try PlainDate(parsing: text) }
    }

    /// Encodes the date as an ISO 8601 string such as `"2024-02-29"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

extension PlainTime: Codable {
    /// Decodes a time from an ISO 8601 string such as `"09:30:00"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try PlainTime(parsing: text) }
    }

    /// Encodes the time as an ISO 8601 string such as `"09:30:00"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

extension PlainDateTime: Codable {
    /// Decodes a date-time from an ISO 8601 string such as `"2024-02-29T09:30:00"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try PlainDateTime(parsing: text) }
    }

    /// Encodes the date-time as an ISO 8601 string such as `"2024-02-29T09:30:00"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

extension PlainYearMonth: Codable {
    /// Decodes a year-month from an ISO 8601 string such as `"2024-02"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try PlainYearMonth(parsing: text) }
    }

    /// Encodes the year-month as an ISO 8601 string such as `"2024-02"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

extension PlainMonthDay: Codable {
    /// Decodes a month-day from a string such as `"--02-29"` or `"02-29"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try PlainMonthDay(parsing: text) }
    }

    /// Encodes the month-day as an ISO 8601 string such as `"--02-29"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

extension DatePeriod: Codable {
    /// Decodes a period from an ISO 8601 duration string such as `"P1Y2M10D"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try DatePeriod(parsing: text) }
    }

    /// Encodes the period as an ISO 8601 duration string such as `"P1Y2M10D"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

extension PlainTimeRange: Codable {
    /// Decodes a range from an ISO 8601 interval string such as `"21:00:00/03:00:00"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try PlainTimeRange(parsing: text) }
    }

    /// Encodes the range as an ISO 8601 interval string such as `"21:00:00/03:00:00"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

extension ExtendedTime: Codable {
    /// Decodes an extended time from a string such as `"26:30:00"`.
    public init(from decoder: any Decoder) throws {
        self = try _decodeISO8601(from: decoder) { text throws(CivilTimeParseError) in try ExtendedTime(parsing: text) }
    }

    /// Encodes the extended time as a string such as `"26:30:00"`.
    public func encode(to encoder: any Encoder) throws {
        try _encodeISO8601(description, to: encoder)
    }
}

#endif
