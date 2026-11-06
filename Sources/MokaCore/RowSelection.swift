/// 설정 창 목록의 체크 고르기 규칙(R-122). 판정과 토글은 지금 보이는 줄만 본다.
public enum RowSelection {
    public enum State: Equatable, Sendable { case none, some, all }

    public static func state<ID: Hashable>(checked: Set<ID>, visible: [ID]) -> State {
        let count = visible.filter(checked.contains).count
        if count == 0 { return .none }
        return count == visible.count ? .all : .some
    }

    /// 보이는 줄을 다 골랐으면 보이는 것만 풀고, 아니면 보이는 것을 모두 고른다. 숨은 줄의 체크는 그대로 둔다.
    public static func toggledAll<ID: Hashable>(checked: Set<ID>, visible: [ID]) -> Set<ID> {
        state(checked: checked, visible: visible) == .all
            ? checked.subtracting(visible) : checked.union(visible)
    }

    /// 보이는 줄 가운데 완료한 것만.
    public static func doneOnly<ID: Hashable>(_ rows: [(id: ID, isDone: Bool)]) -> Set<ID> {
        Set(rows.filter(\.isDone).map(\.id))
    }
}
