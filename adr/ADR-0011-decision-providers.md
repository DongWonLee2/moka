# ADR-0011: 판단 공급자 여러 개를 공통 코덱과 공급자 설정으로 지원한다

- 상태: Proposed
- 작성일 / 사람 승인일: 2026-11-10 / 미정. 이 문서는 PR 병합으로 확정한다
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: spec 003 R-210·R-211·R-212·R-214, data-model §1·§3·§6·§9, contracts/decision-provider.md, contracts/questions-json.md, spec 004 R-313, 헌법 I·VIII, ADR-0001(실제 공급자는 앱 타깃에만), ADR-0004(스키마 계약)
- 대체 범위: spec 003 R-210의 "공급자는 TypeSafe Jev 하나"와 spec 003 대안 표의 "공급자 TypeSafe 직접 하나" 줄(사용자 결정 2026-10-30)을 대체한다. R-210의 나머지(바꿔 끼울 수 있는 경계, 시험·CI·시뮬레이터는 가짜 공급자)는 그대로다. spec 003 R-214의 account `typesafe` 하나도 공급자마다 account 하나로 넓힌다. Jev의 account는 `typesafe` 그대로다.
- 사용한 외부 근거: 공급자 공식 문서 조사 요약(2026-11-10, `.audit/research/20261110-decision-providers.md`, 커밋 안 함). 공급자별 주소·인증·모델 이름은 아래 표에 옮겼다.

## 맥락

사용자 결정(2026-11-10)은 두 가지다. 판단 모델 다섯 개(Microsoft-Decision-1, TypeSafe Jev, Liquid d1-ultra, OpenAI Decisions, Perplexity Decider v1.2)를 지원하고, 사용자가 하나를 골라 그 키를 넣는다. 나중에는 오픈웨이트 모델을 사용자가 넣은 API 주소로 부른다. 이 결정은 2026-10-30의 "TypeSafe 하나" 결정을 바꾼다.

지금 구조는 TypeSafe 하나를 전제로 한다.
- `TypeSafeCodec`(MokaCore)이 요청 본문 조립, 응답 해석, 상태 코드 표를 맡는다. 앱 `TypeSafeProvider`는 고정 주소에 Bearer 헤더로 보낸다.
- `KeychainKeyStore`는 account `typesafe` 하나만 쓴다.
- `questions.json`은 최상위 `model` 하나와 `thresholds[model]`을 둔다(`QuestionSet.swift:43`, `ConcreteGate.swift:54`).
- 쓰는 판단 결과(`ScoreRules.usable`, `ScoreRules.swift:105`)와 다시 물을 할 일(`ScoringPlan.needsQuery`, `ScoringPlan.swift:13`)은 질문 버전과 해시만 비교한다. 공급자를 바꾸면 다른 모델이 매긴 점수가 섞인다.

조사 결과 다섯 공급자 가운데 넷은 TypeSafe와 같은 System One 요청·응답 모양이다. OpenAI만 모양이 다르다. 확률 보정이 모델마다 달라 임계값은 모델마다 다시 검증해야 한다.

## 평가 기준

1. 공급자를 더해도 MokaCore 순수 함수 시험으로 요청·응답을 검증할 수 있는가
2. 실제 API를 시험·CI·`moka-sim`에서 부르지 않는 구조(ADR-0001, 헌법 VIII)를 지키는가
3. 공급자를 바꿔도 다른 모델 점수가 섞이지 않는가
4. 스키마와 공개 계약 변경을 최소로 하는가
5. 할 일 제목이 가는 곳을 사용자가 알 수 있는가

## 결정

### 1. 공급자 경계

- MokaCore에 System One 모양 공통 코덱 하나를 둔다. 지금 `TypeSafeCodec`의 이름을 `SystemOneCodec`으로 바꾼다. 본문 조립, 응답 해석, 상태 코드 표는 그대로다.
- OpenAI는 변환 코덱 `OpenAIDecisionsCodec`을 따로 둔다. 같은 `DecisionRequest`를 OpenAI 모양으로 바꾸고, OpenAI 응답을 같은 `DecisionResponse`로 바꾼다.
  - 요청: `questions` 객체를 `{name, type, ...}` 배열로 바꾼다. noul은 OpenAI의 참 확률 질문 타입(문서 이름 predicate)으로 보낸다. `state`는 `input`에 넣는다.
  - 응답: 답 배열을 질문 이름 사전으로 바꾼다. predicate의 `probability`는 `Answer.noul`이 된다. score의 `{label, value, probability}` 목록은 `value`를 옵션 번호로 삼아 `probabilities`가 된다.
  - 응답에 score 값과 신뢰도 칸이 없으면 확률로 계산할지는 첫 실제 호출에서 필드 이름을 확인한 뒤 구현 PR에서 정한다(미확인).
- 공급자는 코드가 아니라 설정으로 다르다. 설정 하나는 공급자 ID, 화면 이름, 주소, 인증 헤더 방식(`Authorization: Bearer <키>` 또는 `api-key: <키>`), 보낼 모델 이름, 코덱 종류(System One 또는 OpenAI)를 든다. 이 표는 MokaCore 값으로 두고 시험한다.
- 앱의 실제 공급자는 `TypeSafeProvider`를 `HTTPDecisionProvider` 하나로 바꿔 설정을 받는다. 시간 한도(`Defaults.decisionTimeout`), 재시도 없음, 로그 규칙은 그대로다.
- `DecisionProvider` 프로토콜 모양은 유지한다. `name`과 `decide(_:key:)` 그대로다.
  - 유지할 수 있는 이유: 공급자마다 다른 것은 주소·헤더·모델 이름·본문 모양뿐이다. 모두 공급자 값이 생성 때 들고 있으면 된다. 키는 지금처럼 별도 인자로 받는다.
  - 뜻이 바뀌는 곳은 둘이다. `name`은 공급자 ID다. `DecisionRequest.model`은 보낼 모델 이름이다(Microsoft는 사용자가 만든 배포 이름, 나머지는 기준 모델 ID).
  - 이 뜻 변경은 공개 계약 문서(contracts/decision-provider.md)를 바꾸므로 승인 항목이다.
- 공급자마다 첫 실제 호출은 사람이 확인한다(spec 003 SC-209와 같은 방식). 결과는 PASS/FAIL과 응답 최상위·답 안쪽 필드 이름만 적는다. 응답 원문과 할 일 제목은 PR·저장소에 넣지 않는다.
- 가정(토론하지 않음): 확인 전인 공급자는 화면에서 고를 수 없게 둔다.

공급자 표(공식 문서 기준, 2026-11-10):

| 공급자 ID | 화면 이름 | 주소 | 인증 | 코덱 | 기준 모델 ID |
|---|---|---|---|---|---|
| `typesafe` | TypeSafe Jev | `https://api.typesafe.ai/v1/systemone` | Bearer | System One | `jev-1.13.0` |
| `microsoft` | Microsoft-Decision-1 | 사용자가 리소스 주소를 넣고 앱이 `/providers/microsoft/v1/systemone`을 붙임 | `api-key` 헤더 | System One | 미정(사람 확인 항목) |
| `liquid` | Liquid d1-ultra | `https://api.liquid.ai/decisions/v1/systemone` | Bearer | System One | `d1-ultra`(고정 버전 규칙 미확인) |
| `perplexity` | Perplexity Decider v1.2 | `https://api.perplexity.ai/v1/decisions` | Bearer | System One | `pplx-decider-v1.2` |
| `openai` | OpenAI Decisions | `https://api.openai.com/v1/decisions` | Bearer | OpenAI 변환 | `gpt-6-luna` |

- 별칭(`jev-latest`, `latest` 등)은 기준 모델 ID로 쓰지 않는다.
- Microsoft의 요청 `model`은 배포 이름이라 기준 모델 ID가 될 수 없다. 기준 모델 ID는 Microsoft가 공개한 모델 이름과 버전으로 정한다.
- 가정(토론하지 않음): Microsoft 인증은 `api-key` 헤더만 쓴다. 키 칸에 넣는 값은 오래 쓰는 키여야 하는데, Entra Bearer 토큰은 만료가 있다.

### 2. 주소 칸

- 공급자 설정에 주소 칸을 둔다. 이번에는 Microsoft에만 보인다. 나머지 넷은 표의 고정 주소를 쓰고 칸을 숨긴다.
- 오픈웨이트(vLLM 등 사용자가 띄운 서버)는 이번에 켜지 않는다. 다음 작업에서 같은 칸으로 받고, 요청 모양(System One 또는 OpenAI)을 고르게 한다.
- 사용자가 넣는 주소의 허용 조건은 지금 정한다. Microsoft 주소에 이번부터 적용하고, 오픈웨이트도 같은 조건을 따른다.
  - `https`만 받는다. 예외로 loopback(`localhost`, `127.0.0.1`, `::1`)은 `http`를 받는다. IPv6는 주소 안에서 `[::1]`로 쓰고, 비교는 대괄호를 벗긴 호스트로 한다.
  - 호스트가 비었거나, 주소에 사용자 정보(`user:pass@`), 쿼리(`?`), 조각(`#`)이 있으면 거부한다.
  - 가정(토론하지 않음): Microsoft는 사용자가 스킴·호스트·포트까지의 리소스 주소만 넣는다. 앱이 경로 `/providers/microsoft/v1/systemone`을 붙이고, 넣은 주소에 경로가 있으면 거부한다. 오픈웨이트의 경로 규칙은 그 작업에서 정한다.
  - 리디렉트를 따라가지 않는다. URLSession은 기본으로 따라가므로 세션 대리자에서 거부하는 코드가 필요하다. 가정(토론하지 않음): 거부한 3xx 응답은 `server(status)`로 본다.
  - 주소를 바꾸면 그 공급자의 Keychain 키를 지우고 다시 입력받는다. 옛 키가 새 호스트로 가지 않게 한다.
  - 할 일 제목이 가는 호스트 이름을 설정 화면에 보인다.
  - 로그에 주소를 남기지 않는다. 지금처럼 실패 종류와 상태 코드만 남긴다.
- 조건마다 확인 방법은 다르다. 실제 공급자 주소로 요청을 보내는 시험은 두지 않는다.

| 조건 | 확인 방법 |
|---|---|
| 스킴, loopback 예외, `[::1]`, 빈 호스트, 사용자 정보·쿼리·조각, 경로 | MokaCore 순수 함수(`EndpointRule` 같은 이름) 시험 |
| 호스트 표시 | 호스트를 꺼내는 순수 함수 시험과 설정 화면 스냅샷 시험(ADR-0009) |
| 주소를 바꾸면 키 지움 | AppState 앱 시험(`InMemoryKeyStore`, 가짜 공급자) |
| 리디렉트 거부 | 사람 확인. 앱 시험 번들은 실제 공급자 파일을 컴파일하지 않는다(research R19 F3, SC-207). 사람이 loopback에 3xx를 돌려주는 로컬 서버를 띄워 Microsoft 주소로 넣고, 실패 종류가 `server`이고 두 번째 요청이 없는지 본다 |
| 로그에 주소 없음 | 로그는 실패 종류와 상태 코드만 받는 함수 한 곳에서 남긴다. PR 리뷰에서 그 함수 밖 로그 호출이 없는지 본다 |

### 3. 임계값과 질문 파일

- `questions.json`은 한 벌이다. 질문 문구와 옵션은 공급자와 상관없이 같다.
- `thresholds`의 키는 공급자 기준 고정 모델 ID다. Microsoft 배포 이름은 키가 될 수 없다.
- 임계값을 라벨셋으로 검증하지 않은 모델은 잠정값을 쓴다. 설정 화면에 잠정값이라는 사실을 알린다. 가정(토론하지 않음): 잠정값은 지금 Jev 값을 그대로 옮긴다.
- 최상위 `model` 한 칸을 공급자별 기본 모델 표로 바꾸는 형식 변경이 필요하다. AGENTS.md에 따라 `version`을 올려(v2) 제안만 한다. 구현 PR에서 사람이 승인한다. 제안 모양은 아래와 같다.

```json
{
  "version": "v2",
  "language": "ko",
  "models": {"typesafe": "jev-1.13.0", "liquid": "d1-ultra", "perplexity": "pplx-decider-v1.2", "openai": "gpt-6-luna"},
  "provisional": ["d1-ultra", "pplx-decider-v1.2", "gpt-6-luna"],
  "questions": {"…": "v1 그대로"},
  "thresholds": {"jev-1.13.0": {"concrete": 0.5, "avoiding": 0.7}, "…": "모델마다"}
}
```

- 읽기 규칙:
  1. 한 질문 버전 안에서 공급자 하나에 기준 모델은 하나다. `models`가 공급자 ID를 키로 하는 JSON 객체라 구조상 늘 참이다. 따로 시험하지 않는다.
  2. `models`의 모든 값이 `thresholds` 키로 있고, 그 항목마다 `concrete`와 `avoiding`이 둘 다 있다. 값은 0~1이다. 지금 v1이 `thresholds[model]` 하나에 거는 조건을 모든 모델로 넓힌 것이다. 어기면 파일을 읽지 않는다(`malformed`, data-model §9처럼 판단 기능 꺼짐). 파일 읽기 시험으로 지킨다.
  3. 같은 `version` 문자열을 다른 `models`·`thresholds`로 다시 쓰지 않는다. 값을 바꾸면 `version`을 올린다. 파일 하나를 읽는 시험으로는 못 잡는다. 그래서 버전마다 `models`·`thresholds` 고정값(golden)을 시험 쪽에 두고, 지금 파일의 `version`이 golden에 있으면 값이 같아야 하고 없으면 실패하게 한다. 새 버전을 만들면 golden을 덧붙여야 통과한다.
- 고른 공급자 ID가 `models`에 없으면 판단 기능을 끈다. 키가 없을 때처럼 노치는 마감 순으로 고르고, 질의를 보내지 않으며, 로그 한 줄을 남긴다. 임계값을 읽는 곳은 강제 언래핑하지 않는다. 예를 들어 Microsoft 기준 모델 ID를 정하기 전에는 Microsoft를 고를 수 없게 하고, settings에 남은 값이 있어도 이 규칙으로 꺼진다.
- `ConcreteGate`와 `ScoreRules.priority`의 avoiding 판정은 `thresholds[기준 모델 ID]`를 읽는다. 기준 모델 ID는 앱이 settings의 고른 공급자 ID로 `models`에서 찾아 `DecisionSetup`에 넣는다. 시험과 `moka-sim`의 가짜 공급자 설정은 기준 모델 ID를 직접 받는다(영향 절).
- 위 예시 값 가운데 Microsoft 기준 모델 ID는 비워 두었다. 사람이 정한다.
- 튜닝 스크립트는 행동 로그 줄의 질문 버전으로 그때의 질문 파일을 읽어야 기준 모델과 임계값을 안다(결정 6). 지난 버전 파일을 어디서 읽을지는 열린 질문이다. 두 안이 있다.
  - git 기록의 커밋이나 태그. 태그는 사람이 만든다(AGENTS.md).
  - 저장소에 버전별 사본을 둔다. 이 사본은 읽기 규칙 3의 golden으로도 쓸 수 있다.

### 4. 중계

- OpenRouter 같은 중계는 지원하지 않는다. 앱은 공급자에 직접 보낸다.

### 5. 키와 선택 저장

- Keychain은 공급자마다 항목 하나다. service는 `dev.dongwon.moka` 그대로이고 account는 공급자 ID다. Jev는 기존 account `typesafe`를 유지해 이미 저장된 키를 다시 넣지 않게 한다.
- 고른 공급자 ID, Microsoft 배포 이름, Microsoft 주소는 settings 표에 둔다. 앞선 토론의 "고른 공급자·모델 ID·주소"에서 모델 ID는 Microsoft 배포 이름(보낼 모델 이름)에만 해당한다. 기준 모델은 사용자가 고르지 않는다(결정 6, 사용자 결정 2026-11-11). `settings(key, value)`(`schema/moka-schema.sql:5`)라 스키마 변경이 없다. 키 이름은 구현 PR에서 `CoreSettings` 무늬로 정한다.
- 동시에 쓰는 공급자는 하나다. 실패하면 다른 공급자로 넘어가는 구조는 두지 않는다.
- 공급자를 바꾸면 보내기 장부(`attempted`)를 비우고 `keyNeedsCheck`를 `false`로 돌린다. `hasKey`는 새 공급자의 account로 다시 읽는다.

### 6. 데이터 정합성

- 쓰는 판단 결과와 다시 물을 할 일 판정에 공급자 비교를 더한다. 비교 기준은 settings 값이 아니라 AppState에 주입된 공급자의 `name`이다. 저장할 때 이미 이 값을 쓴다(`AppState.swift:891`의 `provider.name`, `:951`). 시험과 `moka-sim`의 가짜 공급자 이름은 `fake`(`DecisionProvider.swift:58`)라서, settings와 비교하면 `moka-sim` 기대 출력이 바뀐다. 앱은 settings의 고른 공급자로 실제 공급자를 만들어 주입하므로 결과는 같다.
  - `ScoreRules.usable`: 질문 버전이 같고 `provider`가 주입된 공급자 `name`과 같은 판단 결과만 쓴다.
  - `ScoringPlan.needsQuery`: 판단 결과의 `provider`가 주입된 공급자 `name`과 다르면 다시 묻는다.
- 기준 모델 ID는 따로 비교하지 않는다. 결정 3의 읽기 규칙(한 버전 안에서 공급자 하나에 기준 모델 하나)이 있어 질문 버전과 공급자 ID가 같으면 기준 모델도 같다.
- 사용자는 공급자(회사)만 고르고 키를 넣는다. 공급자 안의 모델은 고르지 않고, 기준 모델은 앱이 질문 파일 `models` 표로 정한다(사용자 결정 2026-11-11, 이유는 API 키가 회사에 붙는다는 점). settings에는 기준 모델을 두지 않는다.
- 이 사용자 결정으로 토론의 2:1(아래 "근거")을 다수안 D로 정리했다. 스키마 변경은 없다.
- 틀리는 조건: 나중에 사용자가 공급자 안에서 모델을 고르게 되면 다시 본다. 그때는 대안 A(새 열)가 맞다.
- 요청한 기준 모델 ID를 남기는 방법: 새 열을 두지 않는다. `provider` 칸에는 공급자 ID만 적고, `model_snapshot`은 지금처럼 응답 `model`을 적는다. 기준 모델 ID는 줄의 `(question_version, provider)`를 그 버전 `questions.json`의 `models` 표에 대 보면 하나로 정해진다.
  - 이미 쌓인 `provider = typesafe`, `question_version = v1` 줄은 v1 `"model": "jev-1.13.0"`으로 풀린다.
  - 질문 파일을 v1에서 v2로 올리면 질문 버전 비교 때문에 기존 판단 결과는 Jev를 계속 써도 모두 쓰지 않고 다시 묻는다. 이후에도 공급자 하나의 임계값이나 기준 모델만 바꿔도 `version`이 올라, 어느 공급자를 쓰든 모든 대기·진행 중 할 일을 다시 묻는다.
  - 이 비용은 받아들인다. 입력 가격은 100만 토큰에 0.01~0.10달러이고 출력은 무료다(조사 요약). 할 일은 수십 건 규모다(data-model §4). 다시 묻는 동안에도 노치는 마감 순으로 돈다(spec 003 R-211).
- 그래서 이 결정은 스키마 변경을 부르지 않는다.
- 가정(토론하지 않음, 토론 A 자리 2라운드 제안): Microsoft 배포 이름이나 주소를 바꾸면 공급자를 바꿀 때처럼 보내기 장부를 비우고 `keyNeedsCheck`를 돌린다.
- 남는 빈틈: Microsoft에서 같은 배포 이름 안의 가중치가 바뀌거나 배포 이름이 가리키는 모델이 바뀌면 위 비교로 잡지 못한다. 배포 이름을 바꿀 때 저장된 판단 결과까지 다시 물을지는 Microsoft를 켜는 구현 PR에서 정한다. Perplexity는 응답 `model`이 보낸 이름 그대로라 `model_snapshot`이 실제 버전을 가리지 못한다. 이것은 받아들인다.

## 근거

- 결정 1·2·3·4·5는 추천안 토론에서 1라운드 3:0으로 채택했다(`.audit/debate/20261110-1400-provider-adr.md`, 커밋 안 함). 결정마다 "가정(토론하지 않음)"으로 표시한 줄은 그 토론에서 표결하지 않았다.
- 결정 6의 공급자 비교는 같은 토론에서 표결한 질문이 아니다. 세 자리 가운데 둘 이상이 더한 조건으로 판정에 담겼다.
- 결정 6은 따로 토론했다(`.audit/debate/20261110-1500-provider-model-id.md`, 커밋 안 함). 2라운드 최종 표결은 두 질문 모두 2:1이고 판정은 사람에게였다. 갈린 조건(사용자가 공급자 안에서 기준 모델을 고르는가)에 사용자가 고르지 않는다고 답해(2026-11-11) 다수안 D를 채택했다.
  - Q1 기록 방법: 가이드·실행 자리는 D, 위험 자리는 A다.
  - Q2 비교 대상: 가이드·실행 자리는 공급자 ID만, 위험 자리는 공급자 ID와 기준 모델 ID다. Q1이 A가 되면 Q2도 기준 모델 비교를 더한다.
  - 소수 의견(위험 자리): 앞선 토론 Q5는 settings에 모델 ID를 두기로 했다. 조사에서 Jev(`jev-1.14.0`·`jev-1.13.0`)와 Perplexity(`pplx-decider-v1.2`·flash)는 공급자 하나에 고정 ID가 둘이다. 사용자가 그 가운데 고를 수 있으면 D로 쌓인 `decisions_log` 줄은 기준 모델을 되찾지 못한다. 이 손실은 되돌릴 수 없으니 NULL을 허용하는 새 열(v4)을 같은 PR에서 승인받자는 의견이다.
  - 세 자리 모두 같은 조건을 틀리는 조건으로 적었다. 사용자가 공급자 안에서 기준 모델을 고르지 않으면 D, 고르면 A다.
- 공통 코덱: System One 모양 공급자가 넷이라 코덱을 공급자마다 두면 같은 코드가 넷 생긴다. 상태 코드 표와 응답 검사(`ScoreRules.score`)도 하나로 시험할 수 있다.
- 프로토콜 유지: `decide(_:key:)`는 키를 요청 밖 인자로 받는다(data-model §1, research R19 F1). 공급자 설정을 생성 때 넣으면 이 모양으로 충분하다. AppState와 가짜 공급자 시험은 바뀌지 않는다.
- 주소 허용 조건: 사용자가 넣은 주소로 할 일 제목과 키가 나간다. 사용자 정보·쿼리가 든 주소나 리디렉트는 키와 제목이 다른 곳으로 새는 길이다.
- 임계값 키: `QuestionSet.swift:43`의 `raw.thresholds[raw.model]`처럼 임계값은 이미 모델 ID 키다. 배포 이름은 사용자마다 달라 저장소에 둘 수 없다.
- Keychain account `typesafe` 유지: spec 003 R-214와 이미 저장된 키를 그대로 쓴다.
- 새 열을 두지 않는 이유(결정 6):
  - `decisions_log`는 지우거나 고치지 않는다. 값 규칙을 바꾸면(아래 대안 B) 옛 줄과 새 줄이 한 칸에 영구히 섞인다.
  - 같은 사실을 두 칸에 적으면 어긋날 길이 생긴다(spec 003 research R8, `research.md:51`).
  - 부족하면 나중에 새 열(대안 A)을 더할 수 있다. 반대로 값 규칙으로 쌓인 줄은 되돌릴 수 없다.

## 대안

결정 1(공급자 경계):

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 공통 System One 코덱 + OpenAI 변환 코덱 + 공급자 설정(채택) | 코덱 둘로 다섯을 덮음, 순수 함수 시험 하나 | OpenAI 응답 필드가 미확인이라 변환 코덱은 첫 호출 뒤 고칠 수 있음 |
| B. 공급자마다 코덱 | 공급자별 차이를 넣기 쉬움 | 같은 코드 넷, 시험 넷 |

결정 2(주소):

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 주소 칸, 이번에는 Microsoft만, 오픈웨이트는 조건만(채택) | 구조를 한 번에 정함, 허용 조건을 먼저 시험 | 오픈웨이트는 다음 작업 |
| B. 고정 주소 공급자 넷만, Microsoft·오픈웨이트는 미룸 | 가장 단순 | 사용자 결정의 다섯을 채우지 못함 |
| C. 주소 칸을 모든 공급자에 열어 둠 | 유연함 | 키가 엉뚱한 호스트로 갈 길이 넓어짐 |

결정 3(임계값):

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 질문 파일 한 벌, 기준 모델 ID 키(채택) | 문구가 하나, 버전 하나로 추적 | 형식 변경(v2) 승인 필요 |
| B. 공급자마다 질문 파일 | 공급자별 문구 조정 가능 | 버전이 여러 갈래, 튜닝 비교가 어려움 |

결정 4(중계):

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 지원 안 함(채택) | 할 일 제목이 가는 곳이 공급자 하나 | 키 하나로 여러 모델을 못 씀 |
| B. OpenRouter를 공급자 하나로 | 키 하나 | alpha 경로, 제목이 중계를 한 번 더 거침 |

결정 5(키와 선택):

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 공급자별 account, 선택은 settings, 동시에 하나(채택) | 스키마 변경 없음, 기존 키 유지 | 공급자를 바꾸면 다시 물음 |
| B. 여러 공급자를 차례로 시도 | 한 곳이 실패해도 점수 | 점수가 섞임, 제목이 여러 곳으로 감 |

결정 6(기준 모델 ID 기록):

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 새 열 `scores.base_model`·`decisions_log.base_model`(NULL 허용, 마이그레이션 v4, 토론 소수안) | DB만 보고 기준 모델을 앎, 사용자가 공급자 안에서 모델을 골라도 맞음 | 스키마 변경 승인, `schema/moka-schema.sql`·`tuning/tests/test_schema_contract.py`·마이그레이션 이름 시험(ADR-0007) 변경, 사용자가 모델을 고르지 않으면 같은 사실을 두 칸에 적음. 사용자가 공급자 안에서 모델을 고르게 되면 다시 본다 |
| B. `provider` 값을 `<공급자 ID>/<기준 모델 ID>`로 | 스키마 그대로, 바꿀 곳 하나 | 옛 `typesafe` 줄과 영구히 섞임, 값 규칙은 pytest가 시험하지 않아 계약이 몰래 바뀜 |
| C. `model_snapshot`에 응답 model 대신 기준 모델 ID | 스키마 그대로 | R-212 "응답 모델 이름" 뜻이 바뀜, Jev 응답의 실제 버전을 버림, 옛 줄과 뜻이 갈림 |
| D. 공급자 ID와 질문 버전으로 기준 모델을 정하는 읽기 규칙(채택, 사용자 결정 2026-11-11) | 스키마·칸 뜻 그대로, 옛 줄도 풀림 | 공급자 안에서 사용자가 기준 모델을 고르게 되면 틀림(그때 A로 감) |

## 영향

- 바뀌는 코드(구현 PR에서):
  - MokaCore: `TypeSafeCodec` 이름 변경, `OpenAIDecisionsCodec`, 공급자 설정 표, 주소 검사 함수, `QuestionSet`(v2 읽기), `ScoreRules.usable`·`ScoringPlan.needsQuery`의 공급자 비교, `ConcreteGate` 임계값 읽기.
  - 앱: `HTTPDecisionProvider`, `KeychainKeyStore`(account 인자), 설정 화면의 공급자 고르기·주소 칸·잠정값 표시, `AppState`의 공급자 바꾸기.
- 질문 파일 값 타입의 모양이 공급자에 따라 달라진다(구현 PR에서 시그니처를 정한다).
  - `QuestionSet.model`(`QuestionSet.swift:28`)은 `models` 사전이 된다.
  - `QuestionSet.avoidingThreshold`(`QuestionSet.swift:33`)는 지금 읽을 때 `thresholds[raw.model]`에서 한 값을 정한다(`QuestionSet.swift:43-46`). 앞으로는 기준 모델 ID를 받아 임계값 한 벌을 돌려주는 함수가 되고, 없으면 `nil`이다.
  - `ConcreteGate.threshold(_:)`(`ConcreteGate.swift:53-55`)는 `thresholds[questions.model]!["concrete"]!`로 강제 언래핑한다. 기준 모델 ID를 받고, 값이 없으면 게이트를 열지 않는 쪽으로 바꾼다.
  - `QuestionSet.bundled()`의 시그니처는 그대로이고, 읽기 검사가 읽기 규칙 2로 넓어진다.
  - 공급자 ID에서 기준 모델 ID를 찾는 일은 앱이 `DecisionSetup`을 만들 때 한 번 한다. 가짜 공급자 설정은 기준 모델 ID를 직접 받는다. 그래서 `fake`가 `models`에 없어도 시험과 `moka-sim`은 지금처럼 판단을 돌린다.
  - 요청 `model`은 Microsoft면 settings의 배포 이름, 나머지면 기준 모델 ID다(지금 `AppState.swift:916`의 `questions.model`).
- 튜닝 계약: `tuning/tests/test_questions_contract.py:22-26`이 `data["thresholds"][data["model"]]`을 읽는다. v2에서는 `models`의 모든 값으로 바꾼다. contracts/questions-json.md:13-18의 형식 표도 바뀐다. 둘 다 승인 항목 2에 든다.
- 스키마: 변경 없음(결정 6, 사용자 결정 2026-11-11).
- `moka-sim`: 가짜 공급자 이름(`fake`)은 그대로이고 비교 기준이 주입된 공급자 `name`이라 기대 출력이 바뀌지 않는다.
- 문장이 어긋나는 문서(이 PR에서는 고치지 않고, 구현 PR에서 대체 표기를 붙인다):
  1. spec 003 `spec.md:132` R-210 "공급자는 TypeSafe Jev 하나", `spec.md:183` 하지 않음의 "두 번째 공급자", `spec.md:200` 대안 표 "공급자 TypeSafe 직접 하나".
  2. spec 004 `spec.md:38`·`spec.md:198` "판단 공급자는 TypeSafe Jev 하나", R-313(`spec.md:165`)의 TypeSafe 발급 링크 하나.
  3. spec 002 `research.md:75` R8 "OpenRouter(Decision-1)는 나중에 account `openrouter`로 더한다"(결정 4와 어긋남).
  4. `GLOSSARY.md` key store 항목의 "MVP는 Jev만"(이 PR에서 고친다).
  5. 헌법 VIII 예시 문구 "(OpenRouter Decision-1, Jev, relay)"(`.specify/memory/constitution.md:70`).
  6. spec 003 R-214(`spec.md:136`) "account `typesafe`에만 둔다"(대체 범위에 적음).
  7. spec 003 Key Entities: 질문 파일의 "요청 모델 이름"(`spec.md:143`), 키 보관함의 "키 하나"(`spec.md:145`).
  8. spec 003 data-model §1 `QuestionSet`의 `model: String`(`data-model.md:9`), §3 `ScoreRules.usable(scores:hasKey:questionVersion:)` 시그니처(`data-model.md:64`).
  9. contracts/questions-json.md의 `model` 줄(`:13`)과 `thresholds[model]` 규칙(`:15`).
  10. AGENTS.md "데이터와 비밀값"의 예시 "(OpenRouter Decision-1, Jev, relay)"(`AGENTS.md:27`).
- 헌법 개정 제안(사람 결정, 이 PR에서는 고치지 않는다): VIII 첫 줄의 괄호를 "(앱이 지원하는 모든 판단 공급자와 사용자가 넣은 주소)"로 바꾸는 PATCH 개정(1.0.1에서 1.0.2). 원칙의 뜻은 그대로이고 예시만 지금 결정에 맞춘다. AGENTS.md:27의 같은 예시도 같은 문구로 바꾸자고 제안한다.
- 트레이드오프:
  - 공급자를 바꾸면 모든 할 일을 다시 묻는다.
  - 질문 파일 `version`을 올릴 때마다(v1에서 v2로 처음 올릴 때 포함) 어느 공급자를 쓰든 기존 판단 결과를 모두 버리고 다시 묻는다. 공급자 하나의 임계값만 바꿔도 그렇다. 입력 비용이 낮고 할 일이 수십 건 규모라 받아들인다(결정 6).
  - 잠정 임계값 모델은 검증 전까지 구체화 게이트와 aging 판정이 Jev 기준값으로 돈다.
- 되돌리기: 공급자 설정과 코덱은 코드라 쉽다. questions.json v2는 버전을 다시 올려야 한다. Keychain 항목은 공급자를 지우면 사람이 지운다.

## 승인 항목

1. DecisionProvider 경계(헌법 I 공개 계약): 프로토콜 모양은 그대로이고, `name`을 공급자 ID로, `DecisionRequest.model`을 보낼 모델 이름으로 뜻을 바꾼다. `TypeSafeCodec`을 `SystemOneCodec`으로 바꾸고 OpenAI 변환 코덱을 더한다. contracts/decision-provider.md를 바꾼다.
2. questions.json 형식 변경(헌법 I 공개 계약): 최상위 `model`을 `models`(공급자 ID에서 기준 모델 ID로) 표로 바꾸고 `provisional` 목록을 더한다. `version` v2. 읽기 규칙 셋과 버전별 golden 시험. 함께 바뀌는 계약은 contracts/questions-json.md:13-18과 pytest `tuning/tests/test_questions_contract.py:22-26`이다. 튜닝 스크립트가 지난 버전 질문 파일을 어디서 읽을지(결정 3의 열린 질문)도 함께 정한다. 파일 변경은 구현 PR에서 제안하고 라벨셋 비교는 사람이 한다.
3. 스키마 변경: 없음(사용자 결정 2026-11-11). 사용자는 공급자 안의 모델을 고르지 않으므로 결정 6은 새 열 없이 결정 3의 읽기 규칙으로 기준 모델을 정한다.
4. 헌법 VIII 예시 문구 PATCH 개정 제안(위 "영향").

## 사람이 확인할 것

- 공급자마다 첫 실제 호출: PASS/FAIL과 응답 최상위·답 안쪽 필드 이름만 적는다. 특히 OpenAI score 답에 score 값·신뢰도 칸이 있는지, Microsoft 응답 `model` 칸에 무엇이 오는지.
- Microsoft 기준 모델 ID(공개 모델 이름과 버전)와 `api-key` 헤더로 부를 수 있는지.
- Liquid d1-ultra의 고정 버전 ID가 있는지. 없으면 `d1-ultra`가 별칭인지.
- OpenAI 키 발급 주소, TypeSafe 키 발급 주소(조사에서 미확인).
- 토론하지 않은 가정 다섯: 확인 전 공급자는 고를 수 없음, Microsoft는 `api-key` 헤더만, 거부한 3xx는 `server(status)`, 잠정 임계값은 Jev 값, Microsoft 배포 이름·주소를 바꾸면 장부 비움. Microsoft 경로를 앱이 붙이는 것도 가정이다.
- 리디렉트 거부: loopback 로컬 서버로 사람이 확인한다(결정 2 표).
- 튜닝 스크립트가 지난 버전 질문 파일을 읽을 곳(git 기록 또는 저장소 사본).
- 헌법 VIII과 AGENTS.md 예시 문구 개정을 할지.

## 결정 검증

- 실행할 실험(구현 PR, 가짜만):
  - `SystemOneCodec`은 지금 `TypeSafeCodec` 시험이 그대로 PASS.
  - `OpenAIDecisionsCodec`은 공식 문서 예시 모양의 가짜 응답을 같은 `DecisionResponse`로 바꾸는지.
  - 주소 검사 함수는 `http`(loopback 제외), 빈 호스트, 사용자 정보, 쿼리, 조각, Microsoft 주소의 경로를 거부하고 `[::1]`을 loopback으로 보는지.
  - 공급자를 바꾸면 `usable`이 비고 `needsQuery`가 모든 대기 할 일을 돌려주는지(이름이 다른 가짜 공급자 둘).
  - 주소를 바꾸면 그 공급자 키가 지워지는지(AppState 앱 시험).
  - 질문 파일 읽기 규칙 2를 어기면 읽지 않는지, 버전별 golden 시험이 같은 `version`의 값 변경을 잡는지.
  - settings의 공급자 ID가 `models`에 없거나 기준 모델의 임계값이 없으면 판단 기능이 꺼지고, 강제 언래핑으로 멈추지 않는지.
- 재검토 트리거: 한 공급자 안에서 기준 모델을 고르게 하자는 요구(결정 6을 대안 A로), 오픈웨이트를 켤 때, 공급자의 응답 모양이 문서와 다를 때.

## 미확인

- OpenAI score 답의 칸 이름과 score·신뢰도 유무.
- Microsoft 응답 `model` 칸 값, Microsoft 기준 모델 ID.
- Liquid 고정 버전 규칙.
- 다섯 공급자의 상태 코드가 지금 표(401·403·429·529)와 같은지. 다르면 `server(status)`로 떨어지고 동작은 같다.
