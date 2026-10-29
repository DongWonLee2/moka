import Foundation
import MokaCore
import Testing

private let clock = MokaClock.fixed(Date(timeIntervalSince1970: 1_800_000_000))
private let title = "가짜 할 일 A"

private func draft(defaultQuantumMin: Int = 25) -> NotchTimer {
    var timer = NotchTimer.empty(draft: nil)
    _ = timer.apply(.enterTitle(title), at: clock.now(), defaultQuantumMin: defaultQuantumMin)
    return timer
}

/// 25분으로 돌다가 끝 시각에 tick을 받아 시간 끝이 된 상태. 칩은 그때의 기본값 25.
private func expired() -> NotchTimer {
    var timer = draft()
    _ = timer.apply(.start, at: clock.now(), defaultQuantumMin: 25)
    _ = timer.apply(.tick, at: clock.now().addingTimeInterval(1500), defaultQuantumMin: 25)
    return timer
}

@Test("FR-16 R-013: 시간 고르기에서 칩을 고르지 않았으면 기본값 변경이 칩에 바로 반영된다")
func defaultChangeUpdatesUnpickedDraftChip() {
    var timer = draft()
    timer.applyDefaultQuantumChange(40, isEditingCustom: false)
    #expect(timer == .empty(draft: Draft(title: title, chipMin: 40)))

    #expect(timer.apply(.start, at: clock.now(), defaultQuantumMin: 40) == .applied)
    #expect(timer.remainingSeconds(at: clock.now()) == 2400)
}

@Test("FR-16 R-013: 시간 고르기에서 칩을 직접 골랐으면 기본값을 바꿔도 칩은 그대로", arguments: [45, 25])
func defaultChangeKeepsPickedDraftChip(picked: Int) {
    var timer = draft()
    _ = timer.apply(.chooseQuantum(picked), at: clock.now(), defaultQuantumMin: 25)
    timer.applyDefaultQuantumChange(40, isEditingCustom: false)
    #expect(timer == .empty(draft: Draft(title: title, chipMin: picked, chipPicked: true)))
}

@Test("FR-16 R-013: 칩을 고른 뒤 제목을 다시 넣어도 고른 칩은 기본값 변경에 그대로")
func reenteredTitleKeepsPickedChip() {
    var timer = draft()
    _ = timer.apply(.chooseQuantum(45), at: clock.now(), defaultQuantumMin: 25)
    _ = timer.apply(.enterTitle("가짜 할 일 B"), at: clock.now(), defaultQuantumMin: 25)
    timer.applyDefaultQuantumChange(40, isEditingCustom: false)
    #expect(timer == .empty(draft: Draft(title: "가짜 할 일 B", chipMin: 45, chipPicked: true)))
}

@Test("FR-16 R-013: 직접 입력 중이면 기본값을 바꿔도 칩은 그대로")
func defaultChangeKeepsChipWhileEditingCustom() {
    var timer = draft()
    timer.applyDefaultQuantumChange(40, isEditingCustom: true)
    #expect(timer == .empty(draft: Draft(title: title, chipMin: 25)))

    var ended = expired()
    ended.applyDefaultQuantumChange(40, isEditingCustom: true)
    #expect(ended == .expired(title: title, chipMin: 25))
}

@Test("FR-16 R-013 R-010: 시간 끝에서 칩을 고르지 않았으면 기본값 변경이 칩에 반영되고 그 값으로 다시 돈다")
func defaultChangeUpdatesUnpickedExpiredChip() {
    var timer = expired()
    #expect(timer == .expired(title: title, chipMin: 25))
    timer.applyDefaultQuantumChange(40, isEditingCustom: false)
    #expect(timer == .expired(title: title, chipMin: 40))

    let restart = clock.now().addingTimeInterval(1600)
    #expect(timer.apply(.start, at: restart, defaultQuantumMin: 40) == .applied)
    #expect(timer == .running(title: title, quantumMin: 40, startedAt: restart, endsAt: restart.addingTimeInterval(2400)))
}

@Test("FR-16 R-013 R-010: 시간 끝에서 칩을 직접 골랐으면 기본값을 바꿔도 칩은 그대로")
func defaultChangeKeepsPickedExpiredChip() {
    var timer = expired()
    _ = timer.apply(.chooseQuantum(15), at: clock.now().addingTimeInterval(1600), defaultQuantumMin: 25)
    timer.applyDefaultQuantumChange(40, isEditingCustom: false)
    #expect(timer == .expired(title: title, chipMin: 15, chipPicked: true))
}

@Test("FR-16 R-013: 직접 고른 칩으로 시작해도 시간 끝 칩은 고르지 않은 기본값이라 기본값 변경을 따른다")
func expiredChipAfterPickedDraftIsUnpicked() {
    var timer = draft()
    _ = timer.apply(.chooseQuantum(45), at: clock.now(), defaultQuantumMin: 25)
    _ = timer.apply(.start, at: clock.now(), defaultQuantumMin: 25)
    _ = timer.apply(.tick, at: clock.now().addingTimeInterval(2700), defaultQuantumMin: 25)
    #expect(timer == .expired(title: title, chipMin: 25))
    timer.applyDefaultQuantumChange(40, isEditingCustom: false)
    #expect(timer == .expired(title: title, chipMin: 40))
}

@Test("FR-16 R-013: 도는 타이머와 빈 상태는 기본값 변경에 그대로", arguments: [false, true])
func defaultChangeLeavesRunningAndEmpty(isEditingCustom: Bool) {
    var timer = draft()
    _ = timer.apply(.start, at: clock.now(), defaultQuantumMin: 25)
    let started = timer
    let later = clock.now().addingTimeInterval(300)
    timer.applyDefaultQuantumChange(40, isEditingCustom: isEditingCustom)
    #expect(timer == started)
    #expect(timer.remainingSeconds(at: later) == 1200)

    var empty = NotchTimer.empty(draft: nil)
    empty.applyDefaultQuantumChange(40, isEditingCustom: isEditingCustom)
    #expect(empty == .empty(draft: nil))
}
