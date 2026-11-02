/// 두 줄 입력 중인 동작(data-model §2). 앱 `AppState.pendingAction`의 타입이고 저장하지 않는다.
public enum PendingAction: Sendable { case skip, `switch` }

/// 화면 문구 원칙(#42): 상태에서 고르거나 값을 끼워 넣는 화면 문구는 MokaCore가 정하고 MokaCore 시험이 글자를 확인한다.
/// 앱은 받은 글자를 그대로 그린다.
public enum NotchStatus {
    /// 펼친 판 오른쪽 귀에 보이는 지금 단계(시안 v3.5). 도는 중 두 줄 입력이면 그 동작(시안 v2 4번).
    public static func label(for timer: NotchTimer, pending: PendingAction? = nil) -> String {
        switch timer {
        case .empty(nil):
            return "새 할 일"
        case .empty(.some):
            return "시작 전"
        case .running(_, let quantumMin, _, _):
            switch pending {
            case .switch: return "바꾸는 중"
            case .skip: return "미루는 중"
            case nil: return "\(quantumMin)분 타이머"
            }
        case .expired:
            return "시간 끝"
        }
    }
}
