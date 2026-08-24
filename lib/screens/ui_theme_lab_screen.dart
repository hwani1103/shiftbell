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
// ⭐ 세 번째 개정 - 처음 10개 콘셉트 중 "1/4/6/9번이 낫다"는 판단으로 나머지를
// 전부 삭제하고 4개로 좁힘. 이 4개는 아이콘/잠금화면/오버레이 구조를 전부
// 하나로 통일하고, 색상/톤만 테마마다 다르게 함.
//
// ⭐ 네 번째 개정(2026-08-25) - "5분 후" 스누즈 표현 실험(4가지 안)을 종료하고
// "+5m" 하나로 확정. 단 잠금화면에서는 옆의 "끄기" 버튼과 구조(원형버튼+라벨)를
// 맞추기 위해 "+5m" 원 아래에도 "5분 후" 라벨을 다시 붙임. 그리고 새로 두 가지를
// 추가함: (1) 4개 테마 각각에 "다음 알람" 탭(lib/screens/next_alarm_tab.dart) 목업을
// 붙임 - 아이콘/잠금화면/오버레이와 달리 이 목업들은 레이아웃 자체를 테마마다
// 의도적으로 다르게 설계함(오로라=원형 스탯/히어로카드, 파스텔=시계판+대시보드
// 타일, 글래스모피즘=반투명 배너+카드, 라인아트=카드 없는 미니멀 리스트). (2) 선택
// 칩에 "5번"(아이콘 색상 갤러리) 슬롯을 추가 - 배경색/시계색/종색 조합 30가지를
// 번호 매겨 스크롤로 훑어볼 수 있는 화면.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../widgets/app_shift_chip.dart';

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
  });
}

const List<_ConceptSpec> _conceptSpecs = [
  _ConceptSpec(
    number: 1,
    name: '오로라 그라데이션',
    tagline: '보라~파랑~청록 그라데이션 톤. 다음 알람 탭: 히어로 카드 + 원형 카운트다운 스탯.',
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
    name: '소프트 파스텔',
    tagline: '블루 파스텔 톤. 다음 알람 탭: 시계판 원 + 대시보드 타일 2개.',
    bg: Color(0xFFEAF1FC),
    surface: Colors.white,
    primary: Color(0xFF6B93E0),
    secondary: Color(0xFFFFB4A2),
    onBg: Color(0xFF2A3B5C),
    onSurface: Color(0xFF2A3B5C),
  ),
  _ConceptSpec(
    number: 3,
    name: '글래스모피즘',
    tagline: '화사한 배경 위 반투명 유리 톤. 다음 알람 탭: 유리 배너 + 유리 히어로 카드.',
    bg: Color(0xFF4B6FE0),
    surface: Color(0x33FFFFFF),
    primary: Colors.white,
    secondary: Color(0xFFFFE08A),
    onBg: Colors.white,
    onSurface: Colors.white,
    gradient: [Color(0xFF4B6FE0), Color(0xFF8A5CF5), Color(0xFFE05C97)],
  ),
  _ConceptSpec(
    number: 4,
    name: '라인 아트',
    tagline: '아이보리+테라코타 톤. 다음 알람 탭: 카드 없는 미니멀 리스트형.',
    bg: Color(0xFFFBF6EC),
    surface: Color(0xFFFBF6EC),
    primary: Color(0xFFB2543A),
    secondary: Color(0xFF3A6E8F),
    onBg: Color(0xFF3A2E27),
    onSurface: Color(0xFF3A2E27),
  ),
];

/// 알람 타입 3종(소리+진동/진동/무음) - 다음 알람 탭 목업 전체에서 공용으로 씀.
const List<String> _alarmTypeLabels = ['소리+진동', '진동', '무음'];
const List<IconData> _alarmTypeIcons = [
  Icons.volume_up_rounded,
  Icons.vibration_rounded,
  Icons.notifications_off_rounded,
];

/// ⭐ 5번 슬롯(아이콘 색상 갤러리) 항목 하나 - 배경색/시계색/종색 조합.
class _IconPalette {
  final int number;
  final Color bg;
  final Color clock;
  final Color bell;
  const _IconPalette(this.number, this.bg, this.clock, this.bell);
}

const List<_IconPalette> _iconPalettes = [
  _IconPalette(1, Color(0xFF3F51B5), Colors.white, Color(0xFFFFC107)),
  _IconPalette(2, Color(0xFF00695C), Colors.white, Color(0xFFFF7043)),
  _IconPalette(3, Color(0xFF1A237E), Color(0xFF90CAF9), Colors.white),
  _IconPalette(4, Color(0xFF263238), Colors.white, Color(0xFF26A69A)),
  _IconPalette(5, Color(0xFF5E35B1), Colors.white, Color(0xFFFFD54F)),
  _IconPalette(6, Color(0xFF2E7D32), Colors.white, Color(0xFFFFAB91)),
  _IconPalette(7, Color(0xFFE65100), Colors.white, Color(0xFF00796B)),
  _IconPalette(8, Color(0xFF455A64), Color(0xFFFFF176), Colors.white),
  _IconPalette(9, Color(0xFF880E4F), Colors.white, Color(0xFFFFCA28)),
  _IconPalette(10, Color(0xFF0277BD), Colors.white, Color(0xFFFF8A65)),
  _IconPalette(11, Color(0xFF6A1B9A), Color(0xFFCE93D8), Colors.white),
  _IconPalette(12, Color(0xFF827717), Color(0xFFFFF9C4), Colors.white),
  _IconPalette(13, Color(0xFF0288D1), Color(0xFF0D47A1), Colors.white),
  _IconPalette(14, Color(0xFFBF360C), Colors.white, Color(0xFFFFE0B2)),
  _IconPalette(15, Color(0xFF4527A0), Colors.white, Color(0xFF4DD0E1)),
  _IconPalette(16, Color(0xFF00897B), Colors.white, Color(0xFFFF8A80)),
  _IconPalette(17, Color(0xFF1A237E), Color(0xFFFFD700), Colors.white),
  _IconPalette(18, Color(0xFFFF7043), Colors.white, Color(0xFF1565C0)),
  _IconPalette(19, Color(0xFF37474F), Colors.white, Color(0xFFC0CA33)),
  _IconPalette(20, Color(0xFFAD1457), Colors.white, Color(0xFF80CBC4)),
  _IconPalette(21, Color(0xFF376DA8), Colors.white, Color(0xFFFF9800)),
  _IconPalette(22, Color(0xFF4A148C), Color(0xFFF48FB1), Colors.white),
  _IconPalette(23, Color(0xFF1B5E20), Colors.white, Color(0xFFFDD835)),
  _IconPalette(24, Color(0xFFD84315), Colors.white, Color(0xFF00838F)),
  _IconPalette(25, Color(0xFF283593), Colors.white, Color(0xFFFF80AB)),
  _IconPalette(26, Color(0xFF4E342E), Color(0xFFFFF3E0), Colors.white),
  _IconPalette(27, Color(0xFF01579B), Colors.white, Color(0xFFFFB300)),
  _IconPalette(28, Color(0xFF7B1FA2), Colors.white, Color(0xFFAEEA00)),
  _IconPalette(29, Color(0xFFC2185B), Colors.white, Color(0xFF4FC3F7)),
  _IconPalette(30, Color(0xFF0D47A1), Colors.white, Color(0xFFFFEB3B)),
];

class UiThemeLabScreen extends StatefulWidget {
  const UiThemeLabScreen({super.key});

  @override
  State<UiThemeLabScreen> createState() => _UiThemeLabScreenState();
}

class _UiThemeLabScreenState extends State<UiThemeLabScreen> {
  int _selected = 1; // 1..4 = 테마, 5 = 아이콘 색상 갤러리

  @override
  Widget build(BuildContext context) {
    final isGallery = _selected == 5;
    final spec = isGallery ? null : _conceptSpecs.firstWhere((s) => s.number == _selected);

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
                itemCount: 5,
                separatorBuilder: (_, __) => SizedBox(width: 8.w),
                itemBuilder: (context, index) {
                  final n = index + 1;
                  return AppShiftChip(
                    label: n == 5 ? '아이콘' : '$n',
                    selected: n == _selected,
                    onTap: () => setState(() => _selected = n),
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
                    isGallery ? '5. 아이콘 색상 갤러리' : '${spec!.number}. ${spec.name}',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    isGallery ? '배경색 · 시계색 · 종 색 조합 30가지 - 번호를 보고 마음에 드는 걸 골라주세요.' : spec!.tagline,
                    style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: isGallery ? _buildIconGallery() : _buildThemeSections(spec!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSections(_ConceptSpec spec) {
    return Column(
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
        SizedBox(height: 32.h),
        _sectionLabel('다음 알람 탭'),
        SizedBox(height: 12.h),
        _buildNextAlarmTab(spec),
        SizedBox(height: 24.h),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.grey.shade600));
  }

  // ============================================================
  // 5번 슬롯 - 아이콘 색상 갤러리 (배경/시계/종 색 조합 30개)
  // ============================================================
  Widget _buildIconGallery() {
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 22.h,
        crossAxisSpacing: 10.w,
        childAspectRatio: 0.8,
      ),
      itemCount: _iconPalettes.length,
      itemBuilder: (context, i) {
        final p = _iconPalettes[i];
        return Column(
          children: [
            _iconPreview(bg: p.bg, clockColor: p.clock, bellColor: p.bell, size: 72.w),
            SizedBox(height: 6.h),
            Text('${p.number}', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          ],
        );
      },
    );
  }

  /// 아이콘 갤러리 전용 - 그라데이션 없이 순수 단색 3요소(배경/시계/종)만으로
  /// 그리는 축소판 아이콘. `_buildIcon`(테마별 아이콘, 그라데이션 지원)과는 별도.
  Widget _iconPreview({required Color bg, required Color clockColor, required Color bellColor, required double size}) {
    final borderWidth = (size / 104 * 2).clamp(1.0, 2.5);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.23),
        color: bg,
        boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.4), blurRadius: size * 0.17, offset: Offset(0, size * 0.08))],
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.watch_later_rounded, size: size * 0.52, color: clockColor),
          Positioned(
            top: size * 0.02,
            right: size * 0.02,
            child: Container(
              width: size * 0.19,
              height: size * 0.19,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bellColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: borderWidth)),
              child: Icon(Icons.notifications_active_rounded, size: size * 0.11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
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
  // 잠금화면 알람 - 전 테마 공통 레이아웃(원형 다이얼 + 원형 버튼 2개), 색상만 다름.
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
                _snoozeButton(s, dense: false),
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
              _snoozeButton(s, dense: true),
              SizedBox(width: 8.w),
              _iconCircleButton(s, Icons.close_rounded, filled: true),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 다음 알람 탭 - 테마별로 레이아웃 자체를 다르게 설계(색상만 다른 게 아님).
  // 실제 lib/screens/next_alarm_tab.dart의 기능 요소를 모두 포함:
  // 날짜 라벨 · 큰 시간 · 근무 배지 · 남은 시간(카운트다운) · 알람 타입 3종 선택 ·
  // 전체 알람 보기 · 이 알람 끄기.
  // ============================================================
  Widget _buildNextAlarmTab(_ConceptSpec s) {
    switch (s.number) {
      case 1:
        return _nextAlarmAurora(s);
      case 2:
        return _nextAlarmPastel(s);
      case 3:
        return _nextAlarmGlass(s);
      default:
        return _nextAlarmLineArt(s);
    }
  }

  /// 1. 오로라 - 웨어러블 앱 느낌의 "히어로 카드 + 원형 스탯" 구성.
  Widget _nextAlarmAurora(_ConceptSpec s) {
    return _phoneFrame(
      width: 280.w,
      height: 640.h,
      bg: s.bg,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(22.w, 24.h, 22.w, 26.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient ?? [s.primary, s.primary]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28.r)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20.r)),
                  child: Text('오늘', style: TextStyle(fontSize: 11.sp, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                SizedBox(height: 14.h),
                Text('07:30', style: TextStyle(fontSize: 46.sp, fontWeight: FontWeight.w300, color: Colors.white)),
                SizedBox(height: 10.h),
                _shiftLabel(s, '야간 근무'),
              ],
            ),
          ),
          SizedBox(height: 24.h),
          Container(
            width: 128.w,
            height: 128.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: s.secondary, width: 4), color: s.surface),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_bottom_rounded, size: 18.sp, color: s.secondary),
                SizedBox(height: 4.h),
                Text('2시간 30분', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800, color: s.onBg)),
                Text('남음', style: TextStyle(fontSize: 10.sp, color: s.onBg.withValues(alpha: 0.6))),
              ],
            ),
          ),
          SizedBox(height: 6.h),
          Text('임박하면 이 링이 강조색으로 바뀜', style: TextStyle(fontSize: 10.sp, color: s.onBg.withValues(alpha: 0.4))),
          const Spacer(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(18.r)),
              child: Row(
                children: List.generate(3, (i) {
                  final selected = i == 0;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 2.w),
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      decoration: BoxDecoration(color: selected ? s.primary : Colors.transparent, borderRadius: BorderRadius.circular(14.r)),
                      alignment: Alignment.center,
                      child: Icon(_alarmTypeIcons[i], size: 16.sp, color: selected ? Colors.white : s.onBg.withValues(alpha: 0.5)),
                    ),
                  );
                }),
              ),
            ),
          ),
          SizedBox(height: 18.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: s.onBg.withValues(alpha: 0.3)),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
                    ),
                    icon: Icon(Icons.list_rounded, size: 16.sp, color: s.onBg),
                    label: Text('전체 보기', style: TextStyle(fontSize: 12.sp, color: s.onBg)),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE5484D),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
                    ),
                    icon: const Icon(Icons.alarm_off_rounded, size: 16, color: Colors.white),
                    label: Text('이 알람 끄기', style: TextStyle(fontSize: 12.sp, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 22.h),
        ],
      ),
    );
  }

  /// 2. 소프트 파스텔 - 잠금화면과 같은 "원형 시계판" 모티프 + 대시보드 타일 2개.
  Widget _nextAlarmPastel(_ConceptSpec s) {
    return _phoneFrame(
      width: 280.w,
      height: 640.h,
      bg: s.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22.w, 26.h, 22.w, 22.h),
        child: Column(
          children: [
            Row(
              children: [
                Text('다음 근무 알람', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: s.onBg)),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(20.r), border: Border.all(color: s.primary.withValues(alpha: 0.3))),
                  child: Text('오늘', style: TextStyle(fontSize: 11.sp, color: s.primary, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            SizedBox(height: 22.h),
            Container(
              width: 176.w,
              height: 176.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: s.primary, width: 3),
                boxShadow: [BoxShadow(color: s.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Center(child: Text('07:30', style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.w800, color: s.primary))),
            ),
            SizedBox(height: 12.h),
            _shiftLabel(s, '야간 근무'),
            SizedBox(height: 22.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(18.r)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.timer_outlined, size: 18.sp, color: s.secondary),
                        SizedBox(height: 8.h),
                        Text('알람까지', style: TextStyle(fontSize: 10.sp, color: s.onBg.withValues(alpha: 0.6))),
                        SizedBox(height: 2.h),
                        Text('2시간 30분', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: s.onBg)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(18.r)),
                    child: Column(
                      children: List.generate(3, (i) {
                        final selected = i == 0;
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 3.h),
                          child: Row(
                            children: [
                              Container(
                                width: 22.w,
                                height: 22.w,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: selected ? s.primary : Colors.transparent, shape: BoxShape.circle),
                                child: Icon(_alarmTypeIcons[i], size: 12.sp, color: selected ? Colors.white : s.onBg.withValues(alpha: 0.4)),
                              ),
                              SizedBox(width: 6.w),
                              Expanded(
                                child: Text(
                                  _alarmTypeLabels[i],
                                  style: TextStyle(fontSize: 10.sp, color: s.onBg.withValues(alpha: selected ? 0.9 : 0.5), fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: s.primary.withValues(alpha: 0.4)),
                  padding: EdgeInsets.symmetric(vertical: 13.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                ),
                icon: Icon(Icons.list_rounded, size: 16.sp, color: s.primary),
                label: Text('전체 알람 보기', style: TextStyle(fontSize: 12.sp, color: s.primary, fontWeight: FontWeight.w700)),
              ),
            ),
            SizedBox(height: 10.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE5787A),
                  padding: EdgeInsets.symmetric(vertical: 13.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                ),
                icon: const Icon(Icons.alarm_off_rounded, size: 16, color: Colors.white),
                label: Text('이 알람 끄기', style: TextStyle(fontSize: 12.sp, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. 글래스모피즘 - 반투명 상태 배너 + 유리 히어로 카드 + 유리 세그먼트.
  Widget _nextAlarmGlass(_ConceptSpec s) {
    return _phoneFrame(
      width: 280.w,
      height: 640.h,
      bg: s.bg,
      gradient: s.gradient,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 26.h, 20.w, 22.h),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16.sp, color: Colors.white),
                  SizedBox(width: 8.w),
                  Expanded(child: Text('2시간 30분 후 알람', style: TextStyle(fontSize: 12.sp, color: Colors.white, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            SizedBox(height: 18.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 26.h, horizontal: 20.w),
              decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(26.r), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20.r)),
                    child: Text('오늘', style: TextStyle(fontSize: 11.sp, color: Colors.white)),
                  ),
                  SizedBox(height: 14.h),
                  Text('07:30', style: TextStyle(fontSize: 42.sp, fontWeight: FontWeight.w300, color: Colors.white)),
                  SizedBox(height: 10.h),
                  _shiftLabel(s, '야간 근무'),
                ],
              ),
            ),
            SizedBox(height: 18.h),
            Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(18.r), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
              child: Row(
                children: List.generate(3, (i) {
                  final selected = i == 0;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 2.w),
                      padding: EdgeInsets.symmetric(vertical: 9.h),
                      decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: 0.3) : Colors.transparent, borderRadius: BorderRadius.circular(14.r)),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_alarmTypeIcons[i], size: 15.sp, color: Colors.white),
                          SizedBox(height: 3.h),
                          Text(_alarmTypeLabels[i], style: TextStyle(fontSize: 9.sp, color: Colors.white.withValues(alpha: selected ? 1 : 0.6))),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
                    alignment: Alignment.center,
                    child: Icon(Icons.list_rounded, size: 18.sp, color: Colors.white),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(16.r)),
                    alignment: Alignment.center,
                    child: Text('이 알람 끄기', style: TextStyle(fontSize: 12.sp, color: const Color(0xFFC0392B), fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 4. 라인 아트 - 카드/채움 없이 얇은 선과 여백만으로 구성한 에디토리얼 리스트.
  Widget _nextAlarmLineArt(_ConceptSpec s) {
    return _phoneFrame(
      width: 280.w,
      height: 640.h,
      bg: s.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24.w, 30.h, 24.w, 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20.r), border: Border.all(color: s.onBg.withValues(alpha: 0.3))),
              child: Text('오늘', style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.6))),
            ),
            SizedBox(height: 14.h),
            Text('07:30', style: TextStyle(fontSize: 48.sp, fontWeight: FontWeight.w200, color: s.onBg)),
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20.r), border: Border.all(color: s.primary.withValues(alpha: 0.5))),
              child: Text('야간 근무', style: TextStyle(fontSize: 11.sp, color: s.primary, fontWeight: FontWeight.w600)),
            ),
            SizedBox(height: 20.h),
            Divider(color: s.onBg.withValues(alpha: 0.15), height: 1),
            SizedBox(height: 16.h),
            Row(
              children: [
                Icon(Icons.hourglass_bottom_rounded, size: 16.sp, color: s.onBg.withValues(alpha: 0.5)),
                SizedBox(width: 8.w),
                Text('2시간 30분 남음', style: TextStyle(fontSize: 13.sp, color: s.onBg, fontWeight: FontWeight.w600)),
              ],
            ),
            SizedBox(height: 4.h),
            Text('알람 20분 전부터 강조 표시', style: TextStyle(fontSize: 10.sp, color: s.onBg.withValues(alpha: 0.4))),
            SizedBox(height: 16.h),
            Divider(color: s.onBg.withValues(alpha: 0.15), height: 1),
            SizedBox(height: 18.h),
            Text('알람 타입', style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.5), fontWeight: FontWeight.w600)),
            SizedBox(height: 10.h),
            Row(
              children: List.generate(3, (i) {
                final selected = i == 0;
                return Padding(
                  padding: EdgeInsets.only(right: 14.w),
                  child: Container(
                    width: 42.w,
                    height: 42.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? s.primary : Colors.transparent,
                      border: Border.all(color: selected ? s.primary : s.onBg.withValues(alpha: 0.3), width: 1.4),
                    ),
                    child: Icon(_alarmTypeIcons[i], size: 18.sp, color: selected ? Colors.white : s.onBg.withValues(alpha: 0.5)),
                  ),
                );
              }),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.list_alt_rounded, size: 14.sp, color: s.secondary),
                SizedBox(width: 6.w),
                Text('전체 알람 보기', style: TextStyle(fontSize: 12.sp, color: s.secondary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
              ],
            ),
            SizedBox(height: 16.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: s.primary),
                  padding: EdgeInsets.symmetric(vertical: 13.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.r)),
                ),
                icon: Icon(Icons.alarm_off_rounded, size: 16.sp, color: s.primary),
                label: Text('이 알람 끄기', style: TextStyle(fontSize: 12.sp, color: s.primary, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
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

  /// ⭐ "5분 후" 스누즈 버튼 - "+5m" 텍스트로 확정. dense=true면 오버레이(작은 원형,
  /// 라벨 없음 - 옆의 끄기 버튼도 라벨이 없어 구조가 맞음)용, false면 잠금화면(큰
  /// 원형 + 아래 "5분 후" 라벨 - 옆의 끄기 버튼(_labeledRoundButton)과 구조를
  /// 맞추기 위해 라벨을 반드시 붙임)용.
  Widget _snoozeButton(_ConceptSpec s, {required bool dense}) {
    final size = dense ? 40.w : 56.w;
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: s.surface, shape: BoxShape.circle, border: Border.all(color: s.primary.withValues(alpha: 0.5), width: 1.4)),
      child: Text('+5m', style: TextStyle(fontSize: dense ? 11.sp : 15.sp, fontWeight: FontWeight.w800, color: s.primary)),
    );
    if (dense) return circle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        SizedBox(height: 6.h),
        Text('5분 후', style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.7))),
      ],
    );
  }
}
