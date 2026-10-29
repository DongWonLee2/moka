import Foundation
import MokaCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test(
    "FR-06 R-001 R-006: 펼친 판 오른쪽 귀 상태 글자는 단계마다 정해진다",
    arguments: [
        (NotchTimer.empty(draft: nil), "새 할 일"),
        (.empty(draft: Draft(title: "가짜 할 일", chipMin: 25)), "시간 고르기"),
        (.running(title: "가짜 할 일", quantumMin: 25, startedAt: t0, endsAt: t0 + 1500), "25분 집중"),
        (.running(title: "가짜 할 일", quantumMin: 90, startedAt: t0, endsAt: t0 + 5400), "90분 집중"),
        (.expired(title: "가짜 할 일", chipMin: 25), "시간 끝"),
    ])
func statusLabel(timer: NotchTimer, expected: String) {
    #expect(NotchStatus.label(for: timer) == expected)
}
