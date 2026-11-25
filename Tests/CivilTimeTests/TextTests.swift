import Foundation
import Testing
@testable import CivilTime

@Suite("ISO 8601 text")
struct TextTests {
    @Test("Dates print in ISO 8601", arguments: [
        ((2024, 2, 29), "2024-02-29"),
        ((1, 1, 1), "0001-01-01"),
        ((0, 1, 1), "0000-01-01"),
        ((-1, 12, 31), "-000001-12-31"),
        ((-44, 3, 15), "-000044-03-15"),
        ((9999, 12, 31), "9999-12-31"),
        ((10000, 1, 1), "+010000-01-01"),
        ((999_999, 12, 31), "+999999-12-31"),
        ((-999_999, 1, 1), "-999999-01-01"),
    ])
    func datePrinting(civil: (Int, Int, Int), text: String) throws {
        let d = date(civil.0, civil.1, civil.2)
        #expect(d.description == text)
        #expect(try PlainDate(parsing: text) == d)
        #expect(PlainDate(text) == d)
    }

    @Test("Date parsing accepts expanded years")
    func expandedYears() throws {
        #expect(try PlainDate(parsing: "+002024-02-29") == date(2024, 2, 29))
        #expect(try PlainDate(parsing: "+000000-01-01") == date(0, 1, 1))
        #expect(try PlainDate(parsing: Substring("xx2024-02-29").dropFirst(2)) == date(2024, 2, 29))
    }

    @Test("Date parsing rejects everything else", arguments: [
        ("", CivilTimeParseError.Kind.invalidFormat, 0),
        ("2024-02-30", .valueOutOfRange, 8),
        ("2023-02-29", .valueOutOfRange, 8),
        ("2024-13-01", .valueOutOfRange, 5),
        ("2024-00-10", .valueOutOfRange, 5),
        ("2024-01-00", .valueOutOfRange, 8),
        ("2024-1-01", .invalidFormat, 5),
        ("2024-01-1", .invalidFormat, 8),
        ("24-01-01", .invalidFormat, 0),
        ("20240101", .invalidFormat, 4),
        ("12024-01-01", .invalidFormat, 4),
        ("-000000-01-01", .invalidFormat, 0),
        ("+2024-01-01", .invalidFormat, 1),
        (" 2024-01-01", .invalidFormat, 0),
        ("2024-01-01 ", .unexpectedTrailingText, 10),
        ("2024-01-01T00:00", .unexpectedTrailingText, 10),
        ("2024-01-01Z", .unexpectedTrailingText, 10),
        ("2024-01-01+09:00", .unexpectedTrailingText, 10),
        ("２０２４-01-01", .invalidFormat, 0),
        ("2024/01/01", .invalidFormat, 4),
        ("2024-01-01\u{0}", .unexpectedTrailingText, 10),
    ])
    func dateRejections(text: String, kind: CivilTimeParseError.Kind, offset: Int) {
        #expect(PlainDate(text) == nil)
        #expect(throws: CivilTimeParseError(kind: kind, input: text, offset: offset, typeName: "PlainDate")) {
            try PlainDate(parsing: text)
        }
    }

    @Test("Parse errors explain themselves")
    func errorDescription() {
        do {
            _ = try PlainDate(parsing: "2023-02-29")
            Issue.record("expected an error")
        } catch {
            #expect(error.description == "Cannot parse \"2023-02-29\" as PlainDate: value out of range at offset 8")
            #expect(error.kind == .valueOutOfRange)
        }
        let long = String(repeating: "9", count: 200)
        #expect(throws: CivilTimeParseError.self) { try PlainDate(parsing: long) }
        do { _ = try PlainDate(parsing: long) } catch { #expect(error.input.count == 80) }
    }

    @Test("Times print in ISO 8601", arguments: [
        ((9, 30, 0, 0), "09:30:00"),
        ((0, 0, 0, 0), "00:00:00"),
        ((23, 59, 59, 999_999_999), "23:59:59.999999999"),
        ((23, 59, 59, 500_000_000), "23:59:59.5"),
        ((12, 0, 0, 1), "12:00:00.000000001"),
        ((12, 0, 0, 120_000), "12:00:00.00012"),
    ])
    func timePrinting(parts: (Int, Int, Int, Int), text: String) throws {
        let t = time(parts.0, parts.1, parts.2, parts.3)
        #expect(t.description == text)
        #expect(try PlainTime(parsing: text) == t)
    }

    @Test("Time parsing variants")
    func timeVariants() throws {
        #expect(try PlainTime(parsing: "09:30") == time(9, 30))
        #expect(try PlainTime(parsing: "09:30:15,25") == time(9, 30, 15, 250_000_000))
        #expect(try PlainTime(parsing: "23:59:60") == time(23, 59, 59))
        #expect(try PlainTime(parsing: "23:59:60.5") == time(23, 59, 59, 500_000_000))
        #expect(try PlainTime(parsing: "00:00:00.000000000") == .midnight)
    }

    @Test("Time parsing rejects everything else", arguments: [
        ("24:00", CivilTimeParseError.Kind.valueOutOfRange, 0),
        ("24:00:00", .valueOutOfRange, 0),
        ("12:60", .valueOutOfRange, 3),
        ("12:00:61", .valueOutOfRange, 6),
        ("12", .invalidFormat, 2),
        ("12:0", .invalidFormat, 3),
        ("1:00", .invalidFormat, 0),
        ("12:00:00.", .invalidFormat, 9),
        ("12:00:00.1234567891", .tooManyFractionalDigits, 9),
        ("12:00:00Z", .unexpectedTimeZone, 8),
        ("12:00:00+09:00", .unexpectedTimeZone, 8),
        ("1200", .invalidFormat, 2),
        ("T12:00", .invalidFormat, 0),
    ])
    func timeRejections(text: String, kind: CivilTimeParseError.Kind, offset: Int) {
        #expect(throws: CivilTimeParseError(kind: kind, input: text, offset: offset, typeName: "PlainTime")) {
            try PlainTime(parsing: text)
        }
    }

    @Test("Date-time text")
    func dateTimes() throws {
        let t = PlainDateTime(year: 2024, month: 2, day: 29, hour: 9, minute: 30, second: 5, nanosecond: 120_000_000)!
        #expect(t.description == "2024-02-29T09:30:05.12")
        #expect(try PlainDateTime(parsing: "2024-02-29T09:30:05.12") == t)
        #expect(try PlainDateTime(parsing: "2024-02-29t09:30:05.12") == t)
        #expect(try PlainDateTime(parsing: "2024-02-29 09:30:05.12") == t)
        #expect(try PlainDateTime(parsing: "2024-02-29T09:30") == dateTime(2024, 2, 29, 9, 30))
        #expect(dateTime(-5, 1, 1).description == "-000005-01-01T00:00:00")
        #expect(throws: CivilTimeParseError(kind: .unexpectedTimeZone, input: "2024-02-29T09:30:00Z", offset: 19, typeName: "PlainDateTime")) {
            try PlainDateTime(parsing: "2024-02-29T09:30:00Z")
        }
        #expect(throws: CivilTimeParseError(kind: .unexpectedTimeZone, input: "2024-02-29T09:30:00-05:00", offset: 19, typeName: "PlainDateTime")) {
            try PlainDateTime(parsing: "2024-02-29T09:30:00-05:00")
        }
        #expect(throws: CivilTimeParseError(kind: .unexpectedTimeZone, input: "2024-02-29T09:30:00[Asia/Tokyo]", offset: 19, typeName: "PlainDateTime")) {
            try PlainDateTime(parsing: "2024-02-29T09:30:00[Asia/Tokyo]")
        }
        #expect(throws: CivilTimeParseError(kind: .valueOutOfRange, input: "2023-02-29T09:30", offset: 8, typeName: "PlainDateTime")) {
            try PlainDateTime(parsing: "2023-02-29T09:30")
        }
        #expect(throws: CivilTimeParseError(kind: .invalidFormat, input: "2024-02-29", offset: 10, typeName: "PlainDateTime")) {
            try PlainDateTime(parsing: "2024-02-29")
        }
        #expect(throws: CivilTimeParseError(kind: .valueOutOfRange, input: "2024-02-29T25:00", offset: 11, typeName: "PlainDateTime")) {
            try PlainDateTime(parsing: "2024-02-29T25:00")
        }
    }

    @Test("Year-month and month-day text")
    func yearMonthAndMonthDay() throws {
        #expect(PlainYearMonth(year: 2024, month: 2)!.description == "2024-02")
        #expect(PlainYearMonth(year: -12, month: 2)!.description == "-000012-02")
        #expect(try PlainYearMonth(parsing: "2024-02") == PlainYearMonth(year: 2024, month: 2))
        #expect(PlainYearMonth("2024-13") == nil)
        #expect(PlainYearMonth("2024-02-01") == nil)
        #expect(throws: CivilTimeParseError(kind: .unexpectedTrailingText, input: "2024-02-01", offset: 7, typeName: "PlainYearMonth")) {
            try PlainYearMonth(parsing: "2024-02-01")
        }
        #expect(PlainMonthDay(month: 2, day: 29)!.description == "--02-29")
        #expect(try PlainMonthDay(parsing: "--02-29") == PlainMonthDay(month: 2, day: 29))
        #expect(try PlainMonthDay(parsing: "12-25") == PlainMonthDay(month: 12, day: 25))
        #expect(PlainMonthDay("--02-30") == nil)
        #expect(PlainMonthDay("-02-28") == nil)
        #expect(PlainMonthDay("--2-28") == nil)
    }

    @Test("Period text", arguments: [
        (DateDuration(years: 1, months: 2, days: 10), "P1Y2M10D"),
        (DateDuration(), "P0D"),
        (DateDuration(months: -1), "-P1M"),
        (DateDuration(years: -1, days: -3), "-P1Y3D"),
        (DateDuration(years: 1, months: -2), "P1Y-2M"),
        (DateDuration(days: 400), "P400D"),
        (DateDuration(years: Int.min), "-P\(Int.min.magnitude)Y"),
    ])
    func periodPrinting(period: DateDuration, text: String) throws {
        #expect(period.description == text)
        if period.years != Int.min {
            #expect(try DateDuration(parsing: text) == period)
        }
    }

    @Test("Period parsing")
    func periodParsing() throws {
        #expect(try DateDuration(parsing: "P2W") == DateDuration(days: 14))
        #expect(try DateDuration(parsing: "P1Y2W3D") == DateDuration(years: 1, days: 17))
        #expect(try DateDuration(parsing: "+P1D") == DateDuration(days: 1))
        #expect(try DateDuration(parsing: "-P1Y-2M") == DateDuration(years: -1, months: 2))
        // 15 digits fit (even where Int has 32 bits they are rejected cleanly
        // rather than trapping); 16 never do.
        #expect(DateDuration("P999999999999999D") == (MemoryLayout<Int>.size == 8 ? DateDuration(days: 999_999_999_999_999) : nil))
        #expect(throws: CivilTimeParseError(kind: .valueOutOfRange, input: "P2000000000000000W", offset: 1, typeName: "DateDuration")) {
            try DateDuration(parsing: "P2000000000000000W")
        }
        for bad in ["P", "", "1Y", "P1H", "PT1H", "P1D1Y", "P1Y1Y", "P1.5Y", "PY", "P-", "P1Y ", "P1234567890123456D"] {
            #expect(DateDuration(bad) == nil, "\(bad)")
        }
    }

    @Test("Text round-trips for random values")
    func randomRoundTrips() {
        var generator = SplitMix64(seed: 20)
        var bad: [String] = []
        for _ in 0..<100_000 {
            let d = PlainDate.random(using: &generator)
            let t = PlainTime(nanosecondsSinceMidnight: Int64.random(in: 0..<86_400_000_000_000, using: &generator))!
            let dt = d.at(t)
            if PlainDate(d.description) != d { bad.append(d.description) }
            if PlainTime(t.description) != t { bad.append(t.description) }
            if PlainDateTime(dt.description) != dt { bad.append(dt.description) }
            if PlainYearMonth(d.yearMonth.description) != d.yearMonth { bad.append(d.yearMonth.description) }
            if PlainMonthDay(d.monthDay.description) != d.monthDay { bad.append(d.monthDay.description) }
            let p = DateDuration(
                years: Int.random(in: -99_999...99_999, using: &generator),
                months: Int.random(in: -99_999...99_999, using: &generator),
                days: Int.random(in: -99_999...99_999, using: &generator))
            if DateDuration(p.description) != p { bad.append(p.description) }
            if bad.count > 10 { break }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Codable uses the ISO 8601 strings")
    func codable() throws {
        struct Event: Codable, Equatable {
            var day: PlainDate
            var opens: PlainTime
            var starts: PlainDateTime
            var month: PlainYearMonth
            var anniversary: PlainMonthDay
            var every: DateDuration
        }
        let event = Event(
            day: date(2024, 2, 29),
            opens: time(9, 30),
            starts: dateTime(2024, 2, 29, 18),
            month: PlainYearMonth(year: 2024, month: 2)!,
            anniversary: PlainMonthDay(month: 2, day: 29)!,
            every: DateDuration(years: 1)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(event), as: UTF8.self)
        #expect(json == #"{"anniversary":"--02-29","day":"2024-02-29","every":"P1Y","month":"2024-02","opens":"09:30:00","starts":"2024-02-29T18:00:00"}"#)
        #expect(try JSONDecoder().decode(Event.self, from: Data(json.utf8)) == event)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PlainDate].self, from: Data(#"["2023-02-29"]"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PlainDate].self, from: Data(#"[19782]"#.utf8))
        }
    }
}
