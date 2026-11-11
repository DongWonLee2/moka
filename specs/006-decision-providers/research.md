# Research: 판단 공급자 고르기와 키 넣기 (spec 006)

결정마다 결정, 이유, 검토한 대안을 적는다. R1~R3은 debate(2026-11-11 무인 실행, 로컬 `.audit/debate/20261111-spec006-clarify.md`, 커밋 안 함)로 정했고 사람 확인을 기다린다. R4 이후는 ADR-0011과 앞 spec을 근거로 에이전트가 정했고 PR "가정"에 적는다. 표결의 A·B·C는 가이드·실행·위험 자리다.

## R1. 열리지 않은 공급자의 첫 실제 호출 (spec R-617)

- 결정: 열리지 않은 공급자는 어느 빌드에서도 고를 수 없다. 공급자마다 그 공급자를 여는 브랜치를 만든다. 그 브랜치는 `ProviderCatalog`의 `firstCallConfirmed`를 참으로 바꾼다. Microsoft는 질문 파일 `models`에 기준 모델 ID도 더한다(data-model §5). 사람이 그 브랜치의 빌드에 자기 키를 넣어 첫 실제 호출을 확인하고, PASS/FAIL과 응답 필드 이름만 PR에 적은 뒤 병합으로 연다.
- 표결: 1라운드 3:0(C).
- 이유: ADR-0011:57 "확인 전인 공급자는 화면에서 고를 수 없게 둔다"를 그대로 지킨다. 빌드 구성 분기가 없어 시험할 경로가 하나다. 확인하지 않은 공급자가 배포 빌드에 새어 나갈 길이 없다.
- 대안: 확인용 빌드(Debug)에서만 고를 수 있게(빌드마다 다른 동작, 분기 시험 필요), "확인 전" 표시를 붙여 고를 수 있게(ADR 가정을 바꿔야 함).
- 결과: 고정 주소 공급자 셋은 v2에 기준 모델 ID가 이미 있어(ADR-0011 결정 3 예시) 여는 PR이 질문 버전을 올리지 않는다. Microsoft를 열거나 첫 호출에서 기준 모델 ID가 달라 고치면 질문 버전이 올라 모든 할 일을 다시 묻는다(ADR-0011 결정 6).

## R2. 온보딩 키 단계의 공급자 (spec R-624)

- 결정: 온보딩 키 단계는 기본 공급자 TypeSafe Jev 키만 받는다. 공급자 고르기와 Microsoft 칸은 두지 않는다. 다른 공급자는 온보딩을 끝낸 뒤 설정 창에서 고른다. 키 단계에도 보내는 곳(Jev 호스트)을 한 줄로 보인다(위험 자리 지적).
- 표결: 1라운드 3:0(C).
- 이유: 이 spec이 끝날 때 열린 공급자는 Jev 하나다(spec R-617). spec 004 시안 9~11번을 거의 그대로 쓰고 보류된 6번만 확정하면 된다. 온보딩 창은 AppState를 관찰하지 않아(spec 004 data-model §5) 공급자를 바꾸면 키 단계 상태를 다시 읽기 어렵다.
- 대안: 열린 공급자 가운데 고르고 Microsoft면 칸 셋(화면이 가장 큼), 고정 주소 공급자만 고르기(열린 공급자가 늘면 다시 바꿔야 함).
- 결과: `OnboardingKeyInput`은 `hasKey`, `onSave`, `issueURL`에 `host`만 더한다. 키 단계 저장은 `typesafe` 항목에 한다. 설정 표의 고른 공급자는 쓰지 않는다(없으면 Jev로 보므로).

## R3. Microsoft 배포 이름이나 주소를 바꿀 때 저장된 판단 결과 (spec R-616)

- 결정: 계속 쓴다. 보내기 장부를 비우고 키 확인 필요를 끈다. 판단 입력이 바뀐 할 일부터 새 배포 이름으로 다시 묻는다.
- 표결: 1라운드 2:1(A·B는 계속 씀, C는 강제로 모두 다시 묻기), 2라운드 3:0. 위험 자리는 1라운드 근거(공급자 바꾸기 경로를 다시 쓰면 된다)가 틀렸다고 인정했다. 배포 이름은 판단 입력에 없어 그 경로로는 다시 물을 할 일이 0건이고, 강제 경로는 해시를 무시하는 새 분기가 된다.
- 이유: ADR-0011:150이 이 결정을 Microsoft를 여는 PR로 미뤘다. 이 spec에서 Microsoft는 열리지 않아 판단 기능이 꺼져 있고, 섞일 점수가 없다. 하루가 바뀌면 판단 입력의 오늘이 바뀌어 어차피 모두 다시 묻는다.
- 대안: 해시와 상관없이 강제로 다시 묻기(새 분기, 새 답이 올 때까지는 옛 결과를 씀), 다시 물을 때까지 쓰지 않기(메모리 표시라 다시 켜면 동작이 달라짐).
- 남는 조건(사람이 볼 결정): Microsoft를 여는 PR에서 응답 `model`이 배포마다 실제 버전을 주는지 확인하고 이 결정을 다시 본다. 실제 버전을 주지 않아 튜닝에서 옛 배포 줄을 갈라야 하면 옛 결과를 쓰지 않는 쪽으로 간다.

## R4. 공급자 표 값과 발급 링크 (spec R-601)

- 결정: 공급자 표는 ADR-0011 결정 1 표 그대로다. 발급 링크는 조사 요약(2026-11-10) 값이고, 사람이 공식 문서에서 확인한 것만 `issueURLConfirmed`를 참으로 둔다. 확인 전 링크는 화면에 보이지 않는다.

  | 공급자 ID | 화면 이름 | 주소 | 인증 | 요청 모양 | 발급 링크 | 링크 확인 | 첫 호출 확인 |
  |---|---|---|---|---|---|---|---|
  | `typesafe` | TypeSafe Jev | `https://api.typesafe.ai/v1/systemone` | Bearer | System One | 없음 | 아니오 | 예(spec 003 SC-209) |
  | `microsoft` | Microsoft-Decision-1 | 사용자 리소스 주소 + `/providers/microsoft/v1/systemone` | `api-key` | System One | 없음 | 아니오 | 아니오 |
  | `liquid` | Liquid d1-ultra | `https://api.liquid.ai/decisions/v1/systemone` | Bearer | System One | `https://console.liquid.ai` | 아니오 | 아니오 |
  | `perplexity` | Perplexity Decider v1.2 | `https://api.perplexity.ai/v1/decisions` | Bearer | System One | `https://console.perplexity.ai` | 아니오 | 아니오 |
  | `openai` | OpenAI Decisions | `https://api.openai.com/v1/decisions` | Bearer | OpenAI | `https://platform.openai.com/api-keys` | 아니오 | 아니오 |

- 이유: 조사 요약은 조사자 요약이라 사람이 공식 문서에서 다시 본 값만 화면에 보이는 편이 안전하다. 링크 확인 여부는 공급자를 여는 PR이나 시안 확정 때 함께 바꾼다.
- 대안: 조사 요약 값을 바로 보임(틀린 페이지로 보낼 수 있음), 링크 칸을 두지 않음(spec 004 R-313 요구와 어긋남).
- 결과: 이 plan이 끝날 때 Jev 링크는 보이지 않는다. 시안 확정 때 사람이 TypeSafe 발급 주소를 찾으면 그 PR에서 참으로 바꾼다(시안 확정할 것).

## R5. 공급자를 다시 켜지 않고 바꾸는 방법 (spec R-615)

- 결정: `DecisionSetup`이 `bind: @MainActor (DecisionSelection.Ready) -> DecisionBinding`을 든다. `DecisionBinding`은 `provider`, `baseModel`, `requestModel`이다. 키 보관함은 바인딩과 따로 `keyStore: @MainActor (ProviderID) -> any KeyStore`로 받는다. 판단 기능이 꺼진 상태(예: Microsoft 주소 없음)에서도 키를 넣고, 바꾼 뒤 새 공급자 키를 읽고, Microsoft 키를 지우고, 온보딩에서 Jev 키를 써야 하기 때문이다(리뷰 지적 1). AppState는 지금 바인딩 하나를 `var`로 들고, 공급자를 바꾸거나 Microsoft 칸을 저장할 때 다시 만든다. 기존 `DecisionSetup(keyStore:provider:questions:)`는 고정 바인딩을 만드는 편의 생성자로 남긴다. 그때 기준 모델과 보낼 모델 이름은 질문 파일의 `typesafe` 기준 모델 ID다.
- 이유: ADR-0011 영향 절은 "AppState와 가짜 공급자 시험은 바뀌지 않는다"고 했다. 편의 생성자를 남기면 기존 앱 시험 호출이 그대로 컴파일되고, 기준 모델이 지금 Jev 값이라 임계값 기대값도 그대로다. `AppState`는 실제 공급자 타입을 모른다(앱 시험 번들이 그 파일을 컴파일하지 않음).
- 대안: 공급자를 바꾸면 앱을 다시 켜게 함(spec US2 시나리오 6과 어긋남), AppState가 `HTTPDecisionProvider`를 직접 만듦(시험 번들 경계가 깨짐).
- 결과: `DecisionSetup`은 앱 안쪽 타입이라 공개 계약이 아니다. 승인 항목이 아니다.

## R6. 바꾼 뒤 도착한 이전 공급자 답 (spec R-615)

- 결정: AppState에 `providerGeneration: Int`를 두고 바인딩을 바꿀 때마다 올린다. 질의는 떠날 때의 세대를 들고 가고, 답을 받을 때 세대가 다르면 저장하지 않고 `unauthorized`여도 키 확인 필요를 켜지 않는다. 장부에도 적지 않는다(바꿀 때 이미 비웠다). 실패 답(429, timeout 등)도 같다. 지금 `markFailed`는 해시만 비교하는데 판단 입력 해시는 공급자와 상관없이 같으므로, 세대를 먼저 보지 않으면 이전 공급자의 실패가 새 공급자 장부를 실패로 적어 다음 활성화까지 그 할 일을 묻지 않게 된다(리뷰 지적 2). 게이트 판정도 같은 세대 판정을 먼저 거친다. `ScoringPlan.accepts`는 바꾸지 않는다.
- 이유: 지금 `accepts`는 해시와 상태만 본다. 공급자를 바꿔도 판단 입력 해시는 같아서 이전 공급자 답이 그대로 저장되고, 그 줄의 공급자 칸이 이전 공급자라 `needsQuery`가 다시 묻게 되어 한 번 낭비한다. 세대 판정은 MainActor 동기 비교 하나다.
- 대안: 진행 중 질의 취소(spec 003은 취소 없음으로 정함), 답의 공급자 이름을 지금 공급자와 비교(공급자 ID가 같은 Microsoft 칸 저장을 구분하지 못함).
- 결과: 바꾼 직후 실행기가 아직 돌고 있으면 그 실행기가 다음 꺼냄부터 새 바인딩을 쓴다. 실행기는 꺼낼 때마다 바인딩을 다시 읽는다(spec 003 data-model §6의 "꺼낼 때마다 묻지 않는 경우를 다시 봄"과 같은 자리).

## R7. 리디렉트 거부 (spec R-618)

- 결정: 거부 판단은 MokaCore 순수 함수 `RedirectRule.follow(status:to:) -> URL?`(늘 `nil`)로 떼어 리눅스에서 시험한다. `HTTPDecisionProvider`의 세션 대리자 하나가 `urlSession(_:task:willPerformHTTPRedirection:newRequest:)`에서 이 함수의 값을 그대로 돌려준다. 따라가지 않은 3xx 응답은 그대로 `DecisionWire.decode(status:body:)`에 가 `server(status)`가 된다. 대리자는 저장 상태가 없는 `final class`라 `Sendable`을 선언할 수 있다.
- 이유: URLSession은 기본으로 리디렉트를 따라간다(ADR-0011 결정 2). 상태 코드 표에 3xx 줄을 더하지 않아도 "그 밖은 서버 오류" 규칙으로 떨어진다.
- 대안: `URLSessionConfiguration`에 끌 옵션이 없어 대리자 말고 길이 없다. 응답 뒤 `url`을 비교(이미 요청이 새 호스트로 간 뒤라 늦음).
- 결과: 자동 시험은 `RedirectRule`이 3xx 네 종류(301, 302, 307, 308)에 `nil`을 돌려주는 것과 `DecisionWire.decode`가 3xx를 `server(status)`로 보는 것이다. 대리자 연결은 앱 시험 번들 밖이라, 이 spec 동안 사람은 고정 주소 공급자 Jev로 대리자를 단 세션이 정상 응답을 막지 않는지 본다(quickstart 6-3). 실제 3xx를 받는 확인은 Microsoft를 여는 브랜치에서 loopback 로컬 서버로 한다(리뷰 지적 7).

## R8. 설정 키와 저장 (spec R-614)

- 결정: `CoreSettings`에 `decisionProviderKey = "decision_provider"`, `microsoftEndpointKey = "microsoft_endpoint"`, `microsoftDeploymentKey = "microsoft_deployment"`를 더한다. 값은 공급자 ID 문자열, 검사를 통과한 주소 문자열(앞뒤 공백 지움), 배포 이름(앞뒤 공백 지움)이다. 쓰기가 던지면 바꾸지 않고 실패 문구를 보인다.
- 이유: 기존 `default_extend_min`·`day_start`·`onboarding_done` 무늬다. `settings(key, value)` 표라 스키마가 그대로다.
- 대안: `UserDefaults`(앱 DB와 따로 저장되어 백업·이전이 갈림).
- 결과: 앱 DB를 열지 못하면 설정은 메모리로 동작한다(spec 002 R-119, `AppStorage.open`). 그동안 판단 결과 저장소가 없어 어차피 묻지 않는다. 고른 공급자는 다시 켜면 Jev로 돌아간다. 받아들인다.

## R9. 임계값이 없을 때 (spec R-609)

- 결정: `QuestionSet.thresholds(for:) -> ModelThresholds?`가 `nil`이면 게이트를 열지 않고, aging의 avoiding 판정은 임계값 미만(배율 1)으로 본다. 읽기 규칙 2를 통과한 파일에서는 `models`의 모든 값에 임계값이 있으므로, `nil`은 가짜 공급자 설정이 질문 파일에 없는 기준 모델을 넣은 시험에서만 생긴다.
- 이유: 강제 언래핑으로 멈추지 않게 한다(ADR-0011 결정 3). 임계값이 없을 때 avoiding을 높게 보면 미룬 할 일이 근거 없이 앞으로 온다. 낮게 보면 spec 003 키 없음 동작과 가깝다.
- 대안: 판단 기능 전체를 끔(`DecisionSelection`이 이미 그 경우를 끄므로 겹침), 0.7 같은 기본값(질문 파일 밖에 임계값을 두게 됨, AGENTS.md).

## R10. 보내는 곳과 잠정값 표시 (spec R-606·R-620·R-621)

- 결정: 보내는 곳은 다섯 공급자 모두에 보인다. 고정 주소는 표의 주소에서, Microsoft는 저장한 리소스 주소에서 `EndpointRule.host(of:)`로 꺼낸다. Microsoft 주소가 아직 없으면 보내는 곳 줄 대신 주소를 넣어 달라는 안내를 보인다. 잠정값 안내는 고른 공급자의 기준 모델이 `provisional`에 있을 때만 보인다.
- 이유: ADR-0011 평가 기준 5. 고정 주소 공급자도 제목이 외부로 간다.
- 대안: Microsoft만 보임(ADR 문장의 좁은 해석).

## R11. 튜닝 스크립트가 지난 버전 질문 파일을 읽을 곳 (승인 항목 2a, 열린 질문)

- 상태: 이 plan에서 정하지 않는다. ADR-0011 승인 항목 2의 열린 질문이고, 단위 2 PR에서 debate로 추천안을 정해 사람이 고른다.
- 선택지:
  - git 기록의 커밋이나 태그에서 읽는다. 태그는 사람이 만든다(AGENTS.md). 저장소에 사본이 늘지 않는다. 튜닝을 돌리는 곳에 git 기록이 있어야 한다.
  - 저장소에 버전별 사본(예: `tuning/questions/v1.json`, `v2.json`)을 둔다. 이 사본을 R13의 고정값 시험으로도 쓸 수 있다. 같은 내용이 둘 생긴다.
- 이 plan이 가정하는 최소: 단위 2의 pytest는 지금 파일 하나만 읽고 `models`의 모든 값에 임계값이 있는지 본다. 지난 버전 읽기는 마일스톤 5 튜닝 작업에서 만든다.

## R12. 바뀌는 시그니처와 기존 시험 (spec R-609·R-611)

- 결정:
  - `ScoreRules.usable(scores:hasKey:questionVersion:provider:)`
  - `ScoringPlan.needsQuery(tasks:scores:states:questionVersion:provider:)`
  - `ScoreRules.priority(_:task:today:thresholds:calendar:)`, `thresholds`는 `ModelThresholds?`
  - `ConcreteGate.Facts.threshold: Double?`, `ConcreteGate.threshold(_:baseModel:) -> Double?`
  - `QuestionSet`에서 `model`과 `avoidingThreshold`를 빼고 `models`, `provisional`, `thresholds(for:)`를 더한다.
  - 기존 시험은 호출에 `provider: "fake"`(또는 시험이 쓰던 이름)와 Jev 기준 모델 임계값을 넣어 고친다. 기대값은 바꾸지 않는다.
- 이유: 기본 인자를 두면 공급자 비교를 빠뜨린 호출이 컴파일되어 섞임을 막지 못한다. 기본값 없이 모든 호출이 공급자를 넘기게 한다.
- 대안: 기본값 `provider: nil`(비교 생략 경로가 남음).
- 결과: 시험 호출을 고친 이유를 단위 2 PR에 적는다(테스트 약화 아님).

## R13. 버전별 고정값(golden) 시험 자리 (spec R-608)

- 결정: `Tests/MokaCoreTests/QuestionSetV2Tests.swift` 안에 버전 문자열을 키로 `models`·`thresholds` 고정값 사전을 둔다. v1 줄(`typesafe`에 `jev-1.13.0`, 임계값 0.5·0.7)도 기록한다. 지금 파일의 `version`이 사전에 없으면 실패하고, 있으면 값이 같아야 한다.
- 이유: ADR-0011 읽기 규칙 3. 시험 파일 하나라 리눅스 CI에서 돈다. v1 줄은 이미 쌓인 `(v1, typesafe)` 판단 결과 줄을 풀 때의 기준을 남긴다.
- 대안: 별도 JSON 픽스처(R11 결정과 겹쳐 지금 정하면 그 선택을 앞질러 함).

## R14. `moka-sim`과 시험의 가짜 공급자 (spec R-628)

- 결정: `SimStorageRunner`는 가짜 공급자 이름 `fake`와 기준 모델 ID를 직접 받는다. 기준 모델 ID는 질문 파일의 `typesafe` 값(지금 `jev-1.13.0`)이다. `usable`·`needsQuery`에는 `fake`를 넘긴다. 저장되는 판단 결과의 공급자 칸도 `fake`라 비교가 맞다.
- 이유: ADR-0011 결정 6과 영향 절. 기대 출력이 바뀌지 않는다. `fake`는 `models`에 없지만 `DecisionSelection`을 거치지 않으므로 판단 기능이 꺼지지 않는다.
- 대안: `models`에 `fake` 줄 추가(공개 계약 파일에 시험 값이 섞임).
