# 계약: `questions.json` v1

> spec 006 [contracts/questions-json-v2.md](../../006-decision-providers/contracts/questions-json-v2.md)가 대체한다. 최상위 `model`은 `models`로 바뀌고 `provisional`이 더해졌다. 위치와 질문 넷의 문구·타입·옵션은 이 문서 그대로다.

- 위치: `Sources/MokaCore/Resources/questions.json`(`Package.swift`의 MokaCore `resources: [.copy("Resources/questions.json")]`, 앱·시험·`moka-sim`은 `Bundle.module`). 튜닝 pytest는 저장소 루트 기준 같은 경로를 읽는다.
- 공개 계약이다(헌법 I, AGENTS.md). 문구·옵션·임계값·모델 중 하나라도 바꾸면 `version`을 올리고 제안만 한다. 라벨셋 비교는 사람이 실행한다.
- 근거: spec R-202·R-203, research R2·R9.

## 형식

| 키 | 타입 | 규칙 |
|---|---|---|
| `version` | 문자열 | `"v1"`. 로그 `question_version`과 `scores.question_version`에 그대로 |
| `language` | 문자열 | `"ko"` |
| `model` | 문자열 | 요청에 보내는 고정 모델 ID. 별칭(`jev-latest` 등) 금지 |
| `questions` | 객체 | TypeSafe 요청 `questions`와 같은 모양(contracts/decision-provider.md). 키는 질문 이름 |
| `thresholds` | 객체 | 키는 모델 ID. 값은 질문 이름 → 임계값. `thresholds[model]`이 반드시 있어야 한다 |

- 질문 이름은 `urgency`, `impact`, `concrete`, `avoiding` 넷이고 더도 덜도 없다. score의 `criteria`는 낮음에서 높음 순 배열(2~10개).
- 읽기 시험: 넷이 모두 있고 타입이 맞음, `thresholds[model]`에 `concrete`·`avoiding`이 있음, 임계값 0~1, `blocked`가 없음.

## v1 내용

```json
{
  "version": "v1",
  "language": "ko",
  "model": "jev-1.13.0",
  "questions": {
    "urgency": {
      "type": "score",
      "instructions": "마감과 남은 분량을 기준으로, 이 일을 언제까지 시작해야 하는가",
      "criteria": ["여유", "이번주", "급함", "오늘안에"]
    },
    "impact": {
      "type": "score",
      "instructions": "이 일을 안 하면 시험이나 제출 결과에 생기는 손해의 크기",
      "criteria": ["조금", "꽤", "아주"]
    },
    "concrete": {
      "type": "noul",
      "instructions": "이 할 일은 2분 안에 첫 행동을 시작할 수 있을 만큼 구체적이다"
    },
    "avoiding": {
      "type": "noul",
      "instructions": "이 일은 사람이 미루기 쉬운 종류의 일이다 (크고, 지루하고, 끝이 안 보이는)"
    }
  },
  "thresholds": {
    "jev-1.13.0": {"concrete": 0.5, "avoiding": 0.7}
  }
}
```

문구는 PRD 6장 instructions v1 그대로다. impact 옵션만 사용자 결정(2026-11-06)으로 PRD의 "보통/큼/치명적"에서 "조금/꽤/아주"로 바꿨다. concrete 임계값은 이번에 쓰지 않는다(FR-13은 다음 spec).
