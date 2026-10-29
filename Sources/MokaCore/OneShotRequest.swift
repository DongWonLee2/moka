/// 한 번만 소비되는 요청. 사용자의 명시적 동작(예: "직접…" 클릭)으로만 포커스를 주고,
/// 뷰가 다시 만들어질 때(마우스로 다시 펼침)는 포커스를 가져가지 않게 한다(R-002, SC-003).
public struct OneShotRequest: Equatable, Sendable {
    private var pending = false

    public init() {}

    public mutating func request() {
        pending = true
    }

    public mutating func cancel() {
        pending = false
    }

    /// 걸린 요청이 있으면 true를 돌려주고 비운다.
    public mutating func take() -> Bool {
        defer { pending = false }
        return pending
    }
}
