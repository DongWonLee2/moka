import Foundation

/// 마무리 규칙(R-405)에 넘기는 현재 할 일. 앱은 넘기지 않는다(R-407).
public struct CurrentTask: Equatable, Sendable {
    public var id: TaskID
    /// `RemainingEstimate.minutes`. 0 이하도 그대로.
    public var remainingMin: Int?
    public var quantumMin: Int

    public init(id: TaskID, remainingMin: Int?, quantumMin: Int) {
        self.id = id
        self.remainingMin = remainingMin
        self.quantumMin = quantumMin
    }
}

public struct PickInput: Equatable, Sendable {
    /// 후보 순서(data-model §4).
    public var order: [MokaTask]
    /// 쓸 수 있는 판단 결과.
    public var scores: [TaskID: TaskScore]
    /// 점수 있는 후보의 priority.
    public var priorities: [TaskID: Double]
    /// 바꾸기·미루기 직후 방금 할 일(R-408).
    public var excluded: TaskID?
    public var isWarmup: Bool
    public var current: CurrentTask?
    public var memory: SchedulerMemory

    public init(
        order: [MokaTask], scores: [TaskID: TaskScore] = [:], priorities: [TaskID: Double] = [:],
        excluded: TaskID? = nil, isWarmup: Bool = false, current: CurrentTask? = nil, memory: SchedulerMemory = .empty
    ) {
        self.order = order
        self.scores = scores
        self.priorities = priorities
        self.excluded = excluded
        self.isWarmup = isWarmup
        self.current = current
        self.memory = memory
    }
}

public struct PickResult: Equatable, Sendable {
    public var taskID: TaskID?
    public var rule: SchedulerChoice?
    public var memory: SchedulerMemory
}

/// 고르기(spec 005 data-model §5). 순수 함수이고 시계를 받지 않는다.
public enum SchedulerPick {
    /// priority를 정수 몫으로 키우는 배율.
    static let shareScale = 1000.0

    public static func pick(_ input: PickInput) -> PickResult {
        guard !input.order.isEmpty else { return PickResult(taskID: nil, rule: nil, memory: input.memory) }
        if let current = input.current, let remaining = current.remainingMin, remaining <= current.quantumMin {
            return picked(current.id, .weightedRotateV1, credits: input.memory.credits, input)
        }
        if input.isWarmup, let warm = warmupCandidate(input) {
            return picked(warm.id, .warmupV1, credits: input.memory.credits, input)
        }
        return rotate(input)
    }

    /// 창(`order` 앞 `rotationWidth`개)의 몫. 모두 점수 있으면 priority × `shareScale`(최소 몫 이상), 아니면 순위 몫.
    public static func shares(_ input: PickInput) -> [Int] {
        let window = input.order.prefix(Defaults.rotationWidth)
        let priorities = window.map { input.scores[$0.id] == nil ? nil : input.priorities[$0.id] }
        guard priorities.allSatisfy({ $0 != nil }) else {
            return Array(Defaults.rotationRankShares.prefix(window.count))
        }
        let minimum = Int((Defaults.rotationMinWeight * shareScale).rounded())
        return priorities.map { max(Int(($0! * shareScale).rounded()), minimum) }
    }

    private static func warmupCandidate(_ input: PickInput) -> MokaTask? {
        input.order.first { task in
            guard task.id != input.excluded, let score = input.scores[task.id], let est = task.estMin else {
                return false
            }
            return score.concrete >= Defaults.warmupConcreteMin && est <= Defaults.warmupEstMaxMin
        }
    }

    private static func rotate(_ input: PickInput) -> PickResult {
        let window = Array(input.order.prefix(Defaults.rotationWidth))
        let shares = shares(input)
        var credits: [TaskID: Int] = [:]
        for (task, share) in zip(window, shares) {
            credits[task.id] = (input.memory.credits[task.id] ?? 0) + share
        }
        let capped = cappedTask(input.memory.recentPicks)
        let open = window.filter { $0.id != input.excluded }
        let eligible = open.filter { $0.id != capped }
        let pool = !eligible.isEmpty ? eligible : (!open.isEmpty ? open : window)
        var best = pool[0]
        for task in pool.dropFirst() where credits[task.id]! > credits[best.id]! {
            best = task
        }
        credits[best.id]! -= shares.reduce(0, +)
        return picked(best.id, .weightedRotateV1, credits: credits, input)
    }

    /// 최근 고르기 끝 `consecutiveCap`개가 모두 같은 할 일이면 그 할 일.
    private static func cappedTask(_ recent: [TaskID]) -> TaskID? {
        let tail = recent.suffix(Defaults.consecutiveCap)
        guard tail.count == Defaults.consecutiveCap, let first = tail.first, tail.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    private static func picked(_ id: TaskID, _ rule: SchedulerChoice, credits: [TaskID: Int], _ input: PickInput)
        -> PickResult
    {
        var memory = input.memory
        memory.credits = credits
        memory.recentPicks = Array((memory.recentPicks + [id]).suffix(Defaults.consecutiveCap))
        return PickResult(taskID: id, rule: rule, memory: memory)
    }
}
