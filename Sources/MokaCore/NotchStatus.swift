public enum NotchStatus {
    /// 펼친 판 오른쪽 귀에 보이는 지금 단계(시안 v3.5).
    public static func label(for timer: NotchTimer) -> String {
        switch timer {
        case .empty(nil):
            return "새 할 일"
        case .empty(.some):
            return "시간 고르기"
        case .running(_, let quantumMin, _, _):
            return "\(quantumMin)분 집중"
        case .expired:
            return "시간 끝"
        }
    }
}
