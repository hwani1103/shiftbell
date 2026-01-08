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
  // 다크 테마 (푸른 밤하늘 인디고)
  // ========================================
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // Primary 색상 (밝은 색으로)
    colorScheme: ColorScheme.dark(
      primary: Colors.lightBlue.shade300,
      onPrimary: Colors.black,
      secondary: Colors.blue.shade200,
      onSecondary: Colors.black,
      tertiary: Colors.orange.shade400,
      onTertiary: Colors.black,
      surface: Color(0xFF121826), // 진한 인디고 (카드/다이얼로그)
      onSurface: Colors.white,
      surfaceVariant: Color(0xFF1A2332),  // 조금 밝은 인디고
      onSurfaceVariant: Color(0xFFB0B0B0),  // 밝은 회색 텍스트
      background: Color(0xFF0A0E1A), // 진한 인디고 배경 (밤하늘)
      onBackground: Colors.white,
      error: Colors.red.shade400,
      onError: Colors.black,
      outline: Color(0xFF2A3547),  // 인디고 테두리
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF0A0E1A),
      foregroundColor: Colors.white,
      elevation: 1,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),

    // Scaffold
    scaffoldBackgroundColor: Color(0xFF0A0E1A),

    // Card
    cardTheme: CardThemeData(
      color: Color(0xFF121826),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Color(0xFF1A2332), width: 1),
      ),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: Color(0xFF121826),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(
        color: Colors.white70,
        fontSize: 14,
      ),
    ),

    // BottomNavigationBar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF121826),
      selectedItemColor: Colors.lightBlue.shade300,
      unselectedItemColor: Colors.grey.shade500,
      elevation: 8,
    ),

    // TextField
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF1A2332),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF2A3547)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.lightBlue.shade300, width: 2),
      ),
      hintStyle: TextStyle(color: Colors.grey.shade600),
    ),

    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.lightBlue.shade300,
        foregroundColor: Colors.black,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),

    // ListTile
    listTileTheme: ListTileThemeData(
      tileColor: Color(0xFF121826),
      textColor: Colors.white,
      iconColor: Colors.grey.shade400,
    ),

    // Divider
    dividerColor: Color(0xFF1A2332),

    // Icon
    iconTheme: IconThemeData(color: Colors.grey.shade400),
  );
}
