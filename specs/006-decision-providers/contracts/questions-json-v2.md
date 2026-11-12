# 계약: `questions.json` v2

공개 계약이다(헌법 I, AGENTS.md). 이 문서는 spec 003 [contracts/questions-json.md](../../003-decision-model/contracts/questions-json.md)를 대체한다. 위치, 질문 넷의 문구·타입·옵션은 v1 그대로다. 근거: ADR-0011 결정 3·6, spec 006 R-607~R-612, research R11·R13.

승인: ADR-0011 승인 항목 2. 구현 PR(spec 006 단위 2)에서 사람이 승인한다. 파일 변경은 제안만 하고, 라벨셋 비교는 사람이 실행한다. 결과 원문은 PR·저장소에 넣지 않는다.

## 형식

| 키 | 타입 | 규칙 |
|---|---|---|
| `version` | 문자열 | 질문 버전 문자열(v2·v3). 로그 `question_version`과 `scores.question_version`에 그대로 |
| `language` | 문자열 | `"ko"` |
| `models` | 객체 | 키는 공급자 ID, 값은 기준 모델 ID(GLOSSARY). 별칭과 배포 이름은 값이 될 수 없다. v1의 `model`을 대체한다 |
| `provisional` | 배열 | 잠정 임계값을 쓰는 기준 모델 ID. 중복 없음 |
| `questions` | 객체 | v1 그대로 |
| `thresholds` | 객체 | 키는 기준 모델 ID. 값은 질문 이름에서 임계값으로 |

## 읽기 규칙

어기면 파일을 읽지 않는다(`QuestionSetError`). 앱은 판단 기능을 끈다(spec 003 data-model §9).

1. 한 질문 버전 안에서 공급자 하나에 기준 모델은 하나다. `models`가 객체라 구조상 늘 참이고 따로 시험하지 않는다.
2. `models`의 모든 값이 `thresholds` 키로 있고, 그 항목마다 `concrete`와 `avoiding`이 둘 다 있으며 값이 0~1이다.
3. 같은 `version` 문자열을 다른 `models`·`thresholds`로 다시 쓰지 않는다. 값을 바꾸면 `version`을 올린다. 버전별 고정값 시험이 지킨다(아래).
4. `provisional`의 모든 값이 `models`의 값 가운데 있다. 이 spec이 더한 규칙이다(spec 006 data-model §5).
5. v1 규칙 그대로: 질문 이름은 넷이고, 타입이 맞고, score `criteria`는 2~10개이고, `blocked`가 없다.

`models`에 없는 공급자 ID를 고르면 판단 기능을 끈다(spec 006 data-model §6). 시험과 `moka-sim`의 가짜 공급자는 `models`를 거치지 않고 기준 모델 ID를 직접 받는다.

## 버전별 고정값

MokaCore 시험에 버전 문자열을 키로 하는 `models`·`thresholds` 고정값 사전을 둔다(research R13). 지금 파일의 `version`이 사전에 없으면 시험이 실패하고, 있으면 값이 같아야 한다. 새 버전을 만들면 고정값을 덧붙여야 통과한다.

| 버전 | `models` | `thresholds` |
|---|---|---|
| v1 | `typesafe`: `jev-1.13.0`(v1 `model`을 공급자 `typesafe`로 읽음) | `jev-1.13.0`: concrete 0.5, avoiding 0.7 |
| v2 | 아래 제안 내용 | 아래 제안 내용 |
| v3 | v2 그대로 | v2 그대로 |

v1 줄은 이미 쌓인 `(question_version = v1, provider = typesafe)` 판단 결과와 행동 로그 줄을 기준 모델 `jev-1.13.0`으로 풀기 위한 기록이다(ADR-0011 결정 6).

## 튜닝 계약 (pytest)

- `tuning/tests/test_questions_contract.py`의 임계값 시험은 `data["thresholds"][data["model"]]` 대신 `data["models"]`의 모든 값에 대해 같은 조건을 본다.
- 지난 버전 질문 파일은 저장소 루트 `questions-history/<version>.json` 사본에서 읽는다(research R11, 승인 항목 2a, 단위 2 PR #122에서 debate 3:0으로 B안 채택). 사본은 `Sources/MokaCore/` 밖이라 번들에 들지 않는다.
- 사본 시험 둘을 Swift(`QuestionsHistoryTests`)와 pytest 양쪽에 둔다. 지금 파일은 같은 `version`의 사본과 바이트까지 같다. 지난 사본은 지문을 시험에 고정한다(pytest SHA-256, Swift FNV-1a 64).
- 새 버전을 만들면 사본 `questions-history/<새 version>.json`을 더하고, 지난 사본이 된 파일의 지문을 두 시험에 고정한다.

## v2 제안 내용

```json
{
  "version": "v2",
  "language": "ko",
  "models": {
    "typesafe": "jev-1.13.0",
    "liquid": "d1-ultra",
    "perplexity": "pplx-decider-v1.2",
    "openai": "gpt-6-luna"
  },
  "provisional": ["d1-ultra", "pplx-decider-v1.2", "gpt-6-luna"],
  "questions": {"…": "v1 그대로"},
  "thresholds": {
    "jev-1.13.0": {"concrete": 0.5, "avoiding": 0.7},
    "d1-ultra": {"concrete": 0.5, "avoiding": 0.7},
    "pplx-decider-v1.2": {"concrete": 0.5, "avoiding": 0.7},
    "gpt-6-luna": {"concrete": 0.5, "avoiding": 0.7}
  }
}
```

- 잠정 임계값은 Jev 값을 그대로 옮겼다(ADR-0011 가정). 이전 값 없음, 새 값 0.5·0.7.
- Microsoft 줄은 기준 모델 ID가 정해질 때까지 두지 않는다. Microsoft를 여는 PR이 줄을 더하고 `version`을 올린다.
- `d1-ultra`가 별칭인지는 미확인이다(ADR-0011 미확인). Liquid를 여는 PR의 첫 실제 호출에서 고정 버전 ID가 따로 있다고 나오면 값을 바꾸고 `version`을 올린다.
- v1에서 v2로 올리면 질문 버전이 달라져 기존 판단 결과는 모두 다시 묻는다(ADR-0011 트레이드오프).

## v3 (사용자 결정 2026-11-12)

형식, 읽기 규칙, `models`, `provisional`, `thresholds`, 질문 이름·타입·`criteria`는 v2 그대로다. 바뀌는 것은 `version`과 질문 셋의 `instructions`다. `version`은 `"v3"`이다. urgency는 그대로다.

| 질문 | v2 `instructions` | v3 `instructions` |
|---|---|---|
| impact | 이 일을 안 하면 시험이나 제출 결과에 생기는 손해의 크기 | 마감이 언제인지와 상관없이, 이 일을 안 하면 시험 점수나 제출 결과에 생기는 손해의 크기 |
| concrete | 이 할 일은 2분 안에 첫 행동을 시작할 수 있을 만큼 구체적이다 | 이 할 일은 지금 바로 손댈 첫 행동이 무엇인지 분명할 만큼 구체적이다 |
| avoiding | 이 일은 사람이 미루기 쉬운 종류의 일이다 (크고, 지루하고, 끝이 안 보이는) | 이 일은 사람이 미루기 쉬운 종류의 일이다 (하기 싫거나 지루하고, 어디까지 하면 끝인지 모호한) |

- 지난 사본이 된 `questions-history/v2.json`의 지문을 두 시험에 고정하고, `questions-history/v3.json`을 지금 파일과 같은 바이트로 둔다.
- concrete 문구에서 2분이 빠져 spec 004 R-307 게이트 설명도 같이 바꾼다.
- v2에서 v3로 올리면 질문 버전이 달라져 기존 판단 결과는 모두 다시 묻는다.
