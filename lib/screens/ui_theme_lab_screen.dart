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
// ⭐ 2026-08-25 재작성 - 1차 버전은 "색만 다르고 구조가 같다"는 피드백을 받음.
// 1/4/6/9/10번(오로라/소프트 파스텔/글래스모피즘/라인 아트/머티리얼 유)은 구조를
// 그대로 유지하고, 2/3/5/7/8번(미니멀 모노크롬/네온 사이버/레트로 디지털/다크
// 뉴모피즘/볼드 블록)은 레이아웃 자체를 다시 짬(예: 모노크롬은 카드/버튼 모양을
// 없애고 타이포그래피와 선만으로, 레트로는 물리 알람시계 베젤+LED 표시등,
// 뉴모피즘은 원형 다이얼, 볼드 블록은 대각선 분할 포스터, 네온은 각진 HUD).
// 앱 아이콘도 1번만 고정하고 나머지는 전부 콘셉트별로 다르게 그림(전엔 대부분
// 종 모양 아이콘을 색만 바꿔 썼음).

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
    tagline: '카드/버튼 형태를 없애고 타이포그래피와 얇은 선만으로 구성. 극도로 절제.',
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
    tagline: 'HUD 계기판 느낌. 각진 대괄호 프레임, 신호 바, 시간 이중노출 글리치.',
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
    tagline: '진짜 물리 알람시계처럼 베젤+LED 표시등+세븐세그 숫자, 큼직한 사각 키.',
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
    tagline: '시간을 원형 엠보싱 다이얼 안에 표시. 버튼도 다이얼 주위 원형 버튼.',
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
    tagline: '대각선으로 갈라지는 원색 포스터. 큼직한 슬랩 숫자 + 두꺼운 사각 버튼.',
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
  // 앱 아이콘 - family별로 완전히 다른 그림(1번만 고정, 나머지는 전부 개성 있게)
  // ============================================================
  Widget _buildIcon(_ConceptSpec s) {
    final size = 104.w;
    final radius = s.family == _Family.boldBlocks
        ? 20.r
        : (s.family == _Family.materialYou ? 32.r : (s.family == _Family.retroDigital ? 14.r : 24.r));

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
        deco = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.black, width: 2.5));
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
          color: const Color(0xFF08120A),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: s.primary.withValues(alpha: 0.7), width: 3),
        );
        break;
      case _Family.darkNeumorphism:
        deco = BoxDecoration(
          color: s.bg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 14, offset: const Offset(6, 6)),
            BoxShadow(color: Colors.white.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(-6, -6)),
          ],
        );
        break;
      case _Family.boldBlocks:
        deco = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.black, width: 4));
        break;
      case _Family.lineArt:
        deco = BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(radius), border: Border.all(color: s.primary, width: 2));
        break;
      case _Family.materialYou:
        deco = const BoxDecoration(); // materialYou는 blob 클리퍼가 배경까지 그림
        break;
    }

    final glyph = _iconGlyph(s, size * 0.52);

    if (s.family == _Family.materialYou) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipPath(
          clipper: _BlobClipper(),
          child: Container(color: s.primary, alignment: Alignment.center, child: glyph),
        ),
      );
    }

    return Container(width: size, height: size, decoration: deco, alignment: Alignment.center, child: glyph);
  }

  /// 근무/알람을 상징하는 글리프. 1번(오로라)만 고정, 나머지는 family별로
  /// 서로 다른 조형(단순 아이콘 색상 교체가 아니라 도형 구성 자체를 다르게 함).
  Widget _iconGlyph(_ConceptSpec s, double g) {
    switch (s.family) {
      case _Family.aurora:
        // ⭐ 고정 - 건드리지 않음.
        return Icon(Icons.notifications_active_rounded, size: g, color: Colors.white);

      case _Family.monochrome:
        // 원 + 시계바늘 하나 - 극도로 절제된 형태.
        return SizedBox(
          width: g,
          height: g,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(width: g, height: g, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 3))),
              Container(width: g * 0.06, height: g * 0.06, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle)),
              Transform.translate(
                offset: Offset(0, -g * 0.16),
                child: Transform.rotate(angle: 0.5, child: Container(width: 3, height: g * 0.34, color: Colors.black)),
              ),
            ],
          ),
        );

      case _Family.neonCyber:
        // 각진 육각 프레임 + 코어 도트 + 글로우.
        return SizedBox(
          width: g,
          height: g,
          child: ClipPath(
            clipper: _HexagonClipper(),
            child: Container(
              color: s.bg,
              alignment: Alignment.center,
              child: Container(
                width: g * 0.22,
                height: g * 0.22,
                decoration: BoxDecoration(
                  color: s.primary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: s.primary, blurRadius: 12, spreadRadius: 2), BoxShadow(color: s.secondary.withValues(alpha: 0.6), blurRadius: 20)],
                ),
              ),
            ),
          ),
        );

      case _Family.softPastel:
        // 둥근 시계 + 우측 상단 알림 점 - 친근한 느낌.
        return Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.watch_later_rounded, size: g, color: Colors.white),
            Positioned(
              top: g * 0.02,
              right: g * 0.02,
              child: Container(
                width: g * 0.24,
                height: g * 0.24,
                decoration: BoxDecoration(color: s.secondary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              ),
            ),
          ],
        );

      case _Family.retroDigital:
        // 미니 LED 세그먼트 바 3줄 - 디지털 리드아웃 느낌.
        return SizedBox(
          width: g,
          height: g,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ledBar(g, 0.9, s.primary),
              SizedBox(height: g * 0.1),
              _ledBar(g, 0.6, s.primary),
              SizedBox(height: g * 0.1),
              _ledBar(g, 0.4, s.secondary),
            ],
          ),
        );

      case _Family.glass:
        // 겹쳐진 반투명 유리 원 두 개 + 중심 아이콘.
        return SizedBox(
          width: g,
          height: g,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                child: Container(
                  width: g * 0.7,
                  height: g * 0.7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18), border: Border.all(color: Colors.white.withValues(alpha: 0.5))),
                ),
              ),
              Positioned(
                right: 0,
                child: Container(
                  width: g * 0.7,
                  height: g * 0.7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.12), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
                ),
              ),
              Icon(Icons.notifications_rounded, size: g * 0.5, color: Colors.white),
            ],
          ),
        );

      case _Family.darkNeumorphism:
        // 엠보싱 원형 다이얼 - 알림 대신 순수 소프트 UI 조형.
        return Container(
          width: g,
          height: g,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.bg,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(4, 4)),
              BoxShadow(color: Colors.white.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(-4, -4)),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: g * 0.42,
            height: g * 0.42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.bg,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 6, offset: const Offset(-3, -3)),
                BoxShadow(color: s.secondary.withValues(alpha: 0.5), blurRadius: 6, offset: const Offset(3, 3)),
              ],
            ),
          ),
        );

      case _Family.boldBlocks:
        // 바우하우스풍 원+삼각형 겹침 - 포스터 조형.
        return SizedBox(
          width: g,
          height: g,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(width: g * 0.62, height: g * 0.62, decoration: BoxDecoration(color: s.secondary, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 3))),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: ClipPath(
                  clipper: _TriangleClipper(),
                  child: Container(width: g * 0.62, height: g * 0.62, color: s.primary),
                ),
              ),
            ],
          ),
        );

      case _Family.lineArt:
        // 얇은 손그림풍 종 + 옆에 작은 반원 악센트.
        return CustomPaint(size: Size(g, g), painter: _LineBellPainter(color: s.primary));

      case _Family.materialYou:
        return Icon(Icons.notifications_active_rounded, size: g * 0.55, color: Colors.white);
    }
  }

  Widget _ledBar(double g, double widthFactor, Color color) {
    return Container(
      width: g * 0.7 * widthFactor,
      height: g * 0.12,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)]),
    );
  }

  // ============================================================
  // 잠금화면 알람 (AlarmActivity 목업)
  // ============================================================
  Widget _buildLockScreen(_ConceptSpec s) {
    switch (s.family) {
      case _Family.monochrome:
        return _lockMonochrome(s);
      case _Family.neonCyber:
        return _lockNeonCyber(s);
      case _Family.retroDigital:
        return _lockRetroDigital(s);
      case _Family.darkNeumorphism:
        return _lockDarkNeumorphism(s);
      case _Family.boldBlocks:
        return _lockBoldBlocks(s);
      default:
        return _lockGeneric(s);
    }
  }

  Widget _lockGeneric(_ConceptSpec s) {
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

  // ⭐ 2번 - 카드/버튼 형태 없이 타이포그래피+선만으로.
  Widget _lockMonochrome(_ConceptSpec s) {
    final w = 280.w;
    final h = 580.h;
    return _phoneFrame(
      width: w,
      height: h,
      bg: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(28.w, 56.h, 28.w, 32.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ALARM', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, letterSpacing: 6, color: Colors.black54)),
            const Spacer(flex: 2),
            Text('07:30', style: TextStyle(fontSize: 72.sp, fontWeight: FontWeight.w200, color: Colors.black, height: 1)),
            SizedBox(height: 10.h),
            Row(
              children: [
                Container(width: 28.w, height: 1.4, color: Colors.black),
                SizedBox(width: 10.w),
                Text('야간 근무', style: TextStyle(fontSize: 14.sp, color: Colors.black87, letterSpacing: 1)),
              ],
            ),
            const Spacer(flex: 3),
            Divider(color: Colors.black.withValues(alpha: 0.15), height: 1),
            SizedBox(height: 18.h),
            Row(
              children: [
                Expanded(
                  child: Text('5분 후', textAlign: TextAlign.left, style: TextStyle(fontSize: 15.sp, color: Colors.black54, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text(
                    '끄기',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 15.sp, color: Colors.black, fontWeight: FontWeight.w800, decoration: TextDecoration.underline, decorationThickness: 1.5),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            Center(child: Text('— 위로 스와이프 —', style: TextStyle(fontSize: 10.sp, color: Colors.black38, letterSpacing: 1))),
          ],
        ),
      ),
    );
  }

  // ⭐ 3번 - 각진 HUD 프레임 + 신호바 + 시간 이중노출(글리치).
  Widget _lockNeonCyber(_ConceptSpec s) {
    final w = 280.w;
    final h = 580.h;
    return _phoneFrame(
      width: w,
      height: h,
      bg: s.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18.w, 32.h, 18.w, 24.h),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: List.generate(4, (i) => Container(margin: EdgeInsets.only(right: 3.w), width: 4.w, height: (8 + i * 4).h, color: s.primary))),
                Text('ALARM // ACTIVE', style: TextStyle(fontSize: 10.sp, color: s.secondary, letterSpacing: 2, fontWeight: FontWeight.w700)),
              ],
            ),
            const Spacer(flex: 2),
            _hudBracketFrame(
              color: s.primary,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 28.h, horizontal: 10.w),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: const Offset(-2, 2),
                      child: Text('07:30', style: TextStyle(fontSize: 50.sp, fontWeight: FontWeight.w800, color: s.secondary.withValues(alpha: 0.5))),
                    ),
                    Text('07:30', style: TextStyle(fontSize: 50.sp, fontWeight: FontWeight.w800, color: s.primary, shadows: [Shadow(color: s.primary, blurRadius: 16)])),
                  ],
                ),
              ),
            ),
            SizedBox(height: 14.h),
            _shiftLabel(s, '야간 근무'),
            const Spacer(flex: 3),
            Row(
              children: [
                Expanded(child: _chevronButton(s, '5분 후', filled: false)),
                SizedBox(width: 14.w),
                Expanded(child: _chevronButton(s, '끄기', filled: true)),
              ],
            ),
            SizedBox(height: 18.h),
            Text('◁▷ 좌우로 스와이프해서 끄기', style: TextStyle(fontSize: 10.sp, color: s.onBg.withValues(alpha: 0.6), letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  // ⭐ 5번 - 진짜 알람시계 베젤 + LED 표시등 + 큼직한 사각 키.
  Widget _lockRetroDigital(_ConceptSpec s) {
    final w = 280.w;
    final h = 580.h;
    return _phoneFrame(
      width: w,
      height: h,
      bg: s.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18.w, 36.h, 18.w, 24.h),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ledDot(s.primary, on: true),
                SizedBox(width: 8.w),
                Text('ALARM', style: TextStyle(fontSize: 11.sp, color: s.primary, letterSpacing: 3, fontWeight: FontWeight.w700)),
                SizedBox(width: 8.w),
                _ledDot(s.secondary, on: true),
              ],
            ),
            const Spacer(flex: 2),
            // 베젤(물리 시계 프레임)
            Container(
              padding: EdgeInsets.symmetric(vertical: 22.h, horizontal: 14.w),
              decoration: BoxDecoration(
                color: const Color(0xFF08120A),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: s.primary.withValues(alpha: 0.35), width: 3),
              ),
              child: Column(
                children: [
                  Text(
                    '07:30',
                    style: TextStyle(
                      fontSize: 54.sp,
                      fontWeight: FontWeight.w900,
                      color: s.primary,
                      letterSpacing: 4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: [Shadow(color: s.primary.withValues(alpha: 0.8), blurRadius: 14)],
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text('PM', style: TextStyle(fontSize: 12.sp, color: s.secondary, letterSpacing: 2)),
                ],
              ),
            ),
            SizedBox(height: 14.h),
            _shiftLabel(s, '야간 근무'),
            const Spacer(flex: 3),
            Row(
              children: [
                Expanded(child: _retroKey(s, '5분 후', filled: false)),
                SizedBox(width: 10.w),
                Expanded(child: _retroKey(s, '끄기', filled: true)),
              ],
            ),
            SizedBox(height: 16.h),
            Text('← 좌우로 스와이프해서 끄기', style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ⭐ 7번 - 시간을 원형 엠보싱 다이얼 안에, 버튼도 원형.
  Widget _lockDarkNeumorphism(_ConceptSpec s) {
    final w = 280.w;
    final h = 580.h;
    return _phoneFrame(
      width: w,
      height: h,
      bg: s.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 36.h, 20.w, 28.h),
        child: Column(
          children: [
            _statusPill(s, '알람'),
            const Spacer(flex: 2),
            Container(
              width: 210.w,
              height: 210.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.bg,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(9, 9)),
                  BoxShadow(color: Colors.white.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(-9, -9)),
                ],
              ),
              alignment: Alignment.center,
              child: Container(
                width: 168.w,
                height: 168.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.bg,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 10, offset: const Offset(-5, -5)),
                    BoxShadow(color: s.secondary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(5, 5)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text('07:30', style: TextStyle(fontSize: 34.sp, fontWeight: FontWeight.w700, color: s.onBg)),
              ),
            ),
            SizedBox(height: 16.h),
            _shiftLabel(s, '야간 근무'),
            const Spacer(flex: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _neumorphicRoundButton(s, Icons.snooze_rounded, '5분 후', filled: false),
                SizedBox(width: 28.w),
                _neumorphicRoundButton(s, Icons.close_rounded, '끄기', filled: true),
              ],
            ),
            SizedBox(height: 18.h),
            _swipeHint(s),
          ],
        ),
      ),
    );
  }

  // ⭐ 8번 - 대각선 분할 포스터 + 슬랩 숫자 + 두꺼운 사각 버튼.
  Widget _lockBoldBlocks(_ConceptSpec s) {
    final w = 280.w;
    final h = 580.h;
    return _phoneFrame(
      width: w,
      height: h,
      bg: s.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _DiagonalSplitClipper(),
              child: Container(color: s.primary),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 36.h, 20.w, 24.h),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _statusPill(s, '알람'),
                ),
                const Spacer(flex: 2),
                Text(
                  '07:30',
                  style: TextStyle(fontSize: 66.sp, fontWeight: FontWeight.w900, color: Colors.black, height: 0.95, letterSpacing: -1),
                ),
                SizedBox(height: 10.h),
                _shiftLabel(s, '야간 근무'),
                const Spacer(flex: 3),
                Row(
                  children: [
                    Expanded(child: _pillButton(s, '5분 후', filled: false)),
                    SizedBox(width: 12.w),
                    Expanded(child: _pillButton(s, '끄기', filled: true)),
                  ],
                ),
                SizedBox(height: 16.h),
                _swipeHint(s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 홈 화면(해제 상태) 오버레이 알람
  // ============================================================
  Widget _buildOverlay(_ConceptSpec s) {
    final w = 280.w;
    final h = 340.h;

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(28.r)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: 140.h, left: 20.w, right: 20.w),
              child: Wrap(
                spacing: 18.w,
                runSpacing: 18.h,
                children: List.generate(
                  8,
                  (i) => Container(width: 40.w, height: 40.w, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10.r))),
                ),
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _overlayCard(s)),
        ],
      ),
    );
  }

  Widget _overlayCard(_ConceptSpec s) {
    switch (s.family) {
      case _Family.monochrome:
        return Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 14.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('07:30', style: TextStyle(fontSize: 30.sp, fontWeight: FontWeight.w200, color: Colors.black)),
                  SizedBox(width: 10.w),
                  Padding(padding: EdgeInsets.only(bottom: 6.h), child: Text('야간 근무', style: TextStyle(fontSize: 12.sp, color: Colors.black54))),
                ],
              ),
              SizedBox(height: 10.h),
              Divider(color: Colors.black12, height: 1),
              SizedBox(height: 10.h),
              Row(
                children: [
                  Text('5분 후', style: TextStyle(fontSize: 13.sp, color: Colors.black54, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('끄기', style: TextStyle(fontSize: 13.sp, color: Colors.black, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
                ],
              ),
            ],
          ),
        );

      case _Family.neonCyber:
        return Container(
          decoration: BoxDecoration(color: s.bg, border: Border(bottom: BorderSide(color: s.primary, width: 2))),
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 12.h),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('07:30', style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.w800, color: s.primary, shadows: [Shadow(color: s.primary, blurRadius: 12)])),
                    SizedBox(height: 4.h),
                    _shiftLabel(s, '야간 근무'),
                  ],
                ),
              ),
              _chevronButton(s, '끄기', filled: true, dense: true),
            ],
          ),
        );

      case _Family.retroDigital:
        return Container(
          decoration: BoxDecoration(color: const Color(0xFF08120A), border: Border.all(color: s.primary.withValues(alpha: 0.4), width: 2)),
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 12.h),
          child: Row(
            children: [
              _ledDot(s.primary, on: true),
              SizedBox(width: 10.w),
              Expanded(
                child: Text('07:30', style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.w900, color: s.primary, letterSpacing: 2)),
              ),
              _retroKey(s, '끄기', filled: true, dense: true),
            ],
          ),
        );

      case _Family.darkNeumorphism:
        return Container(
          color: s.bg,
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 12.h),
          child: Row(
            children: [
              Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.bg,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(4, 4)),
                    BoxShadow(color: Colors.white.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(-4, -4)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text('7:30', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: s.onBg)),
              ),
              SizedBox(width: 12.w),
              Expanded(child: _shiftLabel(s, '야간 근무')),
              _neumorphicRoundButton(s, Icons.close_rounded, '끄기', filled: true, dense: true),
            ],
          ),
        );

      case _Family.boldBlocks:
        return Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black, width: 4))),
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 12.h),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('07:30', style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.w900, color: Colors.black)),
                    SizedBox(height: 4.h),
                    _shiftLabel(s, '야간 근무'),
                  ],
                ),
              ),
              _smallActionButtons(s),
            ],
          ),
        );

      default:
        BoxDecoration deco = BoxDecoration(
          color: s.family == _Family.glass ? null : s.bg,
          gradient: (s.family == _Family.aurora || s.family == _Family.glass)
              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient!)
              : null,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24.r)),
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
  }

  // ============================================================
  // 공용 조각들 - 1/4/6/9/10번(그대로 유지)과 몇몇 새 콘셉트가 같이 씀
  // ============================================================

  Widget _phoneFrame({required double width, required double height, required Color bg, List<Color>? gradient, required Widget child}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient != null ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: gradient) : null,
        borderRadius: BorderRadius.circular(36.r),
        border: Border.all(color: Colors.black87, width: 8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _hudBracketFrame({required Color color, required Widget child}) {
    return Stack(
      children: [
        Positioned(top: 0, left: 0, child: _cornerMark(color, top: true, left: true)),
        Positioned(top: 0, right: 0, child: _cornerMark(color, top: true, left: false)),
        Positioned(bottom: 0, left: 0, child: _cornerMark(color, top: false, left: true)),
        Positioned(bottom: 0, right: 0, child: _cornerMark(color, top: false, left: false)),
        child,
      ],
    );
  }

  Widget _cornerMark(Color color, {required bool top, required bool left}) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _CornerPainter(color: color, top: top, left: left)),
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
    return Text(text, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: s.onBg.withValues(alpha: 0.7), letterSpacing: 2));
  }

  Widget _bigTime(_ConceptSpec s, String time, {required bool big}) {
    final fontSize = big ? 56.sp : 30.sp;
    return Text(time, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: s.onBg));
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
        child: const Text('야간 근무', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
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
    final radius = s.family == _Family.boldBlocks ? BorderRadius.circular(4.r) : BorderRadius.circular(30.r);

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
        boxShadow: filled && (s.family == _Family.aurora || s.family == _Family.softPastel || s.family == _Family.materialYou)
            ? [BoxShadow(color: s.primary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))]
            : null,
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
    return Column(
      children: [
        Icon(Icons.keyboard_double_arrow_up_rounded, size: 18.sp, color: s.onBg.withValues(alpha: 0.5)),
        SizedBox(height: 2.h),
        Text('위로 스와이프해서 끄기', style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.5))),
      ],
    );
  }

  // ---- 새 콘셉트 전용 버튼 모양들 ----

  Widget _chevronButton(_ConceptSpec s, String label, {required bool filled, bool dense = false}) {
    return Container(
      padding: dense ? EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h) : EdgeInsets.symmetric(vertical: 13.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? s.primary.withValues(alpha: 0.15) : Colors.transparent,
        border: Border(left: BorderSide(color: s.primary, width: 2), right: BorderSide(color: s.primary, width: 2)),
      ),
      child: Text(
        '〈 $label 〉',
        style: TextStyle(fontSize: dense ? 11.sp : 13.sp, fontWeight: FontWeight.w700, color: filled ? s.primary : s.onBg.withValues(alpha: 0.8), letterSpacing: 1),
      ),
    );
  }

  Widget _retroKey(_ConceptSpec s, String label, {required bool filled, bool dense = false}) {
    return Container(
      padding: dense ? EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h) : EdgeInsets.symmetric(vertical: 14.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? s.primary.withValues(alpha: 0.18) : const Color(0xFF16281A),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: s.primary.withValues(alpha: filled ? 0.9 : 0.4), width: 1.6),
      ),
      child: Text(label, style: TextStyle(fontSize: dense ? 11.sp : 13.sp, fontWeight: FontWeight.w800, color: s.primary, letterSpacing: 1)),
    );
  }

  Widget _neumorphicRoundButton(_ConceptSpec s, IconData icon, String label, {required bool filled, bool dense = false}) {
    final size = dense ? 40.w : 56.w;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.bg,
            boxShadow: filled
                ? [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 8, offset: const Offset(-4, -4)),
                    BoxShadow(color: s.secondary.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(4, 4)),
                  ]
                : [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(4, 4)),
                    BoxShadow(color: Colors.white.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(-4, -4)),
                  ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: dense ? 18.sp : 22.sp, color: filled ? s.secondary : s.primary),
        ),
        if (!dense) ...[
          SizedBox(height: 6.h),
          Text(label, style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.7))),
        ],
      ],
    );
  }

  Widget _ledDot(Color color, {required bool on}) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? color : color.withValues(alpha: 0.2),
        boxShadow: on ? [BoxShadow(color: color, blurRadius: 6)] : null,
      ),
    );
  }
}

// ============================================================
// 커스텀 클리퍼/페인터 - 아이콘/배경 조형용
// ============================================================

class _HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.25)
      ..lineTo(w, h * 0.75)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.75)
      ..lineTo(0, h * 0.25)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// 볼드 블록(8번) 배경의 대각선 색면 분할.
class _DiagonalSplitClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.55)
      ..lineTo(0, size.height * 0.75)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// 머티리얼 유(10번) 아이콘의 비대칭 blob 컨테이너.
class _BlobClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(w * 0.32, 0)
      ..quadraticBezierTo(w, 0, w, h * 0.38)
      ..quadraticBezierTo(w, h, w * 0.62, h)
      ..quadraticBezierTo(0, h, 0, h * 0.6)
      ..quadraticBezierTo(0, h * 0.05, w * 0.32, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// 네온 사이버 HUD 프레임의 모서리 브래킷.
class _CornerPainter extends CustomPainter {
  final Color color;
  final bool top;
  final bool left;
  _CornerPainter({required this.color, required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    final y = top ? 0.0 : size.height;
    final x = left ? 0.0 : size.width;
    final dy = top ? size.height * 0.6 : -size.height * 0.6;
    final dx = left ? size.width * 0.6 : -size.width * 0.6;
    path.moveTo(x, y + dy);
    path.lineTo(x, y);
    path.lineTo(x + dx, y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 라인 아트(9번) 아이콘의 손그림풍 종 - 채움 없이 얇은 선으로만.
class _LineBellPainter extends CustomPainter {
  final Color color;
  _LineBellPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;

    final bell = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..cubicTo(w * 0.22, h * 0.1, w * 0.2, h * 0.42, w * 0.18, h * 0.62)
      ..lineTo(w * 0.1, h * 0.74)
      ..lineTo(w * 0.9, h * 0.74)
      ..lineTo(w * 0.82, h * 0.62)
      ..cubicTo(w * 0.8, h * 0.42, w * 0.78, h * 0.1, w * 0.5, h * 0.08)
      ..close();
    canvas.drawPath(bell, paint);

    canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, h * 0.8), width: w * 0.22, height: h * 0.16), 0, 3.14159, false, paint);

    // 옆의 작은 반원 악센트(손그림풍 장식)
    canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.88, h * 0.22), width: w * 0.18, height: w * 0.18), -1.2, 2.2, false, paint..color = color.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
