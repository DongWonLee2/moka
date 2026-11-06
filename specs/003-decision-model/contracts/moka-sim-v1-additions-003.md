# 계약: `moka-sim` v1 덧붙임 (spec 003)

spec 001 `contracts/moka-sim-v1.md`와 spec 002 `contracts/moka-sim-v1-additions.md`에 덧붙인다. `version`은 1 그대로다. 근거: spec R-215, research R13. 승인 항목(헌법 I). tasks 맨 끝 단위이고, 2026-11-08까지 필수 요구가 끝나지 않으면 다음 spec으로 넘긴다.

## 입력 덧붙임 (storage 모드에서만)

| 이벤트 | 필드 | 규칙 |
|---|---|---|
| `judge` | `task`(할 일 id, 정수), `urgency`(0~3 정수 또는 실수), `impact`(0~2), `concrete`(0~1), `avoiding`(0~1) | 가짜 공급자 답으로 그 할 일의 판단 결과를 바로 저장한다(공급자 `fake`, 모델 `fake-1`, 질문 버전은 번들 `questions.json`). 대기·진행 중 할 일만 받는다 |
| `key` | `present`(불리언) | 키 유무. 시작 값은 `false` |

- 할 일은 제목이 아니라 id로 가리킨다(출력에 제목을 내지 않는 규칙과 맞춤).
- 종료 코드 2: storage가 아닌데 새 이벤트, 모르는 키·필수 필드 없음·타입 틀림, 범위 밖 값, 없는 할 일 id, 완료·버린 할 일에 `judge`.

## 출력 덧붙임

시나리오에 `judge`나 `key`가 하나라도 있을 때만, storage 모드의 모든 줄에 spec 002 키 뒤로 아래를 이 순서로 붙인다. 없으면 출력은 spec 002 그대로다(기존 golden 바이트 동일, 시험으로 고정).

| 키 | 규칙 |
|---|---|
| `order` | 노치 후보 순서(data-model §7)의 할 일 id 배열. 대기 할 일이 없으면 `[]` |
| `has_key` | 키 유무 불리언 |

그리고 이 경우 `decision` 객체에 `"provider":"fake"|"fallback"`을 `scheduler_choice` 앞에 더한다. 점수 있는 할 일이면 `fake`, 없으면 `fallback`. `scheduler_choice`는 `priority_rotate_v0`.

## 예

입력(가짜):

```json
{"version":1,"timezone":"Asia/Seoul","storage":true,"events":[
 {"at":"2026-11-07T00:00:00Z","type":"add_task","title":"가짜 할 일 A"},
 {"at":"2026-11-07T00:00:05Z","type":"add_task","title":"가짜 할 일 B"},
 {"at":"2026-11-07T00:00:10Z","type":"key","present":true},
 {"at":"2026-11-07T00:00:20Z","type":"judge","task":2,"urgency":3,"impact":2,"concrete":0.9,"avoiding":0.1},
 {"at":"2026-11-07T00:00:30Z","type":"start"}
]}
```

읽는 법: 키가 생기고 할 일 2에 점수가 붙으면 `order`가 `[2,1]`이 되지만, 노치에는 이미 초안 1이 떠 있으므로 그대로다(data-model §7, 초안은 바꾸지 않음). 다음 고르기부터 2가 1위다. 정확한 출력 바이트는 단위의 첫 Red 커밋에서 golden으로 둔다.
