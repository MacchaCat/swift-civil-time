import CivilTime
@testable import CivilTimeFoundation
import Foundation
import Testing

private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }
private func utc(_ text: String) -> Date { try! Date(text, strategy: .iso8601) }
private func zoned(_ text: String, _ identifier: String) -> ZonedDateTime {
    ZonedDateTime(PlainDateTime(text)!, in: zone(identifier))
}

@Suite("ZonedDateTime")
struct ZonedDateTimeTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    @Test("Construction and properties")
    func basics() {
        let departure = zoned("2025-05-02T22:00", "Asia/Tokyo")
        #expect(departure.description == "2025-05-02T22:00:00+09:00[Asia/Tokyo]")
        #expect(departure.date == utc("2025-05-02T13:00:00Z"))
        #expect(departure.utcOffset == 32_400)
        #expect(departure.plainDate == PlainDate("2025-05-02") && departure.plainTime == PlainTime("22:00"))
        let fraction = ZonedDateTime(Date(timeIntervalSince1970: 1.5), in: zone("UTC"))
        #expect(fraction.secondsSince1970 == 1 && fraction.nanoseconds == 500_000_000)
        #expect(fraction.description == "1970-01-01T00:00:01.5+00:00[\(zone("UTC").identifier)]")
        let beforeEpoch = ZonedDateTime(Date(timeIntervalSince1970: -0.25), in: zone("UTC"))
        #expect(beforeEpoch.secondsSince1970 == -1 && beforeEpoch.nanoseconds == 750_000_000)
    }

    @Test("Skipped and repeated wall-clock times")
    func disambiguation() {
        let skipped = PlainDateTime("2024-03-10T02:30")!
        #expect(ZonedDateTime(skipped, in: newYork).dateTime == PlainDateTime("2024-03-10T03:30"))
        #expect(ZonedDateTime(skipped, in: newYork, disambiguation: .earlier).dateTime == PlainDateTime("2024-03-10T01:30"))
        let repeated = PlainDateTime("2024-11-03T01:30")!
        #expect(ZonedDateTime(repeated, in: newYork).utcOffset == -4 * 3600)
        #expect(ZonedDateTime(repeated, in: newYork, disambiguation: .later).utcOffset == -5 * 3600)
    }

    @Test("Time zones: conversion, equality and fixing the zone")
    func timeZones() throws {
        let tokyo = zoned("2025-05-02T22:00", "Asia/Tokyo")
        let losAngeles = tokyo.withTimeZone(zone("America/Los_Angeles"))
        #expect(losAngeles.dateTime == PlainDateTime("2025-05-02T06:00"))
        #expect(losAngeles.date == tokyo.date)
        #expect(losAngeles != tokyo)
        #expect(Set([tokyo, tokyo.withTimeZone(zone("Asia/Tokyo")), losAngeles]).count == 2)
        // The same zone made in different ways compares equal.
        let current = ZonedDateTime(tokyo.date, in: .autoupdatingCurrent)
        #expect(current == ZonedDateTime(tokyo.date, in: TimeZone(identifier: TimeZone.current.identifier)!))
        #expect(current.timeZone.identifier == TimeZone.current.identifier)
        // now() survives encoding.
        let now = ZonedDateTime.now()
        let decoded = try JSONDecoder().decode(ZonedDateTime.self, from: JSONEncoder().encode(now))
        #expect(decoded == now)
        #expect(decoded.hashValue == now.hashValue)
    }

    @Test("Parsing RFC 9557 strings")
    func parsing() throws {
        #expect(try ZonedDateTime(parsing: "2025-05-02T22:00:00+09:00[Asia/Tokyo]") == zoned("2025-05-02T22:00", "Asia/Tokyo"))
        #expect(try ZonedDateTime(parsing: "2025-05-02T22:00+09:00[!Asia/Tokyo]") == zoned("2025-05-02T22:00", "Asia/Tokyo"))
        #expect(try ZonedDateTime(parsing: "2025-05-02T13:00:00Z[Asia/Tokyo]").dateTime == PlainDateTime("2025-05-02T22:00"))
        // The offset picks the occurrence of a repeated time.
        #expect(try ZonedDateTime(parsing: "2024-11-03T01:30:00-04:00[America/New_York]").date == utc("2024-11-03T05:30:00Z"))
        #expect(try ZonedDateTime(parsing: "2024-11-03T01:30:00-05:00[America/New_York]").date == utc("2024-11-03T06:30:00Z"))
        // Without an offset, .compatible.
        #expect(try ZonedDateTime(parsing: "2024-03-10T02:30:00[America/New_York]").dateTime == PlainDateTime("2024-03-10T03:30"))
        // Fixed-offset zones are written as offsets.
        let fixed = ZonedDateTime(utc("2025-05-02T13:00:00Z"), in: TimeZone(secondsFromGMT: 32_400)!)
        #expect(fixed.description == "2025-05-02T22:00:00+09:00[+09:00]")
        #expect(try ZonedDateTime(parsing: fixed.description) == fixed)
    }

    @Test("Offsets that do not match the time zone")
    func offsetPolicies() throws {
        let text = "2024-11-03T01:30:00-03:00[America/New_York]"
        #expect(throws: CivilTimeParseError(kind: .offsetMismatch, input: text, offset: 19, typeName: "ZonedDateTime")) {
            try ZonedDateTime(parsing: text)
        }
        #expect(try ZonedDateTime(parsing: text, offsetPolicy: .prefer).date == utc("2024-11-03T05:30:00Z"))
        #expect(try ZonedDateTime(parsing: text, offsetPolicy: .ignore).date == utc("2024-11-03T05:30:00Z"))
        let used = try ZonedDateTime(parsing: text, offsetPolicy: .use)
        #expect(used.date == utc("2024-11-03T04:30:00Z") && used.dateTime == PlainDateTime("2024-11-03T00:30"))
        // A skipped time with an offset has no matching instant.
        let gap = "2024-03-10T02:30:00-05:00[America/New_York]"
        #expect(throws: CivilTimeParseError.self) { try ZonedDateTime(parsing: gap) }
        #expect(try ZonedDateTime(parsing: gap, offsetPolicy: .use).dateTime == PlainDateTime("2024-03-10T03:30"))
        #expect(try ZonedDateTime(parsing: gap, offsetPolicy: .prefer).dateTime == PlainDateTime("2024-03-10T03:30"))
        // Decoding uses .prefer, so a mismatched offset still loads.
        struct Event: Codable { var at: ZonedDateTime }
        let event = try JSONDecoder().decode(Event.self, from: Data(#"{"at":"2024-11-03T01:30:00-03:00[America/New_York]"}"#.utf8))
        #expect(event.at.date == utc("2024-11-03T05:30:00Z"))
    }

    @Test("Offsets with seconds, and offsets written to the minute")
    func secondsInOffsets() throws {
        // Liberia used -00:44:30 until 1972. Check the system's time-zone data
        // has that offset before relying on it.
        let monrovia = zone("Africa/Monrovia")
        let local = PlainDateTime("1960-06-01T12:00")!
        let value = ZonedDateTime(local, in: monrovia)
        try #require(value.utcOffset == -2_670)
        let exact = value.description
        #expect(exact == "1960-06-01T12:00:00-00:44:30[Africa/Monrovia]")
        #expect(try ZonedDateTime(parsing: exact) == value)
        // The offset to the minute matches when it equals the rounded offset.
        let rounded = ZonedDateTime._roundedToMinute(value.utcOffset)
        #expect(rounded == -2_700)
        #expect(try ZonedDateTime(parsing: "1960-06-01T12:00:00-00:45[Africa/Monrovia]") == value)
        #expect(throws: CivilTimeParseError.self) { try ZonedDateTime(parsing: "1960-06-01T12:00:00-00:44[Africa/Monrovia]") }
    }

    @Test("Fixed-offset zones keep their exact offset")
    func fixedOffsets() throws {
        let odd = TimeZone(secondsFromGMT: 1_172)!
        let value = ZonedDateTime(utc("2025-05-02T00:00:00Z"), in: odd)
        #expect(value.utcOffset == 1_172 && value.timeZone.secondsFromGMT() == 1_172)
        #expect(value.description == "2025-05-02T00:19:32+00:19:32[+00:19:32]")
        #expect(try ZonedDateTime(parsing: value.description) == value)
        // Not equal to the zone a minute-rounded identifier would give.
        #expect(value != ZonedDateTime(utc("2025-05-02T00:00:00Z"), in: TimeZone(secondsFromGMT: 1_200)!))
        // Exact instants from seconds and nanoseconds.
        let exact = try #require(ZonedDateTime(secondsSince1970: 1_746_190_800, nanoseconds: 123_456_789, in: zone("Asia/Tokyo")))
        #expect(exact.description == "2025-05-02T22:00:00.123456789+09:00[Asia/Tokyo]")
        #expect(ZonedDateTime(secondsSince1970: 0, nanoseconds: -1, in: zone("UTC"))?.dateTime == PlainDateTime("1969-12-31T23:59:59.999999999"))
    }

    @Test("Rejected strings", arguments: [
        ("2025-05-02T22:00:00+09:00", CivilTimeParseError.Kind.invalidFormat),
        ("2025-05-02T22:00:00+09:00[Mars/Olympus]", .unknownTimeZone),
        ("2025-05-02T22:00:00+09:00[u-ca=japanese]", .invalidFormat),
        ("2025-05-02T22:00:00+09:00[Asia/Tokyo][u-ca=iso8601]", .unexpectedTrailingText),
        ("2025-05-02T22:00:00+9:00[Asia/Tokyo]", .invalidFormat),
        ("2025-05-02T22:00:00+24:00[Asia/Tokyo]", .valueOutOfRange),
        ("2025-05-02T22:00:00+09:00[]", .invalidFormat),
        ("2025-05-02T22:00:00+09:00[+09:00x]", .invalidFormat),
        ("2025-05-02[Asia/Tokyo]", .invalidFormat),
    ])
    func rejected(text: String, kind: CivilTimeParseError.Kind) {
        do {
            _ = try ZonedDateTime(parsing: text)
            Issue.record("parsed \(text)")
        } catch {
            #expect(error.kind == kind, "\(text): \(error)")
        }
    }

    @Test("Random text round-trips, and noise never traps")
    func randomText() {
        let zones = ["Asia/Tokyo", "America/New_York", "Australia/Lord_Howe", "Asia/Kathmandu", "Europe/London", "UTC"].map(zone)
        var state: UInt64 = 0xC0FFEE
        func next(_ bound: UInt64) -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (state >> 33) % bound
        }
        var bad: [String] = []
        for _ in 0..<5_000 {
            let seconds = Int64(next(2_000_000_000)) - 500_000_000
            let value = ZonedDateTime(seconds: seconds, nanoseconds: Int64(next(1_000_000_000)), timeZone: zones[Int(next(UInt64(zones.count)))])!
            if ZonedDateTime(value.description) != value { bad.append(value.description) }
        }
        #expect(bad.isEmpty, "\(bad.prefix(5))")
        let alphabet = Array("0123456789-:T+Z[]!/ABab.,".utf8)
        for _ in 0..<5_000 {
            let noise = String(decoding: (0..<next(45)).map { _ in alphabet[Int(next(UInt64(alphabet.count)))] }, as: UTF8.self)
            _ = ZonedDateTime(noise)
            _ = ZonedDateTime("2025-05-02T22:00:00+09:00[" + noise + "]")
        }
    }

    @Test("Adding durations")
    func adding() {
        let noon = zoned("2024-03-09T12:00", "America/New_York")
        #expect(noon.adding(DateTimeDuration(days: 1)).dateTime == PlainDateTime("2024-03-10T12:00"))
        #expect(noon.adding(DateTimeDuration(hours: 24)).dateTime == PlainDateTime("2024-03-10T13:00"))
        #expect(noon.adding(DateTimeDuration(days: 1)).date.timeIntervalSince(noon.date) == 23 * 3600)
        #expect(zoned("2024-01-31T09:00", "Asia/Tokyo").adding(DateTimeDuration(months: 1)).dateTime == PlainDateTime("2024-02-29T09:00"))
        #expect(noon.checkedAdding(DateTimeDuration(years: 2_000_000)) == nil)
        #expect(noon.checkedAdding(DateTimeDuration(hours: .max)) == nil)
        // The same results as Date.adding(_:in:).
        var state: UInt64 = 7
        func next(_ bound: UInt64) -> Int64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int64((state >> 33) % bound)
        }
        var bad = 0
        for _ in 0..<5_000 {
            let start = ZonedDateTime(seconds: 1_000_000_000 + next(900_000_000), nanoseconds: 0, timeZone: newYork)!
            let duration = DateTimeDuration(months: Int(next(30)) - 15, days: Int(next(60)) - 30, hours: next(48) - 24, minutes: next(120) - 60)
            if start.adding(duration).date != start.date.adding(duration, in: newYork) { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test("Durations until another moment lead back to it", arguments: [
        "America/New_York", "Australia/Lord_Howe", "America/Santiago", "Pacific/Apia", "Asia/Tokyo",
    ])
    func until(identifier: String) {
        let timeZone = zone(identifier)
        let others = ["Europe/London", "Asia/Kolkata", identifier].map(zone)
        var state: UInt64 = 99
        func next(_ bound: UInt64) -> Int64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int64((state >> 33) % bound)
        }
        // 2005–2030, plus 2011 for Apia's skipped day.
        let low: Int64 = 1_104_537_600, span: Int64 = 820_000_000
        var bad: [String] = []
        for i in 0..<20_000 {
            let base = i % 4 == 0 ? 1_320_000_000 + next(10_000_000) : low + next(UInt64(span))
            let a = ZonedDateTime(seconds: base, nanoseconds: next(1_000_000_000), timeZone: timeZone)!
            let offset: Int64 = i % 3 == 0 ? next(200_000) - 100_000 : next(200_000_000) - 100_000_000
            let b = ZonedDateTime(seconds: base + offset, nanoseconds: next(1_000_000_000),
                                  timeZone: others[Int(next(UInt64(others.count)))])!
            let d = a.dateTimeDuration(until: b)
            let parts = [Int64(d.years), Int64(d.months), Int64(d.days), d.hours, d.minutes, d.seconds, d.nanoseconds]
            let oneSign = Set(parts.filter { $0 != 0 }.map { $0 > 0 }).count <= 1
            let back = a.adding(d)
            if back.secondsSince1970 != b.secondsSince1970 || back.nanoseconds != b.nanoseconds || !oneSign {
                if bad.count < 5 { bad.append("\(a) → \(b): \(d) → \(back)") }
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("Known durations across clock changes")
    func knownDurations() {
        let before = zoned("2024-03-09T12:00", "America/New_York")
        let after = zoned("2024-03-10T12:00", "America/New_York")
        #expect(before.dateTimeDuration(until: after).description == "P1D")
        #expect(after.dateTimeDuration(until: before).description == "-P1D")
        #expect(before.dateTimeDuration(until: zoned("2024-03-10T11:30", "America/New_York")).description == "PT22H30M")
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            #expect(before.duration(until: after) == .seconds(23 * 3600))
        }
    }

    @Test("Start of day")
    func startOfDay() {
        let santiago = zoned("2024-09-08T15:00", "America/Santiago")
        #expect(santiago.startOfDay.dateTime == PlainDateTime("2024-09-08T01:00"))
        #expect(zoned("2024-07-01T15:45", "Asia/Tokyo").startOfDay.dateTime == PlainDateTime("2024-07-01T00:00"))
    }

    @Test("Untrusted input never traps")
    func untrusted() {
        #expect(ZonedDateTime(checking: Date(timeIntervalSince1970: .infinity), in: newYork) == nil)
        #expect(ZonedDateTime(checking: Date(timeIntervalSince1970: .nan), in: newYork) == nil)
        #expect(ZonedDateTime(checking: Date(timeIntervalSince1970: 1e300), in: newYork) == nil)
        let edge = ZonedDateTime(PlainDateTime.max, in: zone("UTC"))
        #expect(edge.checkedWithTimeZone(zone("Pacific/Kiritimati")) == nil)
        #expect(edge.checkedWithTimeZone(zone("America/New_York")) != nil)
        #expect(edge.checkedAdding(DateTimeDuration(seconds: 1)) == nil)
        // Far beyond the range: rejected before the time zone is consulted.
        let now = ZonedDateTime(utc("2025-05-02T00:00:00Z"), in: newYork)
        #expect(now.checkedAdding(DateTimeDuration("PT999999999999999H")!) == nil)
        #expect(ZonedDateTime(secondsSince1970: .max, in: newYork) == nil)
        #expect(ZonedDateTime(secondsSince1970: .min, nanoseconds: -1, in: newYork) == nil)
        #expect(ZonedDateTime(checking: PlainDateTime.max, in: zone("UTC")) != nil)
    }
}
