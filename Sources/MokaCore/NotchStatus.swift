/// 두 줄 입력 중인 동작(data-model §2). 앱 `AppState.pendingAction`의 타입이고 저장하지 않는다.
public enum PendingAction: Sendable { case skip, `switch` }

/// 화면 문구 원칙(#42): 입력·상태에 따라 분기하거나 값을 끼워 넣는 글자(상태 글자, 오류 안내, "N분 더", 조사 받침)는
/// MokaCore가 정하고 MokaCore 시험이 확인한다. 앱은 받은 글자를 그대로 그린다. 분기 없는 고정 라벨(시작·완료·다음,
/// 단위 "분", 고정 안내)은 뷰에 둔다.
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

    public static func elapsed(minutes: Int) -> String {
        "\(minutes)분 했어요"
    }
}
