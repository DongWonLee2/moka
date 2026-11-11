# Quickstart: 판단 공급자 고르기와 키 넣기 확인 (spec 006)

결과는 PASS / FAIL / SKIP / NOT_RUN으로만 적는다. 실행하지 않은 것은 PASS로 적지 않는다. 가짜 할 일과 가짜 키만 쓴다(사람 확인 6은 사람 자기 키). 규칙은 [data-model.md](data-model.md), 계약은 [contracts/](contracts/)를 본다.

## 1. 핵심 로직 (자동, 리눅스 CI `core-test`)

```
swift test
```

기대: 아래 시험이 모두 PASS이고, 기존 spec 001~004 시험과 시뮬레이터 golden이 그대로 PASS다. 기존 시험은 바뀐 시그니처에 맞춰 호출만 고치고 기대값은 그대로다(research R12).

- 공급자 표: 다섯 줄의 공급자 ID, 주소, 인증, 요청 모양, 열린 공급자가 `typesafe` 하나 (R-601, data-model §2)
- System One 코덱: 지금 `TypeSafeCodec` 시험이 `SystemOneCodec` 이름으로 PASS, 공급자 넷의 본문이 보낼 모델 이름만 다름 (R-602, SC-601)
- OpenAI 코덱: 요청 배열 변환과 `predicate`, 응답 사전 변환, 같은 이름 둘, 같은 `value` 둘, 칸 빠짐, 범위 밖 (R-603, SC-602)
- 상태 코드: 두 모양이 같은 표, 200만 해석, 200이 아닌 2xx와 3xx는 `server(status)`, `RedirectRule`이 3xx 네 종류에 `nil` (R-604, R-618, SC-614)
- 주소 규칙: data-model §4 사례 표 전부와 호스트 꺼내기 (R-605, R-606, SC-603)
- 질문 파일 v2: 읽기 규칙 2·4 위반 파일을 읽지 않음, 버전별 고정값 시험, `thresholds(for:)`가 없는 기준 모델에 `nil` (R-607, R-608, SC-604)
- 고른 공급자 정하기: 설정 없음이면 `typesafe`, 모르는 ID, 열리지 않은 공급자, Microsoft 주소 없음·거부·배포 이름 없음, 보낼 모델 이름 (R-609, R-610, R-614, data-model §6)
- 판단 결과 규칙: 공급자가 다른 결과는 쓰지 않고 다시 묻기 대상, 임계값 `nil`이면 게이트 닫힘과 avoiding 배율 1 (R-609, R-611, SC-605)

## 2. 튜닝 계약 (자동, CI `tuning-test`)

```
cd tuning && python3 -m pytest
```

기대: `test_questions_contract.py`가 `models`의 모든 값에 임계값이 있는지 보고 PASS. `test_schema_contract.py`는 바뀌지 않고 PASS (R-612, SC-613).

## 3. 앱 빌드 (자동, CI `app-build`)

```
xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## 4. 앱 시험 (로컬 macOS, `MokaAppTests`)

```
xcodegen generate && xcodebuild test -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MokaAppTests
```

기대(이름이 다른 가짜 공급자 둘과 공급자별 가짜 키 보관함, 실제 시간을 기다리지 않음):

- 업그레이드: 설정 없음, `typesafe` 항목에 키 있음이면 조작 없이 판단 결과가 붙음 (US1-1, SC-607)
- 고르기와 저장: 키가 고른 공급자 항목에만 저장, 설정·판단 결과·로그에 키 없음 (US1, SC-608)
- 바꾸기: 쓰는 판단 결과가 비고 모든 할 일을 다시 묻음, 장부 비움, 키 확인 필요 꺼짐, `hasKey`가 새 항목으로, 바꾸기 전 떠난 답을 저장하지 않음(가짜 공급자 붙잡기), 그 답이 401이어도 키 확인 필요가 켜지지 않음, 이전 공급자의 429·timeout 실패가 새 장부와 게이트를 바꾸지 않음, off 상태에서도 키 저장과 `hasKey` 읽기, 같은 공급자 다시 고름은 아무것도 안 함, 돌아오면 이전 키와 이전 판단 결과를 다시 씀 (US2, SC-605)
- 꺼짐: 고른 공급자가 질문 파일에 없거나 모르는 ID면 질의 0건, 노치 마감일 순, 멈추지 않음 (SC-606)
- Microsoft 칸(가짜 열린 Microsoft 줄을 넣은 시험용 `catalog`): 주소 거부면 저장 안 함, 처음 저장에는 키를 지우지 않음, 저장된 주소를 바꾸면 키 지움, 주소 없는 off 상태에서도 키 저장, 지우기 실패면 주소 저장 안 함, 배포 이름을 바꾸면 보낼 모델 이름이 바뀌고 저장된 판단 결과는 그대로 씀 (US3, SC-609)
- 온보딩 키 단계: Jev 항목에 저장, 빈 칸이면 다음 꺼짐, 건너뛰기, 저장 실패, 이미 있음, 키 없이 끝낸 뒤 노치에 할 일이 뜸 (US4, SC-611)
- 할 일 탭 키 확인: 401 뒤 켜짐, 키 저장·지움·공급자 바꾸기에 꺼짐, 키 없음에 꺼짐 (US5, SC-612)

## 5. 화면 스냅샷 (로컬, CI `app-snapshots` 경고만)

새 상태: data-model §9 판단 모델 칸 상태(Jev 키 없음, 저장됨, 키 확인 필요, 목록 펼침, 잠정값, Microsoft 주소 없음·거부·저장됨·키 지움 안내, 설정 쓰기 실패), 온보딩 키 단계 셋(키 없음, 저장 실패, 이미 있음)과 보내는 곳 줄, 할 일 탭 키 확인 한 줄. 라이트·다크. 기본 탭 키 칸의 기존 참조 이미지는 바뀌고 PR에 이유를 적는다. 그 밖의 참조 이미지는 그대로다(SC-613). 시안 `~/Dev/ai-platform/projects/moka/design/006-mockup.html`과 나란히 보는 비교 페이지를 `design/pr-<번호>/index.html`에 만든다(ADR-0009).

## 6. 사람 확인 (확인용 빌드, 개인 팀 서명)

확인 순서를 적기 전에 그 상태를 지금 빌드에서 만들 수 있는지 먼저 본다.

| # | 확인 | 상태를 만드는 법 | 대응 |
|---|---|---|---|
| 6-1 | 업데이트 전부터 Jev 키를 쓰던 앱을 이 빌드로 바꾸고 켜면, 기본 탭에 TypeSafe Jev가 골라져 있고 키가 저장되어 있다고 보이며, 가짜 할 일을 저장하면 판단 결과가 붙는다 | 지금 쓰는 앱 그대로 새 빌드를 켬. 질문 파일이 v2라 처음에는 모든 할 일을 다시 묻는다 | US1-1, SC-607 |
| 6-2 | 기본 탭 공급자 목록에 다섯이 보이고, Jev 말고는 고를 수 없으며 이유가 보인다. 보내는 곳에 `api.typesafe.ai`가 보인다 | 기본 탭을 엶 | US1-2, R-620 |
| 6-3 | 리디렉트 거부. 이 spec 동안: 확인용 빌드에서 Jev로 가짜 할 일을 저장해 판단 결과가 붙는지 본다(리디렉트를 거부하는 세션 대리자가 정상 응답을 막지 않음). 거부 판단 자체는 자동 시험(1의 `RedirectRule`, 3xx `server`)이 맡는다. Microsoft를 여는 브랜치에서: loopback에 3xx를 돌려주는 로컬 서버를 띄워 Microsoft 주소로 `http://localhost:<포트>`를 넣고, 실패 종류가 `server`이고 서버에 두 번째 요청이 없는지 본다 | Jev 확인은 6-1과 같은 빌드. loopback 확인은 Microsoft가 열리기 전에는 만들 수 없어 그때까지 NOT_RUN | R-618, SC-614 |
| 6-4 | macOS 새 사용자 계정에서 Moka를 처음 켜면 Jev 키 단계가 첫 단계로 보이고 보내는 곳 줄이 있다. 건너뛰기, 건너뛰기, 시작하기로 끝낸 뒤 할 일을 넣으면 노치에 뜬다 | 새 사용자 계정(에이전트는 실제 앱 DB를 지우거나 열지 않음) | US4, SC-611 |
| 6-5 | 틀린 키를 저장하고 할 일을 저장하면 할 일 탭 목록 위에 키 확인 한 줄이 보이고, 누르면 기본 탭으로 바뀐다. 맞는 키를 다시 저장하면 사라진다 | 기본 탭에 가짜 문자열을 키로 저장 | US5, SC-612 |

## 7. 공급자를 여는 PR (사람, spec R-617·R-629)

이 spec의 단위가 아니다. 공급자마다 한 번 한다.

1. 에이전트가 그 공급자를 여는 브랜치를 만든다. 공급자 표의 `firstCallConfirmed`를 참으로, 공급자 표 시험의 기대값을, Microsoft면 질문 파일 `models`와 `version`과 고정값을 바꾼다.
2. 사람이 그 브랜치의 빌드에서 그 공급자를 고르고 자기 키를 넣은 뒤 가짜 할 일 하나를 저장한다.
3. PR에 PASS/FAIL과 응답 최상위·답 안쪽 필드 이름만 적는다. 응답 원문과 할 일 제목은 적지 않는다. OpenAI는 score 답의 `score`·`confidence` 칸 유무, Microsoft는 응답 `model` 값의 모양(배포마다 실제 버전을 주는지)을 적는다.
4. 필드가 계약과 다르면 그 코덱과 계약 문서를 같은 PR에서 고친다. Microsoft는 research R3을 다시 본다.
5. 사람이 병합하면 그 공급자가 열린다.
