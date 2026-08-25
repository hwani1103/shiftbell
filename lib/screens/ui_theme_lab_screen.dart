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
// ⭐ 다섯 번째 개정(2026-08-25) - 잠금화면/오버레이에서 "오로라" 그라데이션과
// +5m/끄기 버튼 색이 서로 비슷해 묻히는 문제를 계기로, 아예 4개 테마를 전부
// "오로라 그라데이션 하나"의 명도/채도 단계별 변형(진하게→아주 밝게)으로
// 통일함. 톤(보라~파랑~청록)은 그대로 두고 각 그라데이션 색을 25%/50%/75%씩
// 흰색 쪽으로 섞어 4단계를 만듦 - 가장 밝은 4번은 그 위에 얹는 글씨/테두리
// (controlColor)를 흰색 대신 짙은 남색으로 바꿔서 가독성을 지킴. 그리고
// +5m/끄기 버튼 둘 다 배경과 구분되는 테두리(controlColor)를 추가해 어떤
// 밝기에서도 버튼 경계가 보이게 함. 아이콘 색상 갤러리는 30개 → 3개(1번 테마
// 아이콘 자체 + 팔레트 1번 + 팔레트 17번)로 정리. "다음 알람" 탭은 파스텔안
// (원형 시계 모티프)을 최종 레이아웃으로 채택하고, 그 원을 애니메이션 카운트다운
// 링(12시 방향에서 시작해 알람 시각에 가까워질수록 채워짐)으로 발전시킴 -
// 실 데이터가 없는 목업이라 8초 주기로 무한 반복하는 데모 애니메이션으로 대체.
// "오늘" 칩은 원 안, 시간 위로 이동. 테마별로 이 레이아웃을 그라데이션 배경
// 버전과 배경 없는(플랫) 버전 두 가지로 각각 만들어 비교할 수 있게 함.
// "전체 알람 보기"는 AppThirdButton, "이 알람 끄기"는 AppSecondButton(danger)
// 컨셉을 그대로 씀.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../widgets/app_second_button.dart';
import '../widgets/app_shift_chip.dart';
import '../widgets/app_third_button.dart';

class _ConceptSpec {
  final int number;
  final String name;
  final String tagline;
  final List<Color> gradient; // 보라~파랑~청록, 테마마다 명도만 다름
  final Color bg; // 그라데이션 없는(플랫) 버전에서 쓰는 단색 배경
  final Color surface; // 카드/버튼 표면
  final Color primary; // 주 강조색(뱃지 글자, 선택 아이콘 채움 등 - 밝기와 무관하게 항상 진하게 유지)
  final Color secondary; // 보조 강조색(아이콘 배지, 카운트다운 링 채움색)
  final Color onBg; // 배경(그라데이션/플랫 공통) 위 기본 글자색
  final Color onSurface; // 표면(카드) 위 기본 글자색
  final Color controlColor; // +5m/끄기 버튼의 테두리·글자색 - 배경과 항상 구분되게

  const _ConceptSpec({
    required this.number,
    required this.name,
    required this.tagline,
    required this.gradient,
    required this.bg,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.onBg,
    required this.onSurface,
    required this.controlColor,
  });
}

const List<_ConceptSpec> _conceptSpecs = [
  _ConceptSpec(
    number: 1,
    name: '오로라 · 진하게',
    tagline: '가장 진한 톤(원안). 텍스트/테두리는 흰색.',
    gradient: [Color(0xFF6A3DE8), Color(0xFF3D7BF5), Color(0xFF00D9C7)],
    bg: Color(0xFF1B1035),
    surface: Color(0x22FFFFFF),
    primary: Color(0xFF7C4DFF),
    secondary: Color(0xFF00E5C7),
    onBg: Colors.white,
    onSurface: Colors.white,
    controlColor: Colors.white,
  ),
  _ConceptSpec(
    number: 2,
    name: '오로라 · 라이트',
    tagline: '한 단계 밝게(원 그라데이션의 25% 화이트 믹스). 텍스트/테두리는 흰색.',
    gradient: [Color(0xFF8F6DEE), Color(0xFF6D9CF7), Color(0xFF40E2D5)],
    bg: Color(0xFF3D2E7D),
    surface: Color(0x38FFFFFF),
    primary: Color(0xFF7C4DFF),
    secondary: Color(0xFF10C9BB),
    onBg: Colors.white,
    onSurface: Colors.white,
    controlColor: Colors.white,
  ),
  _ConceptSpec(
    number: 3,
    name: '오로라 · 소프트',
    tagline: '더 밝게(50% 화이트 믹스). 텍스트는 흰색 유지하되 살짝 그림자를 더함.',
    gradient: [Color(0xFFB49EF3), Color(0xFF9EBDFA), Color(0xFF80ECE3)],
    bg: Color(0xFF8A76E8),
    surface: Color(0x66FFFFFF),
    primary: Color(0xFF6A4FD9),
    secondary: Color(0xFF0F9C90),
    onBg: Colors.white,
    onSurface: Colors.white,
    controlColor: Colors.white,
  ),
  _ConceptSpec(
    number: 4,
    name: '오로라 · 페일',
    tagline: '가장 밝게(75% 화이트 믹스). 흰 글씨가 안 보여서 텍스트/테두리를 짙은 남색으로 전환.',
    gradient: [Color(0xFFDACEF9), Color(0xFFCEDEFC), Color(0xFFBFF5F1)],
    bg: Color(0xFFEEE9FD),
    surface: Colors.white,
    primary: Color(0xFF6A4FD9),
    secondary: Color(0xFF0F9C90),
    onBg: Color(0xFF3B2E7A),
    onSurface: Color(0xFF3B2E7A),
    controlColor: Color(0xFF3B2E7A),
  ),
];

/// 알람 타입 3종(소리+진동/진동/무음) - 다음 알람 탭 목업 전체에서 공용으로 씀.
const List<String> _alarmTypeLabels = ['소리+진동', '진동', '무음'];
const List<IconData> _alarmTypeIcons = [
  Icons.volume_up_rounded,
  Icons.vibration_rounded,
  Icons.notifications_off_rounded,
];

/// ⭐ 5번 슬롯(아이콘 색상 후보) 항목 하나. 30개 갤러리에서 후보 3개로 정리:
/// (1) 1번 테마 아이콘 자체(그라데이션), (2)(3) 원래 30개 팔레트 중 1번/17번.
class _IconPalette {
  final int number;
  final String label;
  final Color bg;
  final List<Color>? gradient;
  final Color clock;
  final Color bell;
  final Color bellBorder;
  const _IconPalette({
    required this.number,
    required this.label,
    required this.bg,
    this.gradient,
    required this.clock,
    required this.bell,
    this.bellBorder = Colors.white,
  });
}

const List<_IconPalette> _iconPalettes = [
  _IconPalette(
    number: 1,
    label: '1번 테마 아이콘 (그라데이션)',
    bg: Color(0xFF1B1035),
    gradient: [Color(0xFF6A3DE8), Color(0xFF3D7BF5), Color(0xFF00D9C7)],
    clock: Colors.white,
    bell: Color(0xFF00E5C7),
  ),
  _IconPalette(
    number: 2,
    label: '팔레트 1 - 인디고/화이트/앰버',
    bg: Color(0xFF3F51B5),
    clock: Colors.white,
    bell: Color(0xFFFFC107),
  ),
  _IconPalette(
    number: 3,
    label: '팔레트 17 - 네이비/골드/코랄',
    bg: Color(0xFF1A237E),
    clock: Color(0xFFFFD700),
    bell: Color(0xFFFF7043),
    bellBorder: Colors.white,
  ),
];

class UiThemeLabScreen extends StatefulWidget {
  const UiThemeLabScreen({super.key});

  @override
  State<UiThemeLabScreen> createState() => _UiThemeLabScreenState();
}

class _UiThemeLabScreenState extends State<UiThemeLabScreen> {
  int _selected = 1; // 1..4 = 밝기 단계, 5 = 아이콘 색상 후보

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
                    isGallery ? '5. 아이콘 색상 후보' : '${spec!.number}. ${spec.name}',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    isGallery ? '30개 중 추린 후보 3개.' : spec!.tagline,
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
        _sectionLabel('다음 알람 탭 - 그라데이션 버전'),
        SizedBox(height: 12.h),
        _nextAlarmRing(spec, gradientBg: true),
        SizedBox(height: 32.h),
        _sectionLabel('다음 알람 탭 - 그라데이션 없는(플랫) 버전'),
        SizedBox(height: 12.h),
        _nextAlarmRing(spec, gradientBg: false),
        SizedBox(height: 24.h),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.grey.shade600));
  }

  // ============================================================
  // 5번 슬롯 - 아이콘 색상 후보 3개
  // ============================================================
  Widget _buildIconGallery() {
    return Wrap(
      spacing: 24.w,
      runSpacing: 24.h,
      children: _iconPalettes.map((p) {
        return SizedBox(
          width: 92.w,
          child: Column(
            children: [
              _iconGraphic(bg: p.bg, gradient: p.gradient, clockColor: p.clock, bellColor: p.bell, bellBorderColor: p.bellBorder, size: 88.w),
              SizedBox(height: 8.h),
              Text('${p.number}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
              SizedBox(height: 2.h),
              Text(p.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade600)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // 앱 아이콘 / 아이콘 갤러리 공용 - 둥근 사각 + 시계 + 2시 방향 알림 배지.
  // gradient가 있으면 그라데이션, 없으면 bg 단색.
  // ============================================================
  Widget _iconGraphic({
    Color? bg,
    List<Color>? gradient,
    required Color clockColor,
    required Color bellColor,
    required Color bellBorderColor,
    required double size,
  }) {
    final borderWidth = (size / 104 * 2.4).clamp(1.2, 3.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.23),
        color: gradient == null ? bg : null,
        gradient: gradient != null ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient) : null,
        boxShadow: [BoxShadow(color: (bg ?? gradient!.first).withValues(alpha: 0.4), blurRadius: size * 0.17, offset: Offset(0, size * 0.08))],
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.watch_later_rounded, size: size * 0.66, color: clockColor),
          Positioned(
            top: size * 0.01,
            right: size * 0.01,
            child: Container(
              width: size * 0.24,
              height: size * 0.24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bellColor, shape: BoxShape.circle, border: Border.all(color: bellBorderColor, width: borderWidth)),
              child: Icon(Icons.notifications_active_rounded, size: size * 0.135, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(_ConceptSpec s) {
    return _iconGraphic(
      bg: s.bg,
      gradient: s.gradient,
      clockColor: s.controlColor,
      bellColor: s.secondary,
      bellBorderColor: s.controlColor,
      size: 104.w,
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
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient),
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
                Text(
                  '07:30',
                  style: TextStyle(
                    fontSize: 30.sp,
                    fontWeight: FontWeight.w800,
                    color: s.onBg,
                    shadows: const [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                  ),
                ),
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
  // 다음 알람 탭 - 파스텔안(원형 시계 모티프)을 최종 레이아웃으로 채택하고,
  // 원을 애니메이션 카운트다운 링으로 발전시킴. gradientBg로 그라데이션/플랫
  // 두 버전을 같은 레이아웃에서 만들어냄.
  // ============================================================
  Widget _nextAlarmRing(_ConceptSpec s, {required bool gradientBg}) {
    return _phoneFrame(
      width: 280.w,
      height: 600.h,
      bg: s.bg,
      gradient: gradientBg ? s.gradient : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22.w, 28.h, 22.w, 24.h),
        child: Column(
          children: [
            Row(
              children: [
                Text('다음 근무 알람', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: s.onBg)),
              ],
            ),
            SizedBox(height: 22.h),
            SizedBox(
              width: 202.w,
              height: 202.w,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _CountdownRing(size: 202.w, strokeWidth: 12.w, color: s.secondary, trackColor: s.onBg.withValues(alpha: 0.15)),
                  Container(
                    width: 160.w,
                    height: 160.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
                          decoration: BoxDecoration(color: s.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20.r)),
                          child: Text('오늘', style: TextStyle(fontSize: 10.sp, color: s.primary, fontWeight: FontWeight.w700)),
                        ),
                        SizedBox(height: 6.h),
                        Text('07:30', style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800, color: s.primary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
            _shiftLabel(s, '야간 근무'),
            SizedBox(height: 24.h),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(18.r)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer_outlined, size: 18.sp, color: s.secondary),
                          SizedBox(height: 8.h),
                          Text('알람까지', style: TextStyle(fontSize: 10.sp, color: s.onSurface.withValues(alpha: 0.6))),
                          SizedBox(height: 2.h),
                          Text('2시간 30분', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: s.onSurface)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
                      decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(18.r)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                                  child: Icon(_alarmTypeIcons[i], size: 12.sp, color: selected ? Colors.white : s.onSurface.withValues(alpha: 0.4)),
                                ),
                                SizedBox(width: 6.w),
                                Expanded(
                                  child: Text(
                                    _alarmTypeLabels[i],
                                    style: TextStyle(fontSize: 10.sp, color: s.onSurface.withValues(alpha: selected ? 0.9 : 0.5), fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
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
            ),
            SizedBox(height: 22.h),
            SizedBox(
              width: double.infinity,
              child: AppThirdButton(
                onPressed: () {},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_rounded, size: 16),
                    SizedBox(width: 6.w),
                    const Text('전체 알람 보기'),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10.h),
            SizedBox(
              width: double.infinity,
              child: AppSecondButton(
                variant: AppSecondButtonVariant.danger,
                onPressed: () {},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.alarm_off_rounded, size: 16),
                    SizedBox(width: 6.w),
                    const Text('이 알람 끄기'),
                  ],
                ),
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
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: filled ? Border.all(color: s.controlColor, width: 1.6) : null),
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
          decoration: BoxDecoration(color: filled ? s.primary : s.surface, shape: BoxShape.circle, border: filled ? Border.all(color: s.controlColor, width: 1.8) : null),
          child: Icon(icon, size: 22.sp, color: filled ? Colors.white : s.onSurface),
        ),
        SizedBox(height: 6.h),
        Text(label, style: TextStyle(fontSize: 11.sp, color: s.onBg.withValues(alpha: 0.7))),
      ],
    );
  }

  /// ⭐ "5분 후" 스누즈 버튼 - "+5m" 텍스트. 배경(그라데이션)과 버튼 색(원래
  /// s.primary 톤)이 서로 비슷해 묻히는 문제가 있었어서, 테두리/글자를 항상
  /// s.controlColor(배경과 대비되게 미리 정해둔 색 - 흰색 또는 짙은 남색)로
  /// 씀. dense=true면 오버레이(작은 원형, 라벨 없음)용, false면 잠금화면(큰
  /// 원형 + 아래 "5분 후" 라벨 - 옆의 끄기 버튼과 구조를 맞춤)용.
  Widget _snoozeButton(_ConceptSpec s, {required bool dense}) {
    final size = dense ? 40.w : 56.w;
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: s.surface, shape: BoxShape.circle, border: Border.all(color: s.controlColor, width: 1.6)),
      child: Text('+5m', style: TextStyle(fontSize: dense ? 11.sp : 15.sp, fontWeight: FontWeight.w800, color: s.controlColor)),
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

/// ⭐ "다음 알람" 탭 원형 카운트다운 링 - 12시 방향에서 시작해 시계 방향으로
/// 채워지며, 다시 12시 방향에 가까워질수록(=원이 거의 다 찼을수록) 알람이
/// 임박했다는 뜻. 실제 알람 데이터가 없는 순수 디자인 목업이라 "지금부터
/// 남은 시간까지"를 진짜로 계산하는 대신, 그 컨셉을 계속 보여주기 위해 8초
/// 주기로 0→1을 무한 반복하는 데모 애니메이션을 씀 - 실제 화면에 적용할 때는
/// 이 진행률(progress)에 "(now - 알람등록시각) / (알람시각 - 알람등록시각)"
/// 같은 실계산 값을 넣기만 하면 됨.
class _CountdownRing extends StatefulWidget {
  const _CountdownRing({required this.size, required this.strokeWidth, required this.color, required this.trackColor});

  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  State<_CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<_CountdownRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _RingPainter(progress: _controller.value, color: widget.color, trackColor: widget.trackColor, strokeWidth: widget.strokeWidth),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.trackColor, required this.strokeWidth});

  final double progress; // 0..1
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * progress;
    // -pi/2 = 12시 방향에서 시작, 시계 방향으로 sweep만큼 채움.
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweep, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
}
