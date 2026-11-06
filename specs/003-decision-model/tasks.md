---

description: "spec 003 판단 모델 연동 MVP 작업 목록"
---

# Tasks: 판단 모델 연동 MVP (마일스톤 3)

**Input**: `specs/003-decision-model/`의 plan.md, spec.md(R-201~R-216), research.md(R1~R18), data-model.md, contracts/(decision-provider.md, questions-json.md, moka-sim-v1-additions-003.md), quickstart.md. 설정 창 시안 `~/Dev/ai-platform/projects/moka/design/003-mockup.html`(T029에서 만들고 사용자 확정, 저장소 밖)

**Tests**: 넣는다. 헌법 II와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다". 테스트 태스크마다 Red 커밋 → 구현 태스크에서 Green 커밋.

**Organization**: 사용자 이야기(US1~US3)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다(아래 "작업 단위 ↔ Issue").

**원본 규칙**: 규칙·값·모양은 data-model.md와 contracts가 원본이다. 태스크는 절 번호를 가리키고 문장을 옮겨 적지 않는다. 시험은 그 절의 규칙을 빠짐없이 덮는다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US3(spec.md)
- **🔒**: 화면·실제 호출·Keychain을 사람이 확인해야 끝난다
- **👁 사람이 볼 결정**: PR "사람이 볼 결정"에 올린다(스키마 스냅샷, `questions.json`, DecisionProvider 경계, `scheduler_choice` 값, storage golden 갱신, `moka-sim` 계약)
- 이 파일의 "확인 지점"은 Phase 완료 조건이다

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 PRD FR과 R-ID로 시작한다(ADR-0003): R-201·202·203·206 `FR-03`, R-207 `FR-01`, R-204·205·215 `FR-04`, R-208·209 `FR-05`, R-210·211 `FR-14`, R-212 `FR-11`, R-213·214 `FR-16`, R-216 `ADR-0003 R-216:`. Swift Testing. 앱 시험 번들(`MokaAppTests`)만 XCTest.
- 타입·함수 이름과 모양은 data-model §1과 contracts를 따른다. 거기 없는 작은 이름은 구현 PR에서 정하고 PR "가정"에 적는다.
- 시각은 주입한 값과 `GregorianCalendar.make(timeZone:)`(고정 `Asia/Seoul`)로 시험한다. MokaCore에서 `Date()`, `TimeZone.current`, `Calendar.current`를 읽지 않는다. 실제 시간을 기다리지 않는다. 타임아웃은 가짜 공급자가 `.timeout`을 돌려주는 것으로 시험한다.
- 실제 판단 API(TypeSafe, OpenRouter)를 시험·CI·`moka-sim`·무인 실행에서 부르지 않는다. `FakeDecisionProvider`와 `InMemoryKeyStore`만 쓴다. 실제 Keychain과 앱 DB를 시험에서 열지 않는다(SC-207). 에이전트는 Keychain 값을 조회하지 않는다.
- 가짜 할 일·가짜 일정만 쓴다(예: "가짜 할 일 A"). 픽스처의 응답 값도 가짜다.
- 새 의존성을 두지 않는다. `Package.swift`는 T003의 MokaCore 리소스 한 줄만 바꾼다. spec 001 타이머 golden 기대 출력은 바이트 그대로다. spec 002 storage golden은 T024에서만 R-209로 갱신한다(data-model §11). `@unchecked Sendable`을 쓰지 않는다.
- 로그·`moka-sim` 출력·`scores`·행동 로그 판단 칸에 할 일 제목, 체크포인트 본문, 일정 이름, 키 값, 응답 본문을 남기지 않는다.
- 화면 문구는 고객용 해요체이고 확정 시안 글자를 그대로 쓴다.
- 검증 명령: `swift test`, `cd tuning && python3 -m pytest`, 앱은 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

- [ ] T001 기준 상태 확인: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드를 돌려 기존 시험이 PASS인지 기록하고, 기존 golden(`Tests/MokaCoreTests/Fixtures/sim/*.expected.jsonl`) 해시를 PR "완료 증거"에 적는다 〔단위 1a〕
- [ ] T002 [P] `Sources/MokaCore/Defaults.swift`에 data-model §1 "Defaults에 더하는 값"(가중치 셋, `avoidingAgingFactor`, `decisionTimeout`, `maxConcurrentDecisions`)을 더한다. PR "사람이 볼 결정"에 이전 값(없음)·새 값·근거(PRD 7장, research R17 E2)를 적는다 〔단위 1a〕
- [ ] T003 `Sources/MokaCore/Resources/questions.json`을 contracts/questions-json.md "v1 내용" 그대로 만들고, `Package.swift` MokaCore 타깃에 `resources: [.copy("Resources/questions.json")]`를 더한다. `AGENTS.md` 저장소 지도에 "`Sources/MokaCore/Resources/questions.json` 판단 질문 파일(Swift·pytest 공유 계약)" 한 줄을 더한다. 👁 〔단위 1a〕

---

## Phase 2: Foundational (모든 이야기가 기대는 판단 코어와 저장)

**순서**: 단위 1a(T004~T006, T012~T014) → 단위 1b(T007~T009, T015~T018). 단위 3 구현(T019)은 1b 병합 뒤. 단위 3의 Red 시험(T010·T011)은 미리 써도 된다.

### Tests (Red)

- [ ] T004 [P] `Tests/MokaCoreTests/QuestionSetTests.swift`: contracts/questions-json.md "읽기 시험" 전부(넷, 타입 noul·score, `thresholds[model]`, 임계값 범위, blocked 없음, `Bundle.module`에서 읽힘)를 쓰고 실패를 확인한다(`FR-03 R-202`, `FR-03 R-203`) 〔단위 1a〕
- [ ] T005 [P] `Tests/MokaCoreTests/JudgmentStateTests.swift`: data-model §4(키 집합이 표와 정확히 같음 = 금지 필드 없음, 값 없는 칸은 키를 뺌, 일정 순서, 날짜 `YYYY-MM-DD`, impact "조금/꽤/아주", 오늘·요일 문자열, 체크포인트는 두 줄 중 하나라도 적힌 id 최대의 것이고 빈 체크포인트는 고르지 않음, 문자열 이스케이프)와 §5(FNV-1a golden: 정한 state 셋 → 정한 16자 해시)를 쓰고 실패를 확인한다(`FR-03 R-201`, SC-202) 〔단위 1a〕
- [ ] T006 [P] `Tests/MokaCoreTests/ScoreRulesTests.swift`: data-model §3 전부(해석 → `TaskScore`와 `malformed` 경우, 정규화 분모가 옵션 수에서 옴, 저장 값은 하한 전 정규화 값, urgency 하한은 고르는 날 기준, aging과 avoiding 임계값, priority 식, `usable`: 키 없음·버전 다름이면 빠짐, 해시가 달라도 남음)를 쓰고 실패를 확인한다(`FR-04 R-204`) 〔단위 1a〕
- [ ] T007 [P] `Tests/MokaCoreTests/TypeSafeCodecTests.swift`와 픽스처 `Tests/MokaCoreTests/Fixtures/decision/`(가짜 값 응답: 정상, 질문 빠짐, 타입 다름, 범위 밖, `model` 없음, 모르는 칸): contracts/decision-provider.md 요청 본문(디코드 비교, `state`는 정준 바이트 그대로), 응답 해석, 상태 코드 → 오류 표 전부를 쓰고 실패를 확인한다(`FR-14 R-210`, `FR-14 R-211`) 〔단위 1b〕
- [ ] T008 [P] `Tests/MokaCoreTests/ScoringPlanTests.swift`: data-model §6 "다시 물을 할 일"(판단 결과 없음·버전 다름·해시 다름, 완료·버림 제외, 하루가 바뀌면 전부, 같은 입력이면 빈 목록)과 "답 받기"(해시가 같고 대기·진행 중일 때만, 질의 중 고침·일정 변경·버림·완료면 버림, 겹친 질의는 지금 입력과 맞는 답만)를 쓰고 실패를 확인한다(`FR-03 R-206`, spec 엣지) 〔단위 1b〕
- [ ] T009 [P] `Tests/MokaStoreTests/StorageContractTests.swift`에 `ScoreStore` 공용 계약 시험(왕복, 같은 할 일 덮어쓰기, 초 아래 시각, `model_snapshot` 없음)을 `StoreKind.allCases`로 덧붙이고 실패를 확인한다. 이 태스크에서는 `.memory`만 통과 대상이고 `.grdb`는 T019에서 켠다(`FR-04 R-205`) 〔단위 1b·3〕
- [ ] T010 [P] `Tests/MokaStoreTests/MigrationTests.swift`: 이름 리터럴을 `["v1_settings", "v2_tasks_contexts_checkpoints_log", "v3_scores"]`로, 스키마 스냅샷에 data-model §2 표가 있는지 실패로 확인한다(ADR-0007) 〔단위 3〕
- [ ] T011 [P] `tuning/tests/test_schema_contract.py`에 `scores` 열 이름 집합 시험, `tuning/tests/test_questions_contract.py`에 `Sources/MokaCore/Resources/questions.json`을 저장소 루트 상대 경로로 읽어 넷·`thresholds[model]`을 확인하는 시험을 쓰고 실패를 확인한다 〔단위 3〕

### Implementation (Green)

- [ ] T012 `Sources/MokaCore/Decision/QuestionSet.swift`: data-model §1 `QuestionSet`·`Question`(noul·score), `QuestionSet.bundled()`. T004 PASS. `Bundle.module`이 리눅스 CI에서 읽히지 않으면 PR "가정"에 대안을 적고 멈춘다(plan 위험 8) 〔단위 1a〕
- [ ] T013 `Sources/MokaCore/Decision/JudgmentState.swift`: data-model §4 조립·정준 바이트, §5 FNV-1a. T005 PASS 〔단위 1a〕
- [ ] T014 `Sources/MokaCore/Decision/ScoreRules.swift`, `TaskScore`, `Answer`(noul·score), `DecisionResponse`: data-model §3. T006 PASS 〔단위 1a〕
- [ ] T015 `Sources/MokaCore/Decision/DecisionProvider.swift`(프로토콜, `DecisionRequest`, `DecisionError`, `FakeDecisionProvider`: 정한 답·오류, 동시 진행 최대 개수 세기)와 `Sources/MokaCore/Decision/TypeSafeCodec.swift`. T007 PASS. 👁(DecisionProvider 경계) 〔단위 1b〕
- [ ] T016 `Sources/MokaCore/Decision/ScoringPlan.swift`(`needsQuery`, `accepts`). T008 PASS 〔단위 1b〕
- [ ] T017 `Sources/MokaCore/Decision/KeyStore.swift`(프로토콜, `InMemoryKeyStore`: 정한 오류를 던질 수 있음) 〔단위 1b〕
- [ ] T018 `Sources/MokaCore/Storage.swift`에 `ScoreStore`·`InMemoryScoreStore`. T009(`.memory`) PASS 〔단위 1b〕
- [ ] T019 `Sources/MokaStore/Migrations.swift`에 `v3_scores`(data-model §2 SQL 그대로), `Sources/MokaStore/GRDBScoreStore.swift`(UPSERT), `schema/moka-schema.sql` 갱신, `StoreKind.grdb`에 판단 결과 저장소. T009(`.grdb`)·T010·T011 PASS. 👁(스키마 스냅샷) 〔단위 3〕

**확인 지점**: `swift test`·pytest PASS. 판단 코어가 가짜 공급자로 리눅스에서 돈다.

---

## Phase 3: User Story 1 - 키를 넣으면 노치가 priority 순으로 할 일을 띄운다 (Priority: P1) 🎯 MVP

**Goal**: 쓰기·활성화 뒤 질의 → 판단 결과 저장 → 노치가 priority 순으로 고른다. 설정 창에 priority 칸.

**Independent Test**: spec US1 Independent Test.

### Tests (Red)

- [ ] T020 [P] [US1] `Tests/MokaCoreTests/PriorityOrderTests.swift`: data-model §7(점수 있는 할 일 priority 내림차순 → 같으면 마감·id, 점수 없는 할 일 마감 순 뒤, `usable`이 비면 전부 마감 순, 순환: 처음·완료 뒤 1위, 바꾸기·미루기 뒤 버튼 처리 뒤 순서에서 다음, 끝이면 1위, 후보 하나, 미루기로 순서가 바뀌는 예: spec US1-4)를 쓰고 실패를 확인한다(`FR-05 R-208`, `FR-05 R-209`) 〔단위 2〕
- [ ] T021 [P] [US1] `Tests/MokaCoreTests/NotchSessionPriorityTests.swift`: `NotchSession`이 `usable`을 받아 빈 상태에서 1위를 고르고, 바꾸기·미루기 뒤 다음 순위, 초안·실행 중은 판단 결과가 바뀌어도 그대로, `nextMark`가 같은 순서, `logLine` 판단 칸이 data-model §8 표대로(점수 있음·없음), `scheduler_choice` `priority_rotate_v0`. `ValueTypeTests`에 `SchedulerChoice.priorityRotateV0` rawValue를 더한다. 실패를 확인한다(`FR-05 R-209`, `FR-11 R-212`, SC-203) 〔단위 2〕
- [ ] T022 [US1] `App/Tests/MokaAppTests/AppDecisionTests.swift`(XCTest, `FakeDecisionProvider`·`InMemoryScoreStore`·`InMemoryKeyStore` 주입): data-model §6·§9의 묻는 때마다(설정 창 저장, 노치 빠른 입력, 버튼, 일정 변경, 활성화, 하루가 바뀐 뒤 활성화, 키 저장) 가짜 공급자가 다시 물을 할 일로만 불리는지, 같은 입력은 다시 보내지 않는지, 동시 진행이 4를 넘지 않는지, 답이 오면 저장되고 "다음" 표시가 바뀌는지, 질의 중 고침이면 버리는지. 실패를 확인한다(`FR-01 R-207`, `FR-03 R-206`, SC-201, SC-206) 〔단위 4〕

### Implementation (Green)

- [ ] T023 [US1] `Sources/MokaCore/PriorityOrder.swift`(`PriorityOrder`, `PriorityRotateRule`, 마감 순 비교는 `TaskListView`의 비교를 꺼내 함께 씀), `Sources/MokaCore/DecisionLog.swift`에 `priorityRotateV0`. T020 PASS. 👁(`scheduler_choice` 값) 〔단위 2〕
- [ ] T024 [US1] `Sources/MokaCore/NotchSession.swift`: `SessionInput`에 `usable`·질문 세트·오늘을 받아 `picked`·`nextMark`·`logLine`이 data-model §7·§8을 따른다. spec 002 단위 시험은 키 없는 입력에서 순서가 마감 순으로 바뀌는 곳만 기대를 고치고, spec 002 storage 시뮬레이터 golden(`Tests/MokaCoreTests/Fixtures/sim/storage-*.expected.jsonl`)의 기대 출력을 새 규칙으로 갱신한다(data-model §11, 시나리오 입력은 그대로). PR에 "spec 002 R-104 → spec 003 R-209 규칙 교체, 테스트 약화 아님"과 바뀐 시나리오·줄 목록을 적는다. spec 001 타이머 golden은 바이트 그대로. T021 PASS. 👁(golden 갱신) 〔단위 2〕
- [ ] T025 [US1] `App/Sources/AppState.swift`: `AppStorage`에 `scores`·`keyStore`, 공급자 주입(`any DecisionProvider`, 구체 타입을 가리키지 않음), `requestScores()`(data-model §6 묻지 않는 경우·보내기 장부·동시 4·답 받기)와 묻는 곳(`reloadTasks`·`reloadContexts`·`activate`·키 저장), 화면 값(할 일별 priority). T022 PASS 〔단위 4〕
- [ ] T026 [P] [US1] `App/Sources/Decision/TypeSafeProvider.swift`: contracts/decision-provider.md HTTP 표(URLSession, `timeoutIntervalForResource = Defaults.decisionTimeout`, 상태 코드 → 오류, 본문은 `TypeSafeCodec`, 질의 때마다 `KeyStore.read()`, 로그는 종류·상태 코드만). 시험에서 링크하지 않는다 〔단위 4〕
- [ ] T027 [P] [US1] `App/Sources/Decision/KeychainKeyStore.swift`: research R10(로그인 키체인 generic password, service `dev.dongwon.moka`, account `typesafe`, `hasKey`는 `kSecReturnAttributes`만, 접근성 속성 없음). 시험에서 쓰지 않는다(`FR-16 R-214`) 〔단위 4〕
- [ ] T028 [US1] `App/Sources/MokaApp.swift`: DB를 열 때 `GRDBScoreStore`, `KeychainKeyStore`, `TypeSafeProvider`를 만들어 넘긴다. DB를 못 열면 `scores` nil(spec 002 R-119). T026·T027 뒤 〔단위 4〕
- [ ] T029 🔒 [US1] 설정 창 시안 `~/Dev/ai-platform/projects/moka/design/003-mockup.html`: data-model §10 키 칸 상태 여섯과 할 일 탭 priority 칸(점수 있음·없음 섞임). 사용자 확정을 받는다. 하루 넘게 밀리면 R-215를 다음 spec으로(plan 위험 1) 〔단위 4〕
- [ ] T030 [US1] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 스냅샷 `test_R215_priorityColumn`을 확정 시안대로 쓰고 실패를 확인한다(`FR-04 R-215`) 〔단위 4〕
- [ ] T031 [US1] `App/Sources/Views/TaskListTabView.swift` 줄에 priority 칸(소수 둘째 자리 반올림, 점수 없으면 빈칸). T030 PASS 〔단위 4〕
- [ ] T032 🔒 [US1] 사람 확인 quickstart 6-3·6-4(확인용 빌드, 개인 팀 서명, `codesign -dv` TeamIdentifier 먼저). 결과는 PASS/FAIL과 응답 필드 이름만 〔단위 4〕

**확인 지점**: SC-201·SC-203·SC-206. 노치가 priority 순으로 고른다.

---

## Phase 4: User Story 2 - 키가 없거나 실패해도 앱은 그대로 동작한다 (Priority: P1)

**Goal**: 키 없음·실패에서 마감일 순, 버튼·타이머 그대로, 401 문구와 멈춤, 실패 뒤 한 번 다시, 다시 물어보기.

**Independent Test**: spec US2 Independent Test.

### Tests (Red)

- [ ] T033 [US2] `App/Tests/MokaAppTests/AppDecisionTests.swift`에 덧붙인다: 실패 일곱 종류(`missingKey`, `unauthorized`, `timeout`, `rateLimited`·`overloaded`, `server`, `network`, `malformed`)에서 저장 없음·노치 상태 그대로, 실패한 할 일은 다음 활성화 때 한 번만 다시 보냄, `unauthorized` 뒤 `keyNeedsCheck` 켜지고 키를 다시 저장하기 전까지 아무것도 보내지 않음, 키 저장·지움 때 꺼짐, "다시 물어보기"가 장부를 비우고 다시 물을 할 일을 보냄, 키 지운 뒤 마감 순, `KeyStore.read`가 던지면 `missingKey`, 주입한 시계로 1시간 동안 시작·완료·바꾸기가 동작(`FR-14 R-211`, `FR-01 R-207`, SC-204, SC-205). 실패를 확인한다 〔단위 4〕

### Implementation (Green)

- [ ] T034 [US2] `App/Sources/AppState.swift`: `keyNeedsCheck`, 실패 표시와 다음 활성화 때 지우기, "다시 물어보기", 키 지움 뒤 순서만 다시. T033 PASS 〔단위 4〕
- [ ] T035 🔒 [US2] 사람 확인 quickstart 6-5·6-6 〔단위 4〕

**확인 지점**: SC-204·SC-205.

---

## Phase 5: User Story 3 - 키는 Keychain에만 있고 화면에 다시 보이지 않는다 (Priority: P1)

**Goal**: 설정 창 키 칸, Keychain 저장, 값이 다시 보이지 않음.

**Independent Test**: spec US3 Independent Test.

### Tests (Red)

- [ ] T036 [P] [US3] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 기본 탭 키 칸 상태 여섯 스냅샷(data-model §10, 확정 시안), `AppDecisionTests`에 키 저장·지우기(성공·실패 문구)와 앱 DB·설정 저장소에 키 값이 없음(`InMemoryKeyStore` 밖 어디에도 없음)을 쓰고 실패를 확인한다(`FR-16 R-213`, `FR-16 R-214`, SC-208, SC-210) 〔단위 4〕

### Implementation (Green)

- [ ] T037 [US3] `App/Sources/Views/BasicTabView.swift` 키 칸(가림 입력, 저장·지우기·다시 물어보기, 안내·401·실패 문구, 확정 시안 글자)과 `AppState` 키 저장·지우기·`hasKey` 갱신. T036 PASS 〔단위 4〕
- [ ] T038 🔒 [US3] 사람 확인 quickstart 6-1·6-2(다시 빌드해도 확인 창이 반복되지 않는지). 접근성 속성이 로그인 키체인에서 지켜지는지는 공식 문서로 확인해 PR "사람이 볼 결정"에 적는다(미확인이면 미확인) 〔단위 4〕

**확인 지점**: SC-208·SC-210.

---

## Phase 6: 시뮬레이터 (R-216, 마지막 단위)

**순서**: 2026-11-08까지 단위 1~4가 끝나지 않으면 이 Phase를 다음 spec으로 넘기고 PR에 적는다(research R13).

- [ ] T039 [P] `Tests/MokaCoreTests/Fixtures/sim/storage-judge-order.json`·`.expected.jsonl`(contracts/moka-sim-v1-additions-003.md 예를 기반으로 바꾸기 뒤 다음 순위까지), `errors/storage-judge-*.json` 오류 픽스처, `SimGoldenTests`에 spec 001 타이머 golden 바이트 동일 시험을 쓰고 실패를 확인한다(`ADR-0003 R-216`) 〔단위 5〕
- [ ] T040 `Sources/MokaCore/Sim/`에 `judge`·`key` 이벤트(contracts의 변환 규칙)와 조건부 출력 칸(`order`, `has_key`, `decision.provider`). T039 PASS. 👁(`moka-sim` 계약) 〔단위 5〕
- [ ] T041 [P] spec 001 `contracts/moka-sim-v1.md`의 storage 절 끝에 spec 003 덧붙임 링크 한 줄 〔단위 5〕

---

## Phase 7: Polish & Cross-Cutting

- [ ] T042 [P] `GLOSSARY.md`: 판단 질문 넷(blocked 없앰, 2026-11-06 사용자 결정), noul·score, impact 옵션 "조금/꽤/아주", 판단 결과(`scores`, priority 저장 안 함), `priority_rotate_v0`, 키 보관함("마일스톤 3에서 만든다" → 만들었음, 온보딩 키 단계는 다음 spec) 〔단위 1a〕
- [ ] T043 🔒 quickstart 1~6 전체를 돌려 결과 표를 마지막 PR에 붙인다 〔단위 4〕
- [ ] T044 PRD 고칠 문장(6장 blocked 줄·impact 옵션, 7장 w_b·정책 1·7번 6시간 캐시, 9장 `scores` 열)을 마지막 PR "사람이 볼 결정"에 적는다. PRD는 저장소 밖이라 고치지 않는다 〔단위 4〕

---

## Dependencies & Execution Order

### Phase 순서

Setup → Foundational(단위 1a → 1b, 그 뒤 단위 3) → US1(단위 2 → 단위 4) → US2·US3(단위 4) → 시뮬레이터(단위 5) → Polish.

### 태스크 사이 의존

- T012~T014는 T004~T006 뒤, T015~T018은 T007~T009 뒤. T019는 T018 뒤.
- T020·T021은 T014(판단 결과 규칙) 뒤. T023·T024는 T020·T021 뒤.
- 단위 4(T022, T025~T038)는 단위 1b·2·3 병합 뒤. T028은 T026·T027 뒤. T029(시안)는 단위 1a와 함께 먼저 만들어 확정을 받아 둔다.
- T039·T040은 단위 2 뒤.

### 작업 단위 ↔ Issue (plan "작업 단위")

| 단위 | 태스크 | Issue 제목 후보 |
|---|---|---|
| 1a | T001~T006, T012~T014, T042 | spec 003 단위 1a: 질문 파일·판단 입력·해시·판단 결과 규칙 |
| 1b | T007~T009(단위 1b 몫), T015~T018 | spec 003 단위 1b: 공급자 경계·TypeSafe 조립·다시 물을 할 일·키 보관함·판단 결과 저장 프로토콜 |
| 2 | T020, T021, T023, T024 | spec 003 단위 2: priority 순 고르기, 로그 판단 칸, storage golden 갱신 |
| 3 | T009(`.grdb`), T010, T011, T019 | spec 003 단위 3: MokaStore v3_scores와 튜닝 계약 시험 |
| 4 | T022, T025~T038, T043, T044 | spec 003 단위 4: 앱 공급자·Keychain·질의 연결·설정 창(사람 세션) |
| 5 | T039~T041 | spec 003 단위 5: moka-sim judge·key |

### Parallel Opportunities

- T004~T011의 Red 시험은 모두 다른 파일이라 병렬.
- 단위 1b와 단위 2는 단위 1a 병합 뒤 병렬. 단위 3은 1b 뒤.
- T026(TypeSafeProvider)과 T027(KeychainKeyStore)은 서로 다른 파일이라 병렬.

### Parallel Example: 단위 1a 병합 뒤

```text
implementer A: 단위 1b (T007~T009 → T015~T018) → 단위 3 (T010, T011 → T019)
implementer B: 단위 2 (T020, T021 → T023, T024)
```

## Implementation Strategy

### MVP First

단위 1a → 1b·2 → 3 → 4의 US1(T022·T025~T028·T032)까지 가면 완료 조건("모델 점수로 정렬된 할 일이 노치에 뜬다")이 선다. US2·US3은 같은 단위 4 안에서 이어 간다. R-215(priority 칸, T029~T031)와 단위 5는 밀리면 넘긴다.

### 무인 실행 경계

moka는 2026-11-02부터 무인 실행을 하지 않는다(사용자 결정). 단위 1a·1b·2·3·5는 사람 세션에서 `implementer`로 돌릴 수 있다. 단위 4는 화면·실제 호출·Keychain 확인(🔒)이 있어 사람 세션 전용이다.

## R-ID ↔ 태스크

| R-ID | Red | Green | 사람 확인 |
|---|---|---|---|
| R-201 판단 입력·금지 필드 | T005 | T013 | — |
| R-202 질문 파일 | T004, T011 | T003, T012 | — |
| R-203 blocked 없음 | T004 | T003, T012 | — |
| R-204 priority 식 | T006 | T014 | — |
| R-205 판단 결과 저장 | T009, T010, T011 | T018, T019 | — |
| R-206 다시 물을 할 일 | T008, T022 | T016, T025 | T032 |
| R-207 묻는 때·장부·동시 4 | T022, T033 | T025, T034 | T032 |
| R-208 노치 순서 | T020 | T023 | T032 |
| R-209 고르기 순환 | T020, T021 | T023, T024 | T032 |
| R-210 공급자 경계 | T007 | T015, T026 | T032 |
| R-211 실패·폴백 | T007, T033 | T015, T034 | T035 |
| R-212 로그 판단 칸 | T021 | T024 | — |
| R-213 키 칸 | T036 | T037 | T038 |
| R-214 Keychain | T036 | T017, T027 | T038 |
| R-215 priority 칸 | T030 | T031 | T029, T032 |
| R-216 시뮬레이터 | T039 | T040 | — |
| SC-201 10초 | T022 | T025 | T032 |
| SC-202 금지 필드 | T005 | T013 | — |
| SC-203 순서 | T020, T021 | T023, T024 | T032 |
| SC-204 키 없이 1시간 | T033 | T034 | T035 |
| SC-205 실패 일곱 | T033 | T034 | — |
| SC-206 질의 규칙 | T008, T022 | T016, T025 | — |
| SC-207 실제 API·Keychain·DB 안 엶 | 공통 규칙, T026·T027이 앱 타깃에만 | — | — |
| SC-208 키 값 없음 | T036 | T037 | T038 |
| SC-209 첫 실제 호출 | — | — | T032 |
| SC-210 키 칸 상태 | T036 | T037 | T038 |
