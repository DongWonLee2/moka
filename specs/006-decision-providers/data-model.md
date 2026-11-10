# Data Model: 판단 공급자 고르기와 키 넣기 (spec 006)

규칙의 원본이다. 결정 이유는 [research.md](research.md), 공개 계약은 [contracts/](contracts/)다. 이름은 GLOSSARY를 따른다. 타입 이름은 구현 PR에서 다듬을 수 있으나 바꾸면 PR "가정"에 적는다. spec 003 data-model과 spec 004 data-model 가운데 여기 적지 않은 규칙은 그대로다.

## 1. MokaCore 값 타입

새로 두는 것:

| 타입 | 모양 | 비고 |
|---|---|---|
| `ProviderID` | `enum: String, CaseIterable, Sendable { typesafe, microsoft, liquid, perplexity, openai }` | 원시값이 공급자 ID다. `fake`·`fallback`은 들지 않는다(GLOSSARY) |
| `RequestShape` | `enum { systemOne, openAI }` | |
| `AuthStyle` | `enum { bearer, apiKeyHeader }` | `Authorization: Bearer <키>` 또는 `api-key: <키>` |
| `ProviderEndpoint` | `enum { fixed(URL), userResource(path: String) }` | Microsoft만 `userResource("/providers/microsoft/v1/systemone")` |
| `ProviderConfig` | `id`, `displayName`, `endpoint: ProviderEndpoint`, `auth`, `shape`, `issueURL: URL?`, `issueURLConfirmed: Bool`, `firstCallConfirmed: Bool` | 줄 하나. `func url(resource: URL?) -> URL?`는 고정이면 그 주소, 사용자 주소면 리소스 주소에 경로를 붙인 값이고, 리소스가 없으면 `nil` |
| `ProviderCatalog` | `static let all: [ProviderConfig]`(다섯, 표 순서는 research R4), `static func config(_: ProviderID, in catalog: [ProviderConfig] = all) -> ProviderConfig?`, `static func isOpen(_: ProviderID, questions: QuestionSet, catalog: [ProviderConfig] = all) -> Bool` | 둘 다 주입한 `catalog`에서 `first(where:)`로 찾는다. 강제 언래핑하지 않는다. 배열에 없으면 `config`는 `nil`, `isOpen`은 거짓이다. `isOpen` = 그 줄의 `firstCallConfirmed && questions.models[id.rawValue] != nil` |
| `SystemOneCodec` | `body(_:)`, `response(_:)`, `decode(status:body:)` | `TypeSafeCodec`의 새 이름, 내용 그대로 |
| `OpenAIDecisionsCodec` | 같은 세 함수 | 규칙은 contracts/decision-provider-v2.md |
| `DecisionWire` | `static func body(_: DecisionRequest, shape:) -> Data`, `static func decode(status:body:shape:) throws(DecisionError) -> DecisionResponse` | 요청 모양에 따라 두 코덱 가운데 하나를 부른다. 앱 공급자는 이것만 부른다 |
| `EndpointRejection` | `enum { unparseable, scheme, emptyHost, userInfo, query, fragment, path }` | 화면 거부 문구의 종류 |
| `EndpointRule` | `static func check(_ text: String, allowsPath: Bool) -> Result<URL, EndpointRejection>`, `static func host(of: URL) -> String` | §4 |
| `RedirectRule` | `static func follow(status: Int, to: URL?) -> URL?` | 늘 `nil`이다. 앱 세션 대리자가 이 함수만 부르고 그 값을 그대로 돌려준다. 그래서 거부 판단을 리눅스 시험으로 지킨다(research R7) |
| `ModelThresholds` | `concrete: Double`, `avoiding: Double` | |
| `DecisionSelection` | `static func resolve(providerID: String?, microsoftEndpoint: String?, microsoftDeployment: String?, questions: QuestionSet, catalog: [ProviderConfig] = ProviderCatalog.all) -> Resolution` | §6. `catalog`은 시험이 Microsoft를 연 가짜 표를 넣을 때만 바꾼다. `DecisionSetup`도 같은 기본값의 `catalog`를 든다 |
| `DecisionSelection.Resolution` | `ready(Ready)`, `off(OffReason)` | |
| `DecisionSelection.Ready` | `config: ProviderConfig`, `url: URL`, `baseModel: String`, `requestModel: String` | |
| `DecisionSelection.OffReason` | `unknownProvider`, `closedProvider(ProviderID)`, `needsEndpoint`, `needsDeployment` | 꺼진 이유. 화면 안내와 로그 한 줄에 쓴다 |

고치는 것:

| 타입 | 지금 | 바뀐 뒤 |
|---|---|---|
| `QuestionSet` | `model: String`, `avoidingThreshold: Double` | 둘을 빼고 `models: [String: String]`, `provisional: Set<String>`, `func thresholds(for baseModel: String) -> ModelThresholds?`를 더한다. `version`, `language`, `questions`, `thresholds`(원본 사전)는 그대로 |
| `ScoreRules.usable` | `(scores:hasKey:questionVersion:)` | `(scores:hasKey:questionVersion:provider:)`. 키가 있고, 질문 버전이 같고, `score.provider == provider`인 것만 |
| `ScoreRules.priority` | `(_:task:today:questions:calendar:)` | `(_:task:today:thresholds:calendar:)`. `thresholds`가 `nil`이면 avoiding 배율 1 |
| `ScoringPlan.needsQuery` | `(tasks:scores:states:questionVersion:)` | `(tasks:scores:states:questionVersion:provider:)`. 판단 결과의 공급자가 다르면 다시 묻는다. 순서 규칙(판단 결과 없는 할 일 먼저, id 오름차순)에서 공급자가 다른 결과는 "있음"으로 센다 |
| `ConcreteGate.threshold` | `(_ questions:) -> Double`(강제 언래핑) | `(_ questions:, baseModel:) -> Double?` |
| `ConcreteGate.Facts.threshold` | `Double` | `Double?`. `nil`이면 `phase`가 열지 않는다. 게이트가 재판정을 기다리는 중에 `nil`이 되면 `afterAnswer`는 통과로 본다(spec 004 R-309의 "물을 수 없게 되면 통과"와 같은 쪽) |
| `SessionScoring` | `usable`, `questions`, `today` | `thresholds: ModelThresholds?`를 더한다. 순서 계산이 `priority`에 넘긴다 |
| `CoreSettings` | 키 셋 | `decisionProviderKey`, `microsoftEndpointKey`, `microsoftDeploymentKey`와 읽기·쓰기 함수를 더한다 |

`Defaults`에는 더하는 값이 없다. 임계값은 `questions.json`에 둔다(AGENTS.md).

## 2. 공급자 표

값은 research R4 표다. 시험은 다섯 줄의 공급자 ID, 주소, 인증, 요청 모양을 고정값과 비교하고, 이 plan이 끝날 때 `firstCallConfirmed`가 참인 줄이 `typesafe` 하나인지 본다. 공급자를 여는 PR은 이 시험의 기대값을 함께 바꾼다(R1).

## 3. 요청 모양

- System One 넷: `SystemOneCodec` 그대로. 공급자마다 다른 것은 주소, 인증 헤더, 요청 `model`(보낼 모델 이름)뿐이다.
- OpenAI: `OpenAIDecisionsCodec`. 본문과 응답 변환은 contracts/decision-provider-v2.md "OpenAI 모양".
- 상태 코드 표는 두 모양이 같다(401·403 `unauthorized`, 429 `rateLimited`, 529 `overloaded`, 200만 본문 해석, 200이 아닌 2xx를 포함한 그 밖은 `server(status)`). spec 003 계약과 지금 `TypeSafeCodec.decode` 그대로다. 3xx도 `server(status)`다(research R7).

## 4. 주소 규칙 (`EndpointRule.check`)

입력은 앞뒤 공백·줄바꿈을 지운 글자다. 아래 순서로 처음 걸린 거부 이유를 돌려준다.

1. URL로 읽지 못하거나 스킴·호스트 모양이 아니면 `unparseable`.
2. 사용자 정보(`user@`, `user:pass@`)가 있으면 `userInfo`.
3. 호스트가 비었으면 `emptyHost`.
4. 스킴이 `https`가 아니면, `http`이고 호스트가 loopback일 때만 받는다. 아니면 `scheme`. loopback은 대괄호를 벗기고 소문자로 바꾼 호스트가 `localhost`, `127.0.0.1`, `::1` 가운데 하나인 것이다.
5. 쿼리(`?`)가 있으면 `query`. 빈 쿼리(`?`만)도 거부한다.
6. 조각(`#`)이 있으면 `fragment`. 빈 조각도 거부한다.
7. `allowsPath`가 거짓이고 경로가 비어 있지도 `/`도 아니면 `path`.

통과하면 끝의 `/`를 뗀 URL을 돌려준다. `host(of:)`는 대괄호를 벗긴 소문자 호스트다. 포트는 보내는 곳에 넣지 않는다.

시험 사례(SC-603):

| 입력 | 결과 |
|---|---|
| `https://example-resource.invalid` | 받음 |
| `https://example-resource.invalid/` | 받음(끝 `/` 뗌) |
| `http://localhost:8080` | 받음 |
| `http://LOCALHOST` | 받음 |
| `http://127.0.0.1:9000` | 받음 |
| `http://[::1]:8080` | 받음, 호스트 `::1` |
| `http://example-resource.invalid` | `scheme` |
| `ftp://example-resource.invalid` | `scheme` |
| `https://` | `emptyHost` 또는 `unparseable`(구현 PR에서 하나로 정해 시험에 적음) |
| `https://user:pass@example-resource.invalid` | `userInfo` |
| `https://example-resource.invalid?x=1` | `query` |
| `https://example-resource.invalid#a` | `fragment` |
| `https://example-resource.invalid/openai` | `path`(Microsoft) |
| `example-resource.invalid` | `unparseable` |

## 5. 질문 파일 v2

형식과 읽기 규칙은 contracts/questions-json-v2.md. 읽은 값:

- `models`: 공급자 ID 문자열에서 기준 모델 ID로. `fake`는 없다.
- `provisional`: 잠정 임계값 기준 모델 ID 집합. `models` 값의 부분집합이어야 한다(읽기 규칙 4).
- `thresholds(for:)`: `thresholds[baseModel]`에서 `concrete`·`avoiding`을 꺼낸다. 없으면 `nil`.

v2 `models`는 ADR-0011 결정 3 예시 그대로 넷(`typesafe`, `liquid`, `perplexity`, `openai`)이고 Microsoft 줄은 없다. `provisional`은 Jev를 뺀 셋이다. 기준 모델 ID가 있어도 `firstCallConfirmed`가 거짓이면 열리지 않는다. 그래서 고정 주소 공급자를 여는 PR은 공급자 표만 바꾸고 `version`을 올리지 않는다. 첫 실제 호출에서 기준 모델 ID가 다르다고 나오면(예: Liquid 고정 버전 규칙) 그 PR에서 `version`을 올린다. Microsoft를 여는 PR은 `models`에 줄을 더하므로 `version`을 올린다.

## 6. 고른 공급자 정하기와 바꾸기

**정하기**(`DecisionSelection.resolve`, 순수 함수):
1. `providerID`가 `nil`이면 `typesafe`로 본다.
2. `ProviderID(rawValue:)`가 `nil`이면 `off(.unknownProvider)`.
3. `ProviderCatalog.isOpen(id, questions:, catalog:)`이 거짓이면 `off(.closedProvider(id))`. 줄은 주입한 `catalog`에서 찾는다.
4. 기준 모델 ID는 `questions.models[id]`다(3에서 있음이 보장됨).
5. Microsoft면 저장된 주소를 `EndpointRule.check(allowsPath: false)`로 다시 보고, 없거나 거부면 `off(.needsEndpoint)`. 배포 이름이 비면 `off(.needsDeployment)`. 보낼 모델 이름은 배포 이름이다.
6. 나머지는 보낼 모델 이름이 기준 모델 ID이고, `url`은 고정 주소다.
7. `ready(Ready)`.

`off`면 AppState는 판단 기능을 끈 것처럼 동작한다. 질의를 보내지 않는다. `input(at:)`의 `scoring`은 `nil`이라 노치는 마감일 순이다. 이유 줄에는 손해 칸이 없고(spec 004 R-303), 게이트는 열지 않는다. 로그는 `OffReason` 종류만 한 줄 남긴다. 키 칸은 그대로 보이고 키를 넣을 수 있다. 키는 바인딩이 아니라 `keyStore(for: selectedProvider)`로 다룬다(§8). `unknownProvider`면 고른 공급자가 없으므로 키 칸 대신 공급자를 다시 골라 달라는 안내만 보이고 키 동작은 끈다.

**바꾸기**(`AppState.selectProvider(_ id: ProviderID)`, MainActor):
1. 지금과 같으면 아무것도 하지 않는다.
2. `ProviderCatalog.isOpen(id, questions:, catalog: setup.catalog)`가 거짓이면 아무것도 하지 않는다(화면이 막지만 한 번 더 본다).
3. 설정 표에 `decision_provider`를 쓴다. 던지면 바꾸지 않고 `providerActionFailure = .select`를 켠다.
4. `selectedProvider = id`, `providerGeneration += 1`, 바인딩을 다시 만든다(`resolve`가 `ready`면 `bind`, `off`면 `nil`). `providerActionFailure = nil`.
5. `attempted = [:]`, `keyNeedsCheck = false`, `keyActionFailure = nil`.
6. `hasKey`를 `keyStore(for: id)`로 다시 읽는다. 바인딩이 `nil`(off)이어도 읽는다.
7. `requestScores()`.

**Microsoft 칸 저장**(`AppState.saveMicrosoft(endpoint:deployment:)`):
1. 두 값의 앞뒤 공백·줄바꿈을 지운다. 비면 저장하지 않는다(화면이 저장을 끔).
2. 주소를 `EndpointRule.check(allowsPath: false)`로 본다. 거부면 저장하지 않고 이유를 돌려준다.
3. 저장된 주소가 있고 새 값과 다를 때만 `keyStore(for: .microsoft)`의 키를 먼저 지운다. 저장된 주소가 없으면(처음 저장) 지우지 않는다. 지우기가 던지면 주소를 저장하지 않고 `keyActionFailure = .delete`를 켠다(옛 키가 새 호스트로 가지 않게).
4. 설정 표에 두 값을 쓴다. 던지면 `providerActionFailure = .saveMicrosoft`를 켜고 바인딩은 옛 주소 그대로 둔다. 3에서 키를 이미 지웠으면 `hasKey`를 다시 읽어 키 없음으로 보이고, 키가 없으므로 옛 주소로도 묻지 않는다.
5. 바꾸기 4~7과 같다. 저장된 판단 결과는 그대로 쓴다(research R3).

## 7. 판단 결과 규칙에서 바뀌는 곳

- 쓰는 판단 결과: `usable(..., provider: binding.provider.name)`. 비교 기준은 설정 값이 아니라 주입된 공급자의 `name`이다(ADR-0011 결정 6).
- 다시 물을 할 일: `needsQuery(..., provider: binding.provider.name)`.
- 요청: `DecisionRequest(taskID:model: binding.requestModel, state:questions:)`.
- 게이트: `ConcreteGate.threshold(questions, baseModel: binding.baseModel)`.
- 순서: `SessionScoring.thresholds = questions.thresholds(for: binding.baseModel)`.
- 답 받기: 세대가 다르면 버린다(research R6). 성공 답만이 아니라 실패 답도 같다. 실패를 장부에 적는 `markFailed`와 게이트 판정도 세대를 먼저 보고, 다르면 아무것도 바꾸지 않는다. 판단 입력 해시는 공급자와 상관없이 같아서 해시 비교만으로는 새 세대 장부를 잘못 실패로 적기 때문이다. 그다음 spec 003 `accepts` 그대로.
- 저장: `TaskScore.provider`는 `binding.provider.name`, `modelSnapshot`은 응답 `model` 그대로(spec 003 R-205).

## 8. 앱 상태

- `DecisionSetup`: `bind: @MainActor (DecisionSelection.Ready) -> DecisionBinding`, `keyStore: @MainActor (ProviderID) -> any KeyStore`, `catalog: [ProviderConfig] = ProviderCatalog.all`, `questions: QuestionSet?`, 기존 3인자 편의 생성자(research R5). `DecisionBinding`은 `provider`, `baseModel`, `requestModel`이고 키 보관함을 들지 않는다. 키는 판단 기능이 꺼져 있어도 다뤄야 하므로 바인딩과 따로 받는다. `MokaApp`의 `bind`는 `HTTPDecisionProvider(config:url:)`를, `keyStore`는 `KeychainKeyStore(account: id.rawValue)`를 만든다. 편의 생성자의 `keyStore`는 공급자와 상관없이 받은 보관함 하나를 돌려준다.
- 메모리 값: `selectedProvider: ProviderID?`(설정 없음이면 `.typesafe`, 모르는 ID면 `nil`), `binding: DecisionBinding?`(`off`면 `nil`), `selectionOff: DecisionSelection.OffReason?`, `providerGeneration`, `providerActionFailure: ProviderAction?`(`select`, `saveMicrosoft`. 다음 성공에 `nil`), 기존 `hasKey`·`keyNeedsCheck`·`keyActionFailure`·`attempted`·`queryRunner`.
- 키 저장·지우기·`hasKey` 읽기·보내기 직전 키 읽기는 모두 `keyStore(for: selectedProvider)`다. `selectedProvider`가 `nil`이면 키 동작을 끄고 `hasKey = false`다.
- `KeyFieldState`는 여섯 상태 그대로다. 칸 제목은 뷰가 고른 공급자 이름으로 만든다.
- `showsKeyNotice`는 그대로 `keyFieldState == .needsCheck`이고, 바꾸기와 Microsoft 칸 저장이 `keyNeedsCheck`를 끄므로 함께 꺼진다(spec R-627).
- 온보딩 `OnboardingKeyInput`: `hasKey`(Jev 항목), `onSave`(Jev 항목에 저장), `issueURL: URL?`(확인된 경우만), `host: String`(Jev 호스트). 저장은 spec 004 data-model §5 무늬 그대로다.
- 온보딩 키 단계는 지금 바인딩과 고른 공급자와 상관없이 `keyStore(for: .typesafe)`를 쓴다. 판단 기능이 꺼져 있어도 같다.

## 9. 화면 상태 (시안으로 확정)

설정 창 기본 탭 판단 모델 칸(`BasicTabView` 새 인자 `decision: DecisionFieldInput`, ADR-0009 값과 콜백만):

| 인자 | 뜻 |
|---|---|
| `providers: [ProviderRow]` | 다섯 줄. `id`, `displayName`, `isOpen`, `closedNote: String?`(열리지 않은 이유 해요체) |
| `selected: ProviderID` | |
| `issueURL: URL?` | 확인된 경우만 |
| `host: String?` | 보내는 곳. Microsoft 주소가 없으면 `nil` |
| `provisional: Bool` | |
| `offNote: String?` | `OffReason` 안내 |
| `microsoft: MicrosoftFieldInput?` | Microsoft를 골랐을 때만. 저장된 주소와 배포 이름, 거부 이유, 키를 지운다는 안내를 보일지 |
| `keyState: KeyFieldState` | 기존 여섯 상태 |
| 콜백 | `onSelect(ProviderID)`, `onSaveMicrosoft(String, String) -> EndpointRejection?`, 기존 `onSaveKey`·`onDeleteKey`·`onRetry` |

상태(스냅샷 이름 후보): Jev 키 없음, Jev 저장됨, Jev 키 확인 필요, 공급자 목록 펼침(열리지 않은 넷), 잠정값 공급자 골라짐(가짜 열린 공급자로), Microsoft 주소 없음, Microsoft 주소 거부(`scheme`), Microsoft 저장됨, 주소를 바꾸면 키를 지운다는 안내, 설정 쓰기 실패. 열리지 않은 공급자를 고른 화면은 실제로 만들 수 없으므로, 잠정값과 Microsoft 상태는 가짜 `ProviderRow`로 뷰만 그린다.

할 일 탭: spec 004 data-model §5 `TaskListTabView` 인자 그대로(`keyNotice`, `onOpenKeySettings`). 문구는 시안 15번 확정 그대로.

온보딩 키 단계: spec 004 data-model §5 표의 세 상태(키 없음, 저장 실패, 이미 있음)에 보내는 곳 한 줄을 더한다. 문구는 006 시안에서 확정한다.

## 10. 시험 경계와 기존 기대 출력

- MokaCore 시험은 리눅스에서 돈다. 공급자 표, 두 코덱, 주소 규칙, 질문 파일 v2, `DecisionSelection`, 바뀐 시그니처.
- 앱 시험은 가짜 공급자 둘(이름 `fake-a`, `fake-b`)과 공급자별 `InMemoryKeyStore`를 돌려주는 가짜 `keyStore`, 가짜 `bind`로 바꾸기, 세대 판정(성공 답과 실패 답 모두), off 상태의 키 저장·확인, Microsoft 칸 저장과 키 지움, 업그레이드(설정 없음, `typesafe` 키 있음)를 본다.
- `moka-sim` 기대 출력, spec 001~004 golden 바이트는 바뀌지 않는다. 바뀌면 멈춘다.
- 기존 스냅샷 가운데 기본 탭 키 칸 상태는 칸 제목과 판단 모델 칸 모양이 바뀌어 참조 이미지가 바뀐다. PR에 이유를 적고 새 이미지로 갈아 끼운다. 그 밖의 참조 이미지는 그대로다.
