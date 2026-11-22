// Compares common operations with their Foundation equivalents.
//
// Each loop feeds every result into the next iteration or into a running
// checksum, so the optimizer cannot skip or vectorize the work. Numbers are
// the best of five runs, in nanoseconds per operation.

import CivilTime
import CivilTimeFoundation
import Foundation

@inline(never)
func consume<T>(_ value: T) { withExtendedLifetime(value) {} }

func measure(_ name: String, operations: Int, _ body: () -> Void) -> Double {
    let clock = ContinuousClock()
    var best = Double.infinity
    for _ in 0..<5 {
        let elapsed = clock.measure(body).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18
        best = min(best, seconds / Double(operations) * 1e9)
    }
    print(name.padding(toLength: 58, withPad: " ", startingAt: 0), String(format: "%8.1f ns", best))
    return best
}

let count = 200_000
let utc = TimeZone(secondsFromGMT: 0)!
let dates = (0..<count).map { PlainDate(daysSinceEpoch: 10_000 + ($0 &* 7919) % 20_000)! }
let texts = dates.map(\.description)
let instants = dates.map { Date(timeIntervalSince1970: TimeInterval($0.daysSinceEpoch) * 86_400) }
var gregorian = Calendar(identifier: .gregorian)
gregorian.timeZone = utc
let isoStyle = Date.ISO8601FormatStyle(timeZone: utc).year().month().day()

print("Parse \"YYYY-MM-DD\"")
let parseOurs = measure("  PlainDate(parsing:)", operations: count) {
    var sum = 0
    for text in texts { sum &+= try! PlainDate(parsing: text).day }
    consume(sum)
}
let parseTheirs = measure("  Date.ISO8601FormatStyle.parse", operations: count) {
    var sum = 0.0
    for text in texts { sum += try! isoStyle.parse(text).timeIntervalSince1970 }
    consume(sum)
}

print("Format as \"YYYY-MM-DD\"")
let formatOurs = measure("  PlainDate.description", operations: count) {
    var sum = 0
    for date in dates { sum &+= date.description.utf8.count }
    consume(sum)
}
let formatTheirs = measure("  Date.ISO8601FormatStyle.format", operations: count) {
    var sum = 0
    for instant in instants { sum &+= isoStyle.format(instant).utf8.count }
    consume(sum)
}

print("Add one month, repeatedly")
let monthsOurs = measure("  PlainDate.adding(months: 1)", operations: count) {
    var date = dates[0]
    for _ in 0..<count {
        date = date.adding(months: 1)
        if date.year > 9000 { date = dates[0] }
    }
    consume(date)
}
let monthsTheirs = measure("  Calendar.date(byAdding: .month, value: 1, to:)", operations: count) {
    var instant = instants[0]
    for _ in 0..<count {
        instant = gregorian.date(byAdding: .month, value: 1, to: instant)!
    }
    consume(instant)
}

print("Calendar date of an instant in Asia/Tokyo")
let tokyo = TimeZone(identifier: "Asia/Tokyo")!
var tokyoCalendar = Calendar(identifier: .gregorian)
tokyoCalendar.timeZone = tokyo
let zoneOurs = measure("  PlainDate(_:in:)", operations: count) {
    var sum = 0
    for instant in instants { sum &+= PlainDate(instant, in: tokyo).day }
    consume(sum)
}
let zoneTheirs = measure("  Calendar.dateComponents([.year, .month, .day], from:)", operations: count) {
    var sum = 0
    for instant in instants { sum &+= tokyoCalendar.dateComponents([.year, .month, .day], from: instant).day! }
    consume(sum)
}

print(String(
    format: "\nFoundation time / CivilTime time: parse %.1fx, format %.1fx, add months %.0fx, date in zone %.1fx",
    parseTheirs / parseOurs, formatTheirs / formatOurs, monthsTheirs / monthsOurs, zoneTheirs / zoneOurs
))
