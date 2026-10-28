import Foundation

/// 숫자를 원문 토큰으로 남기는 JSON 값. `45`와 `45.0`을 구분하려고 `JSONSerialization`·`JSONDecoder`를 쓰지 않는다.
enum SimJSON {
    case object([(key: String, value: SimJSON)])
    case array([SimJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

struct SimJSONParser {
    private static let maxDepth = 64

    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ data: Data) throws(SimError) -> SimJSON {
        var parser = SimJSONParser(bytes: Array(data))
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.invalid("값 뒤에 남은 글자가 있다") }
        return value
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private func invalid(_ reason: String) -> SimError {
        SimError(kind: .invalidJSON, seq: nil, message: "JSON 파싱 실패(바이트 \(index)): \(reason)")
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func expect(_ byte: UInt8) throws(SimError) {
        guard current == byte else { throw invalid("'\(Character(Unicode.Scalar(byte)))'가 와야 한다") }
        index += 1
    }

    private mutating func parseValue(depth: Int) throws(SimError) -> SimJSON {
        guard depth < Self.maxDepth else { throw invalid("너무 깊다") }
        switch current {
        case UInt8(ascii: "{"): return try parseObject(depth: depth)
        case UInt8(ascii: "["): return try parseArray(depth: depth)
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"):
            try parseLiteral("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try parseLiteral("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try parseLiteral("null")
            return .null
        case .some(let byte) where byte == UInt8(ascii: "-") || isDigit(byte): return .number(try parseNumber())
        default: throw invalid("값이 와야 한다")
        }
    }

    private mutating func parseObject(depth: Int) throws(SimError) -> SimJSON {
        index += 1
        var members: [(key: String, value: SimJSON)] = []
        var seen: Set<String> = []
        skipWhitespace()
        if current == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard current == UInt8(ascii: "\"") else { throw invalid("키 문자열이 와야 한다") }
            let key = try parseString()
            guard seen.insert(key).inserted else {
                throw SimError(kind: .duplicateKey, seq: nil, message: "키 \(SimError.quoted(key))가 두 번 나온다")
            }
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            skipWhitespace()
            members.append((key, try parseValue(depth: depth + 1)))
            skipWhitespace()
            if current == UInt8(ascii: ",") {
                index += 1
                continue
            }
            try expect(UInt8(ascii: "}"))
            return .object(members)
        }
    }

    private mutating func parseArray(depth: Int) throws(SimError) -> SimJSON {
        index += 1
        var items: [SimJSON] = []
        skipWhitespace()
        if current == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if current == UInt8(ascii: ",") {
                index += 1
                continue
            }
            try expect(UInt8(ascii: "]"))
            return .array(items)
        }
    }

    private mutating func parseLiteral(_ word: String) throws(SimError) {
        for byte in word.utf8 {
            try expect(byte)
        }
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private mutating func digits() -> Int {
        let start = index
        while let byte = current, isDigit(byte) { index += 1 }
        return index - start
    }

    private mutating func parseNumber() throws(SimError) -> String {
        let start = index
        if current == UInt8(ascii: "-") { index += 1 }
        if current == UInt8(ascii: "0") {
            index += 1
        } else if digits() == 0 {
            throw invalid("숫자가 와야 한다")
        }
        if current == UInt8(ascii: ".") {
            index += 1
            guard digits() > 0 else { throw invalid("소수점 뒤에 숫자가 와야 한다") }
        }
        if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
            index += 1
            if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { index += 1 }
            guard digits() > 0 else { throw invalid("지수에 숫자가 와야 한다") }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func parseHex4() throws(SimError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw invalid("\\u 뒤에 16진수 4자리가 와야 한다") }
        var value: UInt32 = 0
        for byte in bytes[index..<index + 4] {
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: throw invalid("\\u 뒤에 16진수 4자리가 와야 한다")
            }
            value = value << 4 | UInt32(digit)
        }
        index += 4
        return value
    }

    private mutating func parseString() throws(SimError) -> String {
        index += 1
        var out: [UInt8] = []
        while true {
            guard let byte = current else { throw invalid("문자열이 닫히지 않았다") }
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                guard let text = String(bytes: out, encoding: .utf8) else { throw invalid("UTF-8이 아니다") }
                return text
            case UInt8(ascii: "\\"):
                guard let escape = current else { throw invalid("문자열이 닫히지 않았다") }
                index += 1
                switch escape {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(escape)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"): out.append(contentsOf: try parseUnicodeEscape())
                default: throw invalid("모르는 이스케이프")
                }
            case 0x00..<0x20:
                throw invalid("문자열 안에 제어 문자가 있다")
            default:
                out.append(byte)
            }
        }
    }

    private mutating func parseUnicodeEscape() throws(SimError) -> [UInt8] {
        var code = try parseHex4()
        if (0xD800..<0xDC00).contains(code) {
            guard current == UInt8(ascii: "\\") else { throw invalid("짝 없는 서로게이트") }
            index += 1
            try expect(UInt8(ascii: "u"))
            let low = try parseHex4()
            guard (0xDC00..<0xE000).contains(low) else { throw invalid("짝 없는 서로게이트") }
            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
        }
        guard let scalar = Unicode.Scalar(code) else { throw invalid("잘못된 유니코드 코드 포인트") }
        return Array(String(Character(scalar)).utf8)
    }
}
