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

import 'package:flutter/material.dart';

/// 앱 전반의 배경색 - 은은한 블루그레이/인디고 파스텔톤.
/// 달력 탭은 제외(위 주석 참고).
const Color kAppBackgroundPastel = Color(0xFFD9E1EE);

/// 배경색과 같은 색상 계열(Hue)에서 채도/명도만 낮춘 진한 메인 색상 - 버튼,
/// 강조 텍스트, 선택 상태 등에 씀. 배경과 세트로 어울리도록 같은 계열로 골랐음
/// (배경은 연한 블루그레이, 이건 짙은 인디고 블루 - 서로 톤온톤 관계).
const Color kAppMainAccent = Color(0xFF465B86);

/// 메인 색상 위에 흰 글씨가 아니라 살짝 어둡게 눌러 쓸 때(예: 버튼 눌림 상태)
/// 참고용 - 필요할 때 추가로 씀.
const Color kAppMainAccentDark = Color(0xFF35476B);

/// 카드/입력창 등 배경 위에 얹는 "표면" 색 - 순백 대신 배경 파스텔보다 살짝
/// 밝은 톤을 써서 배경과 카드가 서로 구분되면서도 튀지 않게 함.
const Color kAppSurface = Color(0xFFF2F5FA);

/// 칩(근무명 태그 등)의 테두리색 - 파스텔 배경 위에서 또렷하게 대비되도록
/// 블루그레이 계열의 짙은 색상을 사용. 순수 블랙(#000000)보다 살짝 부드러운
/// 톤으로 세련된 느낌을 냄.
const Color kAppChipBorder = Color(0xFF252B35);

/// 칩(근무명 태그 등)의 채움색 - 배경(kAppBackgroundPastel)보다 한 톤 밝은
/// 화이트에 가까운 색이라 배경 위에서 카드처럼 살짝 떠 보임.
const Color kAppChipFill = Color(0xFFE9EEF6);

// ⭐ 2026-08-24 추가 - 배경/버튼이 단색이라 "딱딱하다"는 피드백으로 그라데이션용
// 색을 추가함. app_button.dart(공용 버튼)와 main.dart(앱 배경)에서 씀.

/// kAppMainAccent보다 밝은 톤(흰색 쪽으로 25% 블렌드) - 버튼 그라데이션의 밝은
/// 쪽 끝에 씀. kAppMainAccentDark(어두운 쪽 끝)와 짝을 이룸.
const Color kAppMainAccentLight = Color(0xFF7484A4);

/// 앱 배경 그라데이션의 위쪽(밝은) 끝 - kAppBackgroundPastel을 흰색 쪽으로
/// 15% 블렌드한 값. 아주 은은해서 거의 단색처럼 보이되 미세한 입체감을 줌.
const Color kAppBackgroundGradientTop = Color(0xFFE4E9F5);

/// 앱 배경 그라데이션의 아래쪽(짙은) 끝 - kAppBackgroundPastel을 kAppMainAccent
/// 쪽으로 8% 블렌드한 값. 메인 색상과 배경이 한 계열이라는 느낌을 살짝 더함.
const Color kAppBackgroundGradientBottom = Color(0xFFCDD6E6);
