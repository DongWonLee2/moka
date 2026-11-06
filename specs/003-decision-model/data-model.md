# Data Model: 판단 모델 연동 MVP (spec 003)

규칙의 원본이다. 결정 이유는 [research.md](research.md), 외부 계약은 [contracts/](contracts/). 이름은 GLOSSARY를 따른다. 타입 이름은 구현 PR에서 다듬을 수 있으나 바꾸면 PR "가정"에 적는다.

## 1. MokaCore 값 타입 (새로 둠)

| 타입 | 모양 | 비고 |
|---|---|---|
| `QuestionSet` | `version: String`, `language: String`, `model: String`, `questions: [String: Question]`(키 순서 고정 목록도 함께), `thresholds: [String: [String: Double]]` | `questions.json`을 읽은 값(contracts/questions-json.md). `QuestionSet.bundled()`는 `Bundle.module`에서 읽는다 |
| `Question` | `noul(instructions)`, `score(instructions, criteria: [String])`, `choice(instructions, criteria: [(String, String)])` | choice는 이번에 쓰지 않지만 공급자 계약에 둔다 |
| `JudgmentState` | `today: LocalDay`, `weekday: Weekday`, `task: StateTask`, `contexts: [StateContext]`, `checkpoint: StateCheckpoint?` | 판단 입력. 저장하지 않는다 |
| `StateTask` | `title`, `deadline: LocalDay?`, `estMin: Int?`, `firstAction: String?` | 금지 필드 없음(§4) |
| `StateContext` | `name`, `date: LocalDay`, `impact: ContextImpact` | 보낼 때 "조금/꽤/아주" |
| `StateCheckpoint` | `done: String`, `next: String` | 그 할 일의 가장 최근 체크포인트. 두 줄이 모두 비면 넣지 않는다 |
| `DecisionRequest` | `model: String`, `state: StateJSON`(정준 바이트), `questions: QuestionSet` | |
| `DecisionResponse` | `model: String?`, `answers: [String: Answer]` | |
| `Answer` | `noul(p)`, `score(score, confidence, probabilities: [Int: Double])`, `choice(choice, confidence, probabilities: [String: Double])` | |
| `DecisionError` | `missingKey`, `unauthorized`(401·403), `rateLimited`(429), `overloaded`(529), `timeout`, `network`, `server(status)`, `malformed(prefix)` | `prefix`는 응답 원문 앞 100자까지. 할 일 제목은 넣지 않는다 |
| `protocol DecisionProvider: Sendable` | `var name: String { get }`, `func decide(_: DecisionRequest) async throws(DecisionError) -> DecisionResponse` | 앱 `TypeSafeProvider`의 `name`은 `"typesafe"`. 가짜는 `FakeDecisionProvider`(정한 답 또는 정한 오류를 돌려줌) |
| `TaskScore` | `taskID`, `questionVersion`, `provider`, `modelSnapshot: String?`, `urgency`(0~1), `impact`(0~1), `concrete`(0~1), `avoiding`(0~1), `probsJSON: String`, `stateHash: String`, `scoredAt: Date` | `scores` 한 줄. priority는 없다 |
| `protocol ScoreStore: AnyObject` | `func scores() throws -> [TaskID: TaskScore]`, `func upsertScore(_: TaskScore) throws` | 메모리 `InMemoryScoreStore`(MokaCore), GRDB `GRDBScoreStore`(MokaStore). 지우기 메서드 없음 |
| `protocol KeyStore: AnyObject` | `func hasKey() throws -> Bool`, `func read() throws -> String?`, `func save(_: String) throws`, `func delete() throws` | 가짜 `InMemoryKeyStore`(MokaCore). 앱 `KeychainKeyStore` |
| `ScoreTrigger` | `taskSaved(TaskID)`, `contextsChanged`, `keySaved`, `launch`, `dayStarted`, `retry` | §6 |

`Defaults`에 더하는 값(이전 값 없음, 새 값): `weightUrgency 1.0`, `weightImpact 0.7`, `weightAging 0.8`, `avoidingAgingFactor 1.5`, `rescoreAfter 6시간`, `decisionTimeout 3초`. 질문 임계값은 `questions.json`(AGENTS.md).

`SchedulerChoice`에 `priorityRotateV0 = "priority_rotate_v0"`를 더한다. `rotateByIDV0`는 남긴다(이전 로그를 읽어야 한다).

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

- CHECK 없음(사용자 승인 조건). `provider`에 `fallback`은 들어가지 않는다(폴백은 점수를 저장하지 않는다).
- `upsertScore`는 `INSERT … ON CONFLICT(task_id) DO UPDATE`로 덮어쓴다. 이전 값은 남기지 않는다(버튼을 누른 순간의 판단은 행동 로그에 남는다).
- 마이그레이션 이름 시험 리터럴을 `["v1_settings", "v2_tasks_contexts_checkpoints_log", "v3_scores"]`로 덧붙인다(ADR-0007). `schema/moka-schema.sql` 스냅샷을 갱신한다.
- 시각은 spec 002처럼 UTC 초 문자열(`UTCTimestamp`).
- `probs_json`은 응답 답을 정준 JSON으로 적은 것이다: 질문 이름 오름차순 객체, noul은 `{"noul":p}`, score는 `{"score":s,"confidence":c,"probabilities":{"0":p0,…}}`. 행동 로그 `probs_json`에 그대로 옮긴다. 할 일 제목·체크포인트 본문은 없다.
- pytest: `scores` 열 이름 집합 시험(`tuning/tests/test_schema_contract.py`에 덧붙임), `questions.json`을 같은 경로로 읽는 시험.

## 3. 점수 규칙

- **해석**(`ScoreRules.score(from:questions:state:now:)`): 질문 넷이 모두 있고 타입이 맞고 확률이 0~1, score 값이 0~(옵션 수 − 1) 안이어야 한다. 하나라도 어긋나면 `malformed`로 보고 점수를 만들지 않는다.
- **정규화**: `urgency = score / (urgency 옵션 수 − 1)`(지금 3), `impact = score / (impact 옵션 수 − 1)`(지금 2). noul은 그대로.
- **urgency 하한**: 고르는 날의 오늘(R-114 하루 경계) 기준으로 마감이 내일 이하이거나 지났으면 urgency를 1로 본다. 저장 값은 모델 값 그대로이고, 하한은 priority 계산 때 적용한다(날이 바뀌면 달라지므로).
- **aging** = `skipCount × (avoiding ≥ thresholds[model].avoiding ? 1.5 : 1)`. 이월 횟수는 마일스톤 4.
- **priority** = `1.0 × urgency' + 0.7 × impact + 0.8 × aging`(urgency'는 하한 적용 뒤). 고를 때마다 계산한다.
- **쓰는 점수**: 키가 있고, 그 할 일의 `TaskScore`가 있고, `questionVersion`이 지금 질문 파일 버전과 같을 때만 "점수 있음"이다. 6시간이 지난 점수도 다시 묻기 전까지는 쓴다.

## 4. 판단 입력(state) 조립과 금지 필드

`StateBuilder.state(task:contexts:checkpoints:today:calendar:)`는 다음만 넣는다(R-201).

| 칸 | 값 |
|---|---|
| `today` | `"YYYY-MM-DD (요일)"`, 요일은 일·월·화·수·목·금·토. 오늘은 R-114 하루 경계 |
| `context` | 모든 일정(날짜 오름차순, 같으면 id 순). `{"name","date","impact"}`, impact는 "조금/꽤/아주" |
| `task` | `{"title", "deadline"?, "est_min"?, "first_action"?}`. 값이 없으면 키를 뺀다 |
| `checkpoint` | 그 할 일의 가장 최근 체크포인트 `{"done","next"}`. 없거나 두 줄 모두 비면 키를 뺀다 |

- 넣지 않는 것(헌법 VIII, MUST 시험): 다른 할 일, `skip_count`, `carry_count`, `streak`, 상태, 반복, 이전 확률, 행동 로그, 할 일 id, 만든 시각. 시험은 조립한 JSON의 키 집합이 위 표와 정확히 같은지 본다.
- 바이트는 손으로 조립한다: 키 순서는 위 표 순서(`today`, `context`, `task`, `checkpoint`, 안쪽도 표 순서), 공백 없음, 문자열은 RFC 8259 이스케이프(`"`, `\`, U+0000~U+001F), 그 밖의 문자는 UTF-8 그대로. 실수는 넣지 않는다(est_min은 정수).

## 5. 판단 입력 해시

- `stateHash = FNV-1a 64(state 바이트)`, 소문자 16진수 16자. offset basis `0xcbf29ce484222325`, prime `0x100000001b3`.
- 같은 바이트는 리눅스·macOS에서 같은 해시를 낸다: golden 시험(정한 state 셋 → 정한 해시 셋)을 `swift test`(리눅스 CI)와 macOS 로컬에서 돌린다.
- 보안용이 아니다(R12).

## 6. 누구를 물을지와 답 받기

`ScoringPlan.targets(trigger:tasks:scores:hasKey:questionVersion:now:)` → 물을 할 일 id 목록(id 오름차순).

| 트리거 | 대상 |
|---|---|
| 키 없음 | 늘 빈 목록(부르지 않는다) |
| `taskSaved(id)` | 그 할 일(대기·진행 중일 때) |
| `contextsChanged`, `keySaved` | 대기·진행 중 할 일 전부 |
| `launch`, `dayStarted` | 대기·진행 중 할 일 가운데 점수 없음, `scoredAt`이 6시간보다 오래됨, 질문 버전 다름 |
| `retry` | 대기·진행 중 할 일 가운데 점수 없음(버전 다름 포함) |

- 완료·버림은 묻지 않는다. `dayStarted`는 활성화 판정이 하루 경계를 넘겼을 때 한 번이다(spec 002 R-113과 같은 판정, 반복 리셋 뒤).
- **답 받기**(`ScoringPlan.accepts(requestHash:currentState:)`): 답이 왔을 때 그 할 일의 지금 state를 다시 조립해 해시가 요청 때와 같을 때만 저장한다. 다르면(질의 중 고침·일정 변경) 버린다. 그 할 일이 버림·완료면 버린다. 같은 할 일에 질의가 겹치면 각 답이 이 판정을 따로 거치므로 마지막 내용과 맞는 답만 남는다.
- 실패(`DecisionError` 아무것)는 저장하지 않는다. `unauthorized`면 AppState의 "키 확인 필요" 표시를 켜고, 다음 성공이면 끈다.

## 7. 노치 순서와 고르기

`PriorityOrder.order(tasks:scores:hasKey:questions:today:calendar:)` → 대기 할 일 순서.

1. 점수 있는 대기 할 일: priority 내림차순, 같으면 마감 이른 순(마감 없음 뒤), 같으면 id 순.
2. 점수 없는 대기 할 일: 마감 오름차순(마감 없음 맨 뒤), 같으면 id 순.

`PriorityRotateRule.pick(order:after:)`: `after`가 없거나 순서에 없으면 1위, 있으면 그다음(끝이면 1위). 후보가 하나면 그 할 일. `NotchSession.picked`와 `nextMark`가 `RotateByIDRule` 대신 이것을 쓴다. `NotchSession`에 `SessionInput`으로 점수·키 유무·질문 세트·오늘을 넘긴다. 도는 중·시간 끝·초안 상태는 바꾸지 않는다(고르기는 빈 상태에서만, spec 002와 같음). "다른 할 일" 목록(`OtherTaskList`)은 그대로 급한 순이다.

## 8. 행동 로그 판단 칸

`NotchSession.logLine`이 줄을 만들 때:

| 그 할 일 | `judgment` | `model_snapshot` | `scheduler_choice` |
|---|---|---|---|
| 점수 있음(§3) | `provider`, `questionVersion`, `probsJSON`, `stateHash`는 저장된 `TaskScore` 값 | `TaskScore.modelSnapshot` | `priority_rotate_v0` |
| 점수 없음 | `provider = "fallback"`, 나머지 비움 | 비움 | `priority_rotate_v0` |

spec 002 F5 CHECK(공급자가 없으면 나머지도 비어야 함)에 걸리지 않는다. 제목·두 줄 본문은 판단 칸에 없다.

## 9. 앱 상태 (AppState에 더함)

- 저장소: `AppStorage`에 `scores: (any ScoreStore)?`를 더한다(DB를 열지 못하면 `nil`, spec 002 R-119처럼 메모리로 대체하지 않는다). `keyStore: any KeyStore`.
- 질의: 트리거마다 `ScoringPlan.targets` → 할 일마다 state 조립·해시 → `Task { try await provider.decide(…) }` → MainActor에서 `ScoreRules.score` → `accepts` → `upsertScore` → 점수 다시 읽기 → "다음" 표시 다시 계산. 질의 중에도 노치·타이머·버튼은 막히지 않는다.
- 화면 값: `hasKey`, `keyNeedsCheck`(401 뒤), 할 일별 priority(설정 창 칸, 점수 없으면 `nil`).
- 연결 지점: `addTask`·`editTask` 뒤 `taskSaved`, `addContext`·`editContext`·`deleteContext(s)` 뒤 `contextsChanged`, 키 저장 뒤 `keySaved`, 키 지움 뒤 질의 없음(순서만 다시), `launch()` 끝 `launch`, `activate()`에서 하루를 넘겼으면 `dayStarted`, 버튼 `retry`.

## 10. 설정 창 화면 상태 (시안으로 확정)

| 상태 | 기본 탭 키 칸 |
|---|---|
| 키 없음 | 안내 한 줄 + 붙여 넣기 칸(가림 입력) + "저장"(칸이 비면 꺼짐) |
| 키 있음, 할 일 있음 | "저장돼 있어요" + "지우기" + "다시 물어보기"(점수 없는 할 일이 없으면 꺼짐) |
| 키 있음, 할 일 없음 | 위 + "할 일을 저장하면 키가 맞는지 확인돼요" |
| 키 확인 필요(401) | 위 + 키를 다시 확인해 달라는 문구(경고색) |
| 저장 불가(R-119) | 키 칸은 보이되 "다시 물어보기" 꺼짐 |

할 일 탭: 줄마다 priority 칸(소수 둘째 자리, 점수 없으면 빈칸). 문구는 시안에서 정하고 해요체다.
