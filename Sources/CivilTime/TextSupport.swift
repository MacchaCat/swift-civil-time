// Byte-level helpers shared by the formatters and parsers.
//
// Parsing reads UTF-8 bytes and accepts only ASCII digits, so look-alike
// digits from other scripts (such as full-width "２０２４") are rejected rather
// than silently converted.

// MARK: - Writing

@usableFromInline
struct _ByteWriter {
    @usableFromInline var buffer: UnsafeMutableBufferPointer<UInt8>
    @usableFromInline var count = 0

    @inlinable
    init(buffer: UnsafeMutableBufferPointer<UInt8>) {
        self.buffer = buffer
    }

    @inlinable
    mutating func append(ascii scalar: Unicode.Scalar) {
        buffer[count] = UInt8(truncatingIfNeeded: scalar.value)
        count += 1
    }

    /// Appends a non-negative value, zero-padded to at least `width` digits.
    @inlinable
    mutating func appendDigits(_ value: Int, width: Int) {
        precondition(value >= 0)
        appendDigits(UInt(value), width: width)
    }

    /// Appends a value, zero-padded to at least `width` digits.
    @inlinable
    mutating func appendDigits(_ value: UInt, width: Int) {
        var digits = 1
        var rest = value / 10
        while rest > 0 { digits += 1; rest /= 10 }
        let total = Swift.max(digits, width)
        var v = value
        var i = count + total - 1
        while i >= count {
            buffer[i] = 0x30 + UInt8(truncatingIfNeeded: v % 10)
            v /= 10
            i -= 1
        }
        count += total
    }

    /// Appends a year: four digits for 0…9999, otherwise a sign and six digits.
    @inlinable
    mutating func appendYear(_ year: Int) {
        if year >= 0 && year <= 9999 {
            appendDigits(year, width: 4)
        } else {
            append(ascii: year < 0 ? "-" : "+")
            appendDigits(year < 0 ? -year : year, width: 6)
        }
    }

    /// Appends `.` and the fraction of a second, without trailing zeros.
    /// Appends nothing when `nanoseconds` is zero.
    @inlinable
    mutating func appendFraction(nanoseconds: Int) {
        guard nanoseconds != 0 else { return }
        var value = nanoseconds
        var width = 9
        while value % 10 == 0 {
            value /= 10
            width -= 1
        }
        append(ascii: ".")
        appendDigits(value, width: width)
    }
}

/// Builds a short ASCII string without heap-allocating a scratch buffer.
@inlinable
func _makeString(capacity: Int, _ body: (inout _ByteWriter) -> Void) -> String {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity) { buffer in
        var writer = _ByteWriter(buffer: buffer)
        body(&writer)
        return String(decoding: UnsafeBufferPointer(rebasing: buffer[..<writer.count]), as: UTF8.self)
    }
}

// MARK: - Reading

/// A cursor over UTF-8 bytes.
@usableFromInline
struct _Scanner {
    @usableFromInline let bytes: UnsafeBufferPointer<UInt8>
    @usableFromInline var position = 0

    @inlinable
    init(_ bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    @inlinable
    var isAtEnd: Bool { position >= bytes.count }

    @inlinable
    func peek() -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    /// Consumes `byte` if it is next.
    @inlinable
    mutating func consume(_ byte: UInt8) -> Bool {
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    /// Reads exactly `count` ASCII digits.
    @inlinable
    mutating func digits(exactly count: Int) -> Int? {
        guard bytes.count - position >= count else { return nil }
        var value = 0
        for i in position ..< position + count {
            let digit = bytes[i] &- 0x30
            guard digit < 10 else { return nil }
            value = value * 10 + Int(digit)
        }
        position += count
        return value
    }

    /// Reads one or more ASCII digits, at most `maxCount`, and returns the
    /// value and the number of digits read.
    @inlinable
    mutating func digits(maxCount: Int) -> (value: Int, count: Int)? {
        var value = 0
        var count = 0
        while position < bytes.count, count < maxCount {
            let digit = bytes[position] &- 0x30
            guard digit < 10 else { break }
            value = value * 10 + Int(digit)
            count += 1
            position += 1
        }
        return count == 0 ? nil : (value, count)
    }

    /// The number of ASCII digits starting at the current position.
    @inlinable
    func digitRunLength() -> Int {
        var i = position
        while i < bytes.count, bytes[i] &- 0x30 < 10 { i += 1 }
        return i - position
    }
}

/// Calls `body` with the UTF-8 bytes of `text`, copying only when the string
/// is not stored contiguously.
@inlinable
func _withUTF8<R>(_ text: some StringProtocol, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
    if let result = text.utf8.withContiguousStorageIfAvailable(body) {
        return result
    }
    var copy = String(text)
    return copy.withUTF8(body)
}

// MARK: - Errors

/// The error thrown when text is not a valid ISO 8601 representation of a
/// civil value.
///
/// ```swift
/// do {
///     _ = try PlainDate(parsing: "2023-02-29")
/// } catch {
///     print(error)   // Cannot parse "2023-02-29" as PlainDate: value out of range at offset 8
/// }
/// ```
public struct CivilTimeParseError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The kind of problem found.
    public let kind: Kind
    /// The text that failed to parse, shortened if it was very long.
    public let input: String
    /// The UTF-8 byte offset in `input` where the problem was found.
    public let offset: Int
    /// The name of the type that was being parsed, such as `PlainDate`.
    public let typeName: String

    @usableFromInline
    init(kind: Kind, input: some StringProtocol, offset: Int, typeName: String) {
        self.kind = kind
        self.input = input.utf8.count > 80 ? String(input.prefix(77)) + "..." : String(input)
        self.offset = offset
        self.typeName = typeName
    }

    public var description: String {
        "Cannot parse \"\(input)\" as \(typeName): \(kind) at offset \(offset)"
    }

    /// The kind of problem found while parsing.
    ///
    /// New kinds may be added in future versions, so treat the list as open.
    public struct Kind: Sendable, Hashable, CustomStringConvertible {
        @usableFromInline let _code: UInt8

        @inlinable
        init(_code: UInt8) { self._code = _code }

        /// The text does not have the expected shape, such as a missing
        /// separator or a non-digit where a digit belongs.
        public static let invalidFormat = Kind(_code: 1)
        /// The shape is right, but a value is not: month 13, February 30,
        /// minute 75, or a year beyond ±999999.
        public static let valueOutOfRange = Kind(_code: 2)
        /// The value ended before the text did.
        public static let unexpectedTrailingText = Kind(_code: 3)
        /// The text carries a UTC offset or `Z`, which a plain value cannot
        /// hold. Parse it as an instant (for example with Foundation's
        /// `ISO8601FormatStyle`) and convert it instead.
        public static let unexpectedTimeZone = Kind(_code: 4)
        /// The fraction of a second has more than nine digits.
        public static let tooManyFractionalDigits = Kind(_code: 5)

        public var description: String {
            switch _code {
            case 1: return "invalid format"
            case 2: return "value out of range"
            case 3: return "unexpected trailing text"
            case 4: return "unexpected UTC offset or time zone"
            case 5: return "more than nine fractional digits"
            default: return "unknown error"
            }
        }
    }
}

/// The result of an internal parse step.
@usableFromInline
enum _ParseResult<Value> {
    case success(Value)
    case failure(CivilTimeParseError.Kind, offset: Int)
}

/// Runs a parse step over the UTF-8 bytes of `text` and requires it to
/// consume everything.
///
/// - Parameter endsWithTime: Whether the form ends with a time of day, so
///   that leftover `Z`, `+hh:mm`, `-hh:mm` or `[zone]` text is reported as
///   ``CivilTimeParseError/Kind/unexpectedTimeZone``.
@inlinable
func _parse<Value>(
    _ text: some StringProtocol,
    as typeName: String,
    endsWithTime: Bool = false,
    _ body: (inout _Scanner) -> _ParseResult<Value>
) throws(CivilTimeParseError) -> Value {
    let result: _ParseResult<Value> = _withUTF8(text) { bytes in
        var scanner = _Scanner(bytes)
        let outcome = body(&scanner)
        if case .success = outcome, !scanner.isAtEnd {
            let next = scanner.peek()
            let looksLikeZone = next == UInt8(ascii: "Z") || next == UInt8(ascii: "z")
                || next == UInt8(ascii: "+") || next == UInt8(ascii: "-")
                || next == UInt8(ascii: "[")
            let kind: CivilTimeParseError.Kind =
                endsWithTime && looksLikeZone ? .unexpectedTimeZone : .unexpectedTrailingText
            return .failure(kind, offset: scanner.position)
        }
        return outcome
    }
    switch result {
    case .success(let value):
        return value
    case .failure(let kind, let offset):
        throw CivilTimeParseError(kind: kind, input: text, offset: offset, typeName: typeName)
    }
}
