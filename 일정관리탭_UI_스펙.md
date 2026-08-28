# 일정관리 탭 UI 스펙 (2026-08-28 기준)

> `lib/screens/schedule_management_tab.dart` 단일 파일 구현. 2026-08-25 신규 도입 후
> 여러 세션에 걸쳐 반복 수정됨 - 이 문서는 **2026-08-28 세션 종료 시점의 최종 상태**를
> 정리한 것. 값(수치)을 인용하기 전에 실제 코드를 한 번 확인할 것 - 사용자가 핫리로드로
> 직접 미세조정하는 경우가 많아 문서보다 코드가 최신일 수 있음.

---

## 구성

```
헤더(날짜+근무명 칩, ◀▶ 월 이동)
날짜 스트립(그 달 1일~말일 칩 가로 스크롤 + 설정 톱니 칩)
────────────────────────────────
세로 시간축(00:00~24:00, 30분 슬롯) - _TimeAxisPicker
  └ 우측 하단 고정 버튼(_ScheduleFab) - 일정 생성 진입점
```

## 배경색 연동 색상 스킴 (`_ScheduleColorScheme`)

사용자가 고르는 배경색(`kScheduleBackgroundColors`, 10종 프리셋) 하나로부터
`Color.computeLuminance()` 기준 밝기 판정 후 헤더/칩/시간 텍스트/내용 텍스트 색을
전부 파생시킴(`_ScheduleColorScheme.of(bg)`) - 프리셋마다 색을 하드코딩하지 않음.

**예외**: 근무명 칩(`_ShiftPill`)과 그 안의 색깔 점은 이 스킴과 완전히 무관하게
항상 고정색 - 배경이 바뀌어도 안 바뀜(명시적 요구사항).

날짜 칩/설정 톱니 칩은 `_scheduleChipDecoration(scheme)`(배경색 그대로 + 테두리 +
은은한 엠보스 그림자)을 공유해서 두 칩이 시각적으로 완전히 동일함. 일정생성 flow의
시간 선택 배지 2개(아래 참고)도 같은 데코레이션을 재사용함.

## 기기별 스케일 보정 컨벤션

이 화면의 좌표계(축/슬롯/여백 등)는 전부 `(N * 7 / 8)` 형태로 raw 값을 감싼 뒤
`.h`/`.w`/`.r`(flutter_screenutil)을 붙임 - 기준 기기(SM S948N, 8/7 스케일 비율)에서
과거 픽셀 튜닝값과 동일하게 나오면서 다른 기기에서는 자동 재계산되게 하는 방식.
**`.sp`(폰트)에는 이 보정을 적용하지 않음** - `.sp`는 이미 자체적으로 스케일됨.
`_TimeAxisPickerState` 상단 주석에 상세 설명 있음. 새 상수를 추가할 때 이 컨벤션을
반드시 따를 것 - 예전에 "더하는 값 중 하나만 스케일하고 하나는 raw로 둬서 어긋남"
버그가 있었음.

---

## 일정 생성 flow (2026-08-28 전면 재작업)

### 이전 방식(폐기됨)

- 축 위에 항상 떠 있는 "인디케이터"(앱 아이콘 + 왼쪽 화살표 부리)를 손가락으로
  직접 드래그해서 시간을 고르는 방식. `_AxisIndicator`/`_LeftBeakPainter` -
  **완전히 삭제됨, 코드에 안 남아 있음.**

### 현재 방식

**1) 우측 하단 고정 버튼 (`_ScheduleFab`)**

- 위치 항상 고정(뷰포트 우측, 수직 62.5% 지점 - `_idleIndicatorVerticalRatio`).
- 상태 2가지:
  - **비활성**: 앱 아이콘을 흑백(표준 luminance 매트릭스) + 옅은 opacity(0.75) +
    어두운 테두리로 표시.
  - **활성**: 원색 그대로 + 둘레에 펄스 링 2개(위상이 반 박자씩 어긋남, 두께/알파
    상향 조정됨 - "활성 상태가 잘 안 느껴진다"는 피드백으로 강화됨)가 계속
    커지며 옅어짐(레이더 핑 스타일).
- 탭 동작:
  - 비활성 상태에서 탭 → 활성화(`_activatePicker`). 현재 화면 정중앙에 가장
    가까운 슬롯을 `_selectedSlot`으로 즉시 선택하고 시간 선택 배지 2개가 나타남.
  - 활성 상태에서 탭 → `_selectedSlot`을 시작 시각으로 일정 생성 시트
    (`_CreateBlockSheet`)를 염. 시트가 닫히면(생성/취소 무관) 항상 비활성으로
    복귀(`_deactivatePicker`) - 다음엔 다시 버튼을 눌러 새로 시작.

**2) 시간 선택 배지 2개**

- 왼쪽: 축 위의 시각을 감싸는 사각형 - 정각(짝수 슬롯)이면 그 시간 숫자를
  감싸고, 30분(홀수 슬롯)이면 숫자 없이 그 사이 위치에만 존재.
- 오른쪽: "08:00 AM" 형식의 시각 텍스트가 적힌 사각형.
- 둘 다 `_scheduleChipDecoration(scheme)`(현재 배경색) + `scheme.timeText`
  색상(축 숫자와 동일 색) - 날짜칩/톱니칩과 같은 디자인 언어.
- `AnimatedPositioned`(160ms, easeOut)로 배치 - `_selectedSlot`이 정수 단위로
  바뀔 때마다 "따라 따락" 계단식으로 보간됨(연속적인 매끄러운 이동이 아님 -
  의도된 것, 30분 단위 스냅 느낌을 주기 위함).

**3) 인디케이터 이동 방식 - 스크롤 추적 하나만 존재**

> ⚠️ 2026-08-28 초판에는 "축 직접 탭으로 시간 선택"(방식 2)도 있었으나, 그 후
> 삭제 요청으로 제거됨. 현재는 **스크롤 추적(방식 1) 단독**.

- 화면(축)을 스크롤하면, 화면 정중앙에 가장 가까운 슬롯이 자동으로
  `_selectedSlot`이 됨(활성 상태일 때만).
- **끝단 오버슛 + calibration** (핵심 메커니즘, `_virtualOffset` 필드):
  - 이 화면은 축 스크롤을 `SingleChildScrollView`의 기본 드래그에 맡기지 않고
    (`physics: NeverScrollableScrollPhysics`), 대신 이 위젯을 감싸는
    `GestureDetector.onVerticalDragUpdate`(`_onAxisDragUpdate`)가 직접 받음.
  - `_virtualOffset`(클램프 안 됨, double)을 드래그 델타로 계속 누적함.
  - 화면에 실제 적용하는 스크롤 오프셋은 `_virtualOffset.clamp(0, maxScrollExtent)`
    - `_controller.jumpTo(...)`로 적용.
  - 화면이 물리적 끝(예: 축소된 `_edgePadding` 때문에 00:00까지 정중앙 스크롤이
    안 되고 04:00 근처에서 막히는 경우)에 닿아도 `_virtualOffset` 자체는 계속
    움직이므로, 인디케이터(=중심 슬롯 계산 기준인 `_centerContentY()`)는 진짜
    경계(00:00 / 23:30)까지 계속 갈 수 있음 - "화면은 멈춰도 인디케이터는 계속
    움직인다".
  - 반대 방향으로 되돌리면, `_virtualOffset`이 다시 `[0, maxScrollExtent]` 범위
    안으로 들어올 때까지는 클램프된 값(=화면에 보이는 스크롤)이 안 움직임 -
    "먼저 calibration한 뒤에야 화면이 다시 내려간다"는 요구사항이 `clamp()`
    표현식 하나로 자연스럽게 구현됨(별도 "데드존 모드" 상태 불필요).
  - 드래그 제스처가 끝나도 `_virtualOffset`은 리셋하지 않음 - 다음 드래그가
    이어서 정확히 같은 지점부터 시작해야 하므로(안 그러면 손을 뗐다 다시 잡을
    때 인디케이터가 화면에 보이는 위치에서 갑자기 튐).

---

## 좌우 스와이프 내비게이션 (2026-08-28 정리)

| 탭 | 이전 | 현재 |
|---|---|---|
| 다음알람탭 | 좌→우 스와이프 시 달력탭 이동 | **제거** |
| 설정탭 | 우→좌 스와이프 시 달력탭 이동 | **제거** |
| 일정관리탭 | 우→좌 스와이프 시 달력탭 이동(우측만 반응, 좌측 무반응) | **이전날/다음날 이동**으로 교체 (velocity<0 → 다음날, velocity>0 → 이전날, 달 이동과 동일한 부호 규칙) |
| 달력탭 | 월 이동(변경 없음) | 변경 없음 |

`SettingsTab.onSwipeToCalendar` 필드는 스와이프용이 아니라 `CalendarThemePickerScreen(onApplied: ...)`
콜백(테마 적용 후 달력탭으로 돌아가기)으로 여전히 쓰이므로 필드 자체는 남아있음 -
`NextAlarmTab`은 그 용도가 없어서 필드까지 완전히 삭제됨.

---

## 알려진 이슈 (의도적으로 미수정)

**디버그 빌드 전용 크래시** - 달력 탭 메모 팝업에서 텍스트필드 포커스 상태로
뒤로가기를 누르면 `_dependents.isEmpty` assertion 실패(`framework.dart:6268`).

- 원인(추정): `calendar_tab.dart`의 메모 바텀시트가 쓰는 `WillPopScope.onWillPop`이
  `FocusScope.of(context).unfocus()` 후 `await Future.delayed(150ms)`를 거쳐야
  pop을 진행하는데, 그 딜레이 동안 바텀시트의 닫힘 애니메이션이 겹치면서 TextField의
  Focus가 의존하던 InheritedElement가 dependents를 다 정리하기 전에 Overlay에서
  제거되는 경합이 생기는 것으로 보임.
- release 빌드에서는 이 assert 자체가 스트립되어 크래시로 나타나지 않음(확인됨).
- 일정관리탭의 생성/수정 시트(`_CreateBlockSheet`)는 `WillPopScope`나 "언포커스 후
  딜레이" 패턴이 아예 없어서 이 경합이 발생하지 않음 - 그래서 거기선 재현 안 됨.
- **의도적으로 미수정** - release 영향 없고, 고치려면 `WillPopScope`(레거시) →
  `PopScope` 전환 + unfocus 로직을 pop 이후로 옮기는 리팩터가 필요해서 보류.

---

## 관련 상수/메서드 빠른 참조 (`_TimeAxisPickerState`)

| 이름 | 역할 |
|---|---|
| `_axisLeftMargin` | 세로축 전체를 좌우로 이동 |
| `_idleIndicatorVerticalRatio` / `_fabRightMargin` | FAB 고정 위치 |
| `_pickerBadgeHeight` / `_pickerHourBadgeWidth` / `_pickerBadgeGap` | 시간 선택 배지 2개 크기/간격 |
| `_virtualOffset` | 클램프 안 된 가상 스크롤 오프셋(끝단 오버슛/calibration 핵심) |
| `_centerContentY()` | `_virtualOffset` 기준 "지금 화면 정중앙" 콘텐츠 좌표 |
| `_nearestSlotToContentY(y)` | 콘텐츠 좌표 → 가장 가까운 30분 슬롯 |
| `_activatePicker` / `_deactivatePicker` / `_onFabTap` | FAB 상태 전이 |
| `_onAxisDragUpdate` | 축 드래그 처리(스크롤 + 슬롯 추적 동시 수행) |
