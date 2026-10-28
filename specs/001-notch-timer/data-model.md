# Data Model: 노치와 타이머 (spec 001)

이름은 `GLOSSARY.md`를 따른다(PR #5). 저장하는 것은 기본 작업 시간 설정 하나뿐이다(R-014).

## 1. 현재 할 일 (메모리, 저장 안 함)

| 필드 | 규칙 |
|---|---|
| `title` | 앞뒤 공백을 뺀 문자열, 비어 있으면 안 됨(R-002). 길이 제한 없음, 화면에서 자름 |

동시에 최대 1개(R-005). 앱을 다시 켜면 없다(R-014).

## 2. 타이머 상태기계 (MokaCore 값 타입)

| 상태 | 가진 값 | 들어오는 이벤트 |
|---|---|---|
| `empty` | 없음 | 시작 시, `complete` 뒤 |
| `running` | 할 일, `quantumMin`, `startedAt`, `endsAt = startedAt + quantumMin·60초` | `start(at:)` |
| `expired` | 할 일, `quantumMin`(마지막 값) | `tick(now:)`에서 `now ≥ endsAt` |

전이:

```
empty   --start(task, minutes, at)--> running
running --tick(now) [now < endsAt]--> running      (남은 시간만 갱신)
running --tick(now) [now ≥ endsAt]--> expired
running --complete(at)--------------> empty
expired --start(minutes, at)--------> running      (같은 할 일, R-010)
expired --complete(at)--------------> empty
```

- 남은 초 = `ceil(endsAt − now)`(초). `running`에서 항상 1 이상, `expired`에서 0(R-005·R-008).
- `tick`은 `now`가 이전 `now`보다 작아도 같은 규칙으로 계산한다(시계를 되돌려도 끝 시각 기준). `moka-sim` 입력은 시각 역행을 오류로 막는다(계약).
- 위 표에 없는 이벤트(예: `empty`에서 `tick`은 무시, `empty`에서 `complete`)는 상태를 바꾸지 않는다. 앱은 그런 이벤트를 만들지 않고, `moka-sim`은 입력 오류로 본다.
- 불변식: `endsAt > startedAt`, `quantumMin ∈ 1…180`.

## 3. 시간 칩 (MokaCore 값 규칙)

| 값 | 규칙 |
|---|---|
| 프리셋 | 15, 25, 45, 60분 |
| 직접 입력 | 정수 1~180. 그 밖, 빈 값, 숫자 아님, 소수는 "시작 불가"(R-004) |
| 미리 채움 | 제목 입력 직후와 시간 끝 화면에서 `default_quantum_min`(R-003). 시간 끝 화면은 마지막 `quantumMin`이 아니라 기본값으로 채운다(할 일별 마지막 선택은 범위 밖) |

## 4. 기본 작업 시간 설정 (MokaStore, 저장)

테이블(D1, 마이그레이션 `v1_settings`):

```
settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)
```

| key | value | 읽기 규칙(MokaCore) |
|---|---|---|
| `default_quantum_min` | 10진 정수 문자열 | 행이 없거나 정수가 아니거나 1~180 밖이면 25 |

- seed 행 없음. 처음 저장할 때 행이 생긴다(UPSERT).
- 쓰기는 1~180 정수만 받고 그 밖은 거부해 이전 값을 유지한다(R-012, US4 시나리오 3).
- 변경은 다음 칩 채움에 바로 반영되고 도는 타이머에는 영향이 없다(R-013): 타이머는 시작할 때 분을 복사해 가진다.
- `schema/moka-schema.sql` 스냅샷에 이 테이블이 처음으로 들어간다. 스냅샷 변경은 PR "사람이 볼 결정"에 올린다(ADR-0004).

## 5. 표시 위치 (MokaCore 순수 함수)

입력: 화면 목록 `[(id, isBuiltIn, hasNotch, isMain)]`. 출력: `.notch(id)` 또는 `.floating(id)`.

| 경우 | 결과 |
|---|---|
| `isBuiltIn && hasNotch`인 화면이 있음 | 그 화면의 `.notch` |
| 없음 | `isMain` 화면의 `.floating` |
| 화면이 0개 | 결과 없음(표시 안 함) |

화면 연결이 바뀌면 다시 계산한다. 타이머 상태는 바뀌지 않는다(R-011).

## 6. 화면 상태 (앱 `AppState`, 저장 안 함)

| 값 | 의미 |
|---|---|
| `isExpanded` | 펼침 여부 |
| `isPinnedOpen` | 시간 끝 자동 펼침으로 고정됨. `true`면 마우스가 나가도 접지 않음(R-009). 사용자가 시작·완료를 누르면 `false` |
| `draftTitle`, `chipMinutes`, `isEditingCustom` | 입력 중인 값 |
| `isInputFocused` | 입력칸에 포커스가 있으면 마우스가 나가도 접지 않음(Edge Case) |

자동 펼침(시간 끝)은 창을 key window로 만들지 않는다. 사용자가 노치를 클릭했을 때만 입력 포커스를 준다(R-009, spike 4번).
