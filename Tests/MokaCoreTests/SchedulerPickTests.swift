import Foundation
import MokaCore
import Testing

// spec 005 data-model §5·§6·§8. 가짜 할 일·가짜 판단 결과만 쓴다.

private func score(_ id: TaskID, concrete: Double = 0.5) -> TaskScore {
    TaskScore(
        taskID: id, questionVersion: "v3", provider: "fake", modelSnapshot: nil, urgency: 0.5, impact: 0.5,
        concrete: concrete, avoiding: 0.1, probsJSON: "{}", stateHash: "0123456789abcdef", scoredAt: Fake.noon)
}

/// 점수 있는 후보. `priorities` 순서가 `order` 순서다.
private func scored(_ priorities: [(TaskID, Double)], concrete: [TaskID: Double] = [:], est: [TaskID: Int] = [:])
    -> PickInput
{
    PickInput(
        order: priorities.map { Fake.task($0.0, estMin: est[$0.0]) },
        scores: Dictionary(uniqueKeysWithValues: priorities.map { ($0.0, score($0.0, concrete: concrete[$0.0] ?? 0.5)) }),
        priorities: Dictionary(uniqueKeysWithValues: priorities))
}

private func unscored(_ ids: [TaskID]) -> PickInput {
    PickInput(order: ids.map { Fake.task($0) })
}

/// `count`번 고르고 고른 id 목록. 매번 몫 상태를 이어 받는다. `excludeLast`면 방금 고른 할 일을 뺀다(바꾸기·미루기).
private func run(_ input: PickInput, count: Int, excludeLast: Bool = false) -> (picks: [TaskID], memory: SchedulerMemory)
{
    var input = input
    var picks: [TaskID] = []
    for _ in 0..<count {
        let result = SchedulerPick.pick(input)
        guard let id = result.taskID else { break }
        picks.append(id)
        input.memory = result.memory
        if excludeLast { input.excluded = id }
    }
    return (picks, input.memory)
}

private func counts(_ picks: [TaskID]) -> [TaskID: Int] {
    picks.reduce(into: [:]) { $0[$1, default: 0] += 1 }
}

@Suite struct SchedulerPickRotateTests {
    @Test("FR-05 R-403 SC-401: A 1.5·B 0.9·C 0.6·D 0.3에서 100번이면 50·30·20(2 이내), D는 0번")
    func hundredPicksFollowShares() {
        let (picks, _) = run(scored([(1, 1.5), (2, 0.9), (3, 0.6), (4, 0.3)]), count: 100)
        let tally = counts(picks)
        #expect(abs((tally[1] ?? 0) - 50) <= 2)
        #expect(abs((tally[2] ?? 0) - 30) <= 2)
        #expect(abs((tally[3] ?? 0) - 20) <= 2)
        #expect(tally[4] == nil)
    }

    @Test("FR-05 R-403: 창이 그대로이고 건너뛰기가 없으면 10번마다 정확히 5·3·2")
    func everyTenPicksExact() {
        let (picks, memory) = run(scored([(1, 1.5), (2, 0.9), (3, 0.6)]), count: 30)
        for start in stride(from: 0, to: 30, by: 10) {
            #expect(counts(Array(picks[start..<start + 10])) == [1: 5, 2: 3, 3: 2])
        }
        #expect(memory.credits == [1: 0, 2: 0, 3: 0])
    }

    @Test("FR-05 R-403 R-408: 바꾸기·미루기로 방금 할 일을 건너뛰어도 넷째 후보는 0번이고 방금 할 일은 잇달아 뜨지 않는다")
    func excludedNeverPullsFourth() {
        let (picks, _) = run(scored([(1, 1.5), (2, 0.9), (3, 0.6), (4, 0.3)]), count: 100, excludeLast: true)
        #expect(counts(picks)[4] == nil)
        #expect(zip(picks, picks.dropFirst()).allSatisfy { $0 != $1 })
        let tally = counts(picks)
        #expect((tally[1] ?? 0) > (tally[2] ?? 0))
        #expect((tally[2] ?? 0) > (tally[3] ?? 0))
    }

    @Test("FR-05 R-403: 같은 입력과 같은 몫 상태면 같은 결과(무작위 없음)")
    func deterministic() {
        let input = scored([(1, 1.2), (2, 1.0), (3, 0.7), (4, 0.2)])
        #expect(run(input, count: 50, excludeLast: true).picks == run(input, count: 50, excludeLast: true).picks)
        #expect(SchedulerPick.pick(input) == SchedulerPick.pick(input))
    }

    @Test("FR-05 R-403: 하나라도 점수 없는 할 일이면 순위 몫 5:3:2")
    func mixedUsesRankShares() {
        var input = scored([(1, 2.5), (2, 0.1)])
        input.order.append(Fake.task(3))
        let (picks, _) = run(input, count: 10)
        #expect(counts(picks) == [1: 5, 2: 3, 3: 2])
    }

    @Test("FR-05 R-403 US1-7: 모두 점수 없으면 순서 앞 셋에 순위 몫 5:3:2")
    func unscoredUsesRankShares() {
        let (picks, _) = run(unscored([1, 2, 3, 4]), count: 20)
        #expect(counts(picks) == [1: 10, 2: 6, 3: 4])
    }

    @Test("FR-05 R-403: 후보가 둘이면 앞 둘에 5:3, 하나면 그 할 일")
    func twoAndOneCandidates() {
        #expect(counts(run(unscored([1, 2]), count: 8).picks) == [1: 5, 2: 3])
        #expect(run(unscored([7]), count: 3).picks == [7, 7, 7])
    }

    @Test("FR-05 R-403: 후보가 없으면 고르지 않는다")
    func noCandidates() {
        let result = SchedulerPick.pick(PickInput(order: []))
        #expect(result.taskID == nil)
        #expect(result.rule == nil)
    }

    @Test("FR-05 R-403: priority 0 후보도 창 안이면 최소 몫을 받아 0번이 아니다")
    func zeroPriorityGetsMinimumShare() {
        let (picks, _) = run(scored([(1, 1.0), (2, 0.5), (3, 0)]), count: 200)
        #expect((counts(picks)[3] ?? 0) > 0)
        #expect(SchedulerPick.shares(scored([(1, 1.0), (2, 0.5), (3, 0)])) == [1000, 500, 50])
    }

    @Test("FR-05 R-403: 몫은 priority × 1000을 반올림한 정수")
    func integerShares() {
        #expect(SchedulerPick.shares(scored([(1, 1.2346), (2, 0.9996), (3, 0.0499)])) == [1235, 1000, 50])
        #expect(SchedulerPick.shares(unscored([1, 2, 3, 4])) == [5, 3, 2])
        #expect(SchedulerPick.shares(unscored([1, 2])) == [5, 3])
    }

    @Test("FR-05 R-403: 고른 규칙 이름은 weighted_rotate_v1")
    func ruleName() {
        #expect(SchedulerPick.pick(unscored([1, 2])).rule == .weightedRotateV1)
        #expect(SchedulerChoice.weightedRotateV1.rawValue == "weighted_rotate_v1")
    }

    @Test("FR-05 R-403: 창에서 빠진 후보의 몫만 버리고 새로 든 후보는 0에서 시작한다")
    func windowChangeDropsOnlyLeavers() {
        var input = unscored([1, 2, 3])
        input.memory.credits = [1: 4, 2: -3, 3: -1, 9: 7]
        input.order = [Fake.task(1), Fake.task(2), Fake.task(4), Fake.task(3)]
        let result = SchedulerPick.pick(input)
        // 4는 0에서 시작, 3·9는 창 밖이라 버림. 더한 뒤 1: 9, 2: 0, 4: 2 → 1을 고르고 10을 뺌.
        #expect(result.taskID == 1)
        #expect(result.memory.credits == [1: -1, 2: 0, 4: 2])
    }

    @Test("FR-05 R-403 R-408: 건너뛴 후보의 몫은 버리지 않고 다음 고르기에서 앞선다")
    func excludedKeepsCredit() {
        var input = unscored([1, 2, 3])
        input.excluded = 1
        let first = SchedulerPick.pick(input)
        #expect(first.taskID == 2)
        #expect(first.memory.credits == [1: 5, 2: -7, 3: 2])
        input.excluded = nil
        input.memory = first.memory
        #expect(SchedulerPick.pick(input).taskID == 1)
    }

    @Test("FR-05 R-403: 넷째 후보는 excluded가 있어도 창에 들지 않는다")
    func fourthStaysOutWithExcluded() {
        var input = unscored([1, 2, 3, 4])
        input.excluded = 1
        input.memory.credits = [2: -100, 3: -100]
        #expect(SchedulerPick.pick(input).taskID != 4)
    }

    @Test("FR-05 R-403: 동점이면 순서 앞쪽")
    func tieGoesToOrderFront() {
        let input = scored([(1, 1.0), (2, 1.0), (3, 1.0)])
        #expect(run(input, count: 3).picks == [1, 2, 3])
    }

    @Test("FR-05 R-403: 몫 5:3:2 창에서 0부터 10번 고른 뒤 급한 새 할 일이 1위로 들면 바로 다음에 뽑히고 이어지는 10번 중 5번(특정 사례)")
    func urgentNewcomerCase() {
        let (picks, memory) = run(unscored([1, 2, 3]), count: 10)
        #expect(counts(picks) == [1: 5, 2: 3, 3: 2])
        #expect(memory.credits.values.allSatisfy { $0 == 0 })
        var input = unscored([9, 1, 2, 3])
        input.memory = memory
        let next = run(input, count: 10)
        #expect(next.picks.first == 9)
        #expect(counts(next.picks)[9] == 5)
        #expect(counts(next.picks)[3] == nil)
    }

    @Test("FR-05 R-408: 후보가 하나면 excluded여도 그 할 일")
    func singleCandidateIgnoresExcluded() {
        var input = unscored([5])
        input.excluded = 5
        #expect(SchedulerPick.pick(input).taskID == 5)
    }
}

@Suite struct SchedulerPickCapTests {
    @Test("FR-05 R-404 US1-3: 직전 두 고르기가 A면 A가 아닌 후보를 고른다")
    func capSkipsRepeated() {
        var input = scored([(1, 3.0), (2, 0.1), (3, 0.1)])
        input.memory.recentPicks = [1, 1]
        let result = SchedulerPick.pick(input)
        #expect(result.taskID != 1)
        #expect(result.rule == .weightedRotateV1)
    }

    @Test("FR-05 R-404: 직전 두 고르기가 다르면 상한이 걸리지 않는다")
    func capNeedsTwoSame() {
        var input = scored([(1, 3.0), (2, 0.1), (3, 0.1)])
        input.memory.recentPicks = [2, 1]
        #expect(SchedulerPick.pick(input).taskID == 1)
    }

    @Test("FR-05 R-404: 후보가 A 하나면 상한과 상관없이 A")
    func capIgnoredWhenOnlyOne() {
        var input = unscored([1])
        input.memory.recentPicks = [1, 1]
        #expect(SchedulerPick.pick(input).taskID == 1)
    }

    @Test("FR-05 R-404: 상한 때문에 고를 후보가 비면 상한을 무시한다")
    func capIgnoredWhenItEmpties() {
        var input = unscored([1, 2])
        input.excluded = 2
        input.memory.recentPicks = [1, 1]
        #expect(SchedulerPick.pick(input).taskID == 1)
    }

    @Test("FR-05 R-404: 고른 할 일은 최근 고르기 끝에 붙고 최근 둘만 남는다")
    func recentPicksKeepsTwo() {
        var input = unscored([1, 2])
        input.memory.recentPicks = [2, 1]
        let result = SchedulerPick.pick(input)
        #expect(result.memory.recentPicks == [1, result.taskID ?? 0])
        #expect(result.memory.recentPicks.count == Defaults.consecutiveCap)
    }
}

@Suite struct SchedulerPickFinishTests {
    @Test("FR-05 R-405 US1-4: 현재 A, 남은 20분, 작업 25분이면 A")
    func finishPicksCurrent() {
        var input = scored([(2, 3.0), (1, 0.1), (3, 0.1)])
        input.current = CurrentTask(id: 1, remainingMin: 20, quantumMin: 25)
        let result = SchedulerPick.pick(input)
        #expect(result.taskID == 1)
        #expect(result.rule == .weightedRotateV1)
    }

    @Test("FR-05 R-405: 마무리 규칙이 연속 상한보다 앞선다")
    func finishBeatsCap() {
        var input = scored([(1, 1.0), (2, 1.0)])
        input.current = CurrentTask(id: 1, remainingMin: 25, quantumMin: 25)
        input.memory.recentPicks = [1, 1]
        #expect(SchedulerPick.pick(input).taskID == 1)
    }

    @Test("FR-05 R-405: 다 하는 데 걸릴 시간이 없으면 마무리 규칙 없음")
    func noEstimateNoFinish() {
        var input = scored([(2, 3.0), (1, 0.1)])
        input.current = CurrentTask(id: 1, remainingMin: nil, quantumMin: 25)
        #expect(SchedulerPick.pick(input).taskID == 2)
    }

    @Test("FR-05 R-405: 남은 시간이 작업 시간보다 길면 마무리 규칙 없음")
    func longRemainingNoFinish() {
        var input = scored([(2, 3.0), (1, 0.1)])
        input.current = CurrentTask(id: 1, remainingMin: 26, quantumMin: 25)
        #expect(SchedulerPick.pick(input).taskID == 2)
    }

    @Test("FR-05 R-405: 남은 시간이 0 이하여도 마무리 규칙 대상", arguments: [0, -15])
    func overrunStillFinishes(remaining: Int) {
        var input = scored([(2, 3.0), (1, 0.1)])
        input.current = CurrentTask(id: 1, remainingMin: remaining, quantumMin: 25)
        #expect(SchedulerPick.pick(input).taskID == 1)
    }

    @Test("FR-05 R-405: 남은 예상 시간 = 예상 소요 − 그 할 일 체크포인트 경과 분 합, 예상이 없으면 nil")
    func remainingEstimate() {
        let checkpoints = [
            Checkpoint(id: 1, taskID: 1, notes: .empty, trigger: .skip, elapsedMin: 20, createdAt: Fake.noon),
            Checkpoint(id: 2, taskID: 2, notes: .empty, trigger: .quantum, elapsedMin: 25, createdAt: Fake.noon),
            Checkpoint(id: 3, taskID: 1, notes: .empty, trigger: .quantum, elapsedMin: 25, createdAt: Fake.noon),
        ]
        #expect(RemainingEstimate.minutes(task: Fake.task(1, estMin: 60), checkpoints: checkpoints) == 15)
        #expect(RemainingEstimate.minutes(task: Fake.task(1, estMin: 30), checkpoints: checkpoints) == -15)
        #expect(RemainingEstimate.minutes(task: Fake.task(1), checkpoints: checkpoints) == nil)
        #expect(RemainingEstimate.minutes(task: Fake.task(3, estMin: 10), checkpoints: checkpoints) == 10)
    }
}

@Suite struct SchedulerPickWarmupTests {
    @Test("FR-05 R-406 US1-6: 워밍업은 concrete 0.8 이상·30분 이하 후보 가운데 순서 1위, 이름 warmup_v1")
    func warmupPicksFirstEligible() {
        var input = scored(
            [(1, 2.0), (2, 1.5), (3, 1.0), (4, 0.5)], concrete: [1: 0.9, 2: 0.85, 3: 0.8, 4: 0.95],
            est: [1: 45, 2: 30, 3: 10, 4: 5])
        input.isWarmup = true
        let result = SchedulerPick.pick(input)
        #expect(result.taskID == 2)
        #expect(result.rule == .warmupV1)
    }

    @Test("FR-05 R-406: 워밍업 후보는 창이 아니라 후보 전체에서 찾는다")
    func warmupLooksBeyondWindow() {
        var input = scored([(1, 2.0), (2, 1.5), (3, 1.0), (4, 0.5)], concrete: [4: 0.8], est: [4: 30])
        input.isWarmup = true
        #expect(SchedulerPick.pick(input).taskID == 4)
    }

    @Test(
        "FR-05 R-406: 조건에 맞는 후보가 없으면 가중 순환(점수 없음, concrete 미달, 예상 없음, 30분 초과)",
        arguments: [(0.79, 20), (0.9, 31)])
    func warmupFallsBack(concrete: Double, est: Int) {
        var input = scored([(1, 2.0), (2, 1.0)], concrete: [1: concrete, 2: concrete], est: [1: est, 2: est])
        input.order.append(Fake.task(3, estMin: 5))
        input.isWarmup = true
        let result = SchedulerPick.pick(input)
        #expect(result.rule == .weightedRotateV1)
        #expect(result.taskID == 1)
    }

    @Test("FR-05 R-406: 예상 소요가 없는 할 일은 워밍업 후보가 아니다")
    func warmupNeedsEstimate() {
        var input = scored([(1, 2.0)], concrete: [1: 0.95])
        input.isWarmup = true
        #expect(SchedulerPick.pick(input).rule == .weightedRotateV1)
    }

    @Test("FR-05 R-406: 워밍업 고르기는 최근 고르기에 들고 몫 상태는 바꾸지 않는다")
    func warmupKeepsCredits() {
        var input = scored([(1, 2.0), (2, 1.0)], concrete: [2: 0.9], est: [2: 15])
        input.isWarmup = true
        input.memory.credits = [1: 3, 2: -3]
        let result = SchedulerPick.pick(input)
        #expect(result.taskID == 2)
        #expect(result.memory.credits == [1: 3, 2: -3])
        #expect(result.memory.recentPicks == [2])
    }

    @Test("FR-05 R-406: 워밍업이 아니면 조건에 맞아도 가중 순환")
    func notWarmup() {
        let input = scored([(1, 2.0), (2, 1.0)], concrete: [2: 0.9], est: [2: 15])
        #expect(SchedulerPick.pick(input).taskID == 1)
    }

    @Test("FR-05 R-406: 워밍업 값은 Defaults 한 곳에 있다")
    func warmupDefaults() {
        #expect(Defaults.warmupConcreteMin == 0.8)
        #expect(Defaults.warmupEstMaxMin == 30)
        #expect(SchedulerChoice.warmupV1.rawValue == "warmup_v1")
    }
}

@Suite struct SchedulerMemoryTests {
    @Test("FR-05 R-403: 하루가 바뀌면 몫 상태와 최근 고르기를 비운다")
    func newDayClears() {
        var memory = SchedulerMemory.empty
        memory.credits = [1: 3]
        memory.recentPicks = [1]
        memory.pickedBy = .weightedRotateV1
        let today = Fake.day("2027-01-13")
        let started = memory.on(today)
        #expect(started.credits.isEmpty)
        #expect(started.recentPicks.isEmpty)
        #expect(started.memoryDay == today)
        #expect(started.pickedBy == .weightedRotateV1)
        var same = started
        same.credits = [1: 3]
        #expect(same.on(today) == same)
        #expect(same.on(Fake.day("2027-01-14")).credits.isEmpty)
    }

    @Test("FR-05 R-403: 하루를 모르면(nil) 그대로 둔다")
    func unknownDayKeeps() {
        var memory = SchedulerMemory.empty
        memory.credits = [1: 3]
        #expect(memory.on(nil) == memory)
    }

    @Test("FR-05 R-403: 창 값은 Defaults 한 곳에 있다")
    func rotationDefaults() {
        #expect(Defaults.rotationWidth == 3)
        #expect(Defaults.rotationRankShares == [5, 3, 2])
        #expect(Defaults.rotationMinWeight == 0.05)
        #expect(Defaults.consecutiveCap == 2)
    }
}
