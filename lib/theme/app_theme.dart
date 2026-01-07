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
      surface: Colors.white,
      onSurface: Colors.black,
      background: Colors.white,
      onBackground: Colors.black,
      error: Colors.red.shade700,
      onError: Colors.white,
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
  // 다크 테마 (완전 검정)
  // ========================================
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // Primary 색상 (밝은 색으로)
    colorScheme: ColorScheme.dark(
      primary: Colors.lightBlue.shade400,
      onPrimary: Colors.black,
      secondary: Colors.blue.shade300,
      onSecondary: Colors.black,
      surface: Color(0xFF1A1A1A), // 어두운 회색 (카드/다이얼로그)
      onSurface: Colors.white,
      background: Color(0xFF000000), // 완전 검정
      onBackground: Colors.white,
      error: Colors.red.shade400,
      onError: Colors.black,
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF000000),
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
    scaffoldBackgroundColor: Color(0xFF000000),

    // Card
    cardTheme: CardThemeData(
      color: Color(0xFF1A1A1A),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Color(0xFF2A2A2A), width: 1),
      ),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: Color(0xFF1A1A1A),
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
      backgroundColor: Color(0xFF1A1A1A),
      selectedItemColor: Colors.lightBlue.shade400,
      unselectedItemColor: Colors.grey.shade500,
      elevation: 8,
    ),

    // TextField
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF2A2A2A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF3A3A3A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.lightBlue.shade400, width: 2),
      ),
      hintStyle: TextStyle(color: Colors.grey.shade600),
    ),

    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.lightBlue.shade400,
        foregroundColor: Colors.black,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),

    // ListTile
    listTileTheme: ListTileThemeData(
      tileColor: Color(0xFF1A1A1A),
      textColor: Colors.white,
      iconColor: Colors.grey.shade400,
    ),

    // Divider
    dividerColor: Color(0xFF2A2A2A),

    // Icon
    iconTheme: IconThemeData(color: Colors.grey.shade400),
  );
}
