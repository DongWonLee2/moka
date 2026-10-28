public enum SimErrorKind: Equatable, Sendable {
    case usage
    case fileUnreadable
    case invalidJSON
    case duplicateKey
    case unknownVersion
    case unknownKey
    case missingField
    case wrongType
    case outOfRange
    case unknownType
    case invalidTimestamp
    case fractionalSeconds
    case timeReversed
    case unknownTimezone
    case emptyTitle
    case notAllowedInPhase
    case invariantViolation
}

public struct SimError: Error, Equatable, Sendable, CustomStringConvertible {
    public var kind: SimErrorKind
    /// 실행 중(이벤트 단위) 오류면 그 이벤트의 seq.
    public var seq: Int?
    public var message: String

    public init(kind: SimErrorKind, seq: Int?, message: String) {
        self.kind = kind
        self.seq = seq
        self.message = message
    }

    public var description: String {
        let line = Self.escapingLineBreaks(message)
        guard let seq else { return "moka-sim: \(line)" }
        return "moka-sim: seq \(seq): \(line)"
    }

    static let quotedLimit = 64

    /// 오류 설명에 넣는 입력 문자열을 따옴표로 감싼다. `quotedLimit`자에서 자르고 줄을 바꾸는 문자를 이스케이프한다.
    static func quoted(_ input: String) -> String {
        let cut = input.count > quotedLimit ? String(input.prefix(quotedLimit)) + "…" : input
        return "\"\(escapingLineBreaks(cut))\""
    }

    /// 제어 문자(U+0000~U+001F, U+007F~U+009F)와 U+2028, U+2029를 `\n`, `\r`, `\t`, `\u{..}`로 바꾼다.
    static func escapingLineBreaks(_ text: String) -> String {
        var line = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A: line += "\\n"
            case 0x0D: line += "\\r"
            case 0x09: line += "\\t"
            case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029: line += "\\u{\(String(scalar.value, radix: 16))}"
            default: line.unicodeScalars.append(scalar)
            }
        }
        return line
    }
}
