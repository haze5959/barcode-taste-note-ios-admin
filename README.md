# BarNote Admin (iOS)

BarNote 서비스의 **관리자 전용 iOS 앱**입니다.
어드민 웹([barcode-taste-note-admin](../barcode-taste-note-admin))의 기능을 아이폰 세로 화면에 맞게 재구성했습니다.

- 아이폰 세로모드 전용 (아이패드/맥/가로모드 미지원)
- 스토어 배포 없음 — 개인 기기 설치 전용
- 서버: `https://api.barnote.net` (프로덕션 API 직접 호출)

## 기능

| 탭 | 기능 |
|---|---|
| 대시보드 | 유저/구독/노트/제품/신고 지표, 30일 활성 사용자, API 요청 현황 |
| 제품 | 검색·무한 스크롤 목록, 정보 편집, 자동 기입, 이미지 관리(사진/URL), 바코드 관리, 병합, 삭제 |
| 노트 | 신규 노트 목록 + 상세 (읽기 전용) |
| 신고 | 신고 목록, 신고 유저/제품 상세, 관리자 답변 등록 |
| 관리 | 미참조 이미지(그리드/뷰어/Delete All), 실패 바코드(목록/삭제/바코드 렌더링), 로그아웃 |

실패 바코드의 바코드 렌더링은 EAN-13 / UPC-A / EAN-8을 직접 인코딩하고,
그 외 형식은 CoreImage의 Code128 제너레이터로 폴백합니다 (어드민 웹의 jsbarcode 정책과 동일).

## 빌드 & 실행

```bash
open BarNoteAdmin.xcodeproj
```

- Xcode 26 이상 (iOS 26 SDK)
- 의존성: [Auth0.swift 2.16.1](https://github.com/auth0/Auth0.swift) (SPM, 첫 빌드 시 자동 resolve)
- 프로젝트는 폴더 동기화 방식(objectVersion 77)이라 `BarNoteAdmin/` 아래에 파일을 추가하면 Xcode에 자동 반영됩니다

## 인증 (Auth0)

본가 앱(iOSBarcodeTasteNote)과 동일한 Auth0 테넌트/클라이언트를 사용합니다.

- 설정: `BarNoteAdmin/Auth0.plist` (Domain / ClientId)
- 로그인: Google 커넥션 고정 (`google-oauth2`), audience `https://barnote.net/`
- **콜백 URL**: 본가 앱(`com.oq.barnote`)의 콜백 URL을 `redirectURL`로 재사용합니다.
  ASWebAuthenticationSession이 세션 안에서 콜백을 가로채므로 본가 앱과 충돌하지 않고,
  Auth0 대시보드에 어드민 앱용 콜백을 추가할 필요도 없습니다.
- 토큰: `CredentialsManager`(키체인)가 보관하며 만료 임박 시 자동 갱신, API 401 응답 시 로그인 화면으로 전환
