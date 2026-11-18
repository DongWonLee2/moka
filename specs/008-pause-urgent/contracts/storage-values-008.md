# 계약: 저장 값 덧붙임 (spec 008)

튜닝 스크립트와 앱이 함께 보는 저장 값이다. 원본 규칙은 [data-model.md](../data-model.md) §10·§11. 승인 항목 2·3·5(헌법 I). 값은 덧붙이기만 하고, 이미 쓰인 값을 바꾸거나 빼지 않는다(쌓인 로그를 지울 수 없음, spec 위험 2).

## 1. 스키마

바꾸지 않는다. 마이그레이션이 없고 `schema/moka-schema.sql`도 그대로다.

## 2. `decisions_log.user_action` (승인 항목 2)

| 값 | 뜻 | 줄이 생기는 때 |
|---|---|---|
| 기존 여섯(`done`, `skip`, `switch`, `carry_today`, `carry_drop`, `carry_move`) | 기존 | 그대로 |
| `pause` | 도는 중 일시 중지 | 두 줄의 등록·안 적기 한 번에 한 줄 |
| `resume` | 멈춘 작업 시간을 이어 돌림 | "다시 시작"으로 이어 돌 때 한 줄. 하루 경계로 끝나 이어 돌지 않으면 없음 |
| `urgent` | 긴급 입력으로 끊긴 할 일 | 긴급 제출 한 번에 한 줄 |

줄이 없는 입력: 긴급 할 일 만들기, 초안 일시 중지, 초안에서 멈춘 경우의 "다시 시작". DB에는 값 CHECK가 없다(지금 그대로). 앱은 `UserAction` 열거형으로만 쓰고 읽는다.

## 3. `decisions_log.scheduler_choice` (승인 항목 3)

| 값 | 뜻 |
|---|---|
| 기존 다섯(`rotate_by_id_v0`, `priority_rotate_v0`, `weighted_rotate_v1`, `warmup_v1`, `carry_card_v1`) | 그대로 |
| `urgent_pin_v1` | 긴급 할 일에 누른 버튼 줄, 긴급 고정으로 고른 할 일의 줄(R-813) |
| `urgent_return_v1` | 복귀 제안으로 띄운 할 일의 줄(R-814) |

복귀 제안 초안에서 "다른 할 일"로 바꾸면 `urgent_return_v1`을 그대로 쓴다(spec 005 R-411). `pause`·`resume`·`urgent` 줄의 값은 그 할 일을 노치에 띄운 규칙이다.

판단 칸(`question_version`, `provider`, `probs_json`, `state_hash`, `model_snapshot`)은 spec 003 R-212 그대로다.

## 4. `checkpoints.trigger`

새 값은 없다. 스키마와 `CheckpointTrigger`에 이미 있는 값을 처음 쓴다.

| 값 | 쓰는 때 | 경과 분 |
|---|---|---|
| `pause` | 도는 중 일시 중지의 등록·안 적기(R-802) | 멈출 때까지 돈 분 |
| `urgent` | 긴급으로 끊긴 할 일(R-812) | 돈 분, 입력 중 시간 끝이 왔으면 고른 분 |
| `day_end` | 멈춘 채 하루 경계를 넘김(R-806), 빈 두 줄 | 멈춘 시간을 뺀 돈 분 |
| `quit` | 멈춘 채 정상 종료(R-807), 빈 두 줄 | 멈춘 시간을 뺀 돈 분 |

멈춘 동안 `sleep` 체크포인트는 없다.

## 5. `settings` 키 (승인 항목 5)

`default_pause_min`: 정수 분 글자, 1~180, 없거나 형식이 틀리면 30. 일시 중지 상태와 긴급 고정은 저장하지 않는다(R-807, R-813). 튜닝 스크립트는 `settings`를 읽지 않는다.

## 6. 계약 시험

`tuning/tests/test_schema_contract.py`에 `decisions_log`에 `user_action = 'pause'`·`'resume'`·`'urgent'`, `scheduler_choice = 'urgent_pin_v1'`·`'urgent_return_v1'` 줄이 들어가는지, `checkpoints`에 계기 `pause`·`urgent` 줄이 들어가는지를 더한다(값 CHECK가 없거나 이미 받는 값임을 계약으로 고정).
