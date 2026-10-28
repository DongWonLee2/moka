# Data Model: 노치와 타이머 (spec 001)

이름은 `GLOSSARY.md`를 따른다. 저장하는 것은 기본 작업 시간 설정 하나뿐이다(R-014). EGM 리뷰 뒤 보강(2026-10-28): 시작 전 단계, 전이표, Swift 모양, 스냅샷 형식, 경로 가드.

## 1. 현재 할 일 (메모리, 저장 안 함)

| 필드 | 규칙 |
|---|---|
| `title` | 앞뒤 공백을 뺀 문자열, 비어 있으면 안 됨(R-002). 길이 제한 없음, 화면에서 자름 |

동시에 최대 1개(R-005). 앱을 다시 켜면 없다(R-014).

## 2. 타이머 값 타입 `NotchTimer` (MokaCore)

앱(`AppState`)과 `moka-sim`이 같은 타입과 같은 전이 함수를 쓴다. 앱·시뮬레이터는 이벤트를 전달만 한다.

```swift
public struct Draft: Equatable, Sendable {
    public var title: String      // trim 뒤 비어 있지 않음
    public var chipMin: Int       // 1...180
}

public enum NotchTimer: Equatable, Sendable {
    case empty(draft: Draft?)
    case running(title: String, quantumMin: Int, startedAt: Date, endsAt: Date)
    case expired(title: String, chipMin: Int)
}

public enum TimerEvent: Equatable, Sendable {
    case enterTitle(String)
    case chooseQuantum(Int)
    case start
    case tick
    case complete
}

public enum TransitionResult: Equatable, Sendable {
    case applied
    case rejected(RejectReason)   // 앱은 무시, moka-sim은 종료 코드 2
}

extension NotchTimer {
    /// 처리 전에 `tick(at)`을 먼저 적용한다(암묵 tick).
    public mutating func apply(_ event: TimerEvent, at now: Date, defaultQuantumMin: Int) -> TransitionResult
    public func remainingSeconds(at now: Date) -> Int?   // running: min(ceil(endsAt − now), quantumMin·60), expired: 0, empty: nil
    public func invariantViolation(at now: Date) -> String?   // nil이면 정상(moka-sim 종료 코드 1의 근거)
}
```

`RejectReason`의 경우 이름은 구현 PR에서 정하고 PR "가정"에 적는다.

전이표(초기 상태 `empty(draft: nil)`, 앱 실행 직후):

| 단계 \ 이벤트 | `enterTitle` | `chooseQuantum` | `start` | `tick` | `complete` |
|---|---|---|---|---|---|
| `empty(nil)` | `empty(Draft(title, default))` | rejected | rejected | 변화 없음 | rejected |
| `empty(draft)` | 제목만 바꿈, 칩 유지 | 칩 = 값 | `running(title, chip, now, now+chip·60초)` | 변화 없음 | rejected |
| `running` | rejected | rejected | rejected | `now ≥ endsAt`면 `expired(title, default)` | `empty(nil)` |
| `expired` | rejected | 칩 = 값 | `running(같은 제목, chip, …)` | 변화 없음 | `empty(nil)` |

- `enterTitle`의 제목이 trim 뒤 비거나, `chooseQuantum` 값이 1…180 밖이면 rejected.
- 시간 끝의 칩은 그 순간의 `defaultQuantumMin`으로 채운다(할 일별 마지막 선택은 범위 밖). 그 뒤 기본값이 바뀌어도 이미 채운 칩은 그대로다.
- 남은 초는 끝 시각 기준이고 `quantumMin·60`을 넘지 않는다(시계를 되돌린 경우, R-005). `running`에서 항상 1 이상.
- 불변식: `endsAt > startedAt`, `quantumMin`·`chipMin` ∈ 1…180.
- 기본값 변경(`set_default_quantum`)은 타이머 이벤트가 아니다. 설정에 쓰고, 다음 채움에 쓰이는 `defaultQuantumMin`만 바뀐다(R-013).

시각 주입(앱만 씀, 단위 1에서는 정의만):

```swift
public struct MokaClock: Sendable {
    public var now: @Sendable () -> Date
    public static func fixed(_ date: Date) -> MokaClock
}
```

## 3. 시간 칩과 표시 형식 (MokaCore 순수 함수)

```swift
public enum QuantumChip {
    public static let presets = Defaults.quantumPresets      // [15, 25, 45, 60]
    public static func parseCustom(_ text: String) -> Int?   // Int(text)가 1...180이면 값, 아니면 nil(시작 불가)
}
public enum RemainingFormat {
    public static func string(_ seconds: Int) -> String      // 60분 미만 "M:SS", 이상 "H:MM:SS", 맨 앞 자리는 0 채움 없음: 1500→"25:00", 599→"9:59", 3599→"59:59", 3600→"1:00:00", 5400→"1:30:00", 0→"0:00", 음수→"0:00"(#13)
}
```

- 직접 입력은 Swift `Int(_:)` 결과를 그대로 쓰고 1…180만 받는다. 빈 값, 숫자 아님, 소수는 nil(R-004).
- 미리 채움은 제목 입력 직후와 시간 끝에 `default_quantum_min`(R-003).

## 4. 기본 작업 시간 설정 (MokaCore 규칙 + MokaStore 저장)

```swift
public protocol SettingsStore {
    func value(for key: String) throws -> String?
    func setValue(_ value: String, for key: String) throws
}
public enum QuantumSettings {
    public static let key = "default_quantum_min"
    public static func readDefault(from store: some SettingsStore) -> Int          // 없거나 읽기 실패·정수 아님·범위 밖이면 25
    public static func writeDefault(_ minutes: Int, to store: some SettingsStore) throws   // 1...180 밖이면 QuantumSettingsError.outOfRange, 저장 안 함
}
public final class InMemorySettingsStore: SettingsStore   // 테스트·moka-sim용
```

테이블(D1, 마이그레이션 `v1_settings`, raw SQL 한 문장):

```
CREATE TABLE settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)
```

| key | value | 읽기 규칙 |
|---|---|---|
| `default_quantum_min` | 10진 정수 문자열 | 행이 없거나 정수가 아니거나 1~180 밖이면 25 |

- seed 행 없음. 처음 저장할 때 행이 생긴다(UPSERT).
- 쓰기는 1~180 정수만 받고 그 밖은 거부해 이전 값을 유지한다(R-012). 설정 화면은 제출(Enter)이나 포커스를 잃을 때 저장하고, 범위 밖이면 칸을 이전 값으로 되돌린다.
- 변경은 다음 칩 채움에 바로 반영되고 도는 타이머에는 영향이 없다(R-013).

MokaStore 공개 이름:

```swift
public enum MokaMigrations {
    public static let migrator: DatabaseMigrator     // "v1_settings" 등록(DatabaseMigrator는 Sendable, 전역 가변 var는 Swift 6에서 오류)
}
extension MokaDatabase {
    public static func open(at url: URL) throws -> DatabaseQueue   // 상위 폴더를 createDirectory(withIntermediateDirectories: true) → DatabaseQueue(path:) → migrate
    public static func schemaSQL(_ db: DatabaseQueue) throws -> String
}
public final class GRDBSettingsStore: SettingsStore { public init(_ db: DatabaseQueue) }
```

- 열기 함수는 받은 경로를 그대로 연다. 제품 코드에 테스트 빌드 판별 분기를 두지 않는다.
- 경로 가드는 테스트 쪽에 둔다(ADR-0004 "가드 테스트"): `Tests/MokaStoreTests/Support/TestDatabase.swift`가 `:memory:` 또는 `FileManager.default.temporaryDirectory` 아래 경로만 만들고, 가드 시험이 그 경로들이 메모리이거나 임시 디렉터리 아래이며 `dev.dongwon.moka`를 포함하지 않는지 단언한다.
- 마이그레이션 이름 시험: 시험 파일 안의 리터럴 `["v1_settings"]`와 `MokaMigrations.migrator.migrations`(GRDB 7.11.1 공개 API)가 같은지 단언한다(ADR-0007이 ADR-0004의 해당 문장을 대체).

스키마 스냅샷 `schema/moka-schema.sql`:
- 질의: `SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name <> 'grdb_migrations' ORDER BY name`
- 형식: 각 문장 뒤에 `;\n`. 파일은 그 문자열 그대로(끝 개행 하나).
- 시험은 비교만 하고 파일을 쓰지 않는다. 다르면 실제 텍스트를 `Issue.record`로 출력하고, 사람이 그 출력을 파일로 옮긴다(ADR-0004).
- 스냅샷 변경은 PR "사람이 볼 결정"에 올린다.

## 5. 표시 위치 (MokaCore 순수 함수)

```swift
public struct ScreenInfo: Equatable, Sendable { public var id: UInt32; public var hasNotch: Bool; public var isMain: Bool }
public enum DisplayTarget: Equatable, Sendable { case notch(UInt32), floating(UInt32) }
public func chooseDisplayTarget(_ screens: [ScreenInfo]) -> DisplayTarget?
```

| 경우 | 결과 |
|---|---|
| `hasNotch`인 화면이 있음 | 목록에서 첫 번째 그런 화면의 `.notch` |
| 없음 | `isMain` 화면의 `.floating`. `isMain`이 없으면 목록 첫 화면 |
| 화면이 0개 | `nil`(표시 안 함) |

앱 쪽 입력: `id` = `CGDirectDisplayID`(`deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`), `hasNotch` = `safeAreaInsets.top > 0`(노치는 내장 화면에만 있다), `isMain` = `screen == NSScreen.screens.first`(메뉴 막대가 있는 화면. `NSScreen.main`은 key window 화면이라 쓰지 않는다). 화면 연결이 바뀌면 다시 계산한다. 타이머 상태와 `isPinnedOpen`은 바뀌지 않고 새 위치로 옮겨진다(R-011).

## 6. 화면 상태 (앱 `AppState`, 저장 안 함)

| 값 | 의미 |
|---|---|
| `timer` | `NotchTimer`(초안 포함) |
| `isExpanded` | 펼침 여부 |
| `isPinnedOpen` | 시간 끝 자동 펼침으로 고정됨. 사용자가 시작·완료를 누르면 `false`(R-009) |
| `isHovering` | 마우스가 노치·판 위에 있음 |
| `isInputFocused` | 입력칸에 포커스가 있음 |
| `isEditingCustom` | 직접 입력 칸을 쓰는 중 |

접힘 판정은 MokaCore 순수 함수 `shouldStayExpanded(pinned:focused:hovering:) -> Bool`(셋 중 하나라도 참이면 펼친 채)로 두고 시험한다.

포커스 규칙(사용자 결정 2026-10-28, R-002·R-009):

| 펼침 경로 | key window | 입력 포커스 | 앱 활성화 |
|---|---|---|---|
| 마우스를 올려 펼침 | 아니오 | 없음 | 아니오 |
| 펼친 판 클릭 | 예 | 빈 상태면 제목 칸 | 아니오(패널만 key) |
| 시간 끝 자동 펼침 | 아니오 | 없음 | 아니오 |

첫 클릭 한 번에 입력 포커스까지 가는지는 spike 3번에서 PASS했다(2026-10-28). 시작·완료 뒤 패널이 key를 내려놓고 이전 앱으로 키 입력이 돌아가는지는 spike 기록이 없어 T015 사람 확인 항목이다.
