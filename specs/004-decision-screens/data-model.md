# Data Model: 판단 결과 화면 연결 (spec 004)

규칙의 원본이다. 결정 이유는 [research.md](research.md)에 있다. 이름은 GLOSSARY를 따른다. 타입 이름은 구현 PR에서 다듬을 수 있고, 바꾸면 PR "가정"에 적는다. 스키마, `questions.json`, `DecisionProvider`, `moka-sim` 형식, 행동 로그 값은 바꾸지 않는다.

## 1. MokaCore 값 타입 (새로 둠)

| 타입 | 모양 | 비고 |
|---|---|---|
| `DeadlineDistance` | `none`, `today`, `left(Int)`, `overdue(Int)` | 마감과 오늘(spec 002 R-114 하루 경계)의 날 수 차이 |
| `ReasonLine` | `deadline: DeadlineDistance`, `loss: String?`, `skipCount: Int` | `ReasonLine.make(task:usable:questions:today:calendar:)`. `loss`는 질문 파일 impact 옵션 말 하나이고, `usable`에 그 할 일이 없으면 `nil` |
| `ReasonText` | `static func line(_ reason: ReasonLine) -> String` | 노치에 보일 한 줄. 칸 사이 구분자와 글자는 시안 확정 뒤 고정한다 |
| `GateRecord` | `submissions: Int`, `passed: Bool` | 할 일 하나의 게이트 기록. AppState 메모리에만 있다 |
| `GatePhase` | `asking`, `checking`, `closed` | 노치에 보일 게이트 단계 |
| `ConcreteGate` | 아래 §3 순수 함수 | 판정은 모두 여기서 한다. AppState는 값을 모아 넘기고 결과를 반영한다 |

`Defaults.swift`에 `concreteGateMaxSubmissions = 3`을 더한다(AGENTS.md "가중치와 기본 값은 한 곳"). concrete 임계값은 `questions.json`의 `thresholds[model].concrete`를 그대로 읽는다.

## 2. 이유 줄 규칙 (spec R-301~R-305)

- **남은 날**: 마감이 없으면 `none`. 마감이 오늘이면 `today`. 마감이 오늘 뒤면 `left(날 수)`, 오늘 앞이면 `overdue(날 수)`. 오늘은 고르기와 같은 `LocalDay`(spec 003 `SessionScoring.today`)다.
- **손해**: `usable[taskID]`가 있으면 옵션 번호 `round(impact 곱하기 (옵션 수 빼기 1))`의 옵션 말. 반올림은 0.5에서 위로 간다. 지금 옵션 셋이라 0.25 미만은 "조금", 0.25 이상 0.75 미만은 "꽤", 0.75 이상은 "아주"다. 없으면 `nil`이고 칸을 그리지 않는다.
- **미룬 횟수**: `task.skipCount` 그대로. 0도 그린다.
- **초안 표기**(시안에서 확정): `D-3 · 손해 꽤 · 미룬 2번`, 오늘 `D-day`, 지남 `D+2`, 마감 없음 `마감 없음`, 손해 없음이면 그 칸과 구분자를 뺀다.
- **보이는 곳**: 시작 전과 도는 중 펼친 화면의 제목 아래. 이어서 할 일 줄이 있으면 그 아래(순서는 시안에서 확정). 접힌 화면, 시간 끝, 빈 상태에는 없다.
- **다시 그리기**: AppState의 계산 속성이라 할 일, 판단 결과, 오늘이 바뀌면 다시 계산된다. 노치 할 일은 바꾸지 않는다.

## 3. 게이트 규칙 (spec R-306~R-312)

입력 값(AppState가 모아 넘김):

| 값 | 뜻 |
|---|---|
| `isDraft` | 노치 할 일이 시작 전이다 |
| `canQuery` | 물을 수 있다(spec 003 `queryableQuestions != nil`) |
| `score` | `usable[taskID]`(없으면 `nil`) |
| `currentHash` | 그 할 일의 지금 판단 입력 해시 |
| `failedHash` | 보내기 장부에서 그 할 일이 실패로 적힌 해시(없으면 `nil`) |
| `threshold` | `thresholds[model].concrete` |
| `record` | 그 할 일의 `GateRecord`(없으면 새 기록) |
| `waiting` | 이 할 일의 게이트가 제출 뒤 판정을 기다리는 중이다 |

판정(`ConcreteGate.phase(...) -> GatePhase`와 `ConcreteGate.afterAnswer(...) -> GateRecord`):

1. `isDraft`가 아니거나 `record.passed`면 `closed`.
2. `waiting`이 아닐 때: `canQuery`이고 `score`가 있고 `score.concrete < threshold`면 `asking`, 아니면 `closed`.
3. `waiting`일 때:
   - `canQuery`가 아니면 통과(`passed = true`), `closed`.
   - `failedHash == currentHash`면 통과, `closed`.
   - `score?.stateHash == currentHash`이고 `concrete >= threshold`면 통과, `closed`.
   - `score?.stateHash == currentHash`이고 `concrete < threshold`이면, `submissions >= concreteGateMaxSubmissions`면 통과하고 `closed`, 아니면 기다림을 끝내고 `asking`.
   - 그 밖에는 `checking`(새 판단 결과를 기다림). 기다리는 동안 하루가 바뀌거나 일정이 바뀌어 해시가 다시 바뀌어도 같은 규칙으로 새 해시를 기다린다.

동작:

| 동작 | 결과 |
|---|---|
| 제출(빈 줄 아님) | 앞뒤 공백·줄바꿈을 지운 줄을 `firstAction`에 써서 `StoreBatch(updatedTasks:)`로 저장한다. 성공하면 `submissions += 1`, `waiting = true`이고, 할 일 다시 읽기가 `requestScores()`를 부른다. 저장 실패면 횟수를 세지 않고 실패 문구를 보인다 |
| 같은 줄 제출 | 해시가 그대로라 질의가 나가지 않는다. 위 3의 규칙이 지금 판단 결과로 바로 판정한다 |
| "지금은 넘기기" | `passed = true`, `closed`. 첫 행동과 질의는 그대로 |
| 시작 버튼 | 게이트를 닫는다. `passed`는 그대로 `false`, `waiting`은 끝낸다 |
| 노치 할 일이 바뀜 | 게이트를 닫고 `waiting`을 끝낸다. 기록(`submissions`)은 남긴다 |
| 앱 재시작 | 기록이 모두 사라진다 |

- 행동 로그에는 아무것도 쓰지 않는다(R-312). 첫 행동 쓰기 배치에 `newDecisions`를 넣지 않는다.
- 판정 시점: 노치 할 일이 바뀔 때(기존 `session` didSet), 판단 결과를 저장한 뒤, 질의 실패를 장부에 적은 뒤, 할 일 다시 읽기 뒤, `keyNeedsCheck`·`hasKey`가 바뀐 뒤.
- 게이트 입력 칸의 글자: `asking`으로 돌아올 때 마지막에 제출한 줄을 채워 둔다.

## 4. 앱 상태 (AppState에 더함)

- `gateRecords: [TaskID: GateRecord]`와 `gateWaitingTaskID: TaskID?`(메모리, `@ObservationIgnored` 아님. 화면이 읽는다).
- `gatePhase: GatePhase`(계산 속성), `gateDraftText: String`, `gateSaveFailed: Bool`.
- `submitFirstAction(_ text: String) -> Bool`, `skipGate()`. 시작(`start`)과 노치 할 일 변경은 §3 표대로 게이트를 닫는다.
- 지금 판단 입력 해시는 기존 `judgmentStates(checkpoints:)`로 그 할 일만 다시 만든다. 체크포인트는 spec 003 data-model §4처럼 그때그때 읽는다.
- 실패 해시는 보내기 장부 `attempted[id]`에서 `failed == true`인 항목의 `hash`다. 장부를 비우는 동작(키 저장, 다시 물어보기, 활성화의 실패 항목 지우기)은 spec 003 그대로다. 활성화가 실패 항목을 지우기 전에 판정이 먼저 돌아 통과를 정하도록, 실패를 장부에 적는 자리에서 판정을 부른다.
- `reasonLine: String?`(계산 속성): 노치 할 일이 시작 전이나 도는 중이면 `ReasonText.line(ReasonLine.make(...))`, 아니면 `nil`.
- `showsKeyNotice: Bool`: `keyNeedsCheck`와 같다(R-318).
- `settingsTabRequest: SettingsTab?`(research R8).

## 5. 화면 상태 (시안으로 확정)

노치 펼친 화면(`ExpandedView` 새 인자, ADR-0009 값과 콜백만):

| 인자 | 기본값 | 쓰는 곳 |
|---|---|---|
| `reasonLine: String?` | `nil` | 시작 전, 도는 중 |
| `gate: GateInput?` | `nil` | 시작 전. `phase`, `text` 바인딩, `saveFailed`, `onSubmit`, `onSkip` |
| `keyNotice: Bool` | `false` | 빈 상태, 시작 전, 도는 중 |
| `onOpenKeySettings: () -> Void` | 빈 동작 | 키 확인 한 줄의 동작 |

- 시작 버튼 단축키: `draftInput.isEnteringTitle || gate?.phase == .asking`이면 떼고, 아니면 `.defaultAction`.
- 게이트 `checking`일 때 입력 칸은 읽기만이고 확인하는 중 문구를 보인다. 시작 버튼 Enter는 켜진다.

설정 창 할 일 탭(`TaskListTabView` 새 인자): `keyNotice: Bool = false`, `onOpenKeySettings: () -> Void`. 목록 위 한 줄.

온보딩(`OnboardingView` 새 인자): `keyStep: OnboardingKeyInput?`(`hasKey`, `saveFailed`, `onSave: (String) -> Bool`, `issueURL`). `nil`이면 지금처럼 두 단계다(기존 시험 호출 유지). 값이 있으면 세 단계이고 첫 단계가 키다.

| 키 단계 상태 | 보이는 것 |
|---|---|
| 키 없음 | 안내 한 줄, 발급 링크, 가림 입력 칸, "건너뛰기", "다음"(칸이 비면 꺼짐) |
| 저장 실패 | 위와 같고 다시 해 달라는 문구 |
| 이미 있음 | "저장되어 있어요", "다음"(켜짐) |

문구 초안은 시안 `004-mockup.html`에 있고 사람이 확정한다.

## 6. 시험 경계와 기존 기대 출력

- MokaCore 단위 시험(리눅스 `swift test`): `ReasonLine`, `ReasonText`, `ConcreteGate`. 시험 표시 이름은 `FR-04 R-30x`, `FR-13 R-30x`로 시작한다(ADR-0003).
- 앱 시험(`MokaAppTests`, XCTest): 가짜 공급자(`FakeDecisionProvider`, spec 003 research R19 F2)를 붙잡고 풀어 게이트 단계를 확인한다. 실제 시간을 기다리지 않는다. 가짜 키 보관함으로 온보딩 키 단계를 확인한다.
- 스냅샷: 새 상태만 더한다. 기존 참조 이미지는 바뀌지 않는다(research R9).
- 바뀌지 않는 것: spec 001·002·003 시뮬레이터 golden, 스키마 스냅샷, `questions.json`, pytest.
