# 계약: 판단 공급자 경계와 TypeSafe 요청·응답

공개 계약이다(헌법 I "DecisionProvider 프로토콜"). 근거: spec R-201·R-208·R-209, research R7, TypeSafe 공식 문서(2026-11-06 확인: `https://docs.typesafe.ai/api/system-one.md`, `errors.md`, `models.md`).

## Swift 경계 (MokaCore)

```swift
public protocol DecisionProvider: Sendable {
    var name: String { get }   // 로그·scores의 provider. TypeSafe는 "typesafe"
    func decide(_ request: DecisionRequest) async throws(DecisionError) -> DecisionResponse
}
```

- 타입 모양은 data-model §1. 요청 JSON 조립(`TypeSafeCodec.body(_:)`)과 응답 해석(`TypeSafeCodec.response(_:)`)은 MokaCore 순수 함수다. 앱 `TypeSafeProvider`는 키를 읽고 HTTP를 보내고 상태 코드를 `DecisionError`로 바꾸는 일만 한다.
- 시험·CI·`moka-sim`은 `FakeDecisionProvider`만 쓴다. `TypeSafeProvider`는 앱 타깃에만 있어 링크되지 않는다(ADR-0001).

## HTTP

| 항목 | 값 |
|---|---|
| 요청 | `POST https://api.typesafe.ai/v1/systemone` |
| 헤더 | `Authorization: Bearer <키>`, `Content-Type: application/json` |
| 시간 | `URLSessionConfiguration.timeoutIntervalForResource = Defaults.decisionTimeout`(3초), 넘으면 `timeout` |
| 재시도 | 없음 |

## 요청 본문

```json
{"model":"jev-1.13.0","state":{…data-model §4…},"questions":{…questions.json의 questions 그대로…}}
```

- `state`는 data-model §4의 정준 바이트를 그대로 끼운다(객체). 해시도 이 바이트로 만든다.
- 키 순서는 `model`, `state`, `questions`. `questions` 안은 `questions.json`의 순서.

## 응답 해석

```json
{"model":"jev-1.13.0","answers":{
  "urgency":{"type":"score","score":2.1,"confidence":0.7,"legend":{"0":"여유","1":"이번주","2":"급함","3":"오늘안에"},"probabilities":{"0":0.05,"1":0.15,"2":0.4,"3":0.4}},
  "impact":{"type":"score","score":1.2,"confidence":0.6,"legend":{"0":"조금","1":"꽤","2":"아주"},"probabilities":{"0":0.2,"1":0.4,"2":0.4}},
  "concrete":{"type":"noul","noul":0.9},
  "avoiding":{"type":"noul","noul":0.3}},
 "usage":{"input_tokens":300,"output_tokens":4}}
```

(가짜 값이다. 픽스처는 공식 문서 예시 모양을 따르고 값은 가짜로 둔다.)

- 읽는 칸: 최상위 `model`(없어도 됨 → `modelSnapshot` 비움), `answers.<이름>.type`, noul의 `noul`, score의 `score`·`confidence`·`probabilities`. `legend`·`usage`는 읽지 않는다. 모르는 칸은 무시한다.
- 질문 넷 가운데 하나라도 없거나, 타입이 질문 파일과 다르거나, 값이 범위 밖이면 `malformed`(data-model §3).

## 상태 코드 → 오류

| 응답 | `DecisionError` |
|---|---|
| 키가 없어 보내지 않음 | `missingKey` |
| 401, 403 | `unauthorized` (403은 문서에 없지만 같은 취급) |
| 429 | `rateLimited` |
| 529 | `overloaded` |
| 그 밖의 4xx·5xx | `server(status)` |
| 시간 초과 | `timeout` |
| 연결 실패 등 | `network` |
| 200인데 해석 실패 | `malformed(prefix)`(원문 앞 100자, 로그에만) |

## 첫 실제 호출 확인 (사람, SC-208)

사람이 확인용 빌드(개인 팀 서명)에 자기 키를 넣고 가짜 할 일 하나를 저장한다. 결과는 PASS/FAIL과 응답 최상위·답 안쪽 필드 이름만 적고, 응답 원문·할 일 제목은 PR·저장소에 넣지 않는다. 필드가 위와 다르면 `TypeSafeCodec.response`만 고치고 그 PR에서 픽스처를 맞춘다.
