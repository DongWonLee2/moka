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
        guard let seq else { return "moka-sim: \(message)" }
        return "moka-sim: seq \(seq): \(message)"
    }
}
