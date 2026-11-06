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

/// 설정 창 일정 탭·시트의 글자(R-115, 시안 10번). 값을 끼우거나 분기하는 글자라 MokaCore가 정한다(#42).
public enum ContextText {
    public static func rowDate(_ day: LocalDay) -> String {
        "\(day.month)월 \(day.day)일"
    }

    public static func formDate(_ day: LocalDay) -> String {
        "\(day.year)년 \(day.month)월 \(day.day)일"
    }

    public static func impact(_ impact: ContextImpact) -> String {
        switch impact {
        case .normal: "조금"
        case .high: "꽤"
        case .critical: "아주"
        }
    }
}
