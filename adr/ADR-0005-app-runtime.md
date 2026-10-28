# ADR-0005: 앱 실행 형태(샌드박스, 서명, 메뉴 막대)

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-28 / 2026-10-28
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: PRD 1장(macOS 14+, 메뉴바 상주), PRD v2 범위(App Store), 헌법 비밀값 조항(키는 Keychain에만)
- 사용한 외부 근거: DynamicNotchKit README(macOS 13+) (정정: DynamicNotchKit은 ADR-0008로 제외)

## 맥락

v1은 사용자 한 명이 Xcode로 빌드해 쓰는 앱이고 App Store 배포는 v2다. 에이전트 권한 규칙은 앱 데이터 경로 `~/Library/Application Support/dev.dongwon.moka/`를 막는다. App Sandbox를 켜면 데이터가 `~/Library/Containers/dev.dongwon.moka/…`로 옮겨진다.

## 평가 기준

1. 데이터 경로와 에이전트 차단 규칙이 하나로 맞는가 2. 미확인 위험이 늘지 않는가 3. 매일 다시 빌드할 때 마찰 4. v2 전환 비용

## 대안

| 대안 | 장점 | 단점·위험 | 근거·실험 |
|---|---|---|---|
| A. Sandbox 끔, 개인 팀 서명, Hardened Runtime 끔, `LSUIElement` | 경로가 하나, 미확인 적음 | v2에서 DB 이전 필요 | — |
| B. Sandbox 켬(`network.client`만) | v2 대비 | DB가 Containers로 가서 지금 차단 규칙을 비껴감, DynamicNotchKit 샌드박스 호환 미확인 (정정: DynamicNotchKit은 ADR-0008로 제외) | — |
| C. ad-hoc 서명 | Apple ID 불필요 | 빌드마다 서명이 바뀌어 Keychain 확인 창 반복 가능(미확인) | — |

## Agent의 추천과 근거

A를 추천한다(추천안 토론 3:0).
- App Sandbox 끔. v2에서 켤 때 DB 경로 이전과 에이전트 차단 경로 갱신을 함께 한다(미래 결정).
- 로컬은 개인 팀(Apple Development) 자동 서명. `DEVELOPMENT_TEAM`은 커밋하지 않는 `Config/Signing.local.xcconfig`에 둔다(`.gitignore`가 `*.local.xcconfig`를 제외). CI는 `CODE_SIGNING_ALLOWED=NO`.
- Hardened Runtime 끔(공증하지 않음).
- `LSUIElement = YES`(메뉴 막대 전용). 메뉴 막대 항목은 설정과 종료만.
- API 키는 Keychain에만 둔다.

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택. 판단 이유: 사용자 위임(토론 채택안 "전부 승인", 2026-10-28)

## 포기하는 것·운영 영향

- 트레이드오프: v2 App Store 전환 때 데이터 이전이 필요하다.
- 운영 영향: 사람이 Xcode에 Apple ID로 로그인해 개인 팀을 만들어야 한다.
- 되돌리기: Sandbox는 v1 동안 끈 채로 유지. 켜는 일은 데이터 이전을 동반한다.

## 결정 검증

- 실행할 실험: 첫 앱 빌드에서 DB 파일이 위 경로에 생기는지, Keychain 확인 창이 반복되지 않는지 사람이 확인.
- 성공 판정: 경로 일치, 두 번째 빌드부터 확인 창 없음.
- 재검토 트리거: `LSUIElement` 앱에서 노치 입력 포커스가 잡히지 않음, DynamicNotchKit이 특정 권한을 요구함, v2 착수. (정정: DynamicNotchKit은 ADR-0008로 제외)
