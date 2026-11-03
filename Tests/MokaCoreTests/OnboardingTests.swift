import Foundation
import MokaCore
import Testing

// data-model §6 Onboarding.finish(R-116).

/// 설정·컨텍스트 쓰기를 한 줄씩 남기는 가짜 저장소. `failOn`에 든 키(컨텍스트는 "context")에서 throw한다.
private final class RecordingStores: SettingsStore, ContextStore {
    struct Failure: Error, Equatable {}

    var log: [String] = []
    let failOn: String?
    let settings = InMemorySettingsStore()
    let contextStore = InMemoryContextStore()

    init(failOn: String? = nil) {
        self.failOn = failOn
    }

    func value(for key: String) throws -> String? {
        try settings.value(for: key)
    }

    func setValue(_ value: String, for key: String) throws {
        if key == failOn { throw Failure() }
        log.append("\(key)=\(value)")
        try settings.setValue(value, for: key)
    }

    func contexts() throws -> [MokaContext] {
        try contextStore.contexts()
    }

    func insertContext(_ context: NewContext) throws -> MokaContext {
        if failOn == "context" { throw Failure() }
        log.append("context")
        return try contextStore.insertContext(context)
    }

    func deleteContext(id: ContextID) throws {
        try contextStore.deleteContext(id: id)
    }
}

private let fakeContext = NewContext(name: "가짜 일정", date: LocalDay(text: "2027-01-20")!, impact: .high)

private func finish(_ stores: RecordingStores, context: NewContext? = fakeContext, quantum: Int = 45, extend: Int = 15)
    throws
{
    try Onboarding.finish(
        context: context, quantumMin: quantum, extendMin: extend, dayStart: DayStart(text: "05:30")!,
        settings: stores, contexts: stores)
}

@Suite struct OnboardingTests {
    @Test("FR-21 R-116: 끝내기는 컨텍스트 → 세 설정 → onboarding_done 차례로 쓴다")
    func writesInOrder() throws {
        let stores = RecordingStores()
        try finish(stores)
        #expect(
            stores.log == [
                "context", "default_quantum_min=45", "default_extend_min=15", "day_start=05:30", "onboarding_done=true",
            ])
        #expect(try stores.contexts().map(\.name) == ["가짜 일정"])
        #expect(CoreSettings.isOnboardingDone(in: stores))
    }

    @Test("FR-21 R-116: 일정을 건너뛰면 컨텍스트 없이 세 설정과 onboarding_done만")
    func skipsContext() throws {
        let stores = RecordingStores()
        try finish(stores, context: nil)
        #expect(stores.log.first == "default_quantum_min=45")
        #expect(stores.log.last == "onboarding_done=true")
        #expect(try stores.contexts().isEmpty)
    }

    @Test(
        "FR-21 R-116: 중간에 실패하면 그 오류를 던지고 onboarding_done을 쓰지 않는다",
        arguments: ["context", "default_quantum_min", "default_extend_min", "day_start", "onboarding_done"])
    func failureKeepsOnboarding(failOn: String) {
        let stores = RecordingStores(failOn: failOn)
        #expect(throws: RecordingStores.Failure()) { try finish(stores) }
        #expect(!stores.log.contains("onboarding_done=true"))
        #expect(!CoreSettings.isOnboardingDone(in: stores))
    }

    @Test("FR-21 R-116: 범위 밖 작업 시간·추가 시간이면 던지고 onboarding_done을 쓰지 않는다")
    func outOfRangeRejected() {
        let quantum = RecordingStores()
        #expect(throws: (any Error).self) { try finish(quantum, quantum: 0) }
        #expect(!CoreSettings.isOnboardingDone(in: quantum))
        let extend = RecordingStores()
        #expect(throws: (any Error).self) { try finish(extend, extend: 181) }
        #expect(!CoreSettings.isOnboardingDone(in: extend))
    }

    @Test("FR-21 R-116: 값을 그대로 두고 끝내면 25분·10분·06:00으로 읽힌다")
    func defaultsRoundTrip() throws {
        let settings = InMemorySettingsStore()
        try Onboarding.finish(
            context: nil, quantumMin: Defaults.quantumMin, extendMin: Defaults.extendMin, dayStart: Defaults.dayStart,
            settings: settings, contexts: InMemoryContextStore())
        #expect(QuantumSettings.readDefault(from: settings) == 25)
        #expect(CoreSettings.readExtendMin(from: settings) == 10)
        #expect(CoreSettings.readDayStart(from: settings).text == "06:00")
        #expect(CoreSettings.isOnboardingDone(in: settings))
    }

    @Test("FR-21 R-116: 일정 없이 끝내도 할 일을 더하고 노치가 고를 수 있다")
    func worksWithoutSchedule() throws {
        let settings = InMemorySettingsStore()
        try Onboarding.finish(
            context: nil, quantumMin: 25, extendMin: 10, dayStart: Defaults.dayStart, settings: settings,
            contexts: InMemoryContextStore())
        let repository = InMemoryTaskRepository()
        let dayStart = CoreSettings.readDayStart(from: settings)
        let new = try #require(
            TaskWriteRules.prepareNew(
                NewTask(title: "가짜 할 일 A", deadline: nil, estMin: nil, recurrence: .none, weekday: nil),
                now: Fake.noon, dayStart: dayStart, calendar: Fake.seoul))
        let task = try repository.insertTask(new.task, cycleDay: new.cycleDay, at: Fake.noon)
        let session = NotchSession.initial.picked(
            Fake.input(try repository.tasks(), defaultQuantumMin: QuantumSettings.readDefault(from: settings)))
        #expect(session.taskID == task.id)
        #expect(session.timer == .empty(draft: Draft(title: "가짜 할 일 A", chipMin: 25)))
    }
}
