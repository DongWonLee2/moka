import Foundation
import MokaCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let title = "가짜 할 일 A"

private func running(quantumMin: Int = 25, startedAt: Date = t0) -> NotchTimer {
    .running(
        title: title, quantumMin: quantumMin, startedAt: startedAt,
        endsAt: startedAt.addingTimeInterval(TimeInterval(quantumMin * 60)))
}

@Test("FR-05 R-003: 빈 상태에서 제목을 넣으면 칩이 기본값으로 채워진다")
func enterTitleFromEmptyFillsDefaultChip() {
    var timer = NotchTimer.empty(draft: nil)
    let result = timer.apply(.enterTitle("  \(title)  "), at: t0, defaultQuantumMin: 45)
    #expect(result == .applied)
    #expect(timer == .empty(draft: Draft(title: title, chipMin: 45)))
}

@Test("FR-06 R-002: 앞뒤 공백을 뺀 제목이 비면 rejected", arguments: ["", "   ", "\n\t "])
func blankTitleIsRejected(text: String) {
    for initial in [NotchTimer.empty(draft: nil), .empty(draft: Draft(title: title, chipMin: 25))] {
        var timer = initial
        let result = timer.apply(.enterTitle(text), at: t0, defaultQuantumMin: 25)
        #expect(result == .rejected(.emptyTitle))
        #expect(timer == initial)
    }
}

@Test("FR-06 R-005: 빈 상태에서 tick은 변화 없음")
func tickInEmptyChangesNothing() {
    for initial in [NotchTimer.empty(draft: nil), .empty(draft: Draft(title: title, chipMin: 25))] {
        var timer = initial
        #expect(timer.apply(.tick, at: t0, defaultQuantumMin: 25) == .applied)
        #expect(timer == initial)
    }
}

struct RejectedCell: CustomTestStringConvertible, Sendable {
    let name: String
    let initial: NotchTimer
    let event: TimerEvent
    var testDescription: String { name }
}

let rejectedCells: [RejectedCell] = [
    RejectedCell(name: "empty(nil) + chooseQuantum", initial: .empty(draft: nil), event: .chooseQuantum(45)),
    RejectedCell(name: "empty(nil) + start", initial: .empty(draft: nil), event: .start),
    RejectedCell(name: "empty(nil) + complete", initial: .empty(draft: nil), event: .complete),
    RejectedCell(
        name: "empty(draft) + complete", initial: .empty(draft: Draft(title: title, chipMin: 25)), event: .complete),
    RejectedCell(name: "running + enterTitle", initial: running(), event: .enterTitle("가짜 할 일 B")),
    RejectedCell(name: "running + chooseQuantum", initial: running(), event: .chooseQuantum(45)),
    RejectedCell(name: "running + start", initial: running(), event: .start),
    RejectedCell(
        name: "expired + enterTitle", initial: .expired(title: title, chipMin: 25), event: .enterTitle("가짜 할 일 B")),
]

@Test("FR-06 R-005: 단계에 맞지 않는 이벤트는 rejected이고 상태를 바꾸지 않는다", arguments: rejectedCells)
func eventNotAllowedInPhaseIsRejected(cell: RejectedCell) {
    var timer = cell.initial
    let result = timer.apply(cell.event, at: t0.addingTimeInterval(60), defaultQuantumMin: 25)
    #expect(result == .rejected(.notAllowedInPhase))
    #expect(timer == cell.initial)
}

@Test("FR-06 R-002: 초안에서 제목을 다시 넣으면 제목만 바뀌고 칩은 그대로")
func enterTitleInDraftKeepsChip() {
    var timer = NotchTimer.empty(draft: Draft(title: title, chipMin: 45))
    #expect(timer.apply(.enterTitle("가짜 할 일 B"), at: t0, defaultQuantumMin: 25) == .applied)
    #expect(timer == .empty(draft: Draft(title: "가짜 할 일 B", chipMin: 45)))
}

@Test("FR-05 R-004: 초안에서 칩을 고르면 칩 값이 바뀐다", arguments: [1, 15, 60, 180])
func chooseQuantumInDraft(minutes: Int) {
    var timer = NotchTimer.empty(draft: Draft(title: title, chipMin: 25))
    #expect(timer.apply(.chooseQuantum(minutes), at: t0, defaultQuantumMin: 25) == .applied)
    #expect(timer == .empty(draft: Draft(title: title, chipMin: minutes)))
}

@Test("FR-05 R-004: 1~180 밖의 칩 값은 rejected", arguments: [0, -1, 181, 1000])
func chooseQuantumOutOfRangeIsRejected(minutes: Int) {
    for initial in [NotchTimer.empty(draft: Draft(title: title, chipMin: 25)), .expired(title: title, chipMin: 25)] {
        var timer = initial
        #expect(timer.apply(.chooseQuantum(minutes), at: t0, defaultQuantumMin: 25) == .rejected(.quantumOutOfRange))
        #expect(timer == initial)
    }
}

@Test("FR-06 R-005: 초안에서 시작하면 칩 시간만큼 돌고 끝 시각은 시작 + 칩·60초")
func startFromDraft() {
    var timer = NotchTimer.empty(draft: Draft(title: title, chipMin: 25))
    #expect(timer.apply(.start, at: t0, defaultQuantumMin: 45) == .applied)
    #expect(timer == .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(1500)))
    #expect(timer.remainingSeconds(at: t0) == 1500)
}

@Test("FR-06 R-005: 남은 초는 끝 시각 − 현재 시각을 올림한 값이고 도는 동안 1 이상")
func remainingSecondsIsCeilOfTimeToEnd() {
    let timer = running()
    #expect(timer.remainingSeconds(at: t0.addingTimeInterval(0.4)) == 1500)
    #expect(timer.remainingSeconds(at: t0.addingTimeInterval(1)) == 1499)
    #expect(timer.remainingSeconds(at: t0.addingTimeInterval(1499.999)) == 1)
}

@Test("FR-06 R-005: 시계를 되돌려도 남은 초는 고른 작업 시간을 넘지 않는다")
func clockRollbackIsClamped() {
    var timer = running()
    #expect(timer.remainingSeconds(at: t0.addingTimeInterval(-3600)) == 1500)
    #expect(timer.apply(.tick, at: t0.addingTimeInterval(-3600), defaultQuantumMin: 25) == .applied)
    #expect(timer == running())
}

@Test("FR-06 R-005: 잠자기로 줄어든 시간은 남은 초에 그대로 반영된다")
func sleepIsReflected() {
    var timer = running()
    #expect(timer.apply(.tick, at: t0.addingTimeInterval(600), defaultQuantumMin: 25) == .applied)
    #expect(timer.remainingSeconds(at: t0.addingTimeInterval(600)) == 900)
}

@Test("FR-06 R-008: 끝 시각 이후 tick이면 시간 끝, 칩은 그 순간의 기본값, 남은 초 0", arguments: [0.0, 1, 3600])
func tickAfterEndExpires(overrun: TimeInterval) {
    var timer = running()
    let now = t0.addingTimeInterval(1500 + overrun)
    #expect(timer.apply(.tick, at: now, defaultQuantumMin: 45) == .applied)
    #expect(timer == .expired(title: title, chipMin: 45))
    #expect(timer.remainingSeconds(at: now) == 0)
}

@Test("FR-06 R-007: 도는 중 완료하면 빈 상태로 돌아간다")
func completeWhileRunning() {
    var timer = running()
    #expect(timer.apply(.complete, at: t0.addingTimeInterval(60), defaultQuantumMin: 25) == .applied)
    #expect(timer == .empty(draft: nil))
    #expect(timer.remainingSeconds(at: t0) == nil)
}

@Test("FR-06 R-008: 끝 시각 이후 complete는 암묵 tick 뒤 처리되어 빈 상태가 된다")
func implicitTickBeforeComplete() {
    var timer = running()
    #expect(timer.apply(.complete, at: t0.addingTimeInterval(2000), defaultQuantumMin: 25) == .applied)
    #expect(timer == .empty(draft: nil))
}

@Test("FR-05 R-010: 끝 시각 이후 chooseQuantum은 암묵 tick 뒤 시간 끝 칩을 바꾼다")
func implicitTickBeforeChooseQuantum() {
    var timer = running()
    #expect(timer.apply(.chooseQuantum(15), at: t0.addingTimeInterval(1500), defaultQuantumMin: 25) == .applied)
    #expect(timer == .expired(title: title, chipMin: 15))
}

@Test("FR-06 R-008: 끝 시각 이후 rejected 이벤트에도 암묵 tick은 남는다")
func implicitTickStaysWhenEventRejected() {
    var timer = running()
    #expect(
        timer.apply(.enterTitle("가짜 할 일 B"), at: t0.addingTimeInterval(1600), defaultQuantumMin: 25)
            == .rejected(.notAllowedInPhase))
    #expect(timer == .expired(title: title, chipMin: 25))
}

@Test("FR-06 R-008: 시간 끝에서 tick은 변화 없음")
func tickInExpiredChangesNothing() {
    var timer = NotchTimer.expired(title: title, chipMin: 25)
    #expect(timer.apply(.tick, at: t0, defaultQuantumMin: 45) == .applied)
    #expect(timer == .expired(title: title, chipMin: 25))
    #expect(timer.remainingSeconds(at: t0) == 0)
}

@Test("FR-05 R-010: 시간 끝에서 45분을 고르고 시작하면 같은 제목으로 다시 돈다")
func restartFromExpired() {
    var timer = NotchTimer.expired(title: title, chipMin: 25)
    let t1 = t0.addingTimeInterval(5000)
    #expect(timer.apply(.chooseQuantum(45), at: t1, defaultQuantumMin: 25) == .applied)
    #expect(timer.apply(.start, at: t1, defaultQuantumMin: 25) == .applied)
    #expect(timer == .running(title: title, quantumMin: 45, startedAt: t1, endsAt: t1.addingTimeInterval(2700)))
}

@Test("FR-05 R-010: 시간 끝에서 칩을 바꾸지 않고 시작하면 채워진 칩으로 다시 돈다")
func restartFromExpiredWithFilledChip() {
    var timer = NotchTimer.expired(title: title, chipMin: 45)
    #expect(timer.apply(.start, at: t0, defaultQuantumMin: 25) == .applied)
    #expect(timer == .running(title: title, quantumMin: 45, startedAt: t0, endsAt: t0.addingTimeInterval(2700)))
}

@Test("FR-05 R-010: 끝 시각 이후 start는 암묵 tick 뒤 기본값 칩으로 다시 돈다")
func implicitTickBeforeStart() {
    var timer = running()
    let t1 = t0.addingTimeInterval(1800)
    #expect(timer.apply(.start, at: t1, defaultQuantumMin: 15) == .applied)
    #expect(timer == .running(title: title, quantumMin: 15, startedAt: t1, endsAt: t1.addingTimeInterval(900)))
}

@Test("FR-06 R-007: 시간 끝에서 완료하면 빈 상태로 돌아간다")
func completeWhenExpired() {
    var timer = NotchTimer.expired(title: title, chipMin: 25)
    #expect(timer.apply(.complete, at: t0, defaultQuantumMin: 25) == .applied)
    #expect(timer == .empty(draft: nil))
}

@Test("FR-06 R-005: 정상 값은 불변식 위반이 없다")
func validStatesHaveNoViolation() {
    let states: [NotchTimer] = [
        .empty(draft: nil),
        .empty(draft: Draft(title: title, chipMin: 1)),
        running(quantumMin: 180),
        .expired(title: title, chipMin: 180),
    ]
    for state in states {
        #expect(state.invariantViolation(at: t0) == nil)
    }
}

@Test("FR-06 R-005: 깨진 값은 불변식 위반을 돌려준다")
func brokenStatesHaveViolation() {
    let states: [NotchTimer] = [
        .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0),
        .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(-1)),
        .running(title: title, quantumMin: 0, startedAt: t0, endsAt: t0.addingTimeInterval(60)),
        .running(title: title, quantumMin: 181, startedAt: t0, endsAt: t0.addingTimeInterval(60)),
        .empty(draft: Draft(title: title, chipMin: 0)),
        .expired(title: title, chipMin: 181),
        .empty(draft: Draft(title: "  ", chipMin: 25)),
        .running(title: " ", quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(1500)),
        .expired(title: "", chipMin: 25),
    ]
    for state in states {
        #expect(state.invariantViolation(at: t0) != nil)
    }
}

@Test("FR-06 R-005: 끝 시각이 지난 running은 남은 초가 1 미만이라 불변식 위반", arguments: [0.0, 0.5, 600])
func runningPastEndViolatesInvariant(overrun: TimeInterval) {
    let timer = running()
    #expect(timer.invariantViolation(at: t0.addingTimeInterval(1500 + overrun)) != nil)
    #expect(timer.invariantViolation(at: t0.addingTimeInterval(1499.5)) == nil)
}

@Test("FR-06 R-005: MokaClock.fixed는 주입한 시각을 돌려준다")
func fixedClockReturnsInjectedDate() {
    #expect(MokaClock.fixed(t0).now() == t0)
}
