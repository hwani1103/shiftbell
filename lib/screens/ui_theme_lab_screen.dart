// lib/screens/ui_theme_lab_screen.dart
//
// ⭐ 2026-08-25 추가 - "UI 테마" 탭. 지금 앱의 알람 화면(잠금화면/홈 화면 오버레이)과
// 앱 아이콘 디자인이 마음에 안 든다는 요청으로, 실제로 갈아끼우기 전에 방향을
// 먼저 눈으로 비교해보기 위한 임시 디자인 탐색 화면.
//
// ⚠️ 이 화면은 순수하게 "그림"만 그림 - 스와이프로 끄기/스누즈/알람 재생 같은
// 실제 동작은 전혀 안 붙어 있음(버튼을 눌러도 아무 일도 안 일어남). 지금 있는
// 알람 화면의 기능 구성(시간/근무명/끄기 버튼/스누즈 버튼/스와이프 힌트)만
// 자리 배치로 재현해서, "이 기능들이 다 들어간 채로 이렇게 생기면 어떨까"를
// 비교하는 용도. 마음에 드는 번호가 정해지면 그 디자인을 AlarmActivity.kt/
// AlarmOverlayService.kt(실제 알람 화면)와 앱 아이콘 리소스에 옮겨 적용하고
// 이 탭 자체는 삭제할 예정 - 그래서 l10n(app_ko.arb/app_en.arb) 라운드트립 없이
// 한국어 문자열을 직접 씀(임시 화면이라는 걸 알고 하는 의도적 예외).
//
// 10가지 서로 다른 "디자인 콘셉트"(_conceptSpecs)를 1~10번으로 골라서, 그
// 콘셉트로 그린 앱 아이콘 1개 + 잠금화면 알람 1개 + 홈 화면(해제 상태) 오버레이
// 알람 1개, 총 3개를 스크롤로 볼 수 있음. 잠금화면 하나만 해도 세로 영역을 다
// 차지하므로 스크롤이 필요함.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../widgets/app_shift_chip.dart';

/// ⭐ 콘셉트마다 구조 자체가 달라지는 지점(그라데이션/네온/레트로 LCD/유리질/
/// 뉴모피즘/블록/라인아트/머티리얼 유)을 나누는 축 - 색만 바뀌는 게 아니라
/// 아이콘/버튼/시간 표시 방식 자체가 family에 따라 다르게 그려짐.
enum _Family {
  aurora,
  monochrome,
  neonCyber,
  softPastel,
  retroDigital,
  glass,
  darkNeumorphism,
  boldBlocks,
  lineArt,
  materialYou,
}

class _ConceptSpec {
  final int number;
  final String name;
  final String tagline;
  final _Family family;
  final Color bg; // 화면/카드 바탕
  final Color surface; // 카드/버튼 표면
  final Color primary; // 주 강조색
  final Color secondary; // 보조 강조색
  final Color onBg; // 바탕 위 기본 글자색
  final Color onSurface; // 표면 위 기본 글자색
  final List<Color>? gradient; // family가 그라데이션을 쓸 때만

  const _ConceptSpec({
    required this.number,
    required this.name,
    required this.tagline,
    required this.family,
    required this.bg,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.onBg,
    required this.onSurface,
    this.gradient,
  });
}

const List<_ConceptSpec> _conceptSpecs = [
  _ConceptSpec(
    number: 1,
    name: '오로라 그라데이션',
    tagline: '보라~파랑~청록으로 흐르는 화사한 그라데이션. 알약형 버튼, 은은한 글로우.',
    family: _Family.aurora,
    bg: Color(0xFF1B1035),
    surface: Color(0x22FFFFFF),
    primary: Color(0xFF7C4DFF),
    secondary: Color(0xFF00E5C7),
    onBg: Colors.white,
    onSurface: Colors.white,
    gradient: [Color(0xFF6A3DE8), Color(0xFF3D7BF5), Color(0xFF00D9C7)],
  ),
  _ConceptSpec(
    number: 2,
    name: '미니멀 모노크롬',
    tagline: '흑백+회색조. 그림자 없이 얇은 선만. 시간이 화면의 대부분을 차지.',
    family: _Family.monochrome,
    bg: Colors.white,
    surface: Color(0xFFF2F2F2),
    primary: Colors.black,
    secondary: Color(0xFF8A8A8A),
    onBg: Colors.black,
    onSurface: Colors.black,
  ),
  _ConceptSpec(
    number: 3,
    name: '네온 사이버',
    tagline: '검정 배경 + 시안/마젠타 네온 라인. 각진 형태, 스캔라인 질감.',
    family: _Family.neonCyber,
    bg: Color(0xFF0A0A12),
    surface: Color(0xFF13131F),
    primary: Color(0xFF00F6FF),
    secondary: Color(0xFFFF2EC4),
    onBg: Color(0xFF00F6FF),
    onSurface: Colors.white,
  ),
  _ConceptSpec(
    number: 4,
    name: '소프트 파스텔',
    tagline: '지금 앱의 블루 팔레트를 더 부드럽고 둥글게. 친근하고 포근한 톤.',
    family: _Family.softPastel,
    bg: Color(0xFFEAF1FC),
    surface: Colors.white,
    primary: Color(0xFF6B93E0),
    secondary: Color(0xFFFFB4A2),
    onBg: Color(0xFF2A3B5C),
    onSurface: Color(0xFF2A3B5C),
  ),
  _ConceptSpec(
    number: 5,
    name: '레트로 디지털',
    tagline: '옛날 디지털 알람시계 느낌. 짙은 그린-블랙 배경 + LCD 세븐세그 스타일 숫자.',
    family: _Family.retroDigital,
    bg: Color(0xFF0D1A0F),
    surface: Color(0xFF16281A),
    primary: Color(0xFF3CFF6B),
    secondary: Color(0xFFFFC24B),
    onBg: Color(0xFF3CFF6B),
    onSurface: Color(0xFF3CFF6B),
  ),
  _ConceptSpec(
    number: 6,
    name: '글래스모피즘',
    tagline: '화사한 배경 위에 반투명 유리 카드. 부드러운 블러+테두리 하이라이트.',
    family: _Family.glass,
    bg: Color(0xFF4B6FE0),
    surface: Color(0x33FFFFFF),
    primary: Colors.white,
    secondary: Color(0xFFFFE08A),
    onBg: Colors.white,
    onSurface: Colors.white,
    gradient: [Color(0xFF4B6FE0), Color(0xFF8A5CF5), Color(0xFFE05C97)],
  ),
  _ConceptSpec(
    number: 7,
    name: '다크 뉴모피즘',
    tagline: '짙은 회색 소프트 UI. 버튼이 배경에서 살짝 튀어나오거나 파인 듯한 음영.',
    family: _Family.darkNeumorphism,
    bg: Color(0xFF2B2E36),
    surface: Color(0xFF2B2E36),
    primary: Color(0xFFB9C2D0),
    secondary: Color(0xFF6FE3B4),
    onBg: Color(0xFFE7EAF0),
    onSurface: Color(0xFFE7EAF0),
  ),
  _ConceptSpec(
    number: 8,
    name: '볼드 블록',
    tagline: '원색 색면 + 두꺼운 검정 테두리. 바우하우스풍 기하학적 도형, 강한 대비.',
    family: _Family.boldBlocks,
    bg: Color(0xFFFFD93D),
    surface: Colors.white,
    primary: Color(0xFFFF4D4D),
    secondary: Color(0xFF2F6FED),
    onBg: Colors.black,
    onSurface: Colors.black,
  ),
  _ConceptSpec(
    number: 9,
    name: '라인 아트',
    tagline: '아이보리 배경 + 채움 없이 얇은 컬러 선(획)만으로 그린 아이콘/버튼.',
    family: _Family.lineArt,
    bg: Color(0xFFFBF6EC),
    surface: Color(0xFFFBF6EC),
    primary: Color(0xFFB2543A),
    secondary: Color(0xFF3A6E8F),
    onBg: Color(0xFF3A2E27),
    onSurface: Color(0xFF3A2E27),
  ),
  _ConceptSpec(
    number: 10,
    name: '머티리얼 유 다이나믹',
    tagline: '안드로이드12+ 스타일 톤온톤 팔레트. 큼직한 라운드, 알약형 큰 버튼.',
    family: _Family.materialYou,
    bg: Color(0xFFEFE3FF),
    surface: Color(0xFFE3D6FA),
    primary: Color(0xFF5C4C99),
    secondary: Color(0xFF7D5260),
    onBg: Color(0xFF241C36),
    onSurface: Color(0xFF241C36),
  ),
];

class UiThemeLabScreen extends StatefulWidget {
  const UiThemeLabScreen({super.key});

  @override
  State<UiThemeLabScreen> createState() => _UiThemeLabScreenState();
}

class _UiThemeLabScreenState extends State<UiThemeLabScreen> {
  int _selected = 1; // 1-based number

  @override
  Widget build(BuildContext context) {
    final spec = _conceptSpecs.firstWhere((s) => s.number == _selected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('UI 테마 (임시 - 디자인 비교용)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
            child: SizedBox(
              height: 44.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _conceptSpecs.length,
                separatorBuilder: (_, __) => SizedBox(width: 8.w),
                itemBuilder: (context, index) {
                  final s = _conceptSpecs[index];
                  return AppShiftChip(
                    label: '${s.number}',
                    selected: s.number == _selected,
                    onTap: () => setState(() => _selected = s.number),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${spec.number}. ${spec.name}',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    spec.tagline,
                    style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Column(
                children: [
                  _sectionLabel('앱 아이콘'),
                  SizedBox(height: 12.h),
                  _buildIcon(spec),
                  SizedBox(height: 32.h),
                  _sectionLabel('잠금화면 알람'),
                  SizedBox(height: 12.h),
                  _buildLockScreen(spec),
                  SizedBox(height: 32.h),
                  _sectionLabel('홈 화면(해제 상태) 알람'),
                  SizedBox(height: 12.h),
                  _buildOverlay(spec),
                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.grey.shade600));
  }

  // ============================================================
  // 앱 아이콘
  // ============================================================
  Widget _buildIcon(_ConceptSpec s) {
    final size = 104.w;
    final radius = s.family == _Family.boldBlocks ? 20.r : (s.family == _Family.materialYou ? 32.r : 24.r);

    BoxDecoration deco;
    switch (s.family) {
      case _Family.aurora:
      case _Family.glass:
        deco = BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient!),
          boxShadow: [BoxShadow(color: s.primary.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
        );
        break;
      case _Family.monochrome:
        deco = BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(radius),
        );
        break;
      case _Family.neonCyber:
        deco = BoxDecoration(
          color: s.bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: s.primary, width: 2),
          boxShadow: [BoxShadow(color: s.primary.withValues(alpha: 0.6), blurRadius: 16, spreadRadius: 1)],
        );
        break;
      case _Family.softPastel:
        deco = BoxDecoration(
          color: s.primary,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: s.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
        );
        break;
      case _Family.retroDigital:
        deco = BoxDecoration(
          color: s.bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: s.primary.withValues(alpha: 0.6), width: 2),
        );
        break;
      case _Family.darkNeumorphism:
        deco = BoxDecoration(
          color: s.bg,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 14, offset: const Offset(6, 6)),
            BoxShadow(color: Colors.white.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(-6, -6)),
          ],
        );
        break;
      case _Family.boldBlocks:
        deco = BoxDecoration(
          color: s.primary,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.black, width: 4),
        );
        break;
      case _Family.lineArt:
        deco = BoxDecoration(
          color: s.bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: s.primary, width: 2),
        );
        break;
      case _Family.materialYou:
        deco = BoxDecoration(color: s.primary, borderRadius: BorderRadius.circular(radius));
        break;
    }

    return Container(
      width: size,
      height: size,
      decoration: deco,
      alignment: Alignment.center,
      child: _iconGlyph(s, size * 0.5),
    );
  }

  /// 근무/알람을 상징하는 종+시계 결합 아이콘 - 한글 없이 도형만.
  Widget _iconGlyph(_ConceptSpec s, double glyphSize) {
    switch (s.family) {
      case _Family.lineArt:
        return Icon(Icons.notifications_active_outlined, size: glyphSize, color: s.primary);
      case _Family.monochrome:
        return Icon(Icons.notifications_active_rounded, size: glyphSize, color: Colors.white);
      case _Family.neonCyber:
        return Icon(Icons.notifications_active_rounded, size: glyphSize, color: s.primary);
      case _Family.retroDigital:
        return Icon(Icons.access_time_filled_rounded, size: glyphSize, color: s.primary);
      case _Family.boldBlocks:
        return Icon(Icons.notifications_rounded, size: glyphSize, color: Colors.black);
      default:
        return Icon(Icons.notifications_active_rounded, size: glyphSize, color: Colors.white);
    }
  }

  // ============================================================
  // 잠금화면 알람 (AlarmActivity 목업) - 시간/근무명/끄기·스누즈 버튼/스와이프 힌트
  // ============================================================
  Widget _buildLockScreen(_ConceptSpec s) {
    final w = 280.w;
    final h = 580.h;

    return _phoneFrame(
      width: w,
      height: h,
      bg: s.bg,
      gradient: s.family == _Family.aurora || s.family == _Family.glass ? s.gradient : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 40.h, 20.w, 28.h),
        child: Column(
          children: [
            _statusPill(s, '알람'),
            const Spacer(flex: 2),
            _bigTime(s, '07:30', big: true),
            SizedBox(height: 12.h),
            _shiftLabel(s, '야간 근무'),
            const Spacer(flex: 3),
            _actionButtons(s),
            SizedBox(height: 20.h),
            _swipeHint(s),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 홈 화면(해제 상태) 오버레이 알람 - 화면 위에서 살짝 내려온 카드
  // ============================================================
  Widget _buildOverlay(_ConceptSpec s) {
    final w = 280.w;
    final h = 340.h;

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(28.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 뒤에 깔린 "홈 화면" 느낌의 배경(격자 아이콘 힌트)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: 140.h, left: 20.w, right: 20.w),
              child: Wrap(
                spacing: 18.w,
                runSpacing: 18.h,
                children: List.generate(8, (i) => Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                )),
              ),
            ),
          ),
          // 위에서 내려온 알람 오버레이 카드 - 화면 전체를 덮지 않음
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _overlayCard(s),
          ),
        ],
      ),
    );
  }

  Widget _overlayCard(_ConceptSpec s) {
    BoxDecoration deco = BoxDecoration(
      color: s.family == _Family.glass ? null : s.bg,
      gradient: (s.family == _Family.aurora || s.family == _Family.glass)
          ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient!)
          : null,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24.r)),
      border: s.family == _Family.boldBlocks ? const Border(bottom: BorderSide(color: Colors.black, width: 4)) : null,
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
    );

    return Container(
      decoration: deco,
      padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 16.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bigTime(s, '07:30', big: false),
                SizedBox(height: 4.h),
                _shiftLabel(s, '야간 근무'),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          _smallActionButtons(s),
        ],
      ),
    );
  }

  // ============================================================
  // 공용 조각들 - family에 따라 그리는 방식이 달라짐
  // ============================================================

  Widget _phoneFrame({
    required double width,
    required double height,
    required Color bg,
    List<Color>? gradient,
    required Widget child,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient != null
            ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: gradient)
            : null,
        borderRadius: BorderRadius.circular(36.r),
        border: Border.all(color: Colors.black87, width: 8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _statusPill(_ConceptSpec s, String text) {
    if (s.family == _Family.boldBlocks) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
        decoration: BoxDecoration(color: s.secondary, border: Border.all(color: Colors.black, width: 2)),
        child: Text(text, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w900, color: Colors.black)),
      );
    }
    return Text(
      text,
      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: s.onBg.withValues(alpha: 0.7), letterSpacing: 2),
    );
  }

  Widget _bigTime(_ConceptSpec s, String time, {required bool big}) {
    final fontSize = big ? 56.sp : 30.sp;
    switch (s.family) {
      case _Family.retroDigital:
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Text(
            time,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: s.primary,
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: [Shadow(color: s.primary.withValues(alpha: 0.8), blurRadius: 14)],
            ),
          ),
        );
      case _Family.lineArt:
        return Text(
          time,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w300, color: s.onBg, letterSpacing: 1),
        );
      case _Family.boldBlocks:
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 2.h),
          color: Colors.black,
          child: Text(time, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: s.primary)),
        );
      case _Family.neonCyber:
        return Text(
          time,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: s.primary,
            shadows: [
              Shadow(color: s.primary.withValues(alpha: 0.9), blurRadius: 18),
              Shadow(color: s.secondary.withValues(alpha: 0.5), blurRadius: 30),
            ],
          ),
        );
      default:
        return Text(
          time,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: s.onBg),
        );
    }
  }

  Widget _shiftLabel(_ConceptSpec s, String label) {
    if (s.family == _Family.lineArt) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(border: Border.all(color: s.secondary, width: 1.4), borderRadius: BorderRadius.circular(20.r)),
        child: Text(label, style: TextStyle(fontSize: 12.sp, color: s.secondary, fontWeight: FontWeight.w600)),
      );
    }
    if (s.family == _Family.boldBlocks) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(color: s.secondary, border: Border.all(color: Colors.black, width: 2)),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: s.family == _Family.glass ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1) : null,
      ),
      child: Text(label, style: TextStyle(fontSize: 12.sp, color: s.onSurface, fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionButtons(_ConceptSpec s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: _pillButton(s, '5분 후', filled: false)),
        SizedBox(width: 14.w),
        Expanded(child: _pillButton(s, '끄기', filled: true)),
      ],
    );
  }

  Widget _smallActionButtons(_ConceptSpec s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconCircleButton(s, Icons.snooze_rounded, filled: false),
        SizedBox(width: 8.w),
        _iconCircleButton(s, Icons.close_rounded, filled: true),
      ],
    );
  }

  Widget _pillButton(_ConceptSpec s, String label, {required bool filled}) {
    final radius = s.family == _Family.boldBlocks
        ? BorderRadius.circular(4.r)
        : (s.family == _Family.retroDigital ? BorderRadius.circular(6.r) : BorderRadius.circular(30.r));

    Color bg;
    Color fg;
    Border? border;
    if (s.family == _Family.lineArt) {
      bg = Colors.transparent;
      fg = filled ? s.primary : s.secondary;
      border = Border.all(color: fg, width: 1.6);
    } else if (s.family == _Family.boldBlocks) {
      bg = filled ? s.primary : Colors.white;
      fg = filled ? Colors.white : Colors.black;
      border = const Border.fromBorderSide(BorderSide(color: Colors.black, width: 3));
    } else if (s.family == _Family.glass) {
      bg = filled ? Colors.white : Colors.white.withValues(alpha: 0.18);
      fg = filled ? s.gradient!.first : Colors.white;
      border = filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2);
    } else if (s.family == _Family.darkNeumorphism) {
      bg = s.bg;
      fg = filled ? s.secondary : s.primary;
      border = null;
    } else {
      bg = filled ? s.primary : s.surface;
      fg = filled ? Colors.white : s.onSurface;
      border = filled ? null : Border.all(color: s.primary.withValues(alpha: 0.4), width: 1.2);
    }

    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border,
        boxShadow: s.family == _Family.darkNeumorphism
            ? [
                BoxShadow(color: Colors.black.withValues(alpha: filled ? 0.5 : 0.0), blurRadius: 8, offset: const Offset(3, 3)),
                BoxShadow(color: Colors.white.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(-3, -3)),
              ]
            : (filled && (s.family == _Family.aurora || s.family == _Family.softPastel || s.family == _Family.materialYou)
                ? [BoxShadow(color: s.primary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))]
                : null),
      ),
      child: Text(label, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _iconCircleButton(_ConceptSpec s, IconData icon, {required bool filled}) {
    Color bg;
    Color fg;
    if (s.family == _Family.lineArt) {
      bg = Colors.transparent;
      fg = filled ? s.primary : s.secondary;
    } else if (s.family == _Family.boldBlocks) {
      bg = filled ? s.primary : Colors.white;
      fg = filled ? Colors.white : Colors.black;
    } else if (s.family == _Family.glass) {
      bg = filled ? Colors.white : Colors.white.withValues(alpha: 0.25);
      fg = filled ? s.gradient!.first : Colors.white;
    } else {
      bg = filled ? s.primary : s.surface;
      fg = filled ? Colors.white : s.onSurface;
    }

    return Container(
      width: 40.w,
      height: 40.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: s.family == _Family.boldBlocks ? BoxShape.rectangle : BoxShape.circle,
        border: s.family == _Family.lineArt
            ? Border.all(color: fg, width: 1.6)
            : (s.family == _Family.boldBlocks ? Border.all(color: Colors.black, width: 2.5) : null),
      ),
      child: Icon(icon, size: 20.sp, color: fg),
    );
  }

  Widget _swipeHint(_ConceptSpec s) {
    // ⭐ 스와이프-해제 기능 자체는 유지하되, 화면마다 이 힌트의 표현 방식은
    // 요청대로 자유롭게 다르게 그림(화살표+텍스트 / 트랙바 / 텍스트만 등).
    if (s.family == _Family.retroDigital || s.family == _Family.boldBlocks) {
      return Text(
        '← 좌우로 스와이프해서 끄기',
        style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
      );
    }
    return Column(
      children: [
        Icon(Icons.keyboard_double_arrow_up_rounded, size: 18.sp, color: s.onBg.withValues(alpha: 0.5)),
        SizedBox(height: 2.h),
        Text('위로 스와이프해서 끄기', style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.5))),
      ],
    );
  }
}
