import Foundation
import MokaCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let title = "가짜 할 일 A"

struct BrokenState: CustomTestStringConvertible, Sendable {
    let name: String
    let timer: NotchTimer
    var testDescription: String { name }
}

let brokenStates: [BrokenState] = [
    BrokenState(
        name: "running, 끝 시각 = 시작 시각",
        timer: .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0)),
    BrokenState(
        name: "running, 끝 시각이 지남(남은 초 0)",
        timer: .running(title: title, quantumMin: 25, startedAt: t0.addingTimeInterval(-1500), endsAt: t0)),
    BrokenState(
        name: "running, 작업 시간 181",
        timer: .running(title: title, quantumMin: 181, startedAt: t0, endsAt: t0.addingTimeInterval(181 * 60))),
    BrokenState(name: "expired, 칩 0", timer: .expired(title: title, chipMin: 0)),
    BrokenState(name: "empty 초안, 칩 181", timer: .empty(draft: Draft(title: title, chipMin: 181))),
]

@Test("ADR-0003 R-015: 깨진 상태의 불변식 위반은 종료 코드 1", arguments: brokenStates)
func brokenStateMapsToExitCode1(state: BrokenState) throws {
    let error = try #require(SimRunner.checkInvariant(state.timer, at: t0, seq: 3))
    #expect(error.kind == .invariantViolation)
    #expect(error.seq == 3)
    #expect(SimExitCode.code(for: .failure(error)) == 1)
}

@Test("ADR-0003 R-015: 정상 상태는 불변식 위반이 아니다")
func validStatesPassInvariant() {
    let valid: [NotchTimer] = [
        .empty(draft: nil),
        .empty(draft: Draft(title: title, chipMin: 25)),
        .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(1500)),
        .expired(title: title, chipMin: 25),
    ]
    for timer in valid {
        #expect(SimRunner.checkInvariant(timer, at: t0, seq: 1) == nil)
    }
}

@Test("ADR-0003 R-015: 종료 코드 매핑 — 성공 0, 입력 오류 2")
func exitCodeMapping() {
    #expect(SimExitCode.code(for: .success("")) == 0)
    for kind in [SimErrorKind.usage, .invalidJSON, .unknownKey, .timeReversed, .notAllowedInPhase, .emptyTitle] {
        #expect(SimExitCode.code(for: .failure(SimError(kind: kind, seq: nil, message: "가짜"))) == 2)
    }
}
