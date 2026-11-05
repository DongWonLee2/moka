import Foundation
import MokaCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test(
    "FR-06 R-001 R-006: 펼친 판 오른쪽 귀 상태 글자는 단계마다 정해진다",
    arguments: [
        (NotchTimer.empty(draft: nil), "새 할 일"),
        (.empty(draft: Draft(title: "가짜 할 일", chipMin: 25)), "시작 전"),
        (.running(title: "가짜 할 일", quantumMin: 25, startedAt: t0, endsAt: t0 + 1500), "25분 타이머"),
        (.running(title: "가짜 할 일", quantumMin: 90, startedAt: t0, endsAt: t0 + 5400), "90분 타이머"),
        (.expired(title: "가짜 할 일", chipMin: 25), "시간 끝"),
    ])
func statusLabel(timer: NotchTimer, expected: String) {
    #expect(NotchStatus.label(for: timer) == expected)
}

private let runningTimer = NotchTimer.running(title: "가짜 할 일", quantumMin: 25, startedAt: t0, endsAt: t0 + 1500)

@Test(
    "FR-07 R-106: 두 줄 입력 중이 아니면(pending nil) 상태 글자는 지금 그대로",
    arguments: [
        (NotchTimer.empty(draft: nil), "새 할 일"),
        (.empty(draft: Draft(title: "가짜 할 일", chipMin: 25)), "시작 전"),
        (runningTimer, "25분 타이머"),
        (.expired(title: "가짜 할 일", chipMin: 25), "시간 끝"),
    ])
func statusLabelWithoutPending(timer: NotchTimer, expected: String) {
    #expect(NotchStatus.label(for: timer, pending: nil) == expected)
    #expect(NotchStatus.label(for: timer, pending: nil) == NotchStatus.label(for: timer))
}

@Test(
    "FR-07 R-106: 도는 중 바꾸기·미루기 두 줄 입력이면 바꾸는 중·미루는 중",
    arguments: [(PendingAction.switch, "바꾸는 중"), (.skip, "미루는 중")])
func statusLabelWhilePending(pending: PendingAction, expected: String) {
    #expect(NotchStatus.label(for: runningTimer, pending: pending) == expected)
}

@Test(
    "FR-07 R-106: 두 줄 입력 제목 줄 오른쪽은 지금까지의 경과 분",
    arguments: [(0, "0분 했어요"), (18, "18분 했어요"), (180, "180분 했어요")])
func elapsedText(minutes: Int, expected: String) {
    #expect(NotchStatus.elapsed(minutes: minutes) == expected)
}
