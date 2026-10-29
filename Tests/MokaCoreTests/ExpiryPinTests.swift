import Foundation
import MokaCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let title = "가짜 할 일 B"

private func running25() -> NotchTimer {
    .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(25 * 60))
}

/// 주입한 시각으로 이벤트를 적용하고 고정 여부를 다시 계산한다(AppState와 같은 순서).
private func step(
    _ timer: inout NotchTimer, pinned: Bool, _ event: TimerEvent, at now: Date, defaultQuantumMin: Int = 25
) -> Bool {
    let before = timer
    let result = timer.apply(event, at: now, defaultQuantumMin: defaultQuantumMin)
    return pinnedOpenAfter(event, result: result, from: before, to: timer, wasPinned: pinned)
}

@Test("FR-06 R-008 R-009: 끝 시각을 지난 tick으로 running → expired가 되면 고정한다")
func expiryByTickPinsOpen() {
    var timer = running25()
    #expect(step(&timer, pinned: false, .tick, at: t0.addingTimeInterval(24 * 60)) == false)
    #expect(step(&timer, pinned: false, .tick, at: t0.addingTimeInterval(25 * 60)))
    #expect(timer == .expired(title: title, chipMin: 25))
}

@Test("FR-06 R-008: 잠자는 동안 끝 시각이 지나면 깨어난 뒤 첫 tick에 고정한다")
func expiryAfterSleepPinsOpen() {
    var timer = running25()
    #expect(step(&timer, pinned: false, .tick, at: t0.addingTimeInterval(3 * 3600)))
}

@Test("FR-06 R-009: 시간 끝 동안 tick·칩 고르기·거부된 이벤트는 고정을 풀지 않는다")
func pinSurvivesNonReleasingEvents() {
    var timer = NotchTimer.expired(title: title, chipMin: 25)
    let now = t0.addingTimeInterval(30 * 60)
    #expect(step(&timer, pinned: true, .tick, at: now))
    #expect(step(&timer, pinned: true, .chooseQuantum(45), at: now))
    #expect(step(&timer, pinned: true, .chooseQuantum(181), at: now))
    #expect(step(&timer, pinned: true, .enterTitle("다른 일"), at: now))
    #expect(timer == .expired(title: title, chipMin: 45, chipPicked: true))
}

@Test("FR-05 FR-06 R-009 R-010: 시간 끝에서 시작하면 같은 할 일로 다시 돌고 고정이 풀린다")
func startFromExpiredReleasesPin() {
    var timer = NotchTimer.expired(title: title, chipMin: 15)
    let now = t0.addingTimeInterval(30 * 60)
    #expect(step(&timer, pinned: true, .start, at: now) == false)
    #expect(timer == .running(title: title, quantumMin: 15, startedAt: now, endsAt: now.addingTimeInterval(15 * 60)))
}

@Test("FR-06 R-007 R-009: 시간 끝에서 완료하면 빈 상태가 되고 고정이 풀린다")
func completeFromExpiredReleasesPin() {
    var timer = NotchTimer.expired(title: title, chipMin: 25)
    #expect(step(&timer, pinned: true, .complete, at: t0) == false)
    #expect(timer == .empty(draft: nil))
}

@Test("FR-06 R-009: 끝 시각을 지나 바로 완료가 오면(암묵 tick) 고정하지 않고 빈 상태가 된다")
func completeRightAfterEndDoesNotPin() {
    var timer = running25()
    #expect(step(&timer, pinned: false, .complete, at: t0.addingTimeInterval(26 * 60)) == false)
    #expect(timer == .empty(draft: nil))
}

@Test("FR-06 R-009: 시간 끝이 아닌 전이는 고정하지 않는다")
func ordinaryTransitionsDoNotPin() {
    var timer = NotchTimer.empty(draft: nil)
    #expect(step(&timer, pinned: false, .enterTitle(title), at: t0) == false)
    #expect(step(&timer, pinned: false, .chooseQuantum(45), at: t0) == false)
    #expect(step(&timer, pinned: false, .start, at: t0) == false)
    #expect(step(&timer, pinned: false, .tick, at: t0.addingTimeInterval(60)) == false)
    #expect(step(&timer, pinned: false, .complete, at: t0.addingTimeInterval(120)) == false)
}

@Test("FR-05 R-003 R-004: 직접 입력을 쓰지 않으면 칩 값으로 시작할 수 있다")
func startAllowedWithoutCustom() {
    #expect(QuantumChip.startAllowed(customText: nil))
}

@Test("FR-05 R-004: 직접 입력 중에는 1~180 정수일 때만 시작할 수 있다", arguments: ["1", "30", "180"])
func startAllowedWithValidCustom(text: String) {
    #expect(QuantumChip.startAllowed(customText: text))
}

@Test("FR-05 R-004: 직접 입력이 0, 181, 빈 값, 소수, 숫자 아님이면 시작을 막는다", arguments: ["0", "181", "", "4.5", "abc"])
func startBlockedWithInvalidCustom(text: String) {
    #expect(QuantumChip.startAllowed(customText: text) == false)
}
