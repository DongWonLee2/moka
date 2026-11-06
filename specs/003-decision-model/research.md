# Research: 판단 모델 연동 MVP (spec 003)

결정마다 토론(가이드 A·실행 B·위험 C 세 자리)으로 추천안을 만들고 사용자가 2026-11-06에 골랐다. 토론 기록과 결정 로그는 로컬 `.audit/`(커밋하지 않음): 요구 다지기 `debate/20261106-1640-spec003-grill-r1.md`·`20261106-1720-spec003-grill-r2.md`, plan 승인 항목 `debate/20261106-1900-spec003-plan.md`, 결정 로그 `spec003.tsv`. "사용자 결정"은 토론 안과 다르게 사용자가 정한 것, "사용자 위임"은 3:0 안을 묻지 않고 채택하라는 사용자 지시(2026-11-06)로 채택한 것이다.

## R1. 범위 (요구 다지기 Q1·Q6·Q9, 3:0)

- **Decision**: FR-03 판단 질의, FR-14 어댑터(공급자 하나 + 코드 폴백), 설정 창 키 칸, FR-04 점수 식과 요소 점수 저장, 노치 정렬. 이유 3개 화면, FR-13 구체화 게이트, 온보딩 키 단계, 노치 "키 확인" 표시는 다음 spec(v1 태그 2026-11-09 전).
- **Rationale**: PRD 12장 완료 조건 "모델 점수로 정렬된 할 일이 노치에 뜬다"(prd.md:229)에는 이유 화면과 게이트가 없다. 화면이 늘면 사람 확인이 검증 시작(11/10) 전에 몰린다. 온보딩은 다시 나오지 않아 지금 빌드에서 확인할 길이 없다.
- **Alternatives**: 넷 다 한 spec(사람 확인 몰림), 이유 화면까지 넣고 밀리면 버퍼(1라운드 A, 2라운드에 바꿈). spec 002 research R8의 "온보딩 키 단계도 마일스톤 3"을 이 결정으로 바꾼다.

## R2. 판단 질문 넷, blocked 없앰 (요구 다지기 Q7·R2-6, 사용자 결정)

- **Decision**: 질문은 urgency(score 4단계), impact(score 3단계 "조금/꽤/아주"), concrete(noul), avoiding(noul). 문구는 PRD 6장. 판단 입력의 일정 중요도도 "조금/꽤/아주"로 보낸다. blocked는 질문·식·표에서 모두 뺀다.
- **Rationale**: PRD가 사용자 문서이고 설계서 3.2는 그 입력이다. impact 3단계는 일정 중요도 세 값과 맞는다. blocked는 사용자 결정: 앱의 핵심은 여러 할 일의 우선순위를 판단 모델로 잡는 것이라 막힘 판정이 필요 없고, 판단 입력에 다른 할 일이 없어 모델이 제목만 보고 짐작할 뿐이다.
- **Alternatives**: 설계서 3.2 문구(urgency "내일까지/오늘", impact 4단계), 영어 v1-en 함께(라벨셋 비교는 마일스톤 5). blocked는 토론에서 "0.7 이상 후보 제외"(C)와 "감점만"(A·B)이 3라운드까지 맞섰고, 사용자가 셋째 안(없앰)을 골랐다.
- **PRD와 다름**: PRD 6장 질문 표, 7장 식·w_b·정책 1, 9장 `scores` 열. PRD는 저장소 밖이라 사람이 고친다.

## R3. 판단 결과 저장: 새 표 `scores` (요구 다지기 Q3 3:0 사용자 승인, plan P2 3:0)

- **Decision**: 마이그레이션 `v3_scores`. 할 일당 한 줄, 다시 물으면 덮어쓴다. priority 열은 두지 않고 고를 때 계산한다. CHECK 없음. 열은 data-model §2.
- **Rationale**: 행동 로그는 `user_action NOT NULL`(schema/moka-schema.sql:3)이라 버튼 없는 판단(저장 직후 질의)을 담을 수 없다. 11장 판단 정확도 지표가 `labels, scores`를 읽는다(prd.md:217). 메모리에만 두면 다시 켤 때마다 전부 다시 묻고 순서가 흔들린다. priority는 미룬 횟수에 기대므로 열로 두면 버튼마다 갱신해야 하는 두 번째 원본이 된다. 열은 나중에 더하기 싸고 빼기는 비싸다(ADR-0004·0007).
- **Alternatives**: 메모리만(2라운드 B), 행동 로그에서 복원(버튼 없는 판단은 줄이 없음), priority 열 저장(PRD 9장).

## R4. 질의 시점 (요구 다지기 Q4 3:0, R2-3 보충 사용자 결정)

- **Decision**: 저장·고침 직후 그 할 일, 일정 추가·고침·지움과 키 저장 때 전체, 앱 시작·하루 시작(활성화 판정이 하루를 넘겼을 때)에 점수 없음·6시간 지남·질문 버전 다름, "다시 물어보기" 버튼에 점수 없는 할 일. quantum 만료 재점수는 마일스톤 4.
- **Rationale**: FR-01·FR-02 수용 기준(prd.md:61~62)을 채운다. 상위 5개는 스케줄러 개념이다. 다시 묻는 길은 사용자가 "다음 질의 시점 + 버튼 둘 다"를 골랐다.
- **Alternatives**: PRD 7장 7번 그대로, 실패 뒤 몇 분 뒤 자동 재시도(서킷브레이커와 겹침).

## R5. 실패 처리와 폴백 (요구 다지기 Q8·R2-3, 3:0)

- **Decision**: 3초 전체 시간 상한. 어떤 실패든 재시도 없이 그 할 일의 판단 결과를 저장하지 않는다. 401이면 설정 창 키 칸 옆에 해요체 문구, 노치는 그대로. 폴백은 마감일 정렬만이고 로그에는 공급자 `fallback`만.
- **Rationale**: FR-14 수용 기준은 "키 없이 1시간 동작"뿐이고 서킷브레이커는 마일스톤 5다(prd.md:74, :231). 공급자가 하나라 "다음 공급자"가 없다. 합성 확률(설계서 3.3)을 넣으면 지울 수 없는 로그에 가짜 확률이 섞인다. 폴백 줄은 spec 002 F5 CHECK가 이미 받는다(spec 002 research R5).
- **Alternatives**: 401일 때 노치 표시(1라운드 C, 다음 spec으로), 429 백오프, 확률 0.5 합성.

## R6. 노치 순서 (요구 다지기 Q2·R2-1 3:0, spec 엣지 사용자 확인)

- **Decision**: 점수 있는 대기 할 일을 priority 내림차순으로 앞, 점수 없는 할 일을 마감일 순(마감 없음 맨 뒤, 같으면 만든 순)으로 뒤. 같은 priority는 마감 이른 순, 그다음 만든 순. 키가 없으면 모두 점수 없음. 순환은 spec 002 R-104를 이 순서로(처음·완료 뒤 1위, 바꾸기·미루기 뒤 방금 할 일 다음 순위, 끝이면 1위). 도는 중·초안은 점수가 바뀌어도 바꾸지 않는다.
- **Rationale**: 늘 1위만 띄우면 바꾸기(skip_count를 올리지 않음) 뒤 같은 할 일이 다시 뜬다. R-104 사용자 결정을 그대로 두고 기준만 바꾼다. 점수 없는 할 일에 코드로 priority를 지어내면 R5를 뒤집는다.
- **Alternatives**: 늘 1위, 점수 없는 할 일에 지어낸 priority, 하나라도 없으면 전체 마감일 순.

## R7. 공급자 경계 (plan P1, 3:0)

- **Decision**: MokaCore에 `DecisionProvider` 프로토콜, 질문·답 타입, 오류 열거형, TypeSafe 요청 JSON 조립과 응답 해석, 가짜 공급자. 앱 타깃에 URLSession 전송만 하는 `TypeSafeProvider`. 타임아웃은 `URLSessionConfiguration.timeoutIntervalForResource = 3`(값은 `Defaults`). 설계서 3.1의 `ProviderID` 열거형과 비용 칸은 뺀다(공급자 이름은 문자열, 응답에 cost 없음).
- **Rationale**: ADR-0001:28~29. 헌법 VIII은 금지 필드를 테스트로 막으라 하므로 요청 조립이 리눅스 `swift test` 안에 있어야 한다. `timeoutInterval`(요청)은 데이터가 끊긴 시간만 재고 전체 상한은 resource 쪽이다(Apple URLSessionConfiguration 문서).
- **Alternatives**: 좁은 도메인형 `judge(TaskState)`와 JSON을 앱 안에(SC-202를 리눅스로 못 막음), Core에서 시계를 주입해 타임아웃 경쟁(실제 시간 시험 금지와 충돌).

## R8. `scheduler_choice` 새 값 (plan P3, 3:0)

- **Decision**: `priority_rotate_v0` 하나. 점수 유무는 같은 줄 provider로 가른다.
- **Rationale**: R-211은 규칙 이름을 하나로 적는다. 값을 둘로 쪼개면 같은 사실을 두 칸에 적어 어긋날 길이 생긴다. 로그 값은 지울 수 없으니 적게 만든다.
- **Alternatives**: `priority_rotate_v0` + `deadline_fallback_v0`.

## R9. 질문 파일 형식과 위치 (요구 다지기 R2-5 2:1 사용자 승인, plan P4 3:0)

- **Decision**: `Sources/MokaCore/Resources/questions.json` 한 벌(`Bundle.module`). `version`, `language`, `model`(고정 모델 ID), `questions`(TypeSafe 요청 `questions`와 같은 모양), `thresholds`(모델 ID 아래 concrete·avoiding). 정규화 분모는 `criteria` 수 − 1. 모델을 바꾸면 버전을 올린다. pytest가 같은 경로를 읽는 시험, AGENTS.md 저장소 지도에 공개 계약으로 적는다. 형식은 contracts/questions-json.md.
- **Rationale**: 변환 계층이 없으면 변환 시험도 없다. 모델 ID와 임계값 키가 한 파일에 있으면 어긋날 수 없고 Swift·Python 시험이 같은 값을 본다. `Bundle.module`은 앱·시험·`moka-sim`·리눅스 CI가 같은 경로다.
- **Alternatives**: 루트 `questions/questions.json` + Core 주입(소수 C: 루트 공유 선례, 폴더를 옮겨도 pytest 경로 유지. 기각 이유: 루트 파일을 앱 번들에 넣는 XcodeGen 경로 미확인, `moka-sim` 실행 위치 의존), 앱 고유 형식 + 변환, 모델 ID를 `Defaults`에(1라운드 A).

## R10. 키 보관함 (spec 002 R8 P8 (a) 전제, plan P6 3:0)

- **Decision**: MokaCore `KeyStore`(hasKey·read·save·delete, 동기)와 가짜 구현. 앱 `KeychainKeyStore`: 로그인 키체인 generic password, service `dev.dongwon.moka`, account `typesafe`. `hasKey`는 `kSecReturnAttributes`만 켠 조회(값을 꺼내지 않음). 접근성 속성은 두지 않는다.
- **Rationale**: spec 002 research R8 기록 보존. data protection keychain은 서명·entitlement 조건이 미확인이다. 로그인 키체인에서 `kSecAttrAccessible`이 지켜지는지 미확인이라, 넣으면 보호받는 것처럼 보이기만 하고 사람 확인에서 원인(속성·서명)을 가를 수 없다.
- **사람 확인(미확인 둘)**: 개인 팀 서명 빌드에서 다시 빌드해도 확인 창이 반복되지 않는지, 로그인 키체인에서 접근성 속성이 지켜지는지(공식 문서).
- **Alternatives**: data protection keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`(1라운드 B).

## R11. 비동기 질의 경계 (plan P7, 3:0)

- **Decision**: MokaCore는 순수 함수만(누구를 물을지, 판단 입력 조립·해시, 답 받기 판정, 점수 정규화·priority·순서). 앱 `AppState`(`@MainActor`)가 `Task`로 공급자를 부르고 MainActor에서 판정해 저장한다. Core actor 없음.
- **Rationale**: AppState는 쓰기가 모두 MainActor 동기다. Core에 actor를 두면 쓰는 쪽이 둘이 되고, `moka-sim`의 동기 이벤트 모델이 async로 바뀐다. 순수 함수는 시계 없이 시험된다(헌법 II).
- **틀리는 조건**: AppState의 진행 중 질의 장부가 커지면 앱 타깃 안의 작은 `@MainActor` 조정자로 뗀다(Core actor가 아님).

## R12. 판단 입력 해시 (plan P8, 3:0)

- **Decision**: 의존성 없이 FNV-1a 64비트, 16진수 16자. 입력은 손으로 만든 정준 문자열(data-model §5). Double을 넣지 않고 날짜는 문자열. golden 시험을 리눅스·macOS 둘에서 돌린다.
- **Rationale**: 의존성 추가는 승인 항목이고 리눅스 컨테이너에 CryptoKit이 없다. 용도는 동일성 판정과 로그 대조이고 보안이 아니다. 앱만 CryptoKit을 쓰면 앱과 `moka-sim`의 해시가 달라진다.
- **Alternatives**: swift-crypto SHA-256(의존성), 해시 함수 주입.

## R13. `moka-sim` 확장 (plan P5, 2:1 A·C / B, 사용자 승인)

- **Decision**: storage 모드에 이벤트 `judge`·`key`. 시나리오에 이 이벤트가 하나라도 있을 때만 출력에 새 칸을 붙인다. 기존 golden은 바이트 그대로(시험). tasks 맨 끝, 11/8까지 필수(R-201~R-211, R-213)가 안 끝나면 다음 spec. 형식은 contracts/moka-sim-v1-additions-003.md.
- **Rationale**: R-215가 spec의 요구이고, 리눅스 CI 출력 한 줄에서 순서와 로그 판단 칸을 함께 본다(ADR-0003 검증 경로). 이벤트 type 둘 추가라 되돌리기 싸고 시나리오에 `version` 칸이 있다.
- **소수 의견(B)**: 이번에는 넓히지 않고 단위 시험만. `NotchSession` 단위 시험도 리눅스에서 돌고, 사흘 남은 일정에 공개 계약을 서둘러 확정하는 비용만 남는다. 3라운드까지 B·C가 두 번 맞바뀌었다.
- 어느 쪽이든 `NotchSession` 단위 시험으로 순서·바꾸기 뒤 고르기·로그 판단 칸을 확인한다.

## R14. 설정 창 화면 (요구 다지기 R2-2·R2-4, 3:0)

- **Decision**: 기본 탭 아래 키 칸(없으면 붙여 넣기 칸 + 저장, 있으면 "저장돼 있어요"·지우기·다시 물어보기, 할 일 0개 안내, 401 문구). 할 일 탭 줄마다 priority 칸(점수 없으면 빈칸). HTML 시안을 사람이 확정한 뒤 만든다. 저장할 때 시험 호출 없음, 새 탭 없음.
- **Rationale**: 실제 Jev 점수 순서는 앱 화면에서만 볼 수 있다(헌법 VIII 실제 호출은 사람). 설정 창 탭 셋은 사용자 확정 구조다(spec 002 시안 v2).
- **Alternatives**: 화면 표시 없이 시험만(1라운드 B), 고치기 시트 안 요소 점수, 새 탭 "판단 모델".

## R15. 서명 (요구 다지기 R2-7, 3:0)

- **Decision**: ADR-0005대로 개인 팀 서명. 사용자가 2026-11-06 `App/Config/Signing.local.xcconfig`(커밋 안 함)를 만들고 Apple Development 인증서와 WWDR G3 중간 인증서를 설치했다. 확인용 빌드에서 `codesign -dv`의 `TeamIdentifier`를 본다.
- **Rationale**: ad-hoc 빌드는 다시 빌드할 때마다 서명이 바뀌어 Keychain 확인 창이 반복될 수 있다(ADR-0005 대안 C).

## R16. 화면 문구와 엣지 (메인 세션 가정, 사용자 확인 2026-11-06)

- 같은 priority는 마감 이른 순 → 만든 순. 도는 중·초안은 점수가 바뀌어도 그대로. 판단 입력의 일정 목록에는 지난 일정도 넣는다(PRD). 질의 중 고침·지움이면 받은 답을 버린다(같은 state_hash일 때만 받음).
