import CivilTime

/// A small, fast, seedable generator so that randomized tests repeat exactly.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func date(_ year: Int, _ month: Int, _ day: Int) -> PlainDate {
    PlainDate(year: year, month: month, day: day)!
}

func time(_ hour: Int, _ minute: Int, _ second: Int = 0, _ nanosecond: Int = 0) -> PlainTime {
    PlainTime(hour: hour, minute: minute, second: second, nanosecond: nanosecond)!
}

func dateTime(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> PlainDateTime {
    PlainDateTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second)!
}

extension PlainDate {
    static func random(using generator: inout some RandomNumberGenerator) -> PlainDate {
        PlainDate(daysSinceEpoch: Int.random(in: PlainDate.min.daysSinceEpoch ... PlainDate.max.daysSinceEpoch, using: &generator))!
    }

    /// A random date, usually near the present, sometimes anywhere.
    static func randomMostlyModern(using generator: inout some RandomNumberGenerator) -> PlainDate {
        if Int.random(in: 0..<10, using: &generator) == 0 {
            return random(using: &generator)
        }
        return PlainDate(daysSinceEpoch: Int.random(in: -200_000 ... 200_000, using: &generator))!
    }
}
