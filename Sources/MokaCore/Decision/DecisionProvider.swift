import Foundation

/// 할 일 하나의 판단 요청(contracts/decision-provider.md). 키는 담지 않는다.
public struct DecisionRequest: Equatable, Sendable {
    /// 답을 짝짓는 데만 쓰고 HTTP 본문에는 넣지 않는다.
    public let taskID: TaskID
    public let model: String
    /// `JudgmentState.bytes`.
    public let state: [UInt8]
    public let questions: QuestionSet

    public init(taskID: TaskID, model: String, state: [UInt8], questions: QuestionSet) {
        self.taskID = taskID
        self.model = model
        self.state = state
        self.questions = questions
    }
}

/// 실패 종류(spec R-211). `unauthorized`는 질의를 멈추고, 나머지는 그 할 일 실패로 기록한다.
public enum DecisionError: Error, Equatable, Sendable {
    case missingKey
    /// 401, 403.
    case unauthorized
    /// 429.
    case rateLimited
    /// 529.
    case overloaded
    case timeout
    case network
    case server(status: Int)
    case malformed
}

/// 바꿔 끼울 수 있는 판단 공급자 경계(spec R-210, 공개 계약).
public protocol DecisionProvider: Sendable {
    /// 로그와 `scores.provider`에 적는 이름.
    var name: String { get }
    func decide(_ request: DecisionRequest, key: String) async throws(DecisionError) -> DecisionResponse
}

/// 시험·`moka-sim`용 가짜 공급자. 붙잡기로 동시 진행과 질의 중 고침을 실제 시간 없이 재현한다.
public actor FakeDecisionProvider: DecisionProvider {
    public nonisolated let name: String
    /// 동시에 진행 중이던 요청의 최대 개수.
    public private(set) var maxInFlight = 0
    /// 받은 요청의 할 일 id, 받은 순서.
    public private(set) var calls: [TaskID] = []

    private let defaultAnswer: Result<DecisionResponse, DecisionError>
    private var answers: [TaskID: Result<DecisionResponse, DecisionError>] = [:]
    private var inFlight = 0
    private var holding = false
    private var held: [(taskID: TaskID, resume: CheckedContinuation<Void, Never>)] = []
    private var heldWaiters: [(count: Int, resume: CheckedContinuation<Void, Never>)] = []

    /// `answer`는 따로 정하지 않은 할 일의 답이다.
    public init(name: String = "fake", answer: Result<DecisionResponse, DecisionError>) {
        self.name = name
        defaultAnswer = answer
    }

    /// 이후 받는 그 할 일 요청의 답. 이미 받은 요청에는 닿지 않는다.
    public func setAnswer(_ answer: Result<DecisionResponse, DecisionError>, for taskID: TaskID) {
        answers[taskID] = answer
    }

    /// 지금 붙잡고 있는 요청 수.
    public var heldCount: Int { held.count }

    /// 이후 받는 요청을 풀 때까지 붙잡는다.
    public func hold() {
        holding = true
    }

    /// 그 할 일의 붙잡은 요청 가운데 먼저 온 하나를 푼다.
    public func release(taskID: TaskID) {
        guard let index = held.firstIndex(where: { $0.taskID == taskID }) else { return }
        held.remove(at: index).resume.resume()
    }

    /// 붙잡은 요청을 모두 풀고 붙잡기를 끝낸다. 더 붙잡을 일이 없으므로 `waitForHeld` 기다림도 모두 깨운다.
    public func releaseAll() {
        holding = false
        let all = held
        held = []
        for entry in all { entry.resume.resume() }
        let waiters = heldWaiters
        heldWaiters = []
        for waiter in waiters { waiter.resume.resume() }
    }

    /// 붙잡은 요청이 `count`개 이상이 될 때까지 기다린다. 붙잡지 않는 중이면 바로 돌아온다.
    public func waitForHeld(count: Int) async {
        guard holding, held.count < count else { return }
        await withCheckedContinuation { heldWaiters.append((count, $0)) }
    }

    public func decide(_ request: DecisionRequest, key: String) async throws(DecisionError) -> DecisionResponse {
        calls.append(request.taskID)
        guard !key.isEmpty else { throw .missingKey }
        let answer = answers[request.taskID] ?? defaultAnswer
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        if holding {
            await withCheckedContinuation { continuation in
                held.append((request.taskID, continuation))
                wakeHeldWaiters()
            }
        }
        inFlight -= 1
        return try answer.get()
    }

    private func wakeHeldWaiters() {
        let ready = heldWaiters.filter { $0.count <= held.count }
        heldWaiters.removeAll { $0.count <= held.count }
        for waiter in ready { waiter.resume.resume() }
    }
}
