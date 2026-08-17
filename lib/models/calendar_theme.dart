// lib/models/calendar_theme.dart
//
import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../utils/shift_name_util.dart';
//
// ⭐ 달력 테마 선택 시스템의 중심 모델. calendar_theme_lab_screen.dart에서
// 실험하던 9개 후보(1/2/4/5/8/9/10번 + 메인·화이트/메인·다크)를 실제 선택
// 가능한 값으로 등록함. "근무명 색상 변경" 기능이 삭제되고 테마 선택으로
// 완전히 대체되면서, 이 9개가 유일한 색상/디자인 소스가 됨.
//
// ⭐ id는 SharedPreferences에 영구 저장되는 키라 반드시 안정적이어야 함 -
// enum.index(정수, 선언 순서가 바뀌면 저장된 값이 다른 테마를 가리키게 됨)
// 대신 enum.name(문자열, 이름이 안 바뀌는 한 항상 안전)을 저장함.
// ⭐ "달력 테마 캐러셀에서 메인·화이트/메인·다크가 맨 왼쪽에 오고, 나머지는
// 지금 순서 유지해도 된다"는 요청으로 선언 순서를 재배치함(캐러셀은
// kAllCalendarThemeIds=CalendarThemeId.values를 선언 순서 그대로 씀). 저장은
// enum.name(문자열)으로 하므로 이 순서 변경이 기존 저장된 선택값에 영향 없음.
enum CalendarThemeId {
  mainWhite,    // 메인테마 · 화이트
  mainDark,     // 메인테마 · 다크
  minimal,      // (구)1번 · 미니멀 라인
  materialCard, // (구)2번 · 머티리얼 카드형
  boldGrid,     // (구)4번 · 굵은 격자형
  initialBadge, // (구)5번 · 이니셜 뱃지형
  underline,    // (구)8번 · 언더라인 미니멀형
  eventChip,    // (구)9번 · 이벤트 칩형
  editorial,    // (구)10번 · 매거진 에디토리얼형
}

extension CalendarThemeIdX on CalendarThemeId {
  // ⭐ "테마 번호 대신 각 테마에 어울리는 이름을 붙여달라"는 요청으로 실험
  // 단계 번호(1/2/4/5/8/9/10번)를 각 디자인 컨셉을 담은 이름으로 교체함.
  // ⭐ 영어 현지화: 기존 `label` getter(하드코딩 한국어)를 BuildContext를 받는
  // 메서드로 바꿈 - 호출부(settings_tab.dart, calendar_theme_picker_screen.dart)도
  // 함께 갱신함.
  String label(BuildContext context) {
    final l10n = context.l10n;
    switch (this) {
      case CalendarThemeId.mainWhite: return l10n.themeMainWhite;
      case CalendarThemeId.mainDark: return l10n.themeMainDark;
      case CalendarThemeId.minimal: return l10n.themeMinimal;
      case CalendarThemeId.materialCard: return l10n.themeMaterialCard;
      case CalendarThemeId.boldGrid: return l10n.themeBoldGrid;
      case CalendarThemeId.initialBadge: return l10n.themeInitialBadge;
      case CalendarThemeId.underline: return l10n.themeUnderline;
      case CalendarThemeId.eventChip: return l10n.themeEventChip;
      case CalendarThemeId.editorial: return l10n.themeEditorial;
    }
  }

  // ⭐ 이 테마가 선택돼 있으면 앱 전체가 다크로 바뀌는 게 아니라, 시스템
  // 상태표시줄(시계/배터리/알림 아이콘)만 다크에 맞게(밝은 아이콘) 바뀜 -
  // "다크모드"라는 전역 개념 자체가 없어지고 테마 선택 하나로 흡수됨.
  bool get isDark => this == CalendarThemeId.mainDark;

  // ⭐ 근무를 색상으로만 구분해서 범례(색상=근무명 매칭 카드)가 필수인 테마.
  bool get hasLegend => this == CalendarThemeId.underline || this == CalendarThemeId.editorial;
}

const kDefaultCalendarThemeId = CalendarThemeId.mainWhite;

// ⭐ 캐러셀/위젯 등에서 순서대로 순회할 때 쓰는 고정 목록 (선언 순서 그대로).
const kAllCalendarThemeIds = CalendarThemeId.values;

// ⭐ "근무명 색상 변경" 기능 삭제 + 테마 선택으로 완전히 대체하는 작업의 확정
// 팔레트. 원래 calendar_theme_lab_screen.dart 안에 있었는데, 실제 메인
// 달력탭(calendar_tab.dart)도 똑같은 팔레트로 색을 매겨야 해서 공용 위치로
// 옮김 - 두 군데서 각자 유지보수하면 나중에 색이 어긋날 수 있어서.
//
// 규칙(onboarding_screen.dart의 _generateShiftColors()와 동일한 원칙):
// 1) 이름에 "휴"가 들어간 근무는 무조건 고정 빨강(kMainRestColor).
// 2) 나머지는 생성 순서대로 배정, 인접한 순서끼리 색 계열이 안 겹치게 로테이션.
// ⭐ 영어 현지화: 예전엔 이 상수 하나만 있었는데(calendar_theme_lab_screen.dart의
// 테마 미리보기 캐러셀에서 "샘플 근무명"으로만 씀 - 실제 사용자 데이터가 아니라
// 위치별(index) 팔레트 색상과 짝지어 보여주는 목업 텍스트라, 인덱스 4(=휴무)
// 자리만 팔레트의 고정 빨강과 맞으면 되고 진짜 "휴" 감지 로직과는 무관함),
// 로케일에 따라 다른 샘플을 보여주기 위해 함수로 바꿈. 순서/인덱스 의미(4번째 =
// 휴무 자리)는 두 언어 리스트가 동일하게 유지해야 함(kMainLightPalette 등과
// 위치로 짝지어짐).
List<String> mockShiftNames(BuildContext context) {
  final isKorean = Localizations.localeOf(context).languageCode == 'ko';
  if (isKorean) {
    return const ['주간', '야간', '오전', '오후', '휴무', '당직', '연장', '대기', '재택', '출장', '교육', '특근'];
  }
  return const ['Day', 'Night', 'Morning', 'Afternoon', 'Off', 'On-Call', 'Extra', 'Standby', 'Remote', 'Travel', 'Training', 'Special'];
}

const kMainRestColor = Color(0xFFEF5350); // 휴무 고정 - 라이트/다크 공통

// ⭐ 2026-08-17 전면 재설계 - "소프트 카드(materialCard) 1번째 근무명과 컬러
// 뱃지(initialBadge) 3번째 근무명이 노랑~초록 사이 애매한 연두색이라 서로
// 구분이 안 된다", "소프트 카드 3번째 근무명(청록)이 너무 밝고 쨍하다"는
// 지적으로, 이전처럼 개별 색상 하나씩 땜질하는 대신 팔레트 11칸(휴무 제외)
// 전체를 다시 짬. 규칙:
// 1) 색상환에서 40°~300° 구간(빨강·주황·코랄·핑크가 몰린 -30°~40° 구간을
//    회피)에서만 고름 - 로테이션이 뭐든(0/3/6/9) "앞쪽 4~5칸"이 항상 이 구간
//    안이라 휴무 빨강과 절대 안 겹침.
// 2) 인접 색상끼리 색상환에서 약 25~30° 이상 떨어지게 배치 - 로테이션이
//    바뀌어도(=시작 위치만 밀림) 바로 옆 두 칸이 헷갈리는 일이 없음.
// 3) 채도/명도를 낮춰 화이트 배경에서 또렷하게 보이는 톤(회색빛 도는 짙은
//    올리브~네이비~플럼 계열) 위주로 통일 - 파스텔/형광 계열 배제.
//    (자동 대비 텍스트 - ShiftSchedule.getTextColor - 는 이 팔레트 11개 전부
//    "어두운 배경"으로 판정해 흰 글씨를 씀. 별도 표시 불필요.)
const kMainLightPalette = [
  Color(0xFF7E6125), // 주간 - 브론즈 골드
  Color(0xFF5F6529), // 야간 - 올리브
  Color(0xFF426B2E), // 오전 - 모스 그린
  Color(0xFF296533), // 오후 - 포레스트 그린
  kMainRestColor,     // 휴무 - 고정 빨강
  Color(0xFF27684E), // 당직 - 시그린
  Color(0xFF256A67), // 연장 - 딥 틸
  Color(0xFF266482), // 대기 - 스틸 블루
  Color(0xFF2C4C96), // 재택 - 로열 블루
  Color(0xFF473B91), // 출장 - 인디고
  Color(0xFF5E397F), // 교육 - 퍼플
  Color(0xFF723B72), // 특근 - 플럼
];

// ⭐ "메인 다크가 너무 알록달록/쨍하다" 지적으로 전면 재설계 - Material
// 200~400 위주의 쨍한 톤 대신, 다크 배경(#1A1F2E)에서도 눈이 편한 "뮤트/더스티"
// 톤(채도를 낮추고 살짝 톤다운)으로 교체. 휴무만 기존 고정 빨강 유지.
const kMainDarkPalette = [
  Color(0xFF7FA8C9), // 주간 - 뮤트 블루그레이
  Color(0xFFD68C6A), // 야간 - 뮤트 테라코타
  Color(0xFF8FB89A), // 오전 - 세이지 그린
  Color(0xFFA79BC9), // 오후 - 더스티 라벤더
  kMainRestColor,     // 휴무 - 고정 빨강(다크에서도 그대로 - 잘 보임)
  Color(0xFFD9AE6B), // 당직 - 소프트 앰버
  Color(0xFF7B93B5), // 연장 - 슬레이트 블루
  Color(0xFFA3AD72), // 대기 - 뮤트 올리브
  Color(0xFFC98A9C), // 재택 - 더스티 로즈
  Color(0xFF6FA3A0), // 출장 - 틸그레이
  Color(0xFFB08FC0), // 교육 - 소프트 모브
  Color(0xFFB4998A), // 특근 - 웜 타우프
];

// ⭐ "비슷한 톤의 테마들(1/2/9/메인화이트)이 같은 팔레트를 쓰니 서로 차별점이
// 없다"는 지적 - 이 4개는 계속 kMainLightPalette를 공유하되(팔레트 자체는
// 그대로), 각 테마마다 시작 위치(로테이션)만 다르게 줘서 "같은 색상 세트,
// 다른 순서"로 미묘하게 구분되게 함. 회전은 assignShiftColorsForTheme에서 처리.

// ⭐ "5/8/10번은 알록달록 예쁜 테마니까 전용 팔레트를 따로 달라"는 요청 -
// 채도 높은 비비드 톤 위주의 별도 12색 팔레트. 이 세 테마가 이 팔레트를
// 공유하되(로테이션만 다르게) 위 그룹1(라이트 표준 팔레트)과는 확실히
// 구분되는 톤으로 설계함.
// ⭐ 2026-08-17 전면 재설계 - 위 kMainLightPalette와 같은 원칙(색상환
// 40°~300°만 사용, 인접 25~30°+ 이격, 파스텔/형광 배제)을 비비드 톤에도
// 그대로 적용 - "피치"/"코럴오렌지" 등 빨강 근접 색을 완전히 걷어냈고, 예전엔
// 팔레트 안에서만 서로 안 겹치면 됐지만 이번엔 화이트 배경 가독성까지 고려해
// 채도는 유지하되 명도를 한 단계씩 낮춤(순수 파스텔 X). 자동 대비 텍스트가
// 11개 전부 "어두운 배경"으로 판정해 흰 글씨를 씀.
const kVividPalette = [
  Color(0xFFD6991F), // 골드/머스타드
  Color(0xFF9FAB2B), // 올리브
  Color(0xFF61A630), // 모스 그린
  Color(0xFF30A63A), // 그린
  kMainRestColor,     // 휴무 - 고정 빨강
  Color(0xFF2E9E6F), // 시그린
  Color(0xFF279B9B), // 틸
  Color(0xFF258ED0), // 스카이 블루
  Color(0xFF4267D7), // 블루
  Color(0xFF624DCB), // 인디고
  Color(0xFF8A40BF), // 퍼플
  Color(0xFFB143B1), // 마젠타 플럼
];

// ⭐ 4번(굵은 격자형) 전용 팔레트 - "최초 5가지 색상(휴무 포함)은 절대 같은
// 톤이 되면 안 된다"는 재지적으로 전면 재배치함. 이전엔 다크톤(차콜)과
// 스틸블루가 둘 다 "파랑 계열"이라 앞쪽 4칸 안에 같이 들어가 있었음(주간/야간이
// 거의 같은 색으로 보이던 원인) - 이제 앞 4칸(+휴무 빨강)을 회색계열(차콜) ·
// 금색 · 틸(청록) · 바이올렛으로 서로 최대한 먼 색상군에서 하나씩만 뽑고,
// "짙은 회색~블랙 톤 1~2개" 요구는 유지하되 두 번째 다크톤(슬레이트)과 나머지
// 블루 계열(스틸블루/더스티블루/블루그레이)은 전부 5번째 이후로 밀어냄.
const kBoldGridPalette = [
  Color(0xFF455A64), // 차콜 블루그레이 (어두운 톤 1/2 - 채도 낮아 거의 무채색)
  Color(0xFFC9A66B), // 머스타드 골드
  Color(0xFF4E9E94), // 틸(청록)
  Color(0xFF9575CD), // 바이올렛
  kMainRestColor,     // 휴무 - 고정 빨강
  Color(0xFFB0855C), // 러스트 탄
  Color(0xFF7CA982), // 세이지 그린
  Color(0xFF37474F), // 짙은 슬레이트 (어두운 톤 2/2 - 위 차콜과 최대한 멀리 배치)
  Color(0xFF6D8CA6), // 더스티 블루
  Color(0xFF9E8C6B), // 올리브 타우프
  Color(0xFF78909C), // 블루그레이
  Color(0xFFBC8F8F), // 로지 브라운
];

// ⭐ 실제 스케줄의 근무 종류 목록(생성 순서 그대로, ShiftSchedule.shiftTypes)을
// 받아서 "근무명 → 색상" 매핑을 만듦 - calendar_tab.dart가 (기존처럼 DB에
// 저장된 schedule.shiftColors를 읽는 대신) 이 함수로 매번 계산해서 씀.
// onboarding_screen.dart의 _generateShiftColors()와 동일한 2단계 규칙
// (휴무 먼저 고정 배정 → 나머지는 순서대로 팔레트 배정)을 그대로 따름.
Map<String, Color> assignShiftColors(List<String> shiftTypes, {required bool isDark}) {
  return _assignFromPalette(shiftTypes, isDark ? kMainDarkPalette : kMainLightPalette, 0);
}

// ⭐ "비슷한 테마끼리 근무색까지 똑같아서 차별점이 없다"는 지적을 해결하는
// 테마별 진입점 - 팔레트 자체(그룹1=표준 라이트, 그룹2=비비드, 4번/다크는
// 전용)와 그 안에서의 시작 로테이션을 테마마다 다르게 줘서, 같은 그룹 안에서도
// "같은 색상 세트, 다른 배정 순서"로 서로 구분되게 함.
Map<String, Color> assignShiftColorsForTheme(List<String> shiftTypes, CalendarThemeId theme) {
  switch (theme) {
    case CalendarThemeId.mainWhite:
      return _assignFromPalette(shiftTypes, kMainLightPalette, 0);
    case CalendarThemeId.mainDark:
      return _assignFromPalette(shiftTypes, kMainDarkPalette, 0);
    // ⭐ 그룹1(비슷한 톤 테마) - 표준 라이트 팔레트 공유, 로테이션만 다르게.
    case CalendarThemeId.minimal:
      return _assignFromPalette(shiftTypes, kMainLightPalette, 3);
    case CalendarThemeId.materialCard:
      return _assignFromPalette(shiftTypes, kMainLightPalette, 6);
    case CalendarThemeId.eventChip:
      return _assignFromPalette(shiftTypes, kMainLightPalette, 9);
    // ⭐ 그룹2(알록달록 예쁜 테마) - 비비드 팔레트 공유, 로테이션만 다르게.
    case CalendarThemeId.initialBadge:
      return _assignFromPalette(shiftTypes, kVividPalette, 0);
    case CalendarThemeId.underline:
      return _assignFromPalette(shiftTypes, kVividPalette, 4);
    case CalendarThemeId.editorial:
      return _assignFromPalette(shiftTypes, kVividPalette, 8);
    // ⭐ 4번 - 전용 팔레트(로테이션 없음, 항상 차콜부터 시작).
    case CalendarThemeId.boldGrid:
      return _assignFromPalette(shiftTypes, kBoldGridPalette, 0);
  }
}

Map<String, Color> _assignFromPalette(List<String> shiftTypes, List<Color> palette, int rotation) {
  final colors = <String, Color>{};

  // ⭐ 영어 현지화: 이 함수가 실제 사용자 스케줄(assignShiftColors/
  // assignShiftColorsForTheme 경유)의 색상을 배정하는 실사용 경로라, 여기서
  // '휴' 하드코딩만 남겨두면 영어로 "Off"/"Day Off" 등으로 입력한 근무명이
  // 고정 빨강을 못 받는 실제 버그가 됨 - isRestShiftName()으로 교체.
  for (final shift in shiftTypes) {
    if (isRestShiftName(shift)) colors[shift] = kMainRestColor;
  }

  final nonRestShifts = shiftTypes.where((s) => !isRestShiftName(s)).toList();
  // ⭐ 팔레트 자체가 이미 "휴무 자리"에 고정 빨강을 끼워 넣은 12칸짜리
  // 배열이라, 나머지 근무에 순서대로 배정할 땐 그 빨강 슬롯을 건너뛰어야 함 -
  // 안 그러면 근무 하나가 우연히 빨강을 받을 수 있음. rotation은 이 11칸짜리
  // 목록 안에서 시작 위치만 밀어주는 것 - 팔레트 자체(색상 구성)는 그대로.
  final nonRestPalette = palette.where((c) => c != kMainRestColor).toList();
  for (int i = 0; i < nonRestShifts.length; i++) {
    colors[nonRestShifts[i]] = nonRestPalette[(i + rotation) % nonRestPalette.length];
  }

  return colors;
}
