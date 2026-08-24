// lib/screens/ui_theme_lab_screen.dart
//
// ⭐ 2026-08-25 추가 - "UI 테마" 탭. 지금 앱의 알람 화면(잠금화면/홈 화면 오버레이)과
// 앱 아이콘 디자인이 마음에 안 든다는 요청으로, 실제로 갈아끼우기 전에 방향을
// 먼저 눈으로 비교해보기 위한 임시 디자인 탐색 화면.
//
// ⚠️ 이 화면은 순수하게 "그림"만 그림 - 스와이프로 끄기/스누즈/알람 재생 같은
// 실제 동작은 전혀 안 붙어 있음(버튼을 눌러도 아무 일도 안 일어남). 마음에 드는
// 번호가 정해지면 그 디자인을 AlarmActivity.kt/AlarmOverlayService.kt(실제 알람
// 화면)와 앱 아이콘 리소스에 옮겨 적용하고 이 탭 자체는 삭제할 예정 - 그래서
// l10n(app_ko.arb/app_en.arb) 라운드트립 없이 한국어 문자열을 직접 씀(임시
// 화면이라는 걸 알고 하는 의도적 예외).
//
// ⭐ 2026-08-25 세 번째 개정 - 처음 10개 콘셉트 중 "1/4/6/9번이 낫다"는 판단으로
// 나머지(모노크롬/네온/레트로/뉴모피즘/볼드블록/머티리얼유)를 전부 삭제하고 4개로
// 좁힘. 이 4개는 이제 구조(아이콘 모양/잠금화면 레이아웃/오버레이 레이아웃)를
// 전부 "소프트 파스텔"(옛 4번) 하나로 통일하고, 색상/톤만 테마마다 다르게 함 -
// 그래서 예전처럼 family별로 완전히 다른 위젯 트리를 그리던 코드를 걷어내고,
// 공용 포맷 하나(_buildIcon/_buildLockScreen/_buildOverlay)에 _ConceptSpec의
// 색 토큰만 꽂아 넣는 구조로 단순화함. 유일하게 의도적으로 다르게 남긴 지점은
// "5분 후"(스누즈) 버튼의 표현 방식 - 테마마다 하나씩 다른 안을 실험 중
// (_SnoozeStyle 참고, 요청받은 5안 중 테마가 4개뿐이라 앞 4개만 적용함).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../widgets/app_shift_chip.dart';

/// ⭐ "5분 후" 버튼을 테마마다 다르게 실험해보기 위한 표현 방식.
enum _SnoozeStyle {
  current, // 기존: 달(취침) 아이콘 + "5분 후" 텍스트 라벨
  iconOnly, // "Z" 느낌의 스누즈 아이콘만(라벨 없음)
  plusFive, // "+5" 텍스트만
  plusFiveM, // "+5m" 텍스트만
}

class _ConceptSpec {
  final int number;
  final String name;
  final String tagline;
  final Color bg; // 화면/카드 바탕
  final Color surface; // 카드/버튼 표면
  final Color primary; // 주 강조색
  final Color secondary; // 보조 강조색(아이콘 배지 등)
  final Color onBg; // 바탕 위 기본 글자색
  final Color onSurface; // 표면 위 기본 글자색
  final List<Color>? gradient; // 배경에 그라데이션을 쓰는 테마만(색상 데이터일 뿐, 구조는 동일)
  final _SnoozeStyle snoozeStyle;

  const _ConceptSpec({
    required this.number,
    required this.name,
    required this.tagline,
    required this.bg,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.onBg,
    required this.onSurface,
    this.gradient,
    required this.snoozeStyle,
  });
}

const List<_ConceptSpec> _conceptSpecs = [
  _ConceptSpec(
    number: 1,
    name: '오로라 그라데이션',
    tagline: '보라~파랑~청록 그라데이션 톤. 스누즈 버튼: 기존 그대로(아이콘+"5분 후").',
    bg: Color(0xFF1B1035),
    surface: Color(0x22FFFFFF),
    primary: Color(0xFF7C4DFF),
    secondary: Color(0xFF00E5C7),
    onBg: Colors.white,
    onSurface: Colors.white,
    gradient: [Color(0xFF6A3DE8), Color(0xFF3D7BF5), Color(0xFF00D9C7)],
    snoozeStyle: _SnoozeStyle.current,
  ),
  _ConceptSpec(
    number: 2,
    name: '소프트 파스텔',
    tagline: '블루 파스텔 톤. 스누즈 버튼: "Z" 아이콘만(라벨 없음).',
    bg: Color(0xFFEAF1FC),
    surface: Colors.white,
    primary: Color(0xFF6B93E0),
    secondary: Color(0xFFFFB4A2),
    onBg: Color(0xFF2A3B5C),
    onSurface: Color(0xFF2A3B5C),
    snoozeStyle: _SnoozeStyle.iconOnly,
  ),
  _ConceptSpec(
    number: 3,
    name: '글래스모피즘',
    tagline: '화사한 배경 위 반투명 유리 톤. 스누즈 버튼: "+5" 텍스트만.',
    bg: Color(0xFF4B6FE0),
    surface: Color(0x33FFFFFF),
    primary: Colors.white,
    secondary: Color(0xFFFFE08A),
    onBg: Colors.white,
    onSurface: Colors.white,
    gradient: [Color(0xFF4B6FE0), Color(0xFF8A5CF5), Color(0xFFE05C97)],
    snoozeStyle: _SnoozeStyle.plusFive,
  ),
  _ConceptSpec(
    number: 4,
    name: '라인 아트',
    tagline: '아이보리+테라코타 톤. 스누즈 버튼: "+5m" 텍스트만.',
    bg: Color(0xFFFBF6EC),
    surface: Color(0xFFFBF6EC),
    primary: Color(0xFFB2543A),
    secondary: Color(0xFF3A6E8F),
    onBg: Color(0xFF3A2E27),
    onSurface: Color(0xFF3A2E27),
    snoozeStyle: _SnoozeStyle.plusFiveM,
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
  // 앱 아이콘 - 전 테마 공통 조형(둥근 사각 + 시계 + 2시 방향 알림 배지),
  // 색상만 s.primary/s.secondary로 교체됨.
  // ============================================================
  Widget _buildIcon(_ConceptSpec s) {
    final size = 104.w;
    final radius = 24.r;

    final deco = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: s.gradient == null ? s.primary : null,
      gradient: s.gradient != null ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient!) : null,
      boxShadow: [BoxShadow(color: s.primary.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8))],
    );

    return Container(
      width: size,
      height: size,
      decoration: deco,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.watch_later_rounded, size: size * 0.52, color: Colors.white),
          Positioned(
            top: size * 0.02,
            right: size * 0.02,
            child: Container(
              width: size * 0.19,
              height: size * 0.19,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: s.secondary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: Icon(Icons.notifications_active_rounded, size: size * 0.11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 잠금화면 알람 - 전 테마 공통 레이아웃(원형 다이얼 + 원형 버튼 2개),
  // 색상만 다름. 유일한 변주는 스누즈 버튼 표현(_snoozeControl).
  // ============================================================
  Widget _buildLockScreen(_ConceptSpec s) {
    final w = 280.w;
    final h = 580.h;
    return _phoneFrame(
      width: w,
      height: h,
      bg: s.bg,
      gradient: s.gradient,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 40.h, 20.w, 28.h),
        child: Column(
          children: [
            Text('알람', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: s.onBg.withValues(alpha: 0.7), letterSpacing: 2)),
            const Spacer(flex: 2),
            Container(
              width: 200.w,
              height: 200.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: s.primary, width: 3),
                boxShadow: [BoxShadow(color: s.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              alignment: Alignment.center,
              child: Text('07:30', style: TextStyle(fontSize: 30.sp, fontWeight: FontWeight.w800, color: s.primary)),
            ),
            SizedBox(height: 16.h),
            _shiftLabel(s, '야간 근무'),
            const Spacer(flex: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _snoozeSlot(s, dense: false),
                SizedBox(width: 28.w),
                _labeledRoundButton(s, Icons.close_rounded, '끄기', filled: true),
              ],
            ),
            SizedBox(height: 18.h),
            Column(
              children: [
                Icon(Icons.keyboard_double_arrow_up_rounded, size: 18.sp, color: s.onBg.withValues(alpha: 0.5)),
                SizedBox(height: 2.h),
                Text('위로 스와이프해서 끄기', style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.5))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 홈 화면(해제 상태) 오버레이 알람 - 전 테마 공통 레이아웃, 색상만 다름.
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
    final deco = BoxDecoration(
      color: s.gradient == null ? s.bg : null,
      gradient: s.gradient != null ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient!) : null,
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
                Text('07:30', style: TextStyle(fontSize: 30.sp, fontWeight: FontWeight.w800, color: s.onBg)),
                SizedBox(height: 4.h),
                _shiftLabel(s, '야간 근무'),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _snoozeSlot(s, dense: true),
              SizedBox(width: 8.w),
              _iconCircleButton(s, Icons.close_rounded, filled: true),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 공용 조각들
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

  Widget _shiftLabel(_ConceptSpec s, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
      decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(20.r)),
      child: Text(label, style: TextStyle(fontSize: 12.sp, color: s.onSurface, fontWeight: FontWeight.w600)),
    );
  }

  Widget _iconCircleButton(_ConceptSpec s, IconData icon, {required bool filled}) {
    final bg = filled ? s.primary : s.surface;
    final fg = filled ? Colors.white : s.onSurface;
    return Container(
      width: 40.w,
      height: 40.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 20.sp, color: fg),
    );
  }

  Widget _labeledRoundButton(_ConceptSpec s, IconData icon, String label, {required bool filled}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56.w,
          height: 56.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: filled ? s.primary : s.surface, shape: BoxShape.circle),
          child: Icon(icon, size: 22.sp, color: filled ? Colors.white : s.onSurface),
        ),
        SizedBox(height: 6.h),
        Text(label, style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.7))),
      ],
    );
  }

  // ⭐ 테마마다 실험 중인 "5분 후" 표현. dense=true면 오버레이(작은 아이콘 버튼)용,
  // false면 잠금화면(큰 원형 버튼 + 라벨)용.
  Widget _snoozeSlot(_ConceptSpec s, {required bool dense}) {
    switch (s.snoozeStyle) {
      case _SnoozeStyle.current:
        return dense ? _iconCircleButton(s, Icons.bedtime_rounded, filled: false) : _labeledRoundButton(s, Icons.bedtime_rounded, '5분 후', filled: false);
      case _SnoozeStyle.iconOnly:
        return dense
            ? _iconCircleButton(s, Icons.snooze_rounded, filled: false)
            : Container(
                width: 56.w,
                height: 56.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: s.surface, shape: BoxShape.circle),
                child: Icon(Icons.snooze_rounded, size: 26.sp, color: s.onSurface),
              );
      case _SnoozeStyle.plusFive:
      case _SnoozeStyle.plusFiveM:
        final text = s.snoozeStyle == _SnoozeStyle.plusFive ? '+5' : '+5m';
        final size = dense ? 40.w : 56.w;
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: s.surface, shape: BoxShape.circle, border: Border.all(color: s.primary.withValues(alpha: 0.5), width: 1.4)),
          child: Text(text, style: TextStyle(fontSize: dense ? 11.sp : 15.sp, fontWeight: FontWeight.w800, color: s.primary)),
        );
    }
  }
}
