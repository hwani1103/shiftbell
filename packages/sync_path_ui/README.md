# Sync Path UI

2026-10-15 현행은 `docs/next_version_27이후/game_implementation_v11/00_구현검증_읽기순서.txt`를 따른다. 아래 이전 버전 설명은 당시 구조 이력이다. v11은 수동 공 선택, 문자 없는 공/포탈, 겹침을 구분하는 경유지 깃발, 열쇠·문과 눈금 시계, 마지막 LV 목록 복귀, 기본 순차 해금과 임시 테스트 토글을 사용한다.

`LevelHearts`는 레벨별3개를 보존한다. 모두 소진한 뒤3개까지 충전하며 foreground60초/background3600초를 정수 크레딧으로 합산한다. `GameSessionController`는 시계를 주입받아 저장·복원·생명주기를 검사할 수 있다. UI 타이머는 foreground에서만 동작하고, 재생 ticker 및 동작 줄이기와 독립적으로 실제 시간을 계산한다. 테스트 토글은 전체 해금과 무한 하트를 함께 켜되 저장하지 않는다. 기존 저장 키와 pack identity는 유지한다.

独立 Flutter パッケージ / 한국어·영어 GameStrings / 기존 ShiftBell import 없음.

`GameSessionController`가 경로 초안/Undo/단계/진행도와 저장 순서를 관리하고 core에 판정을 위임한다. 모든 명령이 완성되면 실행할 수 있으며 실패 계획도 실행을 막지 않는다. 실패 후 경로를 유지한다. 저장은 직렬화·최신 snapshot 병합으로 오래된 쓰기가 최신 데이터를 덮지 않게 한다. 손상/옛 identity의 초안은 게임 내부에서만 격리하고 프로세스 복원 후 자동 재생하지 않는다.

`ReplayCursor`는 trace의 정지 시각에서 clamp하고 Goal 도착 이벤트에 따라 Unit을 제거한다. 같은 선형 커서로 모든 Unit을 표시한다. UI의 실제 재생 길이 기본값은 Step당 650ms이며 core는 무차원 Step/정확 유리수 시각만 사용한다.

## 그래픽 교체 경계

- `MovementPresentation` → 불변 `PresentationFrame`/`UnitVisualFrame`: 논리 중심의 화면 좌표, 방향, 이동 상태/진행률/거리, 별도 시각 시계, 동작 줄이기 상태.
- `UnitVisual` → 현재 `BasicUnitVisual`: 원/사각형/삼각형의 임시 표현. `paint`를 정적 이미지·방향별 이미지·스프라이트로 교체할 수 있다.
- `UnitVisual.paintCue` → Goal/충돌/전체 성공의 정확한 이벤트에 대한 장식 표현. 완료 Unit은 active frames에 없으며 장식 cue로만 남을 수 있다.
- `TileVisual` → 현재 `BasicTileVisual`: 벽/열린 칸/Goal/유효 종점 역할만 받는다. 타일 이미지 교체에 LevelSpec/rows/Solver 변경이 필요 없다.
- `GameSkin` → 배경/표면/텍스트/선택/Unit/충돌/버튼 역할, 공통 타이포·간격·크기·모션 규칙.

`SyncPathGameApp(visuals: BoardVisuals(unit: customUnit, tile: customTile))`로 표현을 주입한다. 앱은 주입된 렌더러를 소유하고 교체/종료 때 `dispose`를 호출한다. 이미지 캐시는 향후 해당 렌더러 안에서 재사용하고 dispose로 정리한다. 렌더러 인스턴스를 여러 앱 인스턴스의 공유 소유 리소스로 사용하지 않는다.

캐릭터의 몸체가 점프·회전·자세 변화해도 논리 중심은 그대로다. Board는 그 중심에 작은 점을 별도로 그린다. 스프라이트 크기/피벗/실루엣/애니메이션 프레임/관통한 픽셀은 판정에 들어가지 않는다. 이동 시작/끝의 가속·감속 느낌은 몸체/보폭/포즈에만 적용하고 중심 좌표를 ease하거나 도착 시각을 늦추지 않는다.

이동 거리는 `distanceCells`, 한 명령의 진행률은 `moveProgress`로 제공한다. 거리와 650ms 재생 길이에서 보폭/Walk/Run/프레임 속도를 선택할 수 있지만 논리 시간은 변경하지 않는다. `_visualTime`은 UI 장식 시계이며 ReplayCursor와 별개다. 현재 정적 표현에는 대기 ticker가 필요 없어 재생 중에만 ticker가 돌고 pause/background/허브/종료 때 정지한다. 향후 Idle/Goal 효과 ticker를 추가할 때에도 화면 가시성·동작 줄이기·소유권을 같은 경계에서 지켜야 한다.

cue는 매 프레임의 읽기 전용 timeline snapshot이다. 향후 사운드는 paint에서 호출하지 않고 별도 UI controller에서 **실제 전진 재생 중 시각을 통과한 이벤트**만 한 번 전달해야 한다. 새 replay 인스턴스/trace revision으로 중복을 관리하고 seek/back/background에서는 소리를 내지 않는다. 포즈/음향 이벤트가 엔진 도착·실패를 확정하는 구조는 금지한다.

현재 추가하지 않은 것: 캐릭터 아트, 고급 애니메이션, Flame, audio plugin, 파티클/리소스 매니저/플러그인 시스템. 확장 경계만 확보했다. 저사양 실기기 성능·캐릭터 실루엣의 실제 스침 가독성은 아직 미검증이다.

`routes`는 경로 revision마다 불변 snapshot을 만들고 재생 프레임 간 재사용한다. Sprite decoder/asset 로드는 painter 안에서 하지 말고 렌더러 준비 단계에서 수행한다.

## 검증 및 폰트

패키지 디렉터리에서 `flutter pub get`, `flutter analyze`, `flutter test`를 실행한다. 의존성은 Flutter와 core만 있으며 테스트에는 flutter_test를 사용한다. 오프라인 한글 표시용 Noto Sans KR를 패키지 font asset으로 등록했다. [공식 원본](https://github.com/google/fonts/tree/main/ofl/notosanskr)과 `assets/fonts/OFL-NotoSansKR.txt` 라이선스를 보존했다. 전체 폰트 10.4MB는 재생성용 원본으로 보존하며 앱에 포함하지 않는다. 현행50레벨 콘텐츠291개 코드포인트의84,472byte GameSansSubset.ttf만 등록한다. 원본의 가변 굵기100–900과 라이선스를 유지한다.

## 2026-10-13 현행 추가: 칸당 동일 속도와 프로토타입 에셋

독립 lab은 `constant-cell-speed-v2`를 사용한다. 앞의 동일 명령 시간 설명은 옛 shared-goal-v1 회귀 범위다.
지금의 기본 재생은 칸당 650ms이며 길이 d인 명령은 d×650ms다. 모든 Unit의 칸당 속도는 같다.
`UnitVisualFrame`의 distanceCells / durationUnits / moveProgress는 정확한 논리 motion에서 나온다.
`UnitAnimationController`는 이동 거리 기반 보폭, Idle/Start/Walk/Run/Stop/Collision 포즈만 만든다.
현재 속도 1에서는 Walk이며 Run 연결은 향후 전체 재생 표현 정책에 사용할 수 있다.

`loadPrototypeVisuals()`가 생성 atlas 2장을 한 번 decode한다. `PrototypeUnitVisual`은 3색/4방향 몸체,
절차형 다리/팔, 선택 1.13배/링/화살표, 대기 호흡, 이동 보폭, 출발/정지 기울기와 Goal 점프/충돌 반응을 그린다.
`PrototypeTileVisual`은 floor/wall/goal source rect와 종점 강조만 받는다.
이미지/포즈를 바꿔도 레벨 데이터나 Solver는 바꾸지 않는다. 기존 Basic renderers도 대체 구현으로 유지한다.

단일 ticker는 계획 화면에서 장식 시계만, 실행 중에는 논리 재생 시계와 장식 시계를 각각 진행한다.
리뷰 반응은 1.2초 후 멈춘다. pause/background/hub/종료 및 동작 줄이기에서는 정지한다.
Goal 장식은 이미 흡수된 논리 Unit을 다시 active collider로 만들지 않는다.
shared atlas와 라벨/route/destination/validation snapshot을 재사용하고 앱 종료/교체 때 이미지/codec/ticker를 정리한다.
현재 코드의 그림자/점프/기울기/파티클은 임시 프로토타입이며 사운드/Flame/리소스 플러그인은 추가하지 않았다.

새 규칙 화면/실패/동작 줄이기/복귀/이미지 소유권 검사는 prototype_test.dart에 있다.
320/412 화면 렌더와 기존 320/360/412/736 회귀를 확인했다. 저사양 실기기 FPS와 재미 평가는 후속 실제 플레이 항목이다.

2026-10-13 캠페인30 후속: 호스트의 playbackRate=1.5, 기본 시간 단위650ms /1.5 ≈433.3ms다.
모든 Unit에 공통 배율을 적용하며 trace/도착/충돌은 바뀌지 않는다. Goal cue age도 실제 재생 배율로 환산한다.
기본 패키지 배율1은 기존 호스트/검사의 호환 기본값이고, 독립 lab의 실제 기본값은1.5다.
D/E는 기존 atlas의 색상을 역할 기반 green/gold로 바꿔 구분한다. 새 bitmap 추가 없음.
PuzzleCopy에 선택적 chapter 문구를 넣어30개 목록을5개씩 나눴다. 전체 잠금 해제 실험에서도 시작 버튼은 첫 미완료 레벨로 간다.
새 레벨/속도/30번 접근/4·5유닛 화면 검사는 campaign_test.dart에 있으며 현행 증거는 game_implementation_v4다.

## 2026-10-14 현행: 이미지 없는 공·블록 타일

독립 lab은 `RollingBallVisual`과 `BlockTileVisual`을 사용한다. 원본 로봇/타일 atlas는 보존하지만 pubspec에 등록하지 않으며 런타임 asset 로더도 제거했다. 기존 PrototypeUnitVisual/PrototypeTileVisual은 향후 호스트가 이미지를 주입하는 대체 렌더러로 남긴다.

공의 표면 무늬5개(점/띠/십자/마름모/별)를 3차원 회전 후 2차원으로 투영한다. 거리/시각에서 orientation을 직접 재구성하므로 프레임 누적 오차, seek 순서, 일시정지, 방향 전환에 의존하지 않는다. BallRotation은 UI에만 있고 엔진·레벨·Solver는 변경하지 않았다. 몸체는 이동 중 뜨지 않으며 선택 확대/링, Goal 점프, 충돌 반응은 시각적 효과다. 동작 줄이기는 회전/Idle/반응 ticker를 멈춘다.

블록 타일은 얕은 입체 모서리·명암·테두리로 바닥/벽을 구분하고 도착점은 이중 사각 표식을 사용한다. 5레벨마다 역할 기반 포인트 색을 바꾸며 모양/판정은 유지한다. 공 shader/표면 motif/타일 shader/글자 layout을 재사용하고 renderer.dispose에서 소유 캐시를 정리한다. 저사양 실기기 FPS 검증은 아직 하지 않았다.

폰트 개발 도구 설치(런타임 의존성 아님):
```powershell
python -m pip install --no-deps --target .dart_tool/font_subset_tools -r tools/font-requirements.txt
python -X utf8 tools/subset_font.py
python -X utf8 tools/subset_font.py --check
```
게임 문구/레벨을 바꾸면 subset을 재생성한다. check는 원본 hash, 새 콘텐츠 글자 누락, 가변 굵기, 게임 전용 에셋500KB 예산을 검사한다. 전체 원본 폰트와 보존 atlas는 앱 패키지에 넣지 않는다. 현행 게임 데이터134,938bytes는 폰트+30레벨+문구이며 컴파일된 게임 코드나 Flutter/Material 공통 리소스는 포함하지 않는다.

현행 검사/화면/빌드 증거: `docs/next_version_27이후/game_implementation_v5/`.

## 2026-10-14 캠페인50 현행

선택 공을 약1.22배로 확대하고 같은 색의 링/상단 표식/안내 패널/종점 채움으로 연결했다. UnitVisual.legendIcon은 교체할 캐릭터의 범례를 함께 제공하며 공은 점/띠/십자/마름모 표식을 사용한다. 비선택 공은 계획 중65%로 표시하며 실행 중에는 원래 색으로 돌아온다. 자동 다음 공 선택 때 안내가160ms로 전환하며 동작 줄이기는 즉시 전환한다.

TileVisualFrame은 chapter와선택색을 받는다. 현재 블록 표현은5가지 얕은 표면 디테일과 역할 기반 포인트 색만 바꾼다. 맵의 벽/Goal/충돌 규칙은 바뀌지 않는다. 필요한 최소 페이지 수평 여백을6–20px 공통 토큰으로 계산하여320px에서7×7 마지막 열도 보이도록 했다.

현행리소스170,792bytes는 축소폰트84,472 +50레벨39,753 +문구46,567이다. 전체 APK나 컴파일된게임코드의 용량을 뜻하지 않는다. release/기존ShiftBell 통합 용량은 측정하지 않았다.

campaign50_test.dart는50개 해답,유닛 도입/보드계약,선택안내/합법종점색,50개320px 보드의 마지막열 및 버튼 접근을 확인한다. 기존30/12레벨은 동결JSON으로 역사적 회귀를 유지한다. v6 검사/화면/빌드 원장이 현행이다.
