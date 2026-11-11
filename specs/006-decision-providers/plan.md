# Implementation Plan: 판단 공급자 고르기와 키 넣기

**Branch**: `chore/spec-006-decision-providers` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: `specs/006-decision-providers/spec.md`(R-601~R-630), ADR-0011, 확인 질문 셋 debate(research R1~R3)

## Summary

ADR-0011을 구현한다. MokaCore에 공급자 표 다섯 줄, System One 코덱(지금 `TypeSafeCodec`의 새 이름), OpenAI 변환 코덱, 주소 허용 규칙을 두어 리눅스 `swift test`로 확인한다. 질문 파일은 v2로 올려 공급자 ID에서 기준 모델 ID를 찾는 표 `models`를 두고, 임계값은 기준 모델 ID로 읽는다. 쓰는 판단 결과와 다시 물을 할 일에는 공급자 비교를 더한다. 앱은 실제 공급자를 `HTTPDecisionProvider` 하나로 바꾸고, Keychain 항목을 공급자마다 두며, 고른 공급자를 설정 표에 둔다. 설정 창 기본 탭은 공급자 고르기와 보내는 곳을 보이고, 온보딩 맨 앞에 Jev 키 단계를 더하며, 할 일 탭에 키 확인 한 줄을 더한다(spec 004 단위 4). 스키마, `moka-sim` 형식과 기대 출력, 로그 값은 바꾸지 않는다. 규칙 원본은 [data-model.md](data-model.md), 결정 근거는 [research.md](research.md), 공개 계약은 [contracts/](contracts/)다.

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001), Python 3(튜닝 계약 pytest)

**Primary Dependencies**: GRDB 7.11.1(기존). 새 의존성 없음

**Storage**: 스키마 그대로. 고른 공급자, Microsoft 리소스 주소, 배포 이름은 기존 `settings(key, value)` 표의 새 키 셋. 키는 Keychain 공급자별 항목

**Testing**: Swift Testing(`MokaCoreTests`, 리눅스 CI `core-test`), XCTest `MokaAppTests`(macOS 로컬과 CI `app-snapshots`, 필수 아님), pytest(`tuning-test`). 가짜 공급자와 가짜 키 보관함만 쓴다

**Target Platform**: macOS 14+ 메뉴 막대 앱(ADR-0005), Package는 리눅스에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package

**Performance Goals**: 질의 시간 한도 3초(`Defaults.decisionTimeout`) 그대로. 공급자를 바꾼 뒤 다음 질의부터 새 공급자로 간다. 노치 펼침·접힘 100ms(PRD FR-06)를 지킨다

**Constraints**: 실제 판단 API, Keychain, 앱 DB는 시험·CI에서 열지 않는다(헌법 VIII). 기존 golden 바이트와 `moka-sim` 기대 출력 그대로. `@unchecked Sendable` 금지. 로그에 주소·호스트·키·제목 없음

**Scale/Scope**: MokaCore 새 파일 넷 남짓(공급자 표, OpenAI 코덱, 주소 규칙, 공급자 선택), 고치는 파일 다섯(코덱 이름, 질문 파일, 점수 규칙, 다시 묻기, 게이트), 앱 공급자 파일 하나 교체, 뷰 셋(기본 탭, 할 일 탭, 온보딩), 새 스냅샷 상태 열 남짓

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

확인 질문 셋은 2026-11-11 무인 실행에서 debate로 정했다(최종 모두 3:0, 기록은 로컬 `.audit/debate/20261111-spec006-clarify.md`, 커밋 안 함). 나머지는 에이전트 판단이며 research R4~R14와 PR "가정"에 있다.

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 항목 넷, 아래 표) | DecisionProvider 뜻 변경과 `questions.json` v2는 ADR-0011 승인 항목 1·2 그대로다. 구현 PR에서 사람이 승인한다. 스키마는 바꾸지 않는다 |
| II 테스트 먼저, 약화 금지 | 통과 | R-ID마다 Red 커밋 다음 Green 커밋. 코덱 이름 변경은 기존 시험을 이름만 바꿔 PASS로 지킨다. `usable`·`needsQuery`·`ConcreteGate` 시그니처가 바뀌어 기존 시험 호출을 고치지만 기대값은 바꾸지 않는다(research R12) |
| III 네 가지로만 보고 | 통과 | quickstart. 실제 호출과 리디렉트, 새 사용자 첫 실행은 사람이 하고, 하지 않으면 NOT_RUN |
| IV 같은 실패 2회 중단 | 통과 | 해당 시 handoff |
| V 작은 PR | 통과 | 아래 작업 단위 다섯을 각각 PR로 |
| VI ID로 추적 | 통과 | 시험 표시 이름 `ADR-0011 R-6xx`, 온보딩은 `FR-21 R-62x`, 키 확인은 `FR-14 R-627`(ADR-0003) |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음 |
| VIII 판단 모델은 판단만 | 통과 | 판단 입력은 spec 003 그대로이고 공급자와 상관없다. 실제 공급자 파일은 앱 타깃에만 있고 시험 번들은 컴파일하지 않는다(ADR-0001, spec 003 SC-207) |
| 보안·사용자 데이터 | 통과 | 키는 공급자별 Keychain 항목에만. 사용자 주소는 허용 규칙을 거쳐야 저장. 주소를 바꾸면 키를 지운다. 리디렉트를 따라가지 않는다. 픽스처와 시안은 가짜 예시 |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 승인 항목

ADR-0011 승인 항목과 같은지 표시한다.

| # | 항목 | 이 plan | ADR-0011과 | 계약 문서 |
|---|---|---|---|---|
| 1 | DecisionProvider 경계: 프로토콜 모양 유지, `name`은 공급자 ID, `DecisionRequest.model`은 보낼 모델 이름, `TypeSafeCodec`을 `SystemOneCodec`으로, `OpenAIDecisionsCodec` 추가 | 단위 1 | 같음(승인 항목 1) | [contracts/decision-provider-v2.md](contracts/decision-provider-v2.md)가 spec 003 contracts/decision-provider.md를 대체 |
| 2 | `questions.json` v2: `models`, `provisional`, 읽기 규칙, 버전별 고정값 시험, pytest 계약 | 단위 2 | 같음(승인 항목 2) | [contracts/questions-json-v2.md](contracts/questions-json-v2.md)가 spec 003 contracts/questions-json.md를 대체 |
| 2a | 튜닝 스크립트가 지난 버전 질문 파일을 읽을 곳 | research R11. 단위 2 PR #122에서 debate 3:0으로 B안(루트 `questions-history/` 사본) 채택, 병합이 승인 | 같음(승인 항목 2의 열린 질문) | 같은 문서 |
| 3 | 스키마 | 변경 없음 | 같음(승인 항목 3) | 없음 |
| 4 | 헌법 VIII·AGENTS.md 예시 문구 PATCH 개정 제안 | 단위 1 PR "사람이 볼 결정"에 올린다. 고치지 않는다 | 같음(승인 항목 4) | 없음 |

ADR-0011 밖에서 생긴 승인 항목은 없다. `moka-sim` 시나리오 형식, 의존성, CI, `user_action`·`scheduler_choice` 값은 바꾸지 않는다.

| 바꿀 수 있었던 것 | 이 plan | 근거 |
|---|---|---|
| 판단 결과에 기준 모델 열 추가 | 두지 않음 | ADR-0011 결정 6, 사용자 결정 2026-11-11 |
| 확인용 빌드 분기 | 두지 않음 | research R1 |
| `moka-sim`에 공급자 이벤트 추가 | 두지 않음 | spec R-628 |

### 가정

- 이름: `ProviderID`, `ProviderConfig`, `ProviderCatalog`, `RequestShape`, `AuthStyle`, `SystemOneCodec`, `OpenAIDecisionsCodec`, `DecisionWire`, `EndpointRule`, `EndpointRejection`, `ModelThresholds`, `DecisionSelection`, `DecisionBinding`, `HTTPDecisionProvider`, `DecisionFieldInput`, `providerGeneration`.
- 설정 키: `decision_provider`, `microsoft_endpoint`, `microsoft_deployment`(`CoreSettings` 무늬, research R8).
- 발급 링크와 첫 호출 확인 여부는 `ProviderCatalog` 한 곳에 둔다. 이 plan이 끝날 때 `firstCallConfirmed`가 참인 줄은 `typesafe` 하나다.
- 잠정 임계값은 Jev 값(`concrete 0.5`, `avoiding 0.7`)을 그대로 옮긴다. 이전 값 없음, 새 값은 Jev 값과 같다. 값은 `questions.json`에 두고 `Defaults.swift`에는 두지 않는다(AGENTS.md).

## Project Structure

### Documentation (this feature)

```text
specs/006-decision-providers/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── decision-provider-v2.md   # spec 003 contracts/decision-provider.md 대체
│   └── questions-json-v2.md      # spec 003 contracts/questions-json.md 대체
├── checklists/requirements.md
└── tasks.md                      # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/MokaCore/
├── Decision/SystemOneCodec.swift      # TypeSafeCodec.swift의 새 이름(내용 그대로)
├── Decision/OpenAIDecisionsCodec.swift # 새: 요청·응답 변환
├── Decision/DecisionWire.swift        # 새: 요청 모양에 따라 두 코덱 가운데 하나를 고름
├── Decision/ProviderCatalog.swift     # 새: ProviderID, ProviderConfig, 공급자 표 다섯 줄
├── Decision/EndpointRule.swift        # 새: 주소 허용 규칙, 호스트 꺼내기, RedirectRule
├── Decision/DecisionSelection.swift   # 새: 설정 값과 질문 파일로 고른 공급자·기준 모델·보낼 모델 이름을 정함
├── Decision/QuestionSet.swift         # v2 읽기, models, provisional, thresholds(for:)
├── Decision/ScoreRules.swift          # usable에 공급자, priority는 기준 모델 임계값
├── Decision/ScoringPlan.swift         # needsQuery에 공급자
├── Decision/ConcreteGate.swift        # threshold가 Double?, 강제 언래핑 제거, 기다리는 중 nil이면 통과
├── PriorityOrder.swift                # priority 호출에 기준 모델 임계값을 넘김
├── NotchSession.swift                 # SessionScoring에 thresholds
├── Resources/questions.json           # v2(사람 승인)
├── CoreSettings.swift                 # 설정 키 셋
└── Sim/SimStorageRunner.swift         # 가짜 공급자 설정에 기준 모델 ID를 직접 넣음(기대 출력 그대로)
App/Sources/
├── Decision/HTTPDecisionProvider.swift # TypeSafeProvider.swift를 대체, 리디렉트 거부
├── Decision/KeychainKeyStore.swift    # account 인자
├── AppState.swift                     # DecisionBinding 교체, providerGeneration, 공급자 바꾸기, Microsoft 칸 저장
├── MokaApp.swift                      # 설정 값으로 바인딩을 만드는 방법을 넘김, 온보딩 키 단계
├── Views/BasicTabView.swift           # 판단 모델 칸(공급자 고르기, 보내는 곳, Microsoft 칸)
├── Views/KeyFieldState.swift          # 칸 제목만 공급자 이름을 받음
├── Views/TaskListTabView.swift        # 키 확인 한 줄(spec 004 T026·T027)
├── Views/OnboardingView.swift         # 키 단계(Jev)
└── Settings/SettingsView.swift        # 새 인자 전달, settingsTabRequest 소비
Tests/MokaCoreTests/ ProviderCatalogTests, OpenAIDecisionsCodecTests, EndpointRuleTests, QuestionSetV2Tests, DecisionSelectionTests(새), 기존 TypeSafeCodecTests는 SystemOneCodecTests로 이름만
App/Tests/MokaAppTests/ AppProviderTests(새), AppDecisionTests, SettingsSnapshotTests
tuning/tests/test_questions_contract.py
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 타깃과 의존성은 없다. 공급자 표, 코덱, 주소 규칙은 MokaCore에 두어 리눅스에서 시험한다. `HTTPDecisionProvider`와 `KeychainKeyStore`는 앱 타깃에만 두고 앱 시험 번들이 컴파일하지 않는다(research R19 F3 무늬 그대로). 뷰는 `AppState`를 모르게 값과 콜백만 받는다(ADR-0009).

### 앱 연결

- `DecisionSetup`은 공급자 하나 대신 `bind: @MainActor (DecisionSelection.Ready) -> DecisionBinding`을 든다. `DecisionBinding`은 공급자, 기준 모델 ID, 보낼 모델 이름이다. 키 보관함은 판단 기능이 꺼져 있어도 써야 하므로 `keyStore: @MainActor (ProviderID) -> any KeyStore`로 따로 받는다. 기존 3인자 생성(`keyStore:provider:questions:`)은 고정 바인딩을 만드는 편의 생성자로 남겨 기존 앱 시험을 고치지 않는다(research R5).
- 공급자 바꾸기는 AppState 한 함수(`selectProvider(_:)`)다. 설정 표 쓰기, `providerGeneration` 올림, 바인딩 교체, 장부 비움, `keyNeedsCheck = false`, `keyStore(for:)`로 `hasKey` 다시 읽기, `requestScores()` 순서다(data-model §6).
- 질의는 떠날 때의 `providerGeneration`을 들고 가고, 답을 받을 때 지금 값과 다르면 버린다. `unauthorized`와 그 밖의 실패(장부의 실패 표시), 게이트 판정도 같은 판정을 먼저 거친다(research R6).
- 리디렉트 거부 판단은 MokaCore `RedirectRule`이고, `HTTPDecisionProvider`의 세션 대리자 하나가 그 값을 돌려준다. 3xx는 따라가지 않은 응답 그대로 `DecisionWire.decode`에 가 `server(status)`가 된다(research R7).

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 승인 | 시안 확정 | 무인 가능 | 앞선 단위 |
|---|---|---|---|---|---|---|
| 1 | MokaCore 공급자 표와 코덱: 코덱 이름 변경, OpenAI 변환 코덱, 공급자 표, 주소 규칙, 호스트, 계약 문서 v2, 대체 표기 | R-601·602·603·604·605·606·630(일부) | 1, 4 | 아니오 | 예(병합은 사람 승인) | ADR-0011 병합 |
| 2 | 질문 파일 v2와 판단 결과 규칙: `questions.json` v2, 읽기 규칙, 고정값 시험, `usable`·`needsQuery` 공급자 비교, 게이트·aging 임계값, `DecisionSelection`, `SimStorageRunner`, AppState 호출 고침, pytest 계약 | R-607·608·609·610·611·612·630(일부) | 2, 2a | 아니오 | 예(병합은 사람 승인) | ADR-0011 병합. 질문 파일 쪽은 단위 1과 병렬, `isOpen`·`DecisionSelection`은 단위 1의 공급자 표 뒤 |
| 3 | 앱 공급자 설정과 키: `HTTPDecisionProvider`, Keychain account, 설정 키 셋, 바인딩 교체, 공급자 바꾸기, Microsoft 칸 저장과 키 지움, 세대 판정, 앱 시험 | R-613·614·615·616·617·618·619 | 없음 | 아니오 | 코드는 가능, 리디렉트와 업그레이드 확인은 사람 | 1, 2 |
| 4 | 설정 창 화면: 판단 모델 칸, 잠정값 안내, 바꾸기 안내, Microsoft 칸, 할 일 탭 키 확인 한 줄, 스냅샷 | R-620·621·622·623·627 | 없음 | 예(006 시안) | 코드는 가능, 화면 확정은 사람 | 3 |
| 5 | 온보딩 키 단계(Jev): 키 단계, 보내는 곳 줄, 저장·실패·이미 있음, 스냅샷 | R-624·625·626·630(spec 004 R-313 대체 표기) | 없음 | 예(006 시안 온보딩 줄, 004 시안 9~11번) | 코드는 가능, 새 사용자 첫 실행은 사람 | 3. 단위 4와 병렬 |

R-628(가짜만, 스키마와 `moka-sim` 그대로)은 모든 단위에 걸친다. R-629(공급자별 첫 실제 호출)는 이 plan의 단위가 아니다. 공급자마다 그 공급자를 여는 작은 PR이고, quickstart 7에 절차가 있다.

순서: 1과 2를 나란히 시작하되 2는 1이 먼저 병합된 뒤 병합한다(tasks 의존). 그다음 3, 그다음 4와 5를 나란히. 시안 `006-mockup.html`은 단위 1·2와 함께 확정을 받는다. 밀리면 단위 5를 먼저 다음 spec으로 넘긴다(spec 004 위험 1과 같은 순서).

## ADR-0011·앞 spec 대조

| 출처 | 이 plan | 처리 |
|---|---|---|
| ADR-0011 영향 "AppState와 가짜 공급자 시험은 바뀌지 않는다" | `DecisionSetup`에 바인딩 함수를 더하고 기존 3인자 생성을 남김 | research R5 |
| ADR-0011 결정 6 공급자 비교 | `usable`·`needsQuery`에 공급자 인자, 바꾼 뒤 도착한 답은 세대로 버림 | research R6 |
| ADR-0011 결정 6 남는 빈틈(배포 이름) | 저장된 결과를 계속 씀, Microsoft를 여는 PR에서 다시 봄 | research R3 |
| ADR-0011 가정 "확인 전 공급자는 고를 수 없음" | 빌드 분기 없이 여는 브랜치의 빌드로 확인 | research R1 |
| spec 003 R-213 칸 제목 "판단 모델 키 (TypeSafe)" | 고른 공급자 이름을 따름 | spec R-620, 기존 스냅샷 참조 이미지가 바뀌면 PR에 이유 |
| spec 003 contracts 둘 | 이 spec contracts 둘이 대체 | 대체 표기(R-630) |
| spec 004 R-313 TypeSafe 링크 하나 | Jev만 받는 키 단계, 보내는 곳 줄 추가 | research R2 |
| spec 004 T017~T021·T026~T028 | 이 plan 단위 4·5가 담는다 | spec 004 tasks에 대체 표기 |

## 위험

spec "대안과 위험"의 번호와 같다.

- 위험 1(열린 공급자 하나): 이 plan이 끝나도 사용자가 고를 수 있는 공급자는 Jev 하나다. 공급자마다 여는 PR과 사람 확인이 필요하다. 공급자 넷의 여는 PR은 Issue로 따로 만든다.
- 위험 2(질문 파일 v2 비용): 단위 2가 병합되는 순간 모든 할 일을 다시 묻는다. 단위 2 PR "사람이 볼 결정"에 적는다.
- 위험 3(배포 이름 빈틈): 저장된 Microsoft 판단 결과를 계속 쓴다. Microsoft가 열리기 전에는 판단 기능이 꺼져 섞이지 않는다.
- 위험 4(시안): 단위 4·5는 시안 확정 뒤다.
- 위험 5(개인정보): 공급자를 바꾸면 모든 할 일 제목이 새 공급자로 간다. 보내는 곳 표시로 알린다.
- 위험 6(사람 확인): 리디렉트, 업그레이드한 Jev 사용자의 판단 결과, 새 사용자 온보딩, 공급자별 첫 실제 호출.
- 위험 7(시그니처 변경 폭): `usable`·`needsQuery`·`ConcreteGate.Facts.threshold`·`ScoreRules.priority`의 인자가 바뀌어 기존 MokaCore 시험과 `SimStorageRunner`, AppState 호출이 함께 바뀐다. 기대값은 그대로 두고 호출만 고친다. 기대 출력이 바뀌면 멈추고 원인을 본다.
- 위험 8(OpenAI 응답 미확인): OpenAI score 답의 칸이 문서와 다르면 변환 코덱을 첫 실제 호출 뒤 고친다. OpenAI가 열리기 전이라 사용자 영향은 없다.

## 다음 단계

1. `/speckit-tasks`
2. 시안 `006-mockup.html` 사람 확정
3. ADR-0011(PR #116) 병합 뒤 이 spec PR 병합, Issue 큐(단위 1과 2, 3, 4와 5)
