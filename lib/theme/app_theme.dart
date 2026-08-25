import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  // ========================================
  // 라이트 테마 (기본) - 앱 전체 톤. 새 색이 필요하면 app_colors.dart에 먼저
  // 추가하고 여기서 가져다 쓸 것. 달력 탭은 여기 안 따름(calendar_tab.dart의
  // Scaffold가 배경색을 직접 고정함 - app_colors.dart 상단 주석 참고).
  // ========================================
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    // Primary 색상
    colorScheme: ColorScheme.light(
      primary: kAppMainAccent,
      onPrimary: Colors.white,
      secondary: kAppMainAccent,
      onSecondary: Colors.white,
      tertiary: Colors.orange.shade600,
      onTertiary: Colors.white,
      surface: kAppSurface,
      onSurface: Colors.black,
      surfaceVariant: Color(0xFFF5F5F5),  // grey.shade100 대체
      onSurfaceVariant: Color(0xFF616161),  // grey.shade700 대체
      background: kAppBackgroundPastel,
      onBackground: Colors.black,
      error: Colors.red.shade700,
      onError: Colors.white,
      outline: Color(0xFFE0E0E0),  // grey.shade300 대체 (테두리용)
    ),

    // AppBar
    // ⭐ 2026-08-25 - kAppBackgroundPastel(연보라)에서 흰색으로 통일. 달력 탭은
    // 이미 자기 Scaffold/AppBar를 Colors.white로 직접 고정해뒀는데(calendar_tab.dart),
    // 이 전역 기본값만 연보라라 설정/일정공유 등 나머지 탭 상단(상태바+AppBar
    // 영역)만 달력 탭과 다르게 보였음 - "다 흰색으로 통일해달라" 요청으로 여기
    // 한 곳만 바꿔서 달력 탭을 뺀 모든 화면이 한 번에 흰색이 되도록 함.
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      // ⭐ centerTitle 미지정 시 안드로이드 기본값은 false라, leading(뒤로가기
      // 아이콘/빈 SizedBox)이 있으면 타이틀이 화면 정중앙이 아니라 leading
      // 폭만큼 오른쪽으로 치우쳐 보임(Text를 Center로 감싸는 것만으론 안 고쳐짐 -
      // Center는 title에게 배정된 영역 "안에서만" 중앙 정렬함). true로 고정해서
      // leading 유무와 무관하게 항상 화면 정중앙에 오도록 함.
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: Colors.black),
    ),

    // Scaffold
    // ⭐ 2026-08-24 - 파스텔(kAppBackgroundPastel) → 투명(그라데이션 실험) →
    // 흰색 순으로 바뀜. 그라데이션은 InitialRouter(로딩 게이트, 네이티브
    // 스플래시와 맞추려 항상 불투명 흰색)에서 다음 화면으로 넘어갈 때 "가려져
    // 있던 배경이 드러나는" 깜빡임을 만들어서 보류하고 흰색으로 고정함 - 그럼
    // InitialRouter와 그 다음 화면들의 배경이 완전히 같아서 애초에 드러날
    // "다른 배경"이 없어짐. 달력 탭은 자기 Scaffold에 backgroundColor를 직접
    // 고정해서 이 값과 무관하게 항상 흰 배경(calendar_tab.dart 참고 - 지금은
    // 결과적으로 같은 흰색이지만, 이 값이 나중에 다시 바뀌어도 달력 탭은 안
    // 흔들리도록 여전히 독립적으로 고정해둠).
    scaffoldBackgroundColor: Colors.white,

    // Card
    cardTheme: CardThemeData(
      color: kAppSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08), width: 1),
      ),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: kAppSurface,
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(
        color: Colors.black87,
        fontSize: 14,
      ),
    ),

    // BottomNavigationBar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: kAppSurface,
      selectedItemColor: kAppMainAccent,
      unselectedItemColor: Colors.grey.shade600,
      elevation: 8,
    ),

    // TextField
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kAppSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kAppMainAccent, width: 2),
      ),
    ),

    // ElevatedButton - 이 앱의 "기본 버튼". 칩(근무명 태그 등)은 별도
    // 컴포넌트(app_shift_chip.dart)를 씀 - 버튼과 칩은 서로 다른 디자인 언어.
    // ⭐ 2026-08-24 - 버튼 글자가 작다는 피드백. 처음엔 화면 하나(온보딩 첫
    // 화면)에만 로컬로 크게 키웠다가("너무 크다") 되돌림 - 버튼은 이 공통
    // 테마 하나로 관리하기로 했으므로 여기서 딱 1만큼만 키움(Material3 기본
    // labelLarge가 14 → 15). 화면별로 각자 스타일을 얹지 말고 항상 이 기본
    // ElevatedButton을 그대로 쓸 것 - 그래야 이 값 하나만 바꿔도 전체가 같이 바뀜.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAppMainAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: TextStyle(fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),

    // ListTile
    listTileTheme: ListTileThemeData(
      tileColor: kAppSurface,
      textColor: Colors.black,
      iconColor: Colors.grey.shade700,
    ),

    // Divider
    dividerColor: Colors.grey.shade300,

    // Icon
    iconTheme: IconThemeData(color: Colors.grey.shade700),
  );

  // ========================================
  // 다크 테마 (세련된 인디고 그레이)
  // ========================================
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // Primary 색상 (밝고 세련된 인디고)
    colorScheme: ColorScheme.dark(
      primary: Color(0xFF9AA5F5),      // 더 밝은 인디고 (세련된 느낌)
      onPrimary: Color(0xFF1A1F2E),    // 배경
      secondary: Color(0xFFAAB6FF),    // 연한 인디고 블루
      onSecondary: Color(0xFF1A1F2E),
      tertiary: Color(0xFFFFC4B0),     // 밝은 코랄 주황
      onTertiary: Color(0xFF1A1F2E),
      surface: Color(0xFF242938),      // 밝은 인디고 그레이 (카드/다이얼로그)
      onSurface: Color(0xFFF5F7FB),    // 인디고 틴트 off-white (주 텍스트)
      surfaceVariant: Color(0xFF2E3547),  // 중간 인디고 그레이 (더 밝게)
      onSurfaceVariant: Color(0xFFD8DBE5),  // 밝은 인디고 틴트 회색 (보조 텍스트)
      background: Color(0xFF1A1F2E),   // 밝은 인디고 그레이 배경
      onBackground: Color(0xFFF5F7FB), // 인디고 틴트 off-white
      error: Color(0xFFFFB4AB),        // 밝은 빨강
      onError: Color(0xFF1A1F2E),
      outline: Color(0xFF3E4A5D),      // 인디고 테두리 (명확하게)
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF1A1F2E),
      foregroundColor: Color(0xFFF5F7FB),  // 인디고 틴트 off-white
      elevation: 1,
      titleTextStyle: TextStyle(
        color: Color(0xFFF5F7FB),
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: Color(0xFFF5F7FB)),
    ),

    // Scaffold
    scaffoldBackgroundColor: Color(0xFF1A1F2E),

    // Card
    cardTheme: CardThemeData(
      color: Color(0xFF242938),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Color(0xFF2E3547), width: 1),
      ),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: Color(0xFF242938),
      titleTextStyle: TextStyle(
        color: Color(0xFFF5F7FB),  // 인디고 틴트 off-white
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(
        color: Color(0xFFD8DBE5),  // 밝은 인디고 틴트 회색
        fontSize: 14,
      ),
    ),

    // BottomNavigationBar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF242938),
      selectedItemColor: Color(0xFF9AA5F5),     // 밝은 인디고
      unselectedItemColor: Color(0xFF8A90A0),   // 중성 회색 (더 밝게)
      elevation: 8,
    ),

    // TextField
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF2E3547),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF3E4A5D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF9AA5F5), width: 2),
      ),
      hintStyle: TextStyle(color: Color(0xFF8A90A0)),  // 더 밝게
    ),

    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF9AA5F5),      // 밝은 인디고
        foregroundColor: Color(0xFF1A1F2E),      // 배경색
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),

    // ListTile
    listTileTheme: ListTileThemeData(
      tileColor: Color(0xFF242938),
      textColor: Color(0xFFF5F7FB),  // 인디고 틴트 off-white
      iconColor: Color(0xFFC8CEDA),  // 밝은 아이콘 색상
    ),

    // Divider
    dividerColor: Color(0xFF2E3547),

    // Icon
    iconTheme: IconThemeData(color: Color(0xFFC8CEDA)),  // 밝은 아이콘 색상
  );
}
