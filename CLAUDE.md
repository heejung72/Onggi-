# 옹기종기(Onggi) — Claude Code 작업 규칙

친구들의 상태(공부·일·잠·산책·쉬기)를 귀여운 캐릭터로 맥 바탕화면에 보여주는 앱의 **0단계 프로토타입**.
사용자는 개발 경험이 없는 기획자다. 설명은 한국어로, 쉬운 말로, 짧게 한다.

## 기술 스택
- SwiftUI + AppKit, macOS 14 이상, Swift 5 언어 모드
- 프로젝트 파일은 XcodeGen(`project.yml`)으로 생성한다. `.xcodeproj` 를 직접 고치지 말고 `project.yml` 을 고친 뒤 `xcodegen generate`
- 백엔드: Supabase (supabase-swift 2.x, Swift Package Manager)
- 메뉴바 전용 앱 (`LSUIElement = YES`, 독 아이콘 없음)

## 폴더 구조
- `Onggi/App` — 앱 시작점, AppDelegate (설정 창·오버레이 생성)
- `Onggi/Services` — `SupabaseService`(서버 통신 전부), `AppState`(앱 상태 전부)
- `Onggi/Overlay` — 바탕화면 투명 창(`OverlayController`), 움직임 계산(`Simulation`), 그리기(`OverlayView`)
- `Onggi/Character` — 캐릭터를 도형으로 그리는 `CharacterView`, 공유 소품(이불·책상)
- `Onggi/UI` — 메뉴바 창, 캐릭터·그룹 설정 창
- `supabase/schema.sql` — DB 설계 (이미 Supabase 에 적용되어 있다고 가정)

## 지켜야 할 원칙
1. **화면 코드는 Supabase 를 직접 부르지 않는다.** 서버 통신은 `SupabaseService` 에만 둔다.
2. **실시간 이벤트는 "바뀌었다는 신호"로만 쓰고, 실제 데이터는 다시 조회한다.** (최대 10명이라 충분히 빠르고 단순함)
3. 오버레이 창은 평소 클릭을 통과시키고, 마우스가 캐릭터·카드 위일 때만 클릭을 받는다 (`Simulation.isInteractive`). 새 클릭 가능한 UI를 오버레이에 추가하면 여기에도 영역을 추가할 것.
4. 캐릭터는 이미지 파일 없이 도형으로 그린다. 기존 캐릭터(치이카와, 리락쿠마, 가나디 등 타사 IP)를 흉내 내거나 그 이름·외형을 쓰지 않는다. 오리지널 캐릭터만.
5. 그룹 최대 인원 10명 (`Config.maxMembers`, DB 함수 `join_group` 과 일치시킬 것).
6. 개발자 계정 없이 배포하므로 서명은 `CODE_SIGN_IDENTITY = "-"`, 샌드박스 OFF, 세션은 UserDefaults 저장. **앱스토어 단계 전까지 바꾸지 않는다.**
7. 비밀 키 금지: `Config.swift` 에는 Supabase 의 anon(public) 키만. service_role 키는 절대 코드에 넣지 않는다.

## 빌드·확인 방법
```bash
brew install xcodegen          # 처음 한 번
xcodegen generate
xcodebuild -project Onggi.xcodeproj -scheme Onggi -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Onggi.app
```
- 빌드 에러가 나면 에러 메시지를 읽고 고친 뒤 다시 빌드한다. 성공할 때까지 반복한다.
- supabase-swift 는 버전마다 API 이름이 조금 다를 수 있다 (예: `subscribe()` ↔ `subscribeWithError()`, `in(_:values:)`, 필터 문법). 에러가 나면 설치된 패키지 소스(`build/SourcePackages/checkouts/supabase-swift`)에서 실제 이름을 찾아 맞춘다.
- 경고(warning)는 빌드를 막지 않으면 일단 두고, 에러만 먼저 없앤다.

## 배포 (친구에게 나눠주기)
`./scripts/package.sh` → `dist/Onggi.zip` 생성. 친구용 설치 안내는 `docs/친구용_설치안내.md`.

## 작업 방식
- 한 번에 한 기능만 바꾸고, 빌드가 성공하면 `git commit` 한다 (메시지는 한국어로 무엇을 바꿨는지).
- 큰 구조 변경 전에는 계획을 먼저 짧게 설명하고 확인받는다.
- 끝나면 "무엇을 바꿨고, 사용자가 무엇을 눌러 확인하면 되는지"를 3줄 이내로 알려준다.

## 참고 문서 (docs/)
작업 전에 관련 문서를 먼저 확인한다.
- `docs/01_기획서_요약.md` — 서비스 컨셉, 타깃, 기능, 로드맵, 리스크
- `docs/02_결정사항.md` — 지금까지 정한 것과 이유. **새로 정한 것은 이 표에 한 줄 추가**한다.
- `docs/03_디자인_가이드.md` — 분위기, 캐릭터 원칙, 상태별 장면, 색 사용
- `docs/04_기술_메모.md` — 플랫폼 제약, Supabase 설계, 서명·배포
- `docs/references/mockup_v0.png` — 첫 디자인 시안 (구성 참고용, 색감은 개선 대상)
