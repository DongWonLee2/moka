# 계약: 저장 값 덧붙임 (spec 005)

튜닝 스크립트와 앱이 함께 보는 저장 값이다. 원본 규칙은 [data-model.md](../data-model.md) §2·§13·§16. 승인 항목 1·2·3·5(헌법 I). 값은 덧붙이기만 하고, 이미 쓰인 값을 바꾸거나 빼지 않는다(쌓인 로그를 지울 수 없음, spec 위험 2).

## 1. `tasks` 열 (승인 항목 1)

| 열 | 타입 | 기본 | 제약 |
|---|---|---|---|
| `carry_count` | `INTEGER NOT NULL` | 0 | `CHECK(carry_count >= 0)` |
| `due_decision` | `INTEGER NOT NULL` | 0 | `CHECK(due_decision IN (0, 1))` (Q6-A, debate 3:0) |

마이그레이션 이름 `v4_tasks_carry`. `schema/moka-schema.sql`과 `tuning/tests/test_schema_contract.py`가 같은 내용을 본다.

## 2. `decisions_log.user_action` (승인 항목 2)

| 값 | 뜻 | 줄이 생기는 때 |
|---|---|---|
| `done`, `skip`, `switch` | 기존 | 그대로 |
| `carry_today` | 이월 카드 "오늘 할래요" | 답 한 번에 한 줄 |
| `carry_drop` | 이월 카드 "버릴래요" | 같음 |
| `carry_move` | 이월 카드 "날짜 바꿀래요"(날짜를 고른 뒤) | 같음. "돌아가기"는 줄 없음 |

DB에는 값 CHECK가 없다(지금 그대로). 앱은 `UserAction` 열거형으로만 쓰고 읽고, 모르는 값은 읽을 때 `StoreError.unknownValue`다. 가용 시간 답과 "더 할래요"는 줄이 없다(R-416).

## 3. `decisions_log.scheduler_choice` (승인 항목 3)

| 값 | 뜻 |
|---|---|
| `rotate_by_id_v0` | spec 002 줄(읽기만) |
| `priority_rotate_v0` | spec 003 줄(읽기만) |
| `weighted_rotate_v1` | 가중 순환으로 노치에 뜬 할 일의 버튼 줄(R-403). "더 할래요" 뒤 고르기도 같다 |
| `warmup_v1` | 아침 워밍업으로 뜬 할 일의 버튼 줄(R-406) |
| `carry_card_v1` | 이월 카드 답 줄(R-416) |

"다른 할 일"로 바꾼 할 일은 바꾸기 전 초안의 이름을 그대로 쓴다(R-411). 마무리 규칙과 연속 상한은 앱 경로가 없어 줄에 나오지 않는다(R-407). 긴급 이름은 Issue #171이다.

판단 칸(`question_version`, `provider`, `probs_json`, `state_hash`, `model_snapshot`)은 spec 003 R-212 그대로다. 이월 답 줄도 같다.

## 4. `checkpoints.trigger`

새 값은 없다. `day_end`를 처음 쓴다: 오늘 끝과 겹친 시간 끝 화면에서 누른 완료·미루기·바꾸기(data-model §12, research R11).

## 5. `settings` 키 (승인 항목 5)

data-model §13 표가 원본이다. `day_budget` JSON은 `{"day","extended_min","minutes","more","used_s"}`이고(data-model §11), 직접 적기와 늘리기(사용자 결정 2026-11-16)로 가용 시간을 분으로 둔다. 키 이름: `auto_start`, `carry_judged_at`, `day_budget`, `last_start_day`. `carry_judged_at`은 `TaskRepository`만 읽고 쓰고 `SettingsStore`는 이 키를 거부한다(Q1-B). 튜닝 스크립트는 `settings`를 읽지 않는다.
