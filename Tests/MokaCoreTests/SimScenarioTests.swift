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
    ErrorFixture(name: "unicode-escape-sign", kind: .invalidJSON),
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
    ErrorFixture(name: "unknown-key-newline", kind: .unknownKey),
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
    ErrorFixture(name: "year-before-1", kind: .invalidTimestamp),
    ErrorFixture(name: "year-after-9999", kind: .invalidTimestamp),
    ErrorFixture(name: "at-not-string", kind: .wrongType),
    ErrorFixture(name: "start-in-empty", kind: .notAllowedInPhase),
    ErrorFixture(name: "choose-in-empty", kind: .notAllowedInPhase),
    ErrorFixture(name: "complete-in-draft", kind: .notAllowedInPhase),
    ErrorFixture(name: "enter-title-in-running", kind: .notAllowedInPhase),
    ErrorFixture(name: "start-in-running", kind: .notAllowedInPhase),
    ErrorFixture(name: "enter-title-in-expired", kind: .notAllowedInPhase),
    ErrorFixture(name: "complete-in-empty", kind: .notAllowedInPhase),
    ErrorFixture(name: "choose-in-running", kind: .notAllowedInPhase),
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
    let expected = FileManager.default.contents(
        atPath: simFixturesURL.appendingPathComponent("us1-basic.expected.jsonl").path)
    #expect(Data(result.stdout.utf8) == expected)
    #expect(result.stderr.isEmpty)
    #expect(result.exitCode == 0)
}

/// 끝의 개행 하나를 뺀 나머지에 줄을 바꾸는 문자(제어 문자, U+0085, U+2028, U+2029)가 없다.
private func isOneLine(_ stderr: String) -> Bool {
    guard stderr.hasSuffix("\n") else { return false }
    return !stderr.dropLast().unicodeScalars.contains {
        $0.value < 0x20 || (0x7F...0x9F).contains($0.value) || $0.value == 0x2028 || $0.value == 0x2029
    }
}

private func runCommand(_ json: String) -> SimCommandResult {
    SimCommand.run(arguments: ["run", "fake.json"]) { _ in Data(json.utf8) }
}

@Test("ADR-0003 R-015: errors/ 픽스처의 표준 오류는 개행 없는 한 줄", arguments: errorFixtures)
func errorFixtureStderrIsOneLine(fixture: ErrorFixture) {
    let path = errorsURL.appendingPathComponent("\(fixture.name).json").path
    let command = SimCommand.run(arguments: ["run", path], readFile: readFixture)
    #expect(isOneLine(command.stderr), "\(command.stderr.debugDescription)")
}

@Test(
    "ADR-0003 R-015: 입력 문자열에 제어 문자가 있어도 표준 오류는 한 줄",
    arguments: [
        #"{"version":1,"timezone":"UTC","events":[],"a\nb":1}"#,
        #"{"version":1,"timezone":"UTC","events":[],"settings":{"a\r\nb\u2028c":1}}"#,
        #"{"version":1,"timezone":"UTC","events":[{"at":"2026-11-02T00:00:00Z","type":"ti\nck"}]}"#,
        #"{"version":1,"timezone":"UTC","events":[{"at":"2026-11-02\n00:00:00Z","type":"tick"}]}"#,
        #"{"version":1,"timezone":"UTC","events":[{"at":"2026-11-02T00:00:00.5Z\n","type":"tick"}]}"#,
        #"{"version":1,"timezone":"Asia/\u0000Seoul","events":[]}"#,
        #"{"version":1,"a\tb":1,"a\tb":2,"timezone":"UTC","events":[]}"#,
    ])
func controlCharactersInInputStayOnOneLine(json: String) {
    let command = runCommand(json)
    #expect(command.exitCode == 2)
    #expect(isOneLine(command.stderr), "\(command.stderr.debugDescription)")
}

@Test(
    "ADR-0003 R-015: 인자에 제어 문자가 있어도 표준 오류는 한 줄",
    arguments: [["ch\neck"], ["run", "/nonexistent/fa\nke.json"]])
func controlCharactersInArgumentsStayOnOneLine(arguments: [String]) {
    let command = SimCommand.run(arguments: arguments) { _ in nil }
    #expect(command.exitCode == 2)
    #expect(isOneLine(command.stderr), "\(command.stderr.debugDescription)")
}

@Test("ADR-0003 R-015: 오류 설명에 넣는 입력 문자열은 64자에서 자른다")
func longInputIsTruncated() {
    let key = String(repeating: "x", count: 1000)
    let command = runCommand(#"{"version":1,"timezone":"UTC","events":[],""# + key + #"":1}"#)
    #expect(command.exitCode == 2)
    #expect(command.stderr.contains(String(repeating: "x", count: 64) + "…"))
    #expect(!command.stderr.contains(String(repeating: "x", count: 65)))
}
