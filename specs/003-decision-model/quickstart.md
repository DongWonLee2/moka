# Quickstart: 판단 모델 연동 MVP 확인 (spec 003)

결과는 PASS / FAIL / SKIP / NOT_RUN으로만 적는다. 실행하지 않은 것은 PASS로 적지 않는다. 가짜 할 일·가짜 키만 쓴다(사람 확인 6은 사람 자기 키).

## 1. 핵심 로직과 스키마 (자동, 리눅스 CI `core-test`)

```
swift test
```

기대: 아래 시험이 모두 PASS.
- 판단 입력 키 집합(금지 필드 없음), 정준 바이트, FNV-1a golden(SC-202, data-model §4·§5)
- TypeSafe 요청 본문 조립, 응답 해석(정상·질문 빠짐·타입 다름·범위 밖), 상태 코드 → 오류(contracts/decision-provider.md)
- 정규화·urgency 하한·aging·priority(R-204), 노치 순서와 순환(R-207, SC-203), 로그 판단 칸(R-211)
- 질의 대상·답 받기(질의 중 고침이면 버림, R-206, spec 엣지), 실패 다섯 종류에서 저장 없음(SC-205)
- `questions.json` 읽기(넷, blocked 없음, 임계값)
- `scores` 공용 계약(메모리·GRDB 왕복, 덮어쓰기), 마이그레이션 이름 리터럴, 스키마 스냅샷

## 2. 튜닝 계약 (자동, CI `tuning-test`)

```
cd tuning && python3 -m pytest
```

기대: `scores` 열 이름 집합, `questions.json` 같은 경로 읽기 PASS.

## 3. 시뮬레이터 (자동, 단위 맨 끝, R-215)

```
swift run moka-sim < Tests/MokaCoreTests/Fixtures/sim/storage-judge-order.json
```

기대: golden `.expected.jsonl`과 바이트 같음. 기존 spec 001·002 golden은 바이트 그대로(SimGoldenTests). 단위가 다음 spec으로 넘어가면 SKIP과 이유를 적는다.

## 4. 앱 빌드 (자동, CI `app-build`)

```
xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## 5. 화면 스냅샷 (로컬, CI `app-snapshots` 경고만)

설정 창 기본 탭 키 칸 상태 다섯(data-model §10), 할 일 탭 priority 칸(점수 있음·없음 섞임). 시안과 나란히 비교 페이지를 만든다.

## 6. 사람 확인 (확인용 빌드, 개인 팀 서명)

확인용 빌드 뒤 `codesign -dv`의 `TeamIdentifier`가 찍히는지 먼저 본다(research R15). Moka를 종료하고 다시 연다.

| # | 확인 | 대응 |
|---|---|---|
| 6-1 | 설정 창 기본 탭에 자기 키를 붙여 넣고 저장하면 "저장돼 있어요"로 바뀌고 키 값이 보이지 않는다 | US3, R-212 |
| 6-2 | 다시 빌드하고 다시 켜도 Keychain 확인 창이 반복되지 않는다(처음 한 번은 "항상 허용") | research R10 미확인 |
| 6-3 | 가짜 할 일 하나를 저장하면 10초 안에 설정 창 줄에 priority가 보인다. 결과는 PASS/FAIL과 응답 필드 이름만 | SC-201, SC-208 |
| 6-4 | 가짜 할 일 셋의 priority 순서대로 노치가 띄우고, 바꾸기 뒤 다음 순위가 뜬다 | SC-203 |
| 6-5 | 키를 지우면 priority 칸이 비고 노치가 마감일 순으로 돈다. 그 상태로 타이머·버튼이 동작한다(1시간은 주입 시계 시험이 맡고 사람은 몇 분만 본다) | US2, SC-204 |
| 6-6 | 틀린 키를 넣고 할 일을 저장하면 키 칸 옆에 다시 확인해 달라는 문구가 뜨고 노치는 그대로다 | US2-2 |

확인 순서를 적기 전에 그 상태를 지금 빌드에서 만들 수 있는지 먼저 본다(메모리 check-steps-must-be-doable).
