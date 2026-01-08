import 'package:flutter/material.dart';

class AppTheme {
  // ========================================
  // 라이트 테마 (기본)
  // ========================================
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    // Primary 색상
    colorScheme: ColorScheme.light(
      primary: Colors.indigo.shade700,
      onPrimary: Colors.white,
      secondary: Colors.blue.shade600,
      onSecondary: Colors.white,
      tertiary: Colors.orange.shade600,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
      surfaceVariant: Color(0xFFF5F5F5),  // grey.shade100 대체
      onSurfaceVariant: Color(0xFF616161),  // grey.shade700 대체
      background: Colors.white,
      onBackground: Colors.black,
      error: Colors.red.shade700,
      onError: Colors.white,
      outline: Color(0xFFE0E0E0),  // grey.shade300 대체 (테두리용)
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 1,
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: Colors.black),
    ),

    // Scaffold
    scaffoldBackgroundColor: Colors.white,

    // Card
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
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
      backgroundColor: Colors.white,
      selectedItemColor: Colors.indigo.shade700,
      unselectedItemColor: Colors.grey.shade600,
      elevation: 8,
    ),

    // TextField
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.indigo.shade400, width: 2),
      ),
    ),

    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),

    // ListTile
    listTileTheme: ListTileThemeData(
      tileColor: Colors.white,
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

    // Primary 색상 (부드러운 인디고)
    colorScheme: ColorScheme.dark(
      primary: Color(0xFF7C88E8),      // 채도 낮춘 밝은 인디고 (Material Indigo 300 기반)
      onPrimary: Color(0xFF0F1419),    // 짙은 배경
      secondary: Color(0xFF8FA3E8),    // 연한 인디고 블루
      onSecondary: Color(0xFF0F1419),
      tertiary: Color(0xFFFFAB91),     // 부드러운 주황 (기존보다 채도 낮춤)
      onTertiary: Color(0xFF0F1419),
      surface: Color(0xFF151B26),      // 진한 인디고 그레이 (카드/다이얼로그)
      onSurface: Color(0xFFE8EAF0),    // 부드러운 흰색
      surfaceVariant: Color(0xFF1E2633),  // 중간 인디고 그레이
      onSurfaceVariant: Color(0xFFB8BCC8),  // 밝은 회색 텍스트
      background: Color(0xFF0F1419),   // 아주 짙은 인디고 그레이 (기존보다 약간 밝음)
      onBackground: Color(0xFFE8EAF0),
      error: Color(0xFFEF9A9A),        // 부드러운 빨강
      onError: Color(0xFF0F1419),
      outline: Color(0xFF2E3A4D),      // 인디고 테두리 (더 명확한 구분)
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF0F1419),
      foregroundColor: Color(0xFFE8EAF0),
      elevation: 1,
      titleTextStyle: TextStyle(
        color: Color(0xFFE8EAF0),
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: Color(0xFFE8EAF0)),
    ),

    // Scaffold
    scaffoldBackgroundColor: Color(0xFF0F1419),

    // Card
    cardTheme: CardThemeData(
      color: Color(0xFF151B26),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Color(0xFF1E2633), width: 1),
      ),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: Color(0xFF151B26),
      titleTextStyle: TextStyle(
        color: Color(0xFFE8EAF0),
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(
        color: Color(0xFFB8BCC8),
        fontSize: 14,
      ),
    ),

    // BottomNavigationBar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF151B26),
      selectedItemColor: Color(0xFF7C88E8),     // 부드러운 인디고
      unselectedItemColor: Color(0xFF6B7280),   // 중성 회색
      elevation: 8,
    ),

    // TextField
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF1E2633),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF2E3A4D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF7C88E8), width: 2),
      ),
      hintStyle: TextStyle(color: Color(0xFF6B7280)),
    ),

    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF7C88E8),      // 부드러운 인디고
        foregroundColor: Color(0xFF0F1419),      // 짙은 배경색
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),

    // ListTile
    listTileTheme: ListTileThemeData(
      tileColor: Color(0xFF151B26),
      textColor: Color(0xFFE8EAF0),
      iconColor: Color(0xFF9CA3AF),
    ),

    // Divider
    dividerColor: Color(0xFF1E2633),

    // Icon
    iconTheme: IconThemeData(color: Color(0xFF9CA3AF)),
  );
}
