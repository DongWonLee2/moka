# 계약: 판단 공급자 경계 v2 (System One 모양과 OpenAI 모양)

공개 계약이다(헌법 I "DecisionProvider 프로토콜"). 이 문서는 spec 003 [contracts/decision-provider.md](../../003-decision-model/contracts/decision-provider.md)를 대체한다. 대체하지 않은 내용(질문 타입 표, System One 요청 본문과 응답 해석, 시간 한도, 재시도 없음, 첫 실제 호출 확인 방식)은 그 문서 그대로다. 근거: ADR-0011 결정 1·2·4, spec 006 R-601~R-604·R-618, research R4·R6·R7.

승인: ADR-0011 승인 항목 1. 구현 PR(spec 006 단위 1)에서 사람이 승인한다.

## Swift 경계 (MokaCore)

```swift
public protocol DecisionProvider: Sendable {
    var name: String { get }   // 공급자 ID. 판단 결과·행동 로그의 provider 칸. 시험·moka-sim 가짜는 "fake"
    func decide(_ request: DecisionRequest, key: String) async throws(DecisionError) -> DecisionResponse
}
```

- 모양은 spec 003과 같다. 뜻이 바뀌는 곳은 둘이다.
  - `name`은 공급자 ID다(`typesafe`, `microsoft`, `liquid`, `perplexity`, `openai`). spec 003에서 `TypeSafeProvider.name`이 `"typesafe"`였으므로 Jev의 값은 그대로다.
  - `DecisionRequest.model`은 보낼 모델 이름이다. Microsoft는 사용자가 넣은 배포 이름이고, 나머지는 질문 파일 `models`의 기준 모델 ID다. 별칭은 보내지 않는다.
- 키는 지금처럼 별도 인자로 받는다. 요청·본문·로그에 넣지 않고 인증 헤더에만 넣는다.
- 요청 조립, 응답 해석, 상태 코드 표는 MokaCore 순수 함수다. `SystemOneCodec`(spec 003 `TypeSafeCodec`의 새 이름, 내용 그대로)과 `OpenAIDecisionsCodec` 둘이고, `DecisionWire`가 요청 모양으로 고른다.
- 시험·CI·`moka-sim`은 `FakeDecisionProvider`만 쓴다. 실제 공급자 `HTTPDecisionProvider`는 앱 타깃에만 있어 링크되지 않는다(ADR-0001).

## 공급자 표

| 공급자 ID | 주소 | 인증 헤더 | 요청 모양 | 보낼 모델 이름 |
|---|---|---|---|---|
| `typesafe` | `POST https://api.typesafe.ai/v1/systemone` | `Authorization: Bearer <키>` | System One | `jev-1.13.0` |
| `microsoft` | `POST <리소스 주소>/providers/microsoft/v1/systemone` | `api-key: <키>` | System One | 배포 이름 |
| `liquid` | `POST https://api.liquid.ai/decisions/v1/systemone` | `Authorization: Bearer <키>` | System One | `d1-ultra` |
| `perplexity` | `POST https://api.perplexity.ai/v1/decisions` | `Authorization: Bearer <키>` | System One | `pplx-decider-v1.2` |
| `openai` | `POST https://api.openai.com/v1/decisions` | `Authorization: Bearer <키>` | OpenAI | `gpt-6-luna` |

- 공통 헤더는 `Content-Type: application/json`이다.
- 보낼 모델 이름은 질문 파일 `models`에서 온다(contracts/questions-json-v2.md). 위 값은 v2 제안 값이다.
- 리소스 주소는 spec 006 data-model §4 주소 규칙을 통과한 스킴·호스트·포트다. 경로는 앱이 붙인다.
- 중계(OpenRouter 등)는 공급자가 아니다(ADR-0011 결정 4).

## System One 모양

spec 003 계약의 "요청 본문", "응답 해석" 그대로다. 공급자마다 다른 것은 주소, 인증 헤더, 본문 `model`뿐이다.

## OpenAI 모양

요청 본문(값은 가짜):

```json
{
  "model": "gpt-6-luna",
  "input": {"…": "data-model §4 정준 판단 입력 그대로"},
  "questions": [
    {"name": "urgency", "type": "score", "instructions": "…", "criteria": ["여유", "이번주", "급함", "오늘안에"]},
    {"name": "impact", "type": "score", "instructions": "…", "criteria": ["조금", "꽤", "아주"]},
    {"name": "concrete", "type": "predicate", "instructions": "…"},
    {"name": "avoiding", "type": "predicate", "instructions": "…"}
  ]
}
```

- 질문 사전(`questions.json`의 `questions`)을 이름 순 배열로 바꾼다. 배열 순서는 의미가 없고 시험은 이름으로 짝짓는다.
- noul은 `predicate`로, score는 `score`로 보낸다. `instructions`와 `criteria`는 그대로다.
- `input`은 System One `state`와 같은 정준 바이트를 객체로 끼운다. 해시는 공급자와 상관없이 같은 바이트로 만든다.

응답(값은 가짜):

```json
{
  "model": "gpt-6-luna",
  "answers": [
    {"name": "urgency", "type": "score", "score": 2.1, "confidence": 0.7,
     "probabilities": [{"label": "여유", "value": 0, "probability": 0.05}, {"label": "이번주", "value": 1, "probability": 0.15},
                       {"label": "급함", "value": 2, "probability": 0.4}, {"label": "오늘안에", "value": 3, "probability": 0.4}]},
    {"name": "impact", "type": "score", "score": 1.2, "confidence": 0.6,
     "probabilities": [{"label": "조금", "value": 0, "probability": 0.2}, {"label": "꽤", "value": 1, "probability": 0.4},
                       {"label": "아주", "value": 2, "probability": 0.4}]},
    {"name": "concrete", "type": "predicate", "probability": 0.9},
    {"name": "avoiding", "type": "predicate", "probability": 0.3}
  ]
}
```

- `answers` 배열을 `name`으로 사전으로 바꾼다. 같은 이름이 둘이면 `malformed`다.
- `predicate`의 `probability`는 `Answer.noul(p)`가 된다.
- `score`의 `probabilities` 목록은 `value`를 옵션 번호로 삼아 `[Int: Double]`이 된다. `label`은 읽지 않는다. 같은 `value`가 둘이면 `malformed`다.
- `score`·`confidence`는 그대로 `Answer.score`에 들어간다.
- 그다음 검사는 spec 003 data-model §3 해석 규칙과 같다(질문 넷, 타입, 범위, 옵션 번호가 정확히 0부터 옵션 수 빼기 1까지).
- 미확인: OpenAI score 답에 `score`·`confidence` 칸이 없을 수 있다(ADR-0011 미확인). 이 계약은 칸이 없으면 `malformed`로 본다. 확률로 계산할지는 OpenAI를 여는 PR에서 첫 실제 호출 뒤 정하고, 그때 이 문서를 고친다(승인 항목 1의 범위).

## 상태 코드와 오류

spec 003 계약 표 그대로이고 다섯 공급자가 같다. 더하는 것은 하나다.

- 리디렉트(3xx)를 따라가지 않는다. 판단은 MokaCore `RedirectRule.follow(status:to:)`(늘 `nil`)이고 세션 대리자는 그 값을 돌려준다. 따라가지 않은 3xx 응답은 `server(status)`다. 두 번째 요청은 없다.
- 200이 아닌 2xx도 spec 003 계약대로 `server(status)`다.

## 로그

spec 003 계약 그대로다. 실패 종류와 상태 코드만 남긴다. 주소, 호스트, 배포 이름, 키, 할 일 제목, 요청·응답 본문은 남기지 않는다. 공급자 안쪽(HTTP 요청과 응답 해석)의 로그 호출은 `HTTPDecisionProvider`의 한 함수에서만 한다. AppState의 기존 로그(실패 종류, 꺼진 이유 종류)는 이 문장의 범위 밖이고 같은 금지 칸을 지킨다.

## 첫 실제 호출 확인 (사람, spec 006 R-629)

공급자마다 그 공급자를 여는 브랜치의 빌드에서 사람이 자기 키로 가짜 할 일 하나를 저장한다. 결과는 PASS/FAIL과 응답 최상위·답 안쪽 필드 이름만 PR에 적는다. 응답 원문과 할 일 제목은 PR·저장소에 넣지 않는다. 필드가 이 문서와 다르면 해당 코덱만 고치고 그 PR에서 픽스처와 이 문서를 맞춘다.
