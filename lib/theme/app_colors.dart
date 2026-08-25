// lib/theme/app_colors.dart
//
// ⭐ 2026-08-24 추가 - 앱 전반의 "톤"을 정의하는 공통 색상 파일.
//
// 이 앱은 지금까지 화면마다 색을 직접 골라 써서(`settings_tab.dart`만 해도
// `Colors.*`/`Color(0xFF...)` 직접 사용이 50곳 넘음) 전체적인 톤이 중구난방이었음.
// 이 파일이 "공통 팔레트"의 시작점 - 여기 정의한 값을 `app_theme.dart`의
// `ThemeData`가 가져다 쓰고, 화면 코드는 `Theme.of(context).colorScheme.*`로만
// 접근하는 게 원칙. 새 화면을 만들 때 여기 없는 색이 필요하면 이 파일에 먼저
// 추가할 것 - 화면 안에 `Color(0x...)`를 새로 적지 말 것.
//
// ⭐ 명시적 예외 두 가지 (이 공통 팔레트를 따르지 않아도 되는 곳):
// 1. 근무명 색상 지정(`shift_schedule.dart`의 팔레트, `calendar_theme.dart`) -
//    사용자가 직접 고르거나 테마가 배정하는 32색 팔레트로, 이 앱의 핵심 기능
//    자체가 "근무마다 다른 색"이므로 톤을 하나로 통일할 수 없는 영역.
// 2. 달력 탭(`calendar_tab.dart`) - 9개 달력 테마 각각의 고유한 배색 시스템을
//    그대로 유지함. `CalendarTab`의 `Scaffold`가 `backgroundColor`를 명시적으로
//    고정해두는 것도 이 이유 - 아래 kAppBackgroundPastel이 전역 테마에 반영돼도
//    달력 탭만은 영향받지 않게 하기 위함.
//
// 이 두 곳 외의 모든 화면(온보딩/설정/알람화면/친구공유 등)은 이 파일의 색을 따름.
//
// ⭐ 2026-08-24 - 배경/메인색을 세이지 그린 계열에서 블루그레이/인디고 계열로
// 교체함(사용자 직접 선정).
//
// ⭐ 2026-08-25 - "UI 테마" 탭에서 검토해 확정한 앱 아이콘/알람화면/다음알람탭의
// "오로라 페일" 톤(라벤더~스카이~민트 그라데이션)을 앱 전체 메인 색상으로도
// 확장 적용함. kAppMainAccent를 그 확정 디자인의 primary(Color(0xFF6A4FD9))와
// 완전히 동일한 값으로 맞춰서, 앱 아이콘 → 알람화면 → 다음알람탭 → 버튼/테마
// 전부가 하나의 일관된 톤으로 이어지게 함. 나머지 파생색은 이전과 같은 방식
// (흰색/검정/메인색 쪽으로 블렌드)으로 계산.

import 'package:flutter/material.dart';

// /// 앱 전반의 배경색 - 은은한 블루그레이/인디고 파스텔톤.
// /// 달력 탭은 제외(위 주석 참고).
// const Color kAppBackgroundPastel = Color(0xFFD9E1EE);

// /// 배경색과 같은 색상 계열(Hue)에서 채도/명도만 낮춘 진한 메인 색상 - 버튼,
// /// 강조 텍스트, 선택 상태 등에 씀. 배경과 세트로 어울리도록 같은 계열로 골랐음
// /// (배경은 연한 블루그레이, 이건 짙은 인디고 블루 - 서로 톤온톤 관계).
// const Color kAppMainAccent = Color(0xFF465B86);

// /// 메인 색상 위에 흰 글씨가 아니라 살짝 어둡게 눌러 쓸 때(예: 버튼 눌림 상태)
// /// 참고용으로 만들었다가, 지금은 app_button.dart 그라데이션의 어두운 쪽 끝으로
// /// 씀(검정 쪽으로 35% 블렌드 - "그라데이션이 약하다"는 피드백으로 진하게 키움).
// const Color kAppMainAccentDark = Color(0xFF2E3B57);

// /// 카드/입력창 등 배경 위에 얹는 "표면" 색 - 순백 대신 배경 파스텔보다 살짝
// /// 밝은 톤을 써서 배경과 카드가 서로 구분되면서도 튀지 않게 함.
// const Color kAppSurface = Color(0xFFF2F5FA);

// /// 칩(근무명 태그 등)의 테두리색 - 파스텔 배경 위에서 또렷하게 대비되도록
// /// 블루그레이 계열의 짙은 색상을 사용. 순수 블랙(#000000)보다 살짝 부드러운
// /// 톤으로 세련된 느낌을 냄.
// const Color kAppChipBorder = Color(0xFF252B35);

// /// 칩(근무명 태그 등)의 채움색 - 배경(kAppBackgroundPastel)보다 한 톤 밝은
// /// 화이트에 가까운 색이라 배경 위에서 카드처럼 살짝 떠 보임.
// const Color kAppChipFill = Color(0xFFE9EEF6);

// // ⭐ 2026-08-24 추가 - 배경/버튼이 단색이라 "딱딱하다"는 피드백으로 그라데이션용
// // 색을 추가함. app_button.dart(공용 버튼)와 main.dart(앱 배경)에서 씀.
// // ⭐ 2026-08-24 재조정 - 첫 시도가 "거의 안 보인다"는 피드백을 받아서, 아래
// // 두 그라데이션(버튼/배경) 모두 양 끝 색 차이를 훨씬 크게 벌림.

// /// kAppMainAccent보다 밝은 톤(흰색 쪽으로 60% 블렌드) - 버튼 그라데이션의 밝은
// /// 쪽 끝에 씀. kAppMainAccentDark(어두운 쪽 끝, 검정 쪽 35% 블렌드)와 짝을 이룸 -
// /// 25%→45%→60% 순으로 "대비가 더 잘 되게" 계속 밝은 쪽을 더 밝게 키워옴.
// const Color kAppMainAccentLight = Color(0xFFB5BDCF);

// /// 앱 배경 그라데이션의 위쪽(밝은) 끝 - kAppBackgroundPastel을 흰색 쪽으로 50%
// /// 블렌드한 값. 처음엔 15%라 거의 안 보였음 - 훨씬 밝게 키움.
// const Color kAppBackgroundGradientTop = Color(0xFFECF0F7);

// /// 앱 배경 그라데이션의 아래쪽(짙은) 끝 - kAppBackgroundPastel을 kAppMainAccent
// /// 쪽으로 28% 블렌드한 값. 처음엔 8%라 거의 안 보였음 - 뚜렷하게 짙어지도록 키움.
// const Color kAppBackgroundGradientBottom = Color(0xFFB0BBD1);



// ⭐ 2026-08-24~25 블루 계열(위 코멘트 참고) - "오로라 페일"로 교체되며 보관용으로 남김.
// const Color kAppBackgroundPastel = Color(0xFFDCE8F8);
// const Color kAppMainAccent = Color(0xFF3366B8);
// const Color kAppMainAccentDark = Color(0xFF20437A);
// const Color kAppSurface = Color(0xFFEEF3FC);
// const Color kAppChipBorder = Color(0xFF1D3557);
// const Color kAppChipFill = Color(0xFFEAF2FB);
// const Color kAppMainAccentLight = Color(0xFF9CBFF0);
// const Color kAppBackgroundGradientTop = Color(0xFFEEF4FC);
// const Color kAppBackgroundGradientBottom = Color(0xFFA6C5F0);

// ⭐ 2026-08-25 재조정 - 메인 테마색을 보라(#6A4FD9)에서 앱 아이콘 톤(인디고→블루
// 그라데이션)에 맞춘 블루·인디고 계열로 교체함. "메인 컬러가 꼭 보라일 필요는
// 없다, 아이콘 색 톤에 맞추자"는 요청 - 아이콘(assets/icon/gen_icon.py)의
// BG_STOPS 시작색(인디고 #4850BC)과 중간색(블루 #4474F1)을 50:50으로 섞은 값을
// 새 kAppMainAccent로 삼고, 그 아래 파생색들은 전부 이전과 동일한 블렌드 비율
// 공식으로 재계산함(비율 자체는 안 바꿈 - 기준색만 교체). 아이콘 끝쪽 청록/오로라
// 색까지는 안 가져옴 - 버튼/텍스트로 쓰기엔 너무 밝고 대비가 약해서 인디고~블루
// 구간만 대표색으로 씀.

/// 배경색과 같은 색상 계열(Hue)에서 채도/명도만 낮춘 진한 메인 색상 - 버튼,
/// 강조 텍스트, 선택 상태 등에 씀. 앱 아이콘 그라데이션의 인디고~블루 중간톤.
const Color kAppMainAccent = Color(0xFF4662D6);

/// 앱 전반의 배경색 - kAppMainAccent를 흰색 쪽으로 82% 블렌드한 파스텔.
/// 달력 탭은 제외(위 주석 참고).
const Color kAppBackgroundPastel = Color(0xFFDEE3F8);

/// 메인 색상 위에 흰 글씨가 아니라 살짝 어둡게 눌러 쓸 때(예: 버튼 눌림 상태)
/// 참고용으로 만들었다가, 지금은 app_button.dart 그라데이션의 어두운 쪽 끝으로
/// 씀(검정 쪽으로 35% 블렌드).
const Color kAppMainAccentDark = Color(0xFF2E408B);

/// 카드/입력창 등 배경 위에 얹는 "표면" 색 - kAppBackgroundPastel을 흰색 쪽으로
/// 50% 블렌드해서 배경과 카드가 서로 구분되면서도 튀지 않게 함.
const Color kAppSurface = Color(0xFFEEF1FC);

/// 칩(근무명 태그 등)의 테두리색 - kAppMainAccent를 검정 쪽으로 45% 블렌드한
/// 짙은 남색. 파스텔 배경 위에서 또렷하게 대비되도록 kAppMainAccentDark(35%
/// 블렌드)보다 한 단계 더 어둡게 잡음.
const Color kAppChipBorder = Color(0xFF263676);

/// 칩(근무명 태그 등)의 채움색 - 배경(kAppBackgroundPastel)보다 한 톤 밝은
/// 화이트에 가까운 색이라 배경 위에서 카드처럼 살짝 떠 보임.
const Color kAppChipFill = Color(0xFFE8EBFA);

// ⭐ 2026-08-24 추가 - 배경/버튼이 단색이라 "딱딱하다"는 피드백으로 그라데이션용
// 색을 추가함. app_button.dart(공용 버튼)와 main.dart(앱 배경)에서 씀.

/// kAppMainAccent보다 밝은 톤(흰색 쪽으로 60% 블렌드) - 버튼 그라데이션의 밝은
/// 쪽 끝에 씀. kAppMainAccentDark(어두운 쪽 끝, 검정 쪽 35% 블렌드)와 짝을 이룸.
const Color kAppMainAccentLight = Color(0xFFB5C0EF);

/// 앱 배경 그라데이션의 위쪽(밝은) 끝 - kAppBackgroundPastel을 흰색 쪽으로 50%
/// 블렌드한 값.
const Color kAppBackgroundGradientTop = Color(0xFFEEF1FC);

/// 앱 배경 그라데이션의 아래쪽(짙은) 끝 - kAppBackgroundPastel을 kAppMainAccent
/// 쪽으로 28% 블렌드한 값.
const Color kAppBackgroundGradientBottom = Color(0xFFB3BFEE);

// ⭐ 2026-08-25 추가 - "다음 알람" 탭 전용. 아이콘/알람화면과 같은 "오로라 페일"
// 그라데이션을 탭 배경에도 그대로 씀(라벤더~스카이~민트, topLeft→bottomRight).
// 정적 배경으로만 쓰이던 값이라 지금은 미사용 - 대비를 높인 kAppWaveGradientColors로
// 대체되었으나(파도 애니메이션), 혹시 모를 참고용으로 남겨둠.
const List<Color> kAppAlarmGradient = [Color(0xFFDACEF9), Color(0xFFCEDEFC), Color(0xFFBFF5F1)];

/// ⭐ 2026-08-25 추가 - 잠금화면/오버레이 알람(WaveGradientView.kt)과 동일한 팔레트.
/// kAppAlarmGradient보다 채도를 높여 각도 회전 애니메이션이 눈에 띄게 함("오로라
/// 소프트" 티어). "다음 알람" 탭의 파도 배경(_WaveGradientBackground)에서 사용.
const List<Color> kAppWaveGradientColors = [Color(0xFFB49EF3), Color(0xFF9EBDFA), Color(0xFF80ECE3)];

/// ⭐ 2026-08-25 추가 - kAppWaveGradientColors 3색의 평균 톤. "다음 알람" 탭
/// Scaffold의 backgroundColor로 씀(예전엔 Colors.transparent) - 파도 배경
/// 위젯이 무슨 이유로든 그 프레임에 아직 안 그려졌을 때(리빌드 중간 등) 뒤에
/// 있는 앱 루트의 흰 배경이 그대로 비쳐서 "하얗게 깜빡"이는 것처럼 보이던
/// 문제의 안전장치 - 이 색이 항상 깔려있으면 최악의 경우에도 흰 배경이
/// 아니라 파도 배경과 톤이 비슷한 색만 살짝 비치게 됨.
const Color kAppWaveGradientFallback = Color(0xFF9BC2F0);

/// "다음 알람" 탭의 카운트다운 링 채움색 - 네온 민트. UI 테마 탭에서 "1번(진한
/// 오로라) 테마의 링 색보다는 살짝 덜 밝고, 원래 쓰던 톤보다는 밝게" 요청으로
/// 튜닝한 값 - 0xFF0F9C90(원래 톤)과 0xFF00E5C7(1번 테마 링 색)을 7:3(1번 쪽으로
/// 70%)로 블렌드함.
const Color kAppRingAccent = Color(0xFF05CFB7);