---

description: "spec 006 판단 공급자 고르기와 키 넣기 작업 목록"
---

# Tasks: 판단 공급자 고르기와 키 넣기

**Input**: `specs/006-decision-providers/`의 plan.md, spec.md(R-601~R-630), research.md(R1~R14), data-model.md, contracts/(decision-provider-v2.md, questions-json-v2.md), quickstart.md. 화면 시안 `~/Dev/ai-platform/projects/moka/design/006-mockup.html`(저장소 밖, T002에서 사용자 확정)

**Tests**: 넣는다. 헌법 II와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다". 테스트 태스크마다 Red 커밋을 남기고, 구현 태스크에서 Green 커밋을 남긴다.

**Organization**: 공통 기반(단위 1·2) 다음 사용자 이야기(US1~US5)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다(아래 "작업 단위와 Issue").

**원본 규칙**: 규칙, 값, 모양은 data-model.md와 contracts/가 원본이다. 태스크는 절 번호를 가리키고 문장을 옮겨 적지 않는다. 시험은 그 절의 규칙을 빠짐없이 덮는다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US5(spec.md)
- **[사람]**: 화면 확정이나 실제 판단 결과, 새 사용자 첫 실행을 사람이 확인해야 끝난다
- **[화면 뒤]**: T002(시안 확정) 뒤에만 시작한다
- **[승인 N]**: plan "승인 항목" N번. 그 단위 PR "사람이 볼 결정"에 올리고 병합이 승인이다
- 이 파일의 "확인 지점"은 Phase 완료 조건이다

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 R-ID로 시작한다(ADR-0003): MokaCore·앱 규칙은 `ADR-0011 R-6xx`, 온보딩 R-624~R-626은 `FR-21 R-62x`, 할 일 탭 키 확인 R-627은 `FR-14 R-627`. MokaCore는 Swift Testing, 앱 시험 번들(`MokaAppTests`)은 XCTest.
- 타입과 함수 이름, 모양은 data-model §1·§6·§8·§9를 따른다. 거기 없는 작은 이름은 구현 PR에서 정하고 PR "가정"에 적는다.
- 실제 판단 API를 시험·CI·`moka-sim`에서 부르지 않는다. `FakeDecisionProvider`, `InMemoryKeyStore`, `InMemoryScoreStore`만 쓴다. 실제 Keychain과 앱 DB를 시험에서 열지 않는다. 에이전트는 Keychain 값을 조회하지 않는다. `HTTPDecisionProvider`·`KeychainKeyStore`는 앱 시험 번들이 컴파일하지 않는다.
- 가짜 할 일, 가짜 키, 가짜 주소만 쓴다(예: "가짜 할 일 A", `fake-key-a`, `https://example-resource.invalid`).
- 바꾸지 않는 것: `schema/moka-schema.sql`과 스키마 계약 pytest, `moka-sim` 형식과 golden 기대 출력, `UserAction`·`SchedulerChoice` 값, `Package.swift`, CI. `@unchecked Sendable`을 쓰지 않는다.
- 바뀐 시그니처(research R12) 때문에 기존 시험 호출을 고칠 때 기대값은 바꾸지 않는다. 기대값이 바뀌어야 통과하면 멈추고 원인을 본다.
- 로그에는 실패 종류와 상태 코드, 꺼진 이유 종류만 남긴다. 주소, 호스트, 배포 이름, 키, 할 일 제목은 남기지 않는다.
- 화면 문구는 고객용 해요체이고 확정 시안 글자를 그대로 쓴다.
- 검증 명령: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`, 앱 시험 quickstart 4. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

- [ ] T001 기준 상태 확인: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드, quickstart 4의 앱 시험을 돌려 기존 시험이 PASS인지 기록하고, 기존 스냅샷 참조 이미지 폴더(`SnapshotHelper.swift`가 가리키는 곳)의 파일 해시 목록을 PR "완료 증거"에 적는다(SC-613 비교 기준) 〔단위 1〕
- [ ] T002 [사람] 시안 `~/Dev/ai-platform/projects/moka/design/006-mockup.html`을 사용자에게 보이고 "확정할 것" 목록(판단 모델 칸 구성과 문구, 열리지 않은 공급자 표시, 잠정값 안내, 바꾸기 안내, Microsoft 칸과 거부 문구, 온보딩 키 단계 문구와 보내는 곳 줄, TypeSafe 발급 링크 주소)을 확정받는다. 확정 전에는 [화면 뒤] 태스크를 시작하지 않는다 〔단위 1〕

---

## Phase 2: Foundational (MokaCore, 단위 1·2)

**목적**: 공급자 표, 요청 모양 둘, 주소 규칙, 질문 파일 v2, 공급자 비교. 모든 이야기의 바탕이다.

### 단위 1: 공급자 표와 코덱 [승인 1]

- [ ] T003 [P] `Tests/MokaCoreTests/TypeSafeCodecTests.swift`를 `git mv`로 `Tests/MokaCoreTests/SystemOneCodecTests.swift`로 옮기고 안의 `TypeSafeCodec`을 `SystemOneCodec`으로 바꾼다. 같은 파일에 `DecisionWire.body(_:shape:)`·`decode(status:body:shape:)`가 두 모양에서 같은 상태 코드 표를 쓰고 3xx(301, 302, 307)가 `server(status)`인 시험을 더한다. 컴파일 실패를 확인한다(`ADR-0011 R-602`, `ADR-0011 R-604`, SC-601, data-model §3) 〔단위 1〕
- [ ] T004 `Sources/MokaCore/Decision/TypeSafeCodec.swift`를 `git mv`로 `SystemOneCodec.swift`로 옮겨 이름만 바꾸고(내용 그대로), `Sources/MokaCore/Decision/DecisionWire.swift`를 만든다. `App/Sources/Decision/TypeSafeProvider.swift`의 호출을 `DecisionWire`로 바꾼다(T020에서 파일을 대체할 때까지). T003 PASS, 기존 시험 PASS 〔단위 1〕
- [ ] T005 [P] `Tests/MokaCoreTests/OpenAIDecisionsCodecTests.swift`: contracts/decision-provider-v2.md "OpenAI 모양"의 요청 배열과 `predicate`, 같은 바이트의 `input`, 응답 사전 변환, 같은 `name` 둘, 같은 `value` 둘, `score`·`confidence` 빠짐, 범위 밖이면 `malformed`. 픽스처는 문서 예시 모양에 가짜 값. 실패를 확인한다(`ADR-0011 R-603`, SC-602) 〔단위 1〕
- [ ] T006 `Sources/MokaCore/Decision/OpenAIDecisionsCodec.swift`와 `DecisionWire`의 OpenAI 분기. T005 PASS 〔단위 1〕
- [ ] T007 [P] `Tests/MokaCoreTests/ProviderCatalogTests.swift`: research R4 표 다섯 줄의 공급자 ID, 화면 이름, 주소(`ProviderEndpoint`), 인증, 요청 모양, 발급 링크와 `issueURLConfirmed`, `firstCallConfirmed`가 참인 줄은 `typesafe` 하나, `ProviderConfig.url(resource:)`가 Microsoft에 경로를 붙이고 리소스가 없으면 `nil`. 실패를 확인한다(`ADR-0011 R-601`, data-model §1·§2) 〔단위 1〕
- [ ] T008 `Sources/MokaCore/Decision/ProviderCatalog.swift`(`ProviderID`, `RequestShape`, `AuthStyle`, `ProviderEndpoint`, `ProviderConfig`, `ProviderCatalog.all`·`config(_:)`). `isOpen`은 단위 2(T017). T007 PASS 〔단위 1〕
- [ ] T009 [P] `Tests/MokaCoreTests/EndpointRuleTests.swift`: data-model §4 사례 표 전부, 거부 순서, 끝 `/` 뗌, `host(of:)`가 대괄호를 벗긴 소문자이고 포트가 없음. `https://`의 결과는 구현 PR에서 하나로 정해 표에 적는다. 실패를 확인한다(`ADR-0011 R-605`, `ADR-0011 R-606`, SC-603) 〔단위 1〕
- [ ] T010 `Sources/MokaCore/Decision/EndpointRule.swift`(`EndpointRejection`, `check(_:allowsPath:)`, `host(of:)`). T009 PASS 〔단위 1〕
- [ ] T011 [P] 대체 표기: `specs/003-decision-model/contracts/decision-provider.md` 머리에 "spec 006 contracts/decision-provider-v2.md가 대체"를 붙이고, PR "사람이 볼 결정"에 헌법 VIII·AGENTS.md 예시 문구 PATCH 개정 제안(ADR-0011 승인 항목 4)을 적는다. 헌법과 AGENTS.md는 고치지 않는다(`ADR-0011 R-630`) 〔단위 1〕

### 단위 2: 질문 파일 v2와 판단 결과 규칙 [승인 2]

- [ ] T012 [P] `Tests/MokaCoreTests/QuestionSetV2Tests.swift`(새)와 기존 `Tests/MokaCoreTests/QuestionSetTests.swift`·`App/Tests/MokaAppTests/QuestionSetBundleTests.swift`: contracts/questions-json-v2.md 읽기 규칙 2·4·5를 어긴 JSON을 읽지 않음, 버전별 고정값 사전(v1, v2, research R13)과 지금 파일 비교, `thresholds(for:)`가 없는 기준 모델에 `nil`, `models`·`provisional` 값. 기존 `model`·`avoidingThreshold` 단언은 같은 값을 `models["typesafe"]`·`thresholds(for:)`로 읽게 고친다. 실패를 확인한다(`ADR-0011 R-607`, `ADR-0011 R-608`, SC-604) 〔단위 2〕
- [ ] T013 [P] `tuning/tests/test_questions_contract.py`: `test_thresholds_for_fixed_model`을 `models`의 모든 값에 대한 시험으로 바꾸고 `provisional`이 `models` 값의 부분집합인지 본다. 실패를 확인한다(`ADR-0011 R-612`) 〔단위 2〕
- [ ] T014 [P] `Tests/MokaCoreTests/ScoreRulesTests.swift`, `ScoringPlanTests.swift`, `ConcreteGateTests.swift`, `PriorityOrderTests.swift`, `NotchSessionPriorityTests.swift`: 공급자가 다른 판단 결과는 `usable`에서 빠지고 `needsQuery`에 들며 "판단 결과 있음" 순서로 섬, 이름이 다른 가짜 공급자 둘, `ConcreteGate.Facts.threshold == nil`이면 열지 않음, `priority`의 `thresholds == nil`이면 avoiding 배율 1. 기존 호출은 `provider:`와 Jev 임계값을 넘기게 고치고 기대값은 그대로. 실패를 확인한다(`ADR-0011 R-609`, `ADR-0011 R-611`, SC-605, data-model §1·§7) 〔단위 2〕
- [ ] T015 [P] `Tests/MokaCoreTests/DecisionSelectionTests.swift`: data-model §6 "정하기" 일곱 단계(설정 없음이면 `typesafe`, 모르는 ID, 열리지 않은 공급자, Microsoft 주소 없음·거부·배포 이름 없음, 보낼 모델 이름, `url`), 가짜 `catalog`로 연 Microsoft, `ProviderCatalog.isOpen`. `Tests/MokaCoreTests/CoreSettingsTests.swift`에 설정 키 셋 읽기·쓰기. 실패를 확인한다(`ADR-0011 R-609`, `ADR-0011 R-610`, `ADR-0011 R-614`, `ADR-0011 R-617`) 〔단위 2〕
- [ ] T016 `Sources/MokaCore/Resources/questions.json`을 contracts/questions-json-v2.md "v2 제안 내용"으로, `Sources/MokaCore/Decision/QuestionSet.swift`를 v2 읽기로 바꾼다. 잠정 임계값의 이전 값 없음·새 값 0.5·0.7을 PR "사람이 볼 결정"에 적는다. T012·T013 PASS 〔단위 2〕
- [ ] T017 `Sources/MokaCore/Decision/ScoreRules.swift`·`ScoringPlan.swift`·`ConcreteGate.swift`(강제 언래핑 제거), `SessionScoring`의 `thresholds`, `Sources/MokaCore/Decision/DecisionSelection.swift`(새), `ProviderCatalog.isOpen`, `Sources/MokaCore/CoreSettings.swift` 키 셋(research R8), `Sources/MokaCore/Sim/SimStorageRunner.swift`(가짜 공급자 `fake`와 기준 모델 `jev-1.13.0`, research R14), `App/Sources/AppState.swift`의 호출(지금 공급자 `name`, 요청 모델과 기준 모델은 질문 파일 `typesafe` 값, T020 전까지의 최소 변경). T014·T015 PASS, `SimGoldenTests` 기대 출력 그대로 PASS, 앱 시험 PASS 〔단위 2〕
- [ ] T018 [P] 대체 표기: `specs/003-decision-model/contracts/questions-json.md` 머리에 "spec 006 contracts/questions-json-v2.md가 대체", `specs/003-decision-model/data-model.md` §1 `QuestionSet` 줄과 §3 `usable` 줄에 "spec 006 data-model §1이 대체". PR "사람이 볼 결정"에 v2 비용(모든 할 일 다시 묻기, plan 위험 2)과 열린 질문 research R11(debate로 추천안)을 적는다(`ADR-0011 R-630`) 〔단위 2〕

**확인 지점**: `swift test`, pytest PASS. `moka-sim` golden과 기존 스냅샷 그대로. 앱은 지금처럼 Jev로만 판단한다.

---

## Phase 3: User Story 1 - 설정 창에서 공급자를 고르고 키를 넣는다 (Priority: P1) MVP

**Goal**: 업그레이드한 Jev 사용자는 그대로 쓰고, 기본 탭에서 공급자 목록과 보내는 곳이 보인다.

**Independent Test**: 공급자별 가짜 키 보관함을 주는 가짜 `bind`로 업그레이드, 저장, 꺼짐을 앱 시험으로, 판단 모델 칸을 스냅샷으로 확인한다.

- [ ] T019 [US1] `App/Tests/MokaAppTests/AppProviderTests.swift`(새): 설정 없음과 `typesafe` 항목 키로 조작 없이 판단 결과가 붙음, 키 저장이 고른 공급자 보관함에만 감, 키 값이 설정·판단 결과·행동 로그에 없음, `DecisionSelection`이 `off`면 질의 0건·노치 마감일 순·`selectionOff` 값, 기존 3인자 `DecisionSetup` 생성이 그대로 동작. `App/Tests/MokaAppTests/AppTestSupport.swift`에 공급자별 `InMemoryKeyStore`를 주는 가짜 `bind`. 실패를 확인한다(`ADR-0011 R-613`, `ADR-0011 R-614`, `ADR-0011 R-617`, SC-606, SC-607, SC-608) 〔단위 3〕
- [ ] T020 [US1] `App/Sources/AppState.swift`에 `DecisionSetup.bind`·`catalog`·편의 생성자(research R5), `binding`, `selectionOff`, 꺼짐 로그 한 줄. `App/Sources/Decision/KeychainKeyStore.swift`에 `account` 인자(Jev는 `typesafe`). `App/Sources/Decision/TypeSafeProvider.swift`를 `git mv`로 `HTTPDecisionProvider.swift`로 바꿔 `ProviderConfig`와 `url`을 받고, 인증 헤더 방식, 리디렉트를 거부하는 세션 대리자(research R7), 로그 한 함수(contracts/decision-provider-v2.md "로그")를 둔다. `App/Sources/MokaApp.swift`의 `decisionSetup()`이 설정 값으로 바인딩을 만든다. T019 PASS, 앱 빌드 PASS (`ADR-0011 R-618`, `ADR-0011 R-619`) 〔단위 3〕
- [ ] T021 [US1] [화면 뒤] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 판단 모델 칸 상태(Jev 키 없음, 저장됨, 키 확인 필요, 목록 펼침과 열리지 않은 넷, 가짜 `ProviderRow`로 잠정값, 바꾸기 안내, 설정 쓰기 실패) 라이트·다크를 확정 시안대로 쓰고 실패를 확인한다. 바뀌는 기존 키 칸 참조 이미지 목록을 PR에 적는다(`ADR-0011 R-620`, `ADR-0011 R-621`, `ADR-0011 R-622`, SC-610) 〔단위 4〕
- [ ] T022 [US1] [화면 뒤] `App/Sources/Views/BasicTabView.swift`에 `decision: DecisionFieldInput`(data-model §9), `App/Sources/Views/KeyFieldState.swift`의 칸 제목을 공급자 이름으로, `App/Sources/AppState.swift`가 `DecisionFieldInput` 값을 만들고, `App/Sources/Settings/SettingsView.swift`가 넘긴다. 발급 링크는 `NSWorkspace`로 연다. T021 PASS 〔단위 4〕
- [ ] T023 [사람] [US1] quickstart 6-1, 6-2 〔단위 4〕

**확인 지점**: US1 시나리오 1~6.

---

## Phase 4: User Story 2 - 공급자를 바꿔도 다른 모델 점수가 섞이지 않는다 (Priority: P1)

**Goal**: 바꾸면 모두 다시 묻고, 바꾼 뒤 도착한 이전 공급자 답은 버린다.

**Independent Test**: 이름이 다른 가짜 공급자 둘과 붙잡기로 앱 시험.

- [ ] T024 [US2] `App/Tests/MokaAppTests/AppProviderTests.swift`: data-model §6 "바꾸기" 일곱 단계(같은 공급자 무시, 열리지 않은 공급자 무시, 설정 쓰기 실패면 그대로), 바꾼 뒤 쓰는 판단 결과가 비고 모든 대기·진행 중 할 일을 새 공급자에 묻음, 장부 비움, 키 확인 필요 꺼짐, `hasKey`가 새 보관함으로, 바꾸기 전 떠난 답(붙잡은 가짜 공급자)이 저장되지 않음, 그 답이 401이어도 키 확인 필요가 켜지지 않음, 돌아오면 이전 키와 이전 판단 결과를 다시 씀. 실패를 확인한다(`ADR-0011 R-615`, `ADR-0011 R-611`, SC-605) 〔단위 3〕
- [ ] T025 [US2] `App/Sources/AppState.swift`에 `selectProvider(_:)`, `providerGeneration`과 질의 실행기·답 받기의 세대 판정(research R6), 실행기가 꺼낼 때마다 바인딩을 다시 읽음. T024 PASS, 기존 앱 시험 PASS 〔단위 3〕

**확인 지점**: US2 시나리오 1~6. 공급자 고르기 동작의 화면은 T021·T022에 있다.

---

## Phase 5: User Story 3 - Microsoft 배포를 쓴다 (Priority: P2)

**Goal**: Microsoft가 열렸을 때 주소와 배포 이름을 안전하게 받는다. 이 spec에서는 가짜 `catalog`로만 연다.

**Independent Test**: 가짜 `catalog`(Microsoft `firstCallConfirmed` 참)와 `microsoft` 줄이 든 시험용 질문 파일로 앱 시험, 칸 상태는 스냅샷.

- [ ] T026 [US3] `App/Tests/MokaAppTests/AppProviderTests.swift`: data-model §6 "Microsoft 칸 저장" 다섯 단계(빈 값, 주소 거부 이유, 주소를 바꾸면 Microsoft 키 지움, 지우기 실패면 주소 저장 안 함, 장부 비움과 키 확인 필요 꺼짐), 배포 이름을 바꾸면 다음 요청 `model`이 새 배포 이름이고 저장된 판단 결과는 그대로 쓰임(research R3), 주소의 호스트가 보내는 곳. 실패를 확인한다(`ADR-0011 R-616`, `ADR-0011 R-623`, SC-609) 〔단위 3〕
- [ ] T027 [US3] `App/Sources/AppState.swift`에 `saveMicrosoft(endpoint:deployment:)`. T026 PASS 〔단위 3〕
- [ ] T028 [US3] [화면 뒤] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 Microsoft 칸 상태(주소 없음, 주소 거부 `scheme`·`path`, 저장됨과 보내는 곳, 주소를 바꾸면 키를 지운다는 안내) 라이트·다크를 확정 시안대로 쓰고 실패를 확인한다(`ADR-0011 R-623`) 〔단위 4〕
- [ ] T029 [US3] [화면 뒤] `App/Sources/Views/BasicTabView.swift`에 `MicrosoftFieldInput`과 `EndpointRejection`별 해요체 문구(시안 확정 글자). T028 PASS 〔단위 4〕
- [ ] T030 [사람] [US3] quickstart 6-3(리디렉트 거부). Microsoft를 여는 브랜치 전에는 상태를 만들 수 없어 NOT_RUN으로 적고 quickstart 7로 넘긴다 〔단위 3〕

**확인 지점**: US3 시나리오 1~7(가짜 표 기준).

---

## Phase 6: User Story 4 - 처음 켤 때 Jev 키를 넣거나 건너뛴다 (Priority: P2)

**Goal**: spec 004 R-313~R-315를 Jev만 받는 키 단계로 마친다(research R2).

**Independent Test**: 가짜 설정 저장소(온보딩 안 끝남)와 가짜 키 보관함으로 앱 시험, 키 단계 셋을 스냅샷.

- [ ] T031 [US4] `App/Tests/MokaAppTests/AppDecisionTests.swift`: 온보딩이 안 끝난 상태의 키 단계 첫 값(Jev 보관함 `hasKey`), 저장 콜백이 실패면 `false`·성공이면 `true`, 저장이 `typesafe` 보관함에만 가고 설정의 `decision_provider`를 쓰지 않음, 앞뒤 공백 제거와 장부 비움, 이미 있음, 키 없이 `finishOnboarding` 뒤 할 일을 넣으면 노치에 뜸, 키 저장 뒤 끝내기 전 다시 만든 `AppState`에서 온보딩이 다시 보이고 키는 있음, 키 값이 설정·판단 결과·행동 로그에 없음. 실패를 확인한다(`FR-21 R-625`, `FR-21 R-626`, SC-611) 〔단위 5〕
- [ ] T032 [US4] [화면 뒤] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 `test_R624_onboardingKeyEmpty`, `test_R624_onboardingKeyFailed`, `test_R624_onboardingKeySaved`(보내는 곳 줄 포함, 라이트·다크)를 확정 시안대로 쓰고 실패를 확인한다. `onboardingKeyFailed`는 `false`를 돌려주는 `onSave`로 뷰를 만들고 저장을 눌러 뷰가 스스로 실패 문구로 바뀌는지 찍는다. 기존 온보딩 두 단계 스냅샷은 그대로 둔다(`FR-21 R-624`) 〔단위 5〕
- [ ] T033 [US4] [화면 뒤] `App/Sources/Views/OnboardingView.swift`에 `keyStep: OnboardingKeyInput? = nil`(`hasKey`, `onSave: (String) -> Bool`, `issueURL: URL?`, `host: String`, data-model §8). 값이 있으면 세 단계이고 첫 단계가 키, 칸이 비면 "다음" 꺼짐, 링크는 `issueURL`이 있을 때만. `nil`이면 지금 두 단계 그대로. T032 PASS, 기존 스냅샷 PASS 〔단위 5〕
- [ ] T034 [US4] `App/Sources/AppState.swift`에 온보딩 키 단계 값과 저장 콜백(지금 바인딩과 상관없이 Jev 보관함, 설정 창 `saveKey`와 같은 동작), `App/Sources/MokaApp.swift`가 온보딩에 `keyStep`(Jev `issueURL`은 `issueURLConfirmed`일 때만, `host`는 `EndpointRule.host`)을 넘긴다. T031 PASS 〔단위 5〕
- [ ] T035 [사람] [US4] quickstart 6-4(macOS 새 사용자 계정) 〔단위 5〕

**확인 지점**: US4 시나리오 1~7.

---

## Phase 7: User Story 5 - 키가 맞지 않으면 할 일 탭에서도 알 수 있다 (Priority: P3)

**Goal**: spec 004 R-317(시안 15번 확정)을 만든다.

**Independent Test**: 가짜 공급자 401로 키 확인 필요를 만들고 할 일 탭을 스냅샷, 꺼지는 때를 앱 시험.

- [ ] T036 [US5] `App/Tests/MokaAppTests/AppProviderTests.swift`에 401 뒤 공급자를 바꾸거나 Microsoft 칸을 저장하면 `showsKeyNotice == false`, `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 `test_R627_taskTabKeyNotice`(라이트·다크, 시안 15번). 실패를 확인한다(`FR-14 R-627`, SC-612) 〔단위 4〕
- [ ] T037 [US5] [화면 뒤] `App/Sources/Views/TaskListTabView.swift`에 `keyNotice: Bool = false`, `onOpenKeySettings` 인자와 목록 위 한 줄(시안 15번 글자 그대로), `App/Sources/Settings/SettingsView.swift`가 나타날 때와 `settingsTabRequest`가 바뀔 때 탭을 바꾸고 값을 비우며, 할 일 탭 한 줄의 동작은 탭을 기본으로 바꾼다. T036 PASS 〔단위 4〕
- [ ] T038 [사람] [US5] quickstart 6-5 〔단위 4〕

**확인 지점**: US5 시나리오 1~4.

---

## Phase 8: Polish & Cross-Cutting

- [ ] T039 [P] 대체 표기: `specs/003-decision-model/spec.md` R-210·R-213·R-214와 Key Entities 질문 파일·키 보관함 줄, 하지 않음의 두 번째 공급자, 대안 표 공급자 줄에 "spec 006이 대체", `specs/002-storage-checkpoint/research.md` R8의 OpenRouter 줄에 "ADR-0011 결정 4로 대체"(`ADR-0011 R-630`) 〔단위 3〕
- [ ] T040 [P] 대체 표기: `specs/004-decision-screens/spec.md` Goals·Assumptions의 공급자 하나 문장과 R-313~R-315·R-317, `specs/004-decision-screens/tasks.md` T017~T021·T026~T028에 "spec 006 단위 4·5가 담음"(`ADR-0011 R-630`) 〔단위 5〕
- [ ] T041 [사람] quickstart 1~6 전체를 돌려 결과 표를 마지막 PR에 붙인다 〔단위 5〕
- [ ] T042 공급자를 여는 작업 넷(Liquid, Perplexity, OpenAI, Microsoft)을 quickstart 7 절차로 Issue 후보로 적어 단위 3 PR "사람이 볼 결정"에 올린다. Microsoft 줄에는 research R3 남는 조건(응답 `model`이 배포마다 실제 버전을 주는지)을 적는다 〔단위 3〕

---

## Dependencies & Execution Order

### Phase 순서

Setup 다음 Foundational(단위 1과 2 병렬), 그다음 US1·US2·US3의 앱 상태(단위 3), 그다음 화면(단위 4: US1·US3·US5 화면, 단위 5: US4), 마지막 Polish.

### 태스크 사이 의존

- 단위 1: T003 다음 T004, T005 다음 T006, T007 다음 T008, T009 다음 T010. T006은 T004 뒤(`DecisionWire`).
- 단위 2: T012·T013 다음 T016, T014·T015 다음 T017. T017은 T016 뒤. T015의 `isOpen` 시험은 T008(단위 1)의 `ProviderConfig`가 필요하므로 단위 2는 단위 1의 T008 병합 뒤에 시작하거나, 같은 Issue 순서로 단위 1을 먼저 병합한다.
- 단위 3(T019, T020, T024~T027, T030, T039, T042)은 단위 1·2 병합 뒤.
- 단위 4(T021~T023, T028, T029, T036~T038)는 단위 3 병합과 T002 뒤.
- 단위 5(T031~T035, T040, T041)는 단위 3 병합과 T002 뒤. 단위 4와 나란히 할 수 있다(고치는 뷰 파일이 다르다. `AppState.swift`는 단위 5에서 T034만 고친다. `SettingsSnapshotTests.swift`는 둘이 함께 고치므로 나중에 병합하는 쪽이 충돌을 푼다).

### 작업 단위와 Issue (plan "작업 단위")

| 단위 | 태스크 | Issue 제목 후보 |
|---|---|---|
| 1 | T001~T011 | spec 006 단위 1: 공급자 표, System One·OpenAI 코덱, 주소 규칙(MokaCore) |
| 2 | T012~T018 | spec 006 단위 2: 질문 파일 v2와 공급자 비교(MokaCore) |
| 3 | T019, T020, T024~T027, T030, T039, T042 | spec 006 단위 3: 앱 공급자 설정, 공급자별 키, 바꾸기 |
| 4 | T021~T023, T028, T029, T036~T038 | spec 006 단위 4: 설정 창 판단 모델 칸과 할 일 탭 키 확인 |
| 5 | T031~T035, T040, T041 | spec 006 단위 5: 온보딩 Jev 키 단계 |

### Parallel Opportunities

- 단위 1 안에서 T003, T005, T007, T009는 다른 파일이라 병렬.
- 단위 2 안에서 T012, T013, T014, T015는 다른 파일이라 병렬.
- 단위 4와 단위 5는 단위 3과 T002 뒤 병렬.
- T011, T018, T039, T040은 문서라 그 단위 안에서 언제든 병렬.

### Parallel Example: 단위 3 병합 뒤

```text
implementer A: 단위 4 (T021, T028, T036 Red 다음 T022, T029, T037 Green)
implementer B: 단위 5 (T031, T032 Red 다음 T033, T034 Green)
```

## Implementation Strategy

### MVP First

단위 1, 2, 3까지 가면 공급자 구조가 서고, 업그레이드한 Jev 사용자는 그대로 쓰며, 공급자를 바꿔도 점수가 섞이지 않는다(US1 앱 상태, US2). 사용자가 고를 수 있는 공급자가 Jev 하나라 단위 4의 화면이 없어도 사용자 경험은 지금과 같다. 단위 4는 공급자를 열기 전에 필요하다. 밀리면 단위 5를 먼저 다음 spec으로 넘긴다(spec 위험 4).

### 무인 실행 경계

moka는 2026-11-02부터 무인 실행을 하지 않는다(사용자 결정). 단위 1·2·3은 사람 세션에서 `implementer`로 돌릴 수 있다. 단위 1·2는 승인 항목이라 병합 전에 사람이 계약을 본다. 단위 4·5는 시안 확정과 사람 확인([사람])이 있어 사람 세션에서 진행한다.

## R-ID와 태스크

| R-ID | Red | Green | 사람 확인 |
|---|---|---|---|
| R-601 공급자 표 | T007 | T008 | 없음 |
| R-602 System One 공통 | T003 | T004 | T023 |
| R-603 OpenAI 변환 | T005 | T006 | quickstart 7 |
| R-604 상태 코드 표 | T003 | T004 | 없음 |
| R-605 주소 허용 조건 | T009 | T010 | 없음 |
| R-606 보내는 곳 | T009 | T010 | T023 |
| R-607 질문 파일 v2 | T012 | T016 | 단위 2 PR 승인 |
| R-608 읽기 규칙과 고정값 | T012 | T016 | 없음 |
| R-609 기준 모델 찾기와 임계값 | T014, T015 | T017 | 없음 |
| R-610 보낼 모델 이름 | T015, T026 | T017, T027 | 없음 |
| R-611 공급자 비교 | T014, T024 | T017, T025 | 없음 |
| R-612 pytest 계약 | T013 | T016 | 단위 2 PR 승인(R11 열린 질문) |
| R-613 공급자별 Keychain | T019 | T020 | T023 |
| R-614 설정 표와 기본 Jev | T015, T019 | T017, T020 | T023 |
| R-615 공급자 바꾸기 | T024 | T025 | 없음 |
| R-616 Microsoft 주소·배포 이름 바꾸기 | T026 | T027 | 없음 |
| R-617 열린 공급자 | T015, T019 | T017, T020 | T042, quickstart 7 |
| R-618 HTTP 공급자, 리디렉트, 로그 | 없음(앱 시험 번들 밖) | T020 | T030 |
| R-619 동시에 하나, 중계 없음 | T019 | T020 | 없음 |
| R-620 판단 모델 칸 | T021 | T022 | T002, T023 |
| R-621 잠정값 안내 | T021 | T022 | T002 |
| R-622 바꾸기 안내 | T021 | T022 | T002 |
| R-623 Microsoft 칸 | T026, T028 | T027, T029 | T002 |
| R-624 온보딩 키 단계 화면 | T032 | T033 | T002, T035 |
| R-625 키 단계 저장 | T031 | T034 | T035 |
| R-626 키 없이 끝냄 | T031 | T034 | T035 |
| R-627 할 일 탭 키 확인 | T036 | T037 | T038 |
| R-628 가짜만, 계약 그대로 | 공통 규칙, T001 | 모든 Green의 기존 시험 PASS | T041 |
| R-629 첫 실제 호출 사람 확인 | 없음 | 없음 | T030, T042, quickstart 7 |
| R-630 대체 표기 | 없음 | T011, T018, T039, T040 | 없음 |
| SC-601 System One 시험 그대로 | T003 | T004 | 없음 |
| SC-602 OpenAI 변환 | T005 | T006 | 없음 |
| SC-603 주소 사례 표 | T009 | T010 | 없음 |
| SC-604 읽기 규칙과 고정값 | T012 | T016 | 없음 |
| SC-605 바꾸면 섞이지 않음 | T014, T024 | T017, T025 | 없음 |
| SC-606 꺼짐과 멈추지 않음 | T019 | T020 | 없음 |
| SC-607 업그레이드 조작 0번 | T019 | T020 | T023 |
| SC-608 키는 그 항목에만 | T019 | T020 | 없음 |
| SC-609 주소 바꾸면 키 지움 | T026 | T027 | 없음 |
| SC-610 한 화면 조작 세 번 | T021 | T022 | T023 |
| SC-611 키 없이 온보딩 | T031 | T034 | T035 |
| SC-612 할 일 탭 키 확인 | T036 | T037 | T038 |
| SC-613 실제 API 없음, 기존 출력 그대로 | 공통 규칙, T001 | 모든 Green 태스크 | T041 |
| SC-614 리디렉트 거부 | 없음 | T020 | T030 |
| SC-615 공급자별 첫 호출 기록 | 없음 | 없음 | T042, quickstart 7 |
