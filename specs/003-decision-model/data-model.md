# Data Model: 판단 모델 연동 MVP (spec 003)

규칙의 원본이다. 결정 이유는 [research.md](research.md), 외부 계약은 [contracts/](contracts/). 이름은 GLOSSARY를 따른다. 타입 이름은 구현 PR에서 다듬을 수 있으나 바꾸면 PR "가정"에 적는다.

## 1. MokaCore 값 타입 (새로 둠)

| 타입 | 모양 | 비고 |
|---|---|---|
| `QuestionSet` | `version: String`, `language: String`, `model: String`, `questions: [String: Question]`, `thresholds: [String: [String: Double]]` | `questions.json`을 읽은 값(contracts/questions-json.md). `QuestionSet.bundled() throws`는 `Bundle.module`에서 읽고 내용 해석 실패만 던진다. 번들이 없으면 SwiftPM 생성 코드가 프로세스를 멈추는데, 이는 빌드 결함으로 보고 단위 1a의 리눅스 CI와 앱 시험 번들에서 각각 `bundled()`를 부르는 시험으로 확인한다(research R19 F4). 임계값은 `thresholds[model]` |
| `Question` | `noul(instructions)`, `score(instructions, criteria: [String])` | noul은 "이 문장이 참일 확률" 하나를 받는 질문, score는 낮음→높음 옵션 중 어디인지를 받는 질문(contracts/decision-provider.md "질문 타입") |
| `JudgmentState` | `today: LocalDay`, `weekday: Weekday`, `task: StateTask`, `contexts: [StateContext]`, `checkpoint: StateCheckpoint?` | 판단 입력. 저장하지 않는다. `JudgmentState.build(task:contexts:checkpoints:today:calendar:)`로 만들고 `bytes`(정준 바이트)·`hash`를 낸다(§4·§5) |
| `StateTask` | `title`, `deadline: LocalDay?`, `estMin: Int?`, `firstAction: String?` | 금지 필드 없음(§4) |
| `StateContext` | `name`, `date: LocalDay`, `impact: ContextImpact` | 보낼 때 "조금/꽤/아주" |
| `StateCheckpoint` | `done: String`, `next: String` | §4 |
| `DecisionRequest` | `taskID: TaskID`, `model: String`, `state: [UInt8]`(정준 바이트), `questions: QuestionSet` | `taskID`는 앱·가짜가 답을 짝짓는 데만 쓰고 HTTP 본문에는 넣지 않는다 |
| `DecisionResponse` | `model: String?`, `answers: [String: Answer]` | |
| `Answer` | `noul(p)`, `score(score, confidence, probabilities: [Int: Double])` | |
| `DecisionError` | `missingKey`, `unauthorized`(401·403), `rateLimited`(429), `overloaded`(529), `timeout`, `network`, `server(status)`, `malformed` | 동작은 셋으로 나뉜다: `unauthorized`는 질의를 멈추고 문구를 켬(§6), 나머지는 그 할 일 실패로 기록(§6). 종류는 로그용이다 |
| `protocol DecisionProvider: Sendable` | `var name: String { get }`, `func decide(_: DecisionRequest, key: String) async throws(DecisionError) -> DecisionResponse` | 키는 요청에 넣지 않고 별도 인자로 받는다(요청은 해시·로그와 닿으므로, research R19 F1). 공급자는 키 보관함을 들지 않는다. 앱 `TypeSafeProvider`(상태 없는 `struct`)의 `name`은 `"typesafe"` |
| `actor FakeDecisionProvider: DecisionProvider` | `nonisolated let name`, 할 일별 정한 답 또는 오류, `hold()`(이후 답을 붙잡음), `release(taskID:)`·`releaseAll()`, `maxInFlight`(동시에 진행 중이던 최대 개수), `calls`(받은 요청의 할 일 id 목록) | 시험·`moka-sim`용. 붙잡기로 "질의 중 고침"과 동시 4를 실제 시간 없이 재현한다(research R19 F2). 요청이 어느 할 일인지는 `DecisionRequest.taskID`로 안다(공급자 본문에는 넣지 않음) |
| `TaskScore` | `taskID`, `questionVersion`, `provider`, `modelSnapshot: String?`, `urgency`(0~1), `impact`(0~1), `concrete`(0~1), `avoiding`(0~1), `probsJSON: String`, `stateHash: String`, `scoredAt: Date` | `scores` 한 줄. priority는 없다 |
| `protocol ScoreStore: AnyObject` | `func scores() throws -> [TaskID: TaskScore]`, `func upsertScore(_: TaskScore) throws` | 메모리 `InMemoryScoreStore(tasks: InMemoryTaskRepository)`(MokaCore), GRDB `GRDBScoreStore`(MokaStore). 없는 할 일이면 둘 다 `StoreError.taskNotFound`(기존 `taskExists` 무늬, research R19 F8). 지우기 메서드 없음 |
| `protocol KeyStore: AnyObject` | `func hasKey() throws -> Bool`, `func read() throws -> String?`, `func save(_: String) throws`, `func delete() throws` | MainActor(AppState)에서만 부른다. 가짜 `InMemoryKeyStore`(MokaCore, 정한 오류를 던질 수 있음). 앱 `KeychainKeyStore`. `save`는 같은 항목이 있으면 덮어쓴다(`errSecDuplicateItem`이면 `SecItemUpdate`) |
| `SessionScoring` | `usable: [TaskID: TaskScore]`, `questions: QuestionSet`, `today: LocalDay` | `SessionInput`에 `scoring: SessionScoring? = nil`로 더한다. `nil`이면 모든 할 일이 점수 없음(마감 순). 기존 호출 셋(`AppState.input(at:)`, `SimStorageRunner.input()`, 시험 `Fake.input`)은 고치지 않아도 컴파일되고 키 없는 순서로 돈다 |

`Defaults`에 더하는 값(이전 값 없음, 새 값): `weightUrgency 1.0`, `weightImpact 0.7`, `weightAging 0.8`, `avoidingAgingFactor 1.5`, `decisionTimeout 3초`, `maxConcurrentDecisions 4`. 질문 임계값은 `questions.json`(AGENTS.md).

`SchedulerChoice`에 `priorityRotateV0 = "priority_rotate_v0"`를 더한다. `rotateByIDV0`는 남긴다(이전 로그를 읽어야 한다). 앱과 시뮬레이터의 새 로그 줄은 늘 `priorityRotateV0`이다.

## 2. 스키마: 마이그레이션 `v3_scores`

```sql
CREATE TABLE scores(
  task_id INTEGER PRIMARY KEY NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT,
  question_version TEXT NOT NULL,
  provider TEXT NOT NULL,
  model_snapshot TEXT,
  urgency REAL NOT NULL,
  impact REAL NOT NULL,
  concrete REAL NOT NULL,
  avoiding REAL NOT NULL,
  probs_json TEXT NOT NULL,
  state_hash TEXT NOT NULL,
  scored_at TEXT NOT NULL
);
```

- `Migrations.swift`에는 기존 규칙(10행 주석)대로 위 문장을 한 줄 문자열로 넣는다(스냅샷 바이트 비교). 위 여러 줄은 읽기용이다.
- CHECK 없음(사용자 승인 조건). `provider`에 `fallback`은 들어가지 않는다(폴백은 판단 결과를 저장하지 않는다).
- `upsertScore`는 `INSERT … ON CONFLICT(task_id) DO UPDATE`로 덮어쓴다. 이전 값은 남기지 않는다(버튼을 누른 순간의 판단 결과는 행동 로그에 남는다).
- 마이그레이션 이름 시험 리터럴을 `["v1_settings", "v2_tasks_contexts_checkpoints_log", "v3_scores"]`로 덧붙인다(ADR-0007). `schema/moka-schema.sql` 스냅샷을 갱신한다.
- 시각은 spec 002처럼 UTC 초 문자열(`UTCTimestamp`).
- `probs_json`은 응답 답을 정준 JSON으로 적은 것이다: 질문 이름 오름차순 객체, noul은 `{"noul":p}`, score는 `{"score":s,"confidence":c,"probabilities":{"0":p0,…}}`, `probabilities` 키는 숫자 오름차순("2"가 "10"보다 앞). 숫자는 Swift `String(describing: Double)`(왕복 가능한 최단 표기, 예 `0.4`, `1.0`, `1e-05`)로 적는다(research R19 F6). 같은 입력은 리눅스·macOS에서 같은 문자열이어야 하므로 golden 시험을 둘 다에서 돌린다. 행동 로그 `probs_json`에 그대로 옮긴다. 할 일 제목·체크포인트 본문은 없다.
- pytest: `scores` 열 이름 집합 시험(`tuning/tests/test_schema_contract.py`에 덧붙임), `questions.json`을 같은 경로로 읽는 시험, `probs_json` 예시(지수 표기·`1.0` 포함)를 `json.loads`로 읽는 시험.
- `GRDBScoreStore`는 시각을 기존 `Row.timestamp`·`UTCTimestamp`(`GRDBTaskRepository.swift`)로 읽고 쓴다.

## 3. 판단 결과 규칙

- **해석**(`ScoreRules.score(taskID:response:questions:provider:stateHash:now:)`): 질문 넷이 모두 있고 타입이 질문 파일과 맞고 noul 확률이 0~1, score 값이 0~(옵션 수 − 1), `confidence`가 있고 0~1, `probabilities` 키가 정확히 "0"~"옵션 수 − 1"이고 값이 0~1이어야 한다. 하나라도 어긋나면 `malformed`로 보고 판단 결과를 만들지 않는다.
- **정규화**: `urgency = score / (urgency 옵션 수 − 1)`(지금 3), `impact = score / (impact 옵션 수 − 1)`(지금 2). noul은 그대로. 저장하는 값은 하한을 적용하기 전의 정규화 값이다.
- **urgency 하한**: 고르는 날의 오늘(spec 002 R-114 하루 경계) 기준으로 마감이 내일까지(지난 마감 포함)이면 urgency를 1로 본다. 날이 바뀌면 달라지므로 priority 계산 때 적용한다.
- **aging** = `skipCount × (avoiding ≥ thresholds[model].avoiding ? 1.5 : 1)`. 이월 횟수는 마일스톤 4.
- **priority** = `1.0 × urgency' + 0.7 × impact + 0.8 × aging`(urgency'는 하한 적용 뒤). 고를 때마다 계산한다.
- **쓰는 판단 결과**(`ScoreRules.usable(scores:hasKey:questionVersion:) -> [TaskID: TaskScore]`): 키가 있고 `questionVersion`이 지금 질문 파일 버전과 같은 판단 결과만 남긴다. 판단 입력이 바뀐 판단 결과(해시가 다름)도 다시 묻기 전까지는 쓴다. 순서·고르기·로그 함수는 이 사전만 받는다.

## 4. 판단 입력 조립과 금지 필드

`StateBuilder.state(task:contexts:checkpoints:today:calendar:)`는 다음만 넣는다(spec R-201).

| 칸 | 값 |
|---|---|
| `today` | `"YYYY-MM-DD (요일)"`, 요일은 일·월·화·수·목·금·토(`LocalDay.weekday(calendar:)`). 오늘은 spec 002 R-114 하루 경계(`MokaClock` + `DayStart`) |
| `context` | 모든 일정(날짜 오름차순, 같으면 id 순). `{"name","date","impact"}`, date는 `YYYY-MM-DD`, impact는 "조금/꽤/아주"(화면과 같은 `ContextText.impact(_:)`를 쓴다. 화면 글자를 바꾸면 질문 버전을 올린다) |
| `task` | `{"title", "deadline"?, "est_min"?, "first_action"?}`. deadline은 `YYYY-MM-DD`. 값이 없으면 키를 뺀다 |
| `checkpoint` | 그 할 일의 체크포인트 가운데 두 줄 중 하나라도 적힌 것의 id가 가장 큰 것 `{"done","next"}`. 없으면 키를 뺀다. 종료·잠자기처럼 두 줄이 빈 체크포인트는 고르지 않는다 |

- 넣지 않는 것(헌법 VIII, MUST 시험): 다른 할 일, `skip_count`, `carry_count`, `streak`, 상태, 반복, 이전 확률, 행동 로그, 할 일 id, 만든 시각. 시험은 조립한 JSON의 키 집합이 위 표와 정확히 같은지 본다.
- 바이트는 손으로 조립한다: 키 순서는 위 표 순서(`today`, `context`, `task`, `checkpoint`, 안쪽도 표 순서), 공백 없음, 문자열은 RFC 8259 이스케이프(`"`, `\`, U+0000~U+001F), 그 밖의 문자는 UTF-8 그대로. 실수는 넣지 않는다(est_min은 정수).
- 체크포인트는 `TaskRepository.checkpoints()` 전체를 읽어 할 일별로 고른다. AppState에 사본을 두지 않고 질의를 보낼 때와 답을 받을 때마다 읽는다(`lifecycleCheckpoint`처럼 `reloadTasks`를 거치지 않는 쓰기가 있어서, research R19 F9). 할 일 수십 건, 체크포인트 수백 건 규모라 받아들인다(색인·새 메서드 없음).

## 5. 판단 입력 해시

- `stateHash = FNV-1a 64(state 바이트)`, 소문자 16진수 16자. offset basis `0xcbf29ce484222325`, prime `0x100000001b3`.
- 같은 바이트는 리눅스·macOS에서 같은 해시를 낸다: golden 시험(정한 state 셋 → 정한 해시 셋)을 `swift test`(리눅스 CI)와 macOS 로컬에서 돌린다.
- 보안용이 아니다(research R12).

## 6. 다시 물을 할 일과 보내기 (spec R-206·R-207)

**다시 물을 할 일**(`ScoringPlan.needsQuery(tasks:scores:states:questionVersion:)` → id 오름차순): 대기·진행 중 할 일 가운데 다음 하나에 해당하는 것.
- 판단 결과가 없다
- `questionVersion`이 지금 버전과 다르다
- 지금 판단 입력의 해시가 저장된 `stateHash`와 다르다

**묻지 않는 경우**(AppState가 먼저 본다): 판단 기능 꺼짐(`decision` 주입 없음 또는 질문 파일 해석 실패, §9), 키 없음, `keyNeedsCheck`(401 뒤 키를 다시 저장하기 전), 판단 결과 저장소 없음(앱 DB를 열 수 없음). 보내기 직전 `KeyStore.read()`를 한 번 부르고, 던지거나 `nil`이면 보내지 않는다(`hasKey = false`로 고침, 장부에 적지 않음).

**보내기 장부**(AppState 메모리, 저장하지 않음): `attempted: [TaskID: (hash: String, failed: Bool)]`.
- 실제로 보낼 때(작업 그룹에 넣는 순간) `attempted[id] = (지금 해시, false)`. 이미 같은 해시로 적혀 있으면(실패 여부와 상관없이) 보내지 않는다.
- 실패(`unauthorized` 아님)하거나 `upsertScore`가 던지면 `failed = true`로 바꾸고 종류만 로그에 남긴다.
- 활성화 때, 보내기 전에 `failed == true`인 항목을 지운다(실패한 할 일은 다음 활성화 때 한 번 다시).
- 키 저장, "다시 물어보기", 앱 재시작(메모리라 저절로)에는 장부를 비운다.
- `unauthorized`면 `keyNeedsCheck = true`로 두고 아직 보내지 않은 대상은 보내지 않는다(장부에도 적지 않는다). 이미 떠난 질의의 답은 받기 판정대로 처리한다. 키를 저장하거나 지우면 `false`로 돌린다. `keyNeedsCheck`인 동안 "다시 물어보기"는 꺼진다(research R19 F5).

**묻는 때**(같은 함수 `@discardableResult func requestScores() -> Task<Void, Never>?` 하나를 부름, 보낼 것이 없으면 `nil`. 앱 시험은 돌려받은 `Task`의 `value`를 기다린다): 할 일 다시 읽기(`reloadTasks`, 노치 빠른 입력·버튼·설정 창 쓰기 모두 거침) 뒤, 일정 다시 읽기(`reloadContexts`) 뒤, 활성화(`activate`) 끝, 키 저장 뒤, "다시 물어보기".

**보내기**: 대상마다 판단 입력을 조립·해시하고, `Task` 하나 안에서 `withTaskGroup`으로 진행 중인 질의가 `maxConcurrentDecisions`(4)개를 넘지 않게 하나가 끝날 때마다 다음을 넣는다(묶음 단위가 아니다). 취소·우선순위·백오프 없음. 답 받기와 저장은 MainActor에서 답마다 한다.

**답 받기**(`ScoringPlan.accepts(requestHash:currentHash:taskStatus:)`, MainActor): 답이 왔을 때 그 할 일의 지금 판단 입력을 다시 조립해 해시가 요청 때와 같고, 할 일이 대기·진행 중일 때만 `ScoreRules.score` → `upsertScore` 한다. 다르면 버린다(질의 중 고침·일정 변경·버림·완료). 같은 할 일에 질의가 겹치면 각 답이 이 판정을 따로 거치므로 지금 입력과 맞는 답만 남는다.

## 7. 노치 순서와 고르기 (spec R-208·R-209)

`PriorityOrder.order(tasks:usable:questions:today:calendar:)` → 대기 할 일 순서.

1. 점수 있는 대기 할 일(`usable`에 있음): priority 내림차순, 같으면 아래 2의 비교.
2. 점수 없는 대기 할 일: 마감 오름차순(마감 없음 맨 뒤), 같으면 id 순. 이 비교는 기존 `TaskListView.rows(order: .deadline)`의 비교(`Sources/MokaCore/TaskListView.swift`)를 꺼내 함께 쓴다(`OtherTaskList`도 쓰는 것).

`PriorityRotateRule.pick(order:after:)`: `after`가 없거나 순서에 없으면(완료·버림 포함) 1위, 있으면 그다음(끝이면 1위). 후보가 하나면 그 할 일. `NotchSession.picked`·`nextMark`·`logLine`과 `SimStorageRunner`가 `RotateByIDRule` 대신 이것을 쓴다. `NotchSession`에는 `SessionInput.scoring`으로 `usable` 사전·질문 세트·오늘을 넘긴다.

- spec 002와 달라지는 것(사용자 확인 2026-11-07, research R19 F7): 커서의 할 일을 버리면 spec 002는 "그다음 큰 id"를 골랐지만(`TaskRulesTests` `droppedPreviousStillAdvances`), 이제는 1위를 고른다. `RotateByIDRule`과 그 시험은 단위 2에서 지우고 PR에 이유를 적는다. `SchedulerChoice.rotateByIDV0` 값은 남긴다.

- 순서는 버튼 처리(미룬 횟수 반영)를 저장한 뒤의 할 일로 계산한다. 기존 패턴(커밋 뒤 `pickIfEmpty`)과 같다.
- 실행 중·시간 끝·초안 상태는 바꾸지 않는다(고르기는 빈 상태에서만, spec 002와 같음).
- "다른 할 일" 목록(`OtherTaskList`)은 그대로 급한 순이다.
- 키가 없으면 `usable`이 비어 모든 할 일이 2의 순서다. spec 002의 만든 순서 순환을 대신한다(spec R-209). 그래서 spec 002 storage 시뮬레이터 golden의 기대 출력이 바뀐다(§11).

## 8. 행동 로그 판단 칸 (spec R-212)

`NotchSession.logLine`이 줄을 만들 때:

| 그 할 일 | `judgment` | `model_snapshot` | `scheduler_choice` |
|---|---|---|---|
| `usable`에 있음 | `provider`, `questionVersion`, `probsJSON`, `stateHash`는 저장된 `TaskScore` 값 | `TaskScore.modelSnapshot` | `priority_rotate_v0` |
| 없음 | `provider = "fallback"`, 나머지 비움 | 비움 | `priority_rotate_v0` |

spec 002 F5 CHECK(공급자가 없으면 나머지도 비어야 함)에 걸리지 않는다. 제목·두 줄 본문은 판단 칸에 없다.

## 9. 앱 상태 (AppState에 더함)

- 저장소: `AppStorage`에 `scores: (any ScoreStore)? = nil`만 더한다(DB를 열지 못하면 `nil`, spec 002 R-119처럼 메모리로 대체하지 않는다). 기존 3인자 생성과 `AppStorage.open`의 실패 경로는 그대로 컴파일된다.
- 판단 주입: `struct DecisionSetup { keyStore: any KeyStore; provider: any DecisionProvider; questions: QuestionSet? }`를 `AppState.init(..., decision: DecisionSetup? = nil)`로 받는다. `nil`이면 판단 기능 꺼짐(기존 앱 시험은 그대로). `MokaApp`이 DB 열기와 상관없이 `DecisionSetup(keyStore: KeychainKeyStore(), provider: TypeSafeProvider(), questions: try? QuestionSet.bundled())`을 만든다. `questions`가 `nil`(해석 실패)이면 판단 기능을 끄고 로그 한 줄을 남긴다. `AppState`는 `TypeSafeProvider`·`KeychainKeyStore`를 직접 가리키지 않는다(앱 시험 번들이 그 파일을 컴파일하지 않는다, research R19 F3).
- 메모리 값: `hasKey`(`launch()` 첫머리·키 저장·키 지움 때 `KeyStore.hasKey()`로 갱신, 던지면 `false`. 첫 `requestScores()`보다 먼저 읽는다), `keyNeedsCheck`, `keyActionFailed`(저장·지우기가 던지면 `true`, 다음 성공에 `false`), `attempted`(§6), `scores` 사전(`launch()`와 답을 저장한 뒤 저장소에서 다시 읽음, 읽기가 던지면 빈 사전과 로그).
- 질의 흐름은 §6. 키는 AppState가 보내기 직전 `KeyStore.read()`로 읽어 `decide(_:key:)`에 넘긴다.
- 키 입력: 붙여 넣은 값의 앞뒤 공백·줄바꿈을 지우고, 비면 "저장"을 끈다.
- 답을 저장한 뒤 `scores`를 다시 읽고 "다음" 표시와 설정 창 priority 칸을 다시 계산한다. 질의 중에도 노치·타이머·버튼은 막히지 않는다.

## 10. 설정 창 화면 상태 (시안으로 확정)

| 상태 | 기본 탭 키 칸 |
|---|---|
| 키 없음 | 안내 한 줄 + 붙여 넣기 칸(가림 입력) + "저장"(칸이 비면 꺼짐) |
| 키 있음, 할 일 있음 | "저장돼 있어요" + "지우기" + "다시 물어보기"(다시 물을 할 일이 없으면 꺼짐) |
| 키 있음, 할 일 없음 | 위 + "할 일을 저장하면 키가 맞는지 확인돼요" |
| 키 확인 필요(401) | 위 + 키를 다시 확인해 달라는 문구(경고색). "다시 물어보기"는 꺼짐 |
| 저장·지우기 실패 | 그 상태 + 다시 해 달라는 문구 |
| 저장 불가(spec 002 R-119) | 키 칸은 보이되 "다시 물어보기" 꺼짐 |

상태 여섯의 이름: 키 없음, 저장됨, 저장됨·할 일 없음, 키 확인 필요, 저장·지우기 실패, 저장 불가.

할 일 탭: 줄마다 priority 칸(소수 둘째 자리 반올림해 둘째 자리까지 표시, 예 `1.20`, 점수 없으면 빈칸). 서식은 MokaCore `TaskRowText`에 함수로 둔다. 문구는 시안에서 정하고 해요체다.

뷰 인자(ADR-0009 경계, 값과 콜백만): `TaskListTabView`에 `priorities: [TaskID: Double]`, `BasicTabView`에 `keyState: KeyFieldState`(위 여섯)와 `onSaveKey: (String) -> Void`, `onDeleteKey`, `onRetry`, `canRetry: Bool`. 값은 `App/Sources/Settings/SettingsView.swift`가 AppState에서 꺼내 넘긴다. 기존 스냅샷 호출(`SettingsSnapshotTests`)은 새 인자의 기본값으로 그대로 두고, 참조 이미지가 바뀌면 PR에 이유를 적는다.

## 11. 기존 기대 출력 갱신 (사용자 결정 2026-11-07)

- 바뀌는 것: spec 002 storage 시뮬레이터 golden(`Tests/MokaCoreTests/Fixtures/sim/storage-*.expected.jsonl`)의 `notch_task` 순서와 `decision.scheduler_choice`(`rotate_by_id_v0` → `priority_rotate_v0`). 키가 없으므로 마감일 순이 된다. 시나리오 입력은 지우거나 바꾸지 않는다.
- 바뀌지 않는 것: spec 001 타이머 golden(storage 아님), 이미 쌓인 앱 DB의 `rotate_by_id_v0` 로그 줄.
- 같은 PR에서 계약 문서의 예시·설명도 고친다: spec 002 `contracts/moka-sim-v1-additions.md`의 `RotateByIDRule`·`rotate_by_id_v0` 서술, spec 001 `contracts/moka-sim-v1.md` storage 절. `ValueTypeTests`의 `SchedulerChoice.allCases` 리터럴은 `["rotate_by_id_v0", "priority_rotate_v0"]`로 바꾼다.
- 갱신은 R-209 구현 PR(단위 2) 안에서 하고, PR 본문에 "spec 002 R-104 → spec 003 R-209 규칙 교체, 테스트 약화 아님"과 바뀐 시나리오·줄 목록을 적는다.
