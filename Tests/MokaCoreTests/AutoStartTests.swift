import Foundation
import MokaCore
import Testing

// spec 005 data-model §17(R-410). 시각은 주입한 값만 쓰고 실제 시간을 기다리지 않는다.

private let shown = Fake.noon

private struct Case {
    var enabled = true
    var mode: NotchMode = .session
    var draftShownAt: Date? = shown
    var lastInputAt: Date?
    var gateBusy = false
    var extendNeeded: Int?
    var startFailed = false

    func shouldStart(after seconds: TimeInterval) -> Bool {
        AutoStart.shouldStart(
            enabled: enabled, mode: mode, draftShownAt: draftShownAt, lastInputAt: lastInputAt, gateBusy: gateBusy,
            extendNeeded: extendNeeded, startFailed: startFailed, now: shown.addingTimeInterval(seconds))
    }

    var dueAt: Date? {
        AutoStart.dueAt(
            enabled: enabled, mode: mode, draftShownAt: draftShownAt, lastInputAt: lastInputAt, gateBusy: gateBusy,
            extendNeeded: extendNeeded, startFailed: startFailed)
    }
}

@Suite struct AutoStartTests {
    @Test("FR-05 R-410: 기다림은 Defaults.autoStartDelay 3초(승인 6)")
    func delay() {
        #expect(Defaults.autoStartDelay == 3)
    }

    @Test("FR-05 R-410: 초안이 뜬 뒤 3초가 되면 참, 그 전이면 거짓")
    func boundary() {
        let base = Case()
        #expect(!base.shouldStart(after: 0))
        #expect(!base.shouldStart(after: 2.999))
        #expect(base.shouldStart(after: 3))
        #expect(base.shouldStart(after: 10))
        #expect(base.dueAt == shown.addingTimeInterval(3))
    }

    @Test("FR-05 R-410: 꺼져 있으면 거짓(기본 꺼짐)")
    func disabled() {
        var off = Case()
        off.enabled = false
        #expect(!off.shouldStart(after: 60))
        #expect(off.dueAt == nil)
    }

    @Test("FR-05 R-410: 입력이 있으면 그 입력부터 다시 3초를 센다")
    func inputRearms() {
        var touched = Case()
        touched.lastInputAt = shown.addingTimeInterval(2)
        #expect(!touched.shouldStart(after: 3))
        #expect(!touched.shouldStart(after: 4.999))
        #expect(touched.shouldStart(after: 5))
        #expect(touched.dueAt == shown.addingTimeInterval(5))

        var earlier = Case()
        earlier.lastInputAt = shown.addingTimeInterval(-10)
        #expect(earlier.shouldStart(after: 3), "초안이 뜨기 전 입력은 초안이 뜬 시각으로 본다")
    }

    @Test("FR-05 R-410: 초안이 없으면 거짓")
    func noDraft() {
        var empty = Case()
        empty.draftShownAt = nil
        #expect(!empty.shouldStart(after: 60))
        #expect(empty.dueAt == nil)
    }

    @Test(
        "FR-05 R-410: 이월 카드·가용 시간 질문·오늘 끝·저장 불가에서는 거짓",
        arguments: [
            NotchMode.carryCard(taskID: 1, left: 1, reason: .touched), .askBudget, .dayEnd, .storageUnavailable,
        ])
    func otherModes(mode: NotchMode) {
        var other = Case()
        other.mode = mode
        #expect(!other.shouldStart(after: 60))
        #expect(other.dueAt == nil)
    }

    @Test("FR-05 R-410: 구체화 게이트가 묻거나 확인하는 중이면 거짓")
    func gateBusy() {
        var gate = Case()
        gate.gateBusy = true
        #expect(!gate.shouldStart(after: 60))
        #expect(gate.dueAt == nil)
    }

    @Test("FR-05 R-410 R-421: 늘리기 확인 줄이 열리면(남은 10분에서 25분 칩) 거짓")
    func extendConfirmOpen() {
        var confirm = Case()
        confirm.extendNeeded = QuantumChip.extendNeeded(chipMin: 25, remainingMinutes: 10)
        #expect(confirm.extendNeeded == 15)
        #expect(!confirm.shouldStart(after: 60))
        #expect(confirm.dueAt == nil)
    }

    @Test("FR-05 R-410 R-421: 칩이 남은 분 이하이거나 상한이 없으면 확인 줄이 닫혀 참")
    func extendConfirmClosed() {
        for remaining in [10, 25, nil] as [Int?] {
            var closed = Case()
            closed.extendNeeded = QuantumChip.extendNeeded(
                chipMin: remaining == 10 ? 10 : 25, remainingMinutes: remaining)
            #expect(closed.extendNeeded == nil)
            #expect(closed.shouldStart(after: 3))
        }
    }

    @Test("FR-05 R-410: 시작 실패 문구가 떠 있으면 거짓(다시 시도하지 않는다)")
    func startFailed() {
        var failed = Case()
        failed.startFailed = true
        #expect(!failed.shouldStart(after: 60))
        #expect(failed.dueAt == nil)
    }
}

@Suite struct AutoStartSettingsTests {
    @Test("FR-16 R-410: 설정 키 이름은 auto_start(승인 5)")
    func key() {
        #expect(CoreSettings.autoStartKey == "auto_start")
    }

    @Test("FR-16 R-410: 없으면 꺼짐, 켜면 \"true\"로 쓰고 끄면 꺼짐으로 읽는다")
    func roundTrip() throws {
        let store = InMemorySettingsStore()
        #expect(!CoreSettings.isAutoStartOn(in: store))
        try CoreSettings.writeAutoStart(true, to: store)
        #expect(try store.value(for: "auto_start") == "true")
        #expect(CoreSettings.isAutoStartOn(in: store))
        try CoreSettings.writeAutoStart(false, to: store)
        #expect(!CoreSettings.isAutoStartOn(in: store))
    }

    @Test("FR-16 R-410: 정확히 \"true\"가 아니면 꺼짐", arguments: ["", "TRUE", "1", "yes", " true"])
    func otherTextIsOff(text: String) throws {
        let store = InMemorySettingsStore()
        try store.setValue(text, for: "auto_start")
        #expect(!CoreSettings.isAutoStartOn(in: store))
    }
}
