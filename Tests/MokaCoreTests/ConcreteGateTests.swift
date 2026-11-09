import Foundation
import MokaCore
import Testing

private let questions = try! QuestionSet.bundled()
private let oldHash = "00000000000000aa"
private let newHash = "00000000000000bb"
private let newerHash = "00000000000000cc"

private func judged(concrete: Double, hash: String) -> TaskScore {
    TaskScore(
        taskID: 1, questionVersion: "v1", provider: "fake", modelSnapshot: "jev-1.13.0", urgency: 0.5, impact: 0.5,
        concrete: concrete, avoiding: 0.3, probsJSON: "{}", stateHash: hash, scoredAt: Fake.noon)
}

private func facts(
    isDraft: Bool = true, canQuery: Bool = true, score: TaskScore? = judged(concrete: 0.3, hash: oldHash),
    currentHash: String = oldHash, failedHash: String? = nil, threshold: Double = 0.5,
    record: GateRecord = GateRecord(), waiting: Bool = false
) -> ConcreteGate.Facts {
    ConcreteGate.Facts(
        isDraft: isDraft, canQuery: canQuery, score: score, currentHash: currentHash, failedHash: failedHash,
        threshold: threshold, record: record, waiting: waiting)
}

/// 제출한 뒤 판정을 기다리는 중. 첫 행동이 바뀌어 해시가 `newHash`가 되었다.
private func afterSubmit(
    submissions: Int = 1, canQuery: Bool = true, score: TaskScore? = judged(concrete: 0.3, hash: oldHash),
    currentHash: String = newHash, failedHash: String? = nil
) -> ConcreteGate.Facts {
    facts(
        canQuery: canQuery, score: score, currentHash: currentHash, failedHash: failedHash,
        record: GateRecord(submissions: submissions, passed: false), waiting: true)
}

@Suite struct ConcreteGateValueTests {
    @Test("FR-13 R-309: 제출 상한은 Defaults에 3으로 둔다")
    func maxSubmissions() {
        #expect(Defaults.concreteGateMaxSubmissions == 3)
    }

    @Test("FR-13 R-306: 임계값은 질문 파일의 그 모델 concrete 값이다")
    func threshold() throws {
        #expect(ConcreteGate.threshold(questions) == 0.5)
        let edited = try QuestionSet(
            json: questionsJSON { root in
                root["thresholds"] = [
                    "jev-1.13.0": ["concrete": 0.65, "avoiding": 0.7],
                    "other-model": ["concrete": 0.1, "avoiding": 0.2],
                ]
            })
        #expect(ConcreteGate.threshold(edited) == 0.65)
    }

    @Test("FR-13 R-309: 새 기록은 제출 0번이고 통과하지 않았다")
    func newRecord() {
        #expect(GateRecord() == GateRecord(submissions: 0, passed: false))
    }
}

@Suite struct ConcreteGateOpenTests {
    @Test("FR-13 R-306: 시작 전이고 물을 수 있고 concrete가 임계값 미만이면 연다")
    func opens() {
        #expect(ConcreteGate.phase(facts()) == .asking)
        #expect(ConcreteGate.phase(facts(score: judged(concrete: 0.49, hash: oldHash))) == .asking)
    }

    @Test(
        "FR-13 R-306: 시작 전 아님, 통과함, 판단 결과 없음, 임계값 이상이면 열지 않는다",
        arguments: ["시작 전 아님", "통과함", "판단 결과 없음", "임계값과 같음", "임계값 초과"])
    func staysClosed(caseName: String) {
        let input: ConcreteGate.Facts
        switch caseName {
        case "시작 전 아님": input = facts(isDraft: false)
        case "통과함": input = facts(record: GateRecord(submissions: 0, passed: true))
        case "판단 결과 없음": input = facts(score: nil)
        case "임계값과 같음": input = facts(score: judged(concrete: 0.5, hash: oldHash))
        default: input = facts(score: judged(concrete: 0.8, hash: oldHash))
        }
        #expect(ConcreteGate.phase(input) == .closed)
        #expect(ConcreteGate.afterAnswer(input) == input.record)
    }

    @Test("FR-13 R-306: 물을 수 없으면 열지 않고 통과로 적지도 않는다")
    func cannotQuery() {
        let input = facts(canQuery: false)
        #expect(ConcreteGate.phase(input) == .closed)
        #expect(ConcreteGate.afterAnswer(input) == GateRecord())
    }

    @Test("FR-13 R-306: 임계값은 넘긴 값으로 비교한다")
    func usesGivenThreshold() {
        #expect(ConcreteGate.phase(facts(score: judged(concrete: 0.6, hash: oldHash), threshold: 0.7)) == .asking)
        #expect(ConcreteGate.phase(facts(score: judged(concrete: 0.3, hash: oldHash), threshold: 0.2)) == .closed)
    }

    @Test("FR-13 R-306: 기다리는 중이어도 시작 전이 아니면 닫고 통과로 적지 않는다")
    func waitingButNotDraft() {
        var input = afterSubmit(score: judged(concrete: 0.9, hash: newHash))
        input.isDraft = false
        #expect(ConcreteGate.phase(input) == .closed)
        #expect(ConcreteGate.afterAnswer(input).passed == false)
    }
}

@Suite struct ConcreteGateWaitingTests {
    @Test("FR-13 R-309 SC-305: 기다리는 중 물을 수 없게 되면(401, 키 지움) 그 제출에서 통과다")
    func lostQuery() {
        let input = afterSubmit(canQuery: false)
        #expect(ConcreteGate.phase(input) == .closed)
        #expect(ConcreteGate.afterAnswer(input) == GateRecord(submissions: 1, passed: true))
    }

    @Test("FR-13 R-309 SC-305: 지금 해시로 보낸 질의가 실패로 적히면 통과다")
    func failedHash() {
        let input = afterSubmit(failedHash: newHash)
        #expect(ConcreteGate.phase(input) == .closed)
        #expect(ConcreteGate.afterAnswer(input) == GateRecord(submissions: 1, passed: true))
    }

    @Test("FR-13 R-308: 이전 해시의 실패 기록으로는 통과하지 않고 계속 기다린다")
    func oldFailedHash() {
        let input = afterSubmit(failedHash: oldHash)
        #expect(ConcreteGate.phase(input) == .checking)
        #expect(ConcreteGate.afterAnswer(input) == input.record)
    }

    @Test("FR-13 R-308: 지금 해시와 같은 새 판단 결과가 임계값 이상이면 통과다")
    func passesOnNewScore() {
        for concrete in [0.5, 0.8] {
            let input = afterSubmit(score: judged(concrete: concrete, hash: newHash))
            #expect(ConcreteGate.phase(input) == .closed)
            #expect(ConcreteGate.afterAnswer(input) == GateRecord(submissions: 1, passed: true))
        }
    }

    @Test("FR-13 R-308: 지금 해시와 같은 새 판단 결과가 임계값 미만이면 다시 묻는다(통과 아님)")
    func asksAgain() {
        for submissions in [1, 2] {
            let input = afterSubmit(submissions: submissions, score: judged(concrete: 0.3, hash: newHash))
            #expect(ConcreteGate.phase(input) == .asking)
            #expect(ConcreteGate.afterAnswer(input) == GateRecord(submissions: submissions, passed: false))
        }
    }

    @Test("FR-13 R-309 SC-304: 세 번째 제출의 재판정이 임계값 미만이어도 통과다")
    func thirdSubmissionPasses() {
        let input = afterSubmit(submissions: 3, score: judged(concrete: 0.3, hash: newHash))
        #expect(ConcreteGate.phase(input) == .closed)
        #expect(ConcreteGate.afterAnswer(input) == GateRecord(submissions: 3, passed: true))
    }

    @Test("FR-13 R-308: 해시가 다른 이전 판단 결과로는 판정하지 않고 기다린다")
    func ignoresOldScore() {
        for concrete in [0.3, 0.9] {
            let input = afterSubmit(submissions: 3, score: judged(concrete: concrete, hash: oldHash))
            #expect(ConcreteGate.phase(input) == .checking)
            #expect(ConcreteGate.afterAnswer(input) == input.record)
        }
    }

    @Test("FR-13 R-308: 기다리는 중 판단 결과가 아직 없으면 기다린다")
    func waitsWithoutScore() {
        let input = afterSubmit(score: nil)
        #expect(ConcreteGate.phase(input) == .checking)
        #expect(ConcreteGate.afterAnswer(input) == input.record)
    }

    @Test("FR-13 R-308: 기다리는 중 해시가 다시 바뀌면(하루, 일정) 새 해시의 결과를 기다린다")
    func hashChangesAgain() {
        let stale = afterSubmit(score: judged(concrete: 0.9, hash: newHash), currentHash: newerHash)
        #expect(ConcreteGate.phase(stale) == .checking)
        #expect(ConcreteGate.afterAnswer(stale) == stale.record)
        let staleFailure = afterSubmit(failedHash: newHash, currentHash: newerHash)
        #expect(ConcreteGate.phase(staleFailure) == .checking)
        let fresh = afterSubmit(score: judged(concrete: 0.9, hash: newerHash), currentHash: newerHash)
        #expect(ConcreteGate.phase(fresh) == .closed)
        #expect(ConcreteGate.afterAnswer(fresh).passed)
    }

    @Test("FR-13 R-309: 통과한 기록은 기다리는 중이어도 닫혀 있고 그대로다")
    func passedStaysClosed() {
        var input = afterSubmit(score: judged(concrete: 0.3, hash: newHash))
        input.record.passed = true
        #expect(ConcreteGate.phase(input) == .closed)
        #expect(ConcreteGate.afterAnswer(input) == input.record)
    }
}
