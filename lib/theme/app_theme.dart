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
