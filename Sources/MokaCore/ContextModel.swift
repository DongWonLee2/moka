public typealias ContextID = Int64

/// 화면 이름 "중요도": 조금/꽤/아주.
public enum ContextImpact: String, CaseIterable, Sendable { case normal, high, critical }

public struct MokaContext: Equatable, Sendable {
    public var id: ContextID
    /// 앞뒤 공백을 뺀 값, 비어 있지 않음.
    public var name: String
    public var date: LocalDay
    public var impact: ContextImpact

    public init(id: ContextID, name: String, date: LocalDay, impact: ContextImpact) {
        self.id = id
        self.name = name
        self.date = date
        self.impact = impact
    }

    /// 앞뒤 공백을 뺀 이름. 비면 nil(저장 안 함).
    public static func normalizedName(_ raw: String) -> String? {
        nonBlank(raw)
    }
}

public struct NewContext: Equatable, Sendable {
    public var name: String
    public var date: LocalDay
    public var impact: ContextImpact

    public init(name: String, date: LocalDay, impact: ContextImpact) {
        self.name = name
        self.date = date
        self.impact = impact
    }
}
