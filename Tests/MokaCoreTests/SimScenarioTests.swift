import Foundation
import MokaCore
import Testing

struct ErrorFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let kind: SimErrorKind
    var testDescription: String { name }
}

let errorFixtures: [ErrorFixture] = [
    ErrorFixture(name: "invalid-json", kind: .invalidJSON),
    ErrorFixture(name: "root-not-object", kind: .wrongType),
    ErrorFixture(name: "unknown-version", kind: .unknownVersion),
    ErrorFixture(name: "version-float", kind: .wrongType),
    ErrorFixture(name: "version-missing", kind: .missingField),
    ErrorFixture(name: "timezone-missing", kind: .missingField),
    ErrorFixture(name: "unknown-timezone", kind: .unknownTimezone),
    ErrorFixture(name: "events-missing", kind: .missingField),
    ErrorFixture(name: "events-not-array", kind: .wrongType),
    ErrorFixture(name: "unknown-key", kind: .unknownKey),
    ErrorFixture(name: "unknown-key-settings", kind: .unknownKey),
    ErrorFixture(name: "unknown-key-event", kind: .unknownKey),
    ErrorFixture(name: "settings-out-of-range", kind: .outOfRange),
    ErrorFixture(name: "settings-float", kind: .wrongType),
    ErrorFixture(name: "unknown-type", kind: .unknownType),
    ErrorFixture(name: "type-missing", kind: .missingField),
    ErrorFixture(name: "at-missing", kind: .missingField),
    ErrorFixture(name: "title-missing", kind: .missingField),
    ErrorFixture(name: "title-not-string", kind: .wrongType),
    ErrorFixture(name: "blank-title", kind: .emptyTitle),
    ErrorFixture(name: "quantum-missing", kind: .missingField),
    ErrorFixture(name: "quantum-float", kind: .wrongType),
    ErrorFixture(name: "quantum-exponent", kind: .wrongType),
    ErrorFixture(name: "quantum-string", kind: .wrongType),
    ErrorFixture(name: "quantum-out-of-range", kind: .outOfRange),
    ErrorFixture(name: "set-default-out-of-range", kind: .outOfRange),
    ErrorFixture(name: "time-reversed", kind: .timeReversed),
    ErrorFixture(name: "fractional-seconds", kind: .fractionalSeconds),
    ErrorFixture(name: "missing-offset", kind: .invalidTimestamp),
    ErrorFixture(name: "missing-seconds", kind: .invalidTimestamp),
    ErrorFixture(name: "invalid-date", kind: .invalidTimestamp),
    ErrorFixture(name: "at-not-string", kind: .wrongType),
    ErrorFixture(name: "start-in-empty", kind: .notAllowedInPhase),
    ErrorFixture(name: "choose-in-empty", kind: .notAllowedInPhase),
    ErrorFixture(name: "complete-in-draft", kind: .notAllowedInPhase),
    ErrorFixture(name: "enter-title-in-running", kind: .notAllowedInPhase),
    ErrorFixture(name: "start-in-running", kind: .notAllowedInPhase),
    ErrorFixture(name: "enter-title-in-expired", kind: .notAllowedInPhase),
]

private let errorsURL = simFixturesURL.appendingPathComponent("errors", isDirectory: true)

private func readFixture(_ path: String) -> Data? {
    FileManager.default.contents(atPath: path)
}

private func run(_ json: String) -> Result<String, SimError> {
    SimRunner.run(Data(json.utf8))
}

private func kind(_ result: Result<String, SimError>) -> SimErrorKind? {
    if case .failure(let error) = result { return error.kind }
    return nil
}

@Test("ADR-0003 R-015: errors/ 픽스처는 표에 적은 오류 종류, 빈 표준 출력, 종료 코드 2", arguments: errorFixtures)
func errorFixtureFailsWithExpectedKind(fixture: ErrorFixture) {
    let path = errorsURL.appendingPathComponent("\(fixture.name).json").path
    let data = FileManager.default.contents(atPath: path)
    #expect(data != nil, "\(fixture.name).json 없음")
    #expect(kind(SimRunner.run(data ?? Data())) == fixture.kind)

    let command = SimCommand.run(arguments: ["run", path], readFile: readFixture)
    #expect(command.stdout.isEmpty)
    #expect(!command.stderr.isEmpty)
    #expect(command.exitCode == 2)
}

@Test("ADR-0003 R-015: errors/의 파일은 모두 표에 있다")
func everyErrorFixtureIsListed() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: errorsURL.path)
        .filter { $0.hasSuffix(".json") }
        .map { String($0.dropLast(".json".count)) }
    #expect(Set(files) == Set(errorFixtures.map(\.name)))
}

@Test("ADR-0003 R-015: settings가 없으면 기본 작업 시간 25")
func missingSettingsMeansDefault25() {
    let result = run(
        #"{"version":1,"timezone":"Asia/Seoul","events":[{"at":"2026-11-02T00:00:00Z","type":"enter_title","title":"가짜 할 일 A"}]}"#
    )
    #expect(
        result
            == .success(
                #"{"seq":1,"at":"2026-11-02T00:00:00Z","event":"enter_title","timer_state":"empty","chip_min":25,"remaining_s":null}"#
                    + "\n"))
}

@Test("ADR-0003 R-015: 빈 events는 출력 없이 성공")
func emptyEventsProduceNoOutput() {
    let result = run(#"{"version":1,"timezone":"UTC","settings":{},"events":[]}"#)
    #expect(result == .success(""))
    #expect(SimExitCode.code(for: result) == 0)
}

@Test("ADR-0003 R-015: 정수 필드는 원문 토큰이 정수일 때만 받는다", arguments: ["45", "-0", "1.0", "45e0", "4.5E1"])
func integerFieldUsesRawToken(token: String) {
    let result = run(
        #"{"version":1,"timezone":"UTC","events":[{"at":"2026-11-02T00:00:00Z","type":"enter_title","title":"가짜 할 일 A"},{"at":"2026-11-02T00:00:01Z","type":"choose_quantum","quantum_min":"#
            + token + "}]}")
    switch token {
    case "45": #expect(kind(result) == nil)
    case "-0": #expect(kind(result) == .outOfRange)
    default: #expect(kind(result) == .wrongType)
    }
}

@Test("ADR-0003 R-015: 오프셋은 Z와 ±HH:MM을 받고 UTC로 출력한다")
func offsetsNormalizeToUTC() {
    let result = run(
        #"{"version":1,"timezone":"Asia/Seoul","events":[{"at":"2026-11-02T00:00:00-05:30","type":"tick"},{"at":"2026-11-02T05:30:00Z","type":"tick"}]}"#
    )
    #expect(
        result
            == .success(
                #"{"seq":1,"at":"2026-11-02T05:30:00Z","event":"tick","timer_state":"empty","chip_min":null,"remaining_s":null}"#
                    + "\n"
                    + #"{"seq":2,"at":"2026-11-02T05:30:00Z","event":"tick","timer_state":"empty","chip_min":null,"remaining_s":null}"#
                    + "\n"))
}

@Test("ADR-0003 R-015: 실행 중 오류는 실패한 이벤트의 seq를 담는다")
func runtimeErrorCarriesSeq() {
    let result = run(
        #"{"version":1,"timezone":"UTC","events":[{"at":"2026-11-02T00:00:00Z","type":"tick"},{"at":"2026-11-02T00:00:01Z","type":"start"}]}"#
    )
    guard case .failure(let error) = result else {
        Issue.record("오류가 나야 한다: \(result)")
        return
    }
    #expect(error.kind == .notAllowedInPhase)
    #expect(error.seq == 2)
    #expect(error.description.contains("2"))
}

@Test("ADR-0003 R-015: 같은 키가 두 번 나오면 입력 오류")
func duplicateKeyIsInputError() {
    #expect(kind(run(#"{"version":1,"version":1,"timezone":"UTC","events":[]}"#)) == .duplicateKey)
}

@Test(
    "ADR-0003 R-015: 인자 없음·모르는 하위 명령·인자 초과·파일 없음은 종료 코드 2",
    arguments: [[], ["check", "a.json"], ["run"], ["run", "a.json", "b.json"], ["run", "/nonexistent/fake.json"]])
func commandUsageErrors(arguments: [String]) {
    let result = SimCommand.run(arguments: arguments) { _ in nil }
    #expect(result.stdout.isEmpty)
    #expect(!result.stderr.isEmpty)
    #expect(result.exitCode == 2)
}

@Test("ADR-0003 R-015: run <file> 성공이면 표준 출력에 JSON Lines, 표준 오류 없음, 종료 코드 0")
func commandRunSuccess() {
    let path = simFixturesURL.appendingPathComponent("us1-basic.json").path
    let result = SimCommand.run(arguments: ["run", path], readFile: readFixture)
    let expected = FileManager.default.contents(atPath: simFixturesURL.appendingPathComponent("us1-basic.expected.jsonl").path)
    #expect(Data(result.stdout.utf8) == expected)
    #expect(result.stderr.isEmpty)
    #expect(result.exitCode == 0)
}
