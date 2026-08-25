// lib/screens/ui_theme_lab_screen.dart
//
// ⭐ 2026-08-25 4차 개정 - 앱 아이콘/알람화면/다음알람탭/메인 컬러 테마는 전부
// "오로라 페일" → "17번"(네이비/골드/코랄) 확정을 거쳐 실제 반영 완료됨. 이제
// 이 탭은 순수하게 "앱 아이콘 색상 후보를 실제 설치됐을 때와 100% 동일하게
// 미리 보기"만 하는 임시 화면으로 좁힘.
//
// ⚠️ 왜 다시 만들었나: 처음 아이콘 색상 후보를 고를 때는 이 목업이 그냥
// "정사각형 그림"이었는데, 실제로 설치해보니 완전히 다르게 보였음(적응형
// 아이콘이 (1) flutter_launcher_icons가 자동으로 씌우는 16% 인셋, (2) 안드로이드
// 자체가 108dp 캔버스 중 실제로는 중앙 66~72dp만 "확대 없이 그대로" 보여주는
// 크롭, (3) 런처가 씌우는 마스크(원형 등) - 이 세 단계를 거치기 때문. 이번엔
// 그 세 단계를 전부 그대로 시뮬레이션해서 그려서(assets/icon/gen_icon.py의
// 실측 상수와 동일한 값을 씀), "여기서 고르면 실제로 그렇게 보인다"를 보장함.
//
// 사용법: 마음에 드는 번호를 골라서 알려주면, assets/icon/gen_icon.py의
// BG/HANDS/BELL_BG 상수를 그 후보 값으로 바꾸고 실제 아이콘에 반영함.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 후보 하나 - 배경(단색 또는 그라데이션) / 시계 바늘 / 종 배지 색.
class _IconCandidate {
  final int number;
  final String name;
  final Color? bg;
  final List<Color>? gradient;
  final Color hands;
  final Color bell;
  const _IconCandidate({required this.number, required this.name, this.bg, this.gradient, required this.hands, required this.bell});
}

// ⭐ 1~3번 = 지난번에 마지막까지 남았던 3개 후보(그대로 부활). 4~23번 = 새로 추가.
// 시계 얼굴은 항상 흰색 고정, 바늘/종만 후보마다 다름(assets/icon/gen_icon.py와
// 동일한 기하 구조 - 4시 정각, 종은 시계 테두리에 살짝 겹침).
const List<_IconCandidate> _candidates = [
  _IconCandidate(number: 1, name: '오로라 그라데이션(부활)', gradient: [Color(0xFF6A3DE8), Color(0xFF3D7BF5), Color(0xFF00D9C7)], hands: Colors.white, bell: Color(0xFF00E5C7)),
  _IconCandidate(number: 2, name: '인디고 · 화이트 · 앰버(부활)', bg: Color(0xFF3F51B5), hands: Colors.white, bell: Color(0xFFFFC107)),
  _IconCandidate(number: 3, name: '네이비 · 골드 · 코랄(현재 적용중, 부활)', bg: Color(0xFF1A237E), hands: Color(0xFFFFD700), bell: Color(0xFFFF7043)),

  _IconCandidate(number: 4, name: '틸 · 화이트 · 코랄', bg: Color(0xFF00695C), hands: Colors.white, bell: Color(0xFFFF7043)),
  _IconCandidate(number: 5, name: '포레스트그린 · 화이트 · 앰버', bg: Color(0xFF1B5E20), hands: Colors.white, bell: Color(0xFFFFC107)),
  _IconCandidate(number: 6, name: '버건디 · 화이트 · 골드', bg: Color(0xFF880E4F), hands: Colors.white, bell: Color(0xFFFFCA28)),
  _IconCandidate(number: 7, name: '오션블루 · 화이트 · 코랄', bg: Color(0xFF0277BD), hands: Colors.white, bell: Color(0xFFFF8A65)),
  _IconCandidate(number: 8, name: '딥바이올렛 · 화이트 · 아쿠아', bg: Color(0xFF4527A0), hands: Colors.white, bell: Color(0xFF26C6DA)),
  _IconCandidate(number: 9, name: '차콜 · 틸 · 코랄', bg: Color(0xFF263238), hands: Color(0xFF26A69A), bell: Color(0xFFFF7043)),
  _IconCandidate(number: 10, name: '번트오렌지 · 화이트 · 딥틸', bg: Color(0xFFE65100), hands: Colors.white, bell: Color(0xFF00796B)),
  _IconCandidate(number: 11, name: '플럼 · 골드 · 민트', bg: Color(0xFF6A1B9A), hands: Color(0xFFFFD54F), bell: Color(0xFF4DD0E1)),
  _IconCandidate(number: 12, name: '올리브 · 다크브라운 · 코랄', bg: Color(0xFF827717), hands: Color(0xFF4E342E), bell: Color(0xFFFF7043)),
  _IconCandidate(number: 13, name: '스카이블루 · 네이비 · 앰버', bg: Color(0xFF0288D1), hands: Color(0xFF0D47A1), bell: Color(0xFFFFB300)),
  _IconCandidate(number: 14, name: '러스트 · 화이트 · 탠', bg: Color(0xFFBF360C), hands: Colors.white, bell: Color(0xFFFFB74D)),
  _IconCandidate(number: 15, name: '딥인디고 · 화이트 · 핑크', bg: Color(0xFF283593), hands: Colors.white, bell: Color(0xFFFF80AB)),
  _IconCandidate(number: 16, name: '에메랄드 · 화이트 · 살몬', bg: Color(0xFF00897B), hands: Colors.white, bell: Color(0xFFFF8A80)),
  _IconCandidate(number: 17, name: '마룬 · 화이트 · 골드', bg: Color(0xFFB71C1C), hands: Colors.white, bell: Color(0xFFFFC107)),
  _IconCandidate(number: 18, name: '코발트 · 화이트 · 오렌지', bg: Color(0xFF1565C0), hands: Colors.white, bell: Color(0xFFFF9800)),
  _IconCandidate(number: 19, name: '에스프레소 · 크림 · 앰버', bg: Color(0xFF4E342E), hands: Color(0xFFFFE0B2), bell: Color(0xFFFFC107)),
  _IconCandidate(number: 20, name: '사파이어 · 골드 · 코랄', bg: Color(0xFF01579B), hands: Color(0xFFFFD700), bell: Color(0xFFFF7043)),
  _IconCandidate(number: 21, name: '자수정 · 화이트 · 라임', bg: Color(0xFF7B1FA2), hands: Colors.white, bell: Color(0xFFC0CA33)),
  _IconCandidate(number: 22, name: '딥로즈 · 화이트 · 스카이', bg: Color(0xFFAD1457), hands: Colors.white, bell: Color(0xFF4FC3F7)),
  _IconCandidate(number: 23, name: '잉크블루 · 화이트 · 선플라워', bg: Color(0xFF0D47A1), hands: Colors.white, bell: Color(0xFFFFEB3B)),
];

class UiThemeLabScreen extends StatelessWidget {
  const UiThemeLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('앱 아이콘 색상 후보 (실제 렌더링)')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.w),
            color: Colors.grey.shade100,
            child: Text(
              '이 그림은 실제 안드로이드 적응형 아이콘 파이프라인(16% 인셋 → 108dp 중 '
              '중앙 70dp만 확대 없이 노출 → 원형 마스크)을 그대로 재현한 결과예요. '
              '여기서 보이는 대로 실제 홈 화면에도 나타나요. 마음에 드는 번호를 알려주세요.',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700, height: 1.4),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(16.w),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 22.h,
                crossAxisSpacing: 12.w,
                childAspectRatio: 0.72,
              ),
              itemCount: _candidates.length,
              itemBuilder: (context, index) {
                final c = _candidates[index];
                return Column(
                  children: [
                    _AdaptiveIconPreview(candidate: c, size: 84.w),
                    SizedBox(height: 8.h),
                    Text('${c.number}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                    SizedBox(height: 2.h),
                    Text(c.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5.sp, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 실제 적응형 아이콘 렌더링을 시뮬레이션하는 원형 미리보기.
/// assets/icon/gen_icon.py의 상수(ADAPTIVE_AUTO_INSET=0.16,
/// ADAPTIVE_VISIBLE_WINDOW_DP=70, CANVAS_DP=108, ADAPTIVE_TARGET_FINAL_RATIO=0.59로
/// 역산되는 source 비율)와 완전히 동일한 값을 씀 - 숫자가 어긋나면 이 미리보기도
/// 다시 "실제와 다르게" 보이게 되므로, 저 파일의 상수를 바꾸면 여기도 같이 바꿀 것.
class _AdaptiveIconPreview extends StatelessWidget {
  const _AdaptiveIconPreview({required this.candidate, required this.size});

  final _IconCandidate candidate;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 3))]),
      child: CustomPaint(
        size: Size(size, size),
        painter: _AdaptiveIconPainter(candidate: candidate),
      ),
    );
  }
}

class _AdaptiveIconPainter extends CustomPainter {
  _AdaptiveIconPainter({required this.candidate});
  final _IconCandidate candidate;

  // gen_icon.py와 동일한 상수.
  static const double _autoInset = 0.16; // <inset android:inset="16%"/>
  static const double _canvasDp = 108.0;
  static const double _visibleWindowDp = 70.0; // 실제로 확대 없이 보이는 영역
  static const double _adaptiveTargetFinalRatio = 0.59;

  @override
  void paint(Canvas canvas, Size size) {
    // size = "실제로 눈에 보이는" 원형 아이콘 크기(위젯 크기 그대로).
    final visible = size.width;
    // 이 visible 크기가 108dp 캔버스 중 70dp에 해당하므로, 전체 108dp 캔버스를
    // 재구성한 크기(S)를 역산함.
    final s = visible / (_visibleWindowDp / _canvasDp);
    final cropOffset = (s - visible) / 2;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, visible, visible)));
    canvas.translate(-cropOffset, -cropOffset);

    // 1) 배경 - 108dp 캔버스 전체를 채움(인셋 영향 없음, 배경 레이어는 그대로).
    final bgPaint = Paint();
    final bgRect = Rect.fromLTWH(0, 0, s, s);
    if (candidate.gradient != null) {
      bgPaint.shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: candidate.gradient!).createShader(bgRect);
    } else {
      bgPaint.color = candidate.bg!;
    }
    canvas.drawRect(bgRect, bgPaint);

    // 2) 전경(시계+종) - source 비율로 그린 뒤, <inset 16%> 시뮬레이션으로
    // 전체를 68% 크기로 중앙 축소.
    final sourceRatio = _adaptiveTargetFinalRatio / ((1 - 2 * _autoInset) * (_canvasDp / _visibleWindowDp));
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(1 - 2 * _autoInset);
    canvas.translate(-s / 2, -s / 2);
    _drawForeground(canvas, s, sourceRatio, candidate.hands, candidate.bell);
    canvas.restore();

    canvas.restore();
  }

  void _drawForeground(Canvas canvas, double s, double faceDRatio, Color hands, Color bell) {
    final cx = s / 2, cy = s / 2;
    final r = s * faceDRatio / 2;

    // 시계 얼굴(흰 원)
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.white);

    // 바늘 - 4시 정각(시침=4, 분침=12). gen_icon.py draw_clock_hands와 동일.
    final hourLen = r * 0.42;
    final minuteLen = r * 0.62;
    final hourAng = (-90 + 4 * 30) * math.pi / 180;
    final minuteAng = (-90 + 0) * math.pi / 180;
    final handPaint = Paint()
      ..color = hands
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), Offset(cx + hourLen * math.cos(hourAng), cy + hourLen * math.sin(hourAng)), handPaint..strokeWidth = math.max(r * 0.11, 2));
    canvas.drawLine(Offset(cx, cy), Offset(cx + minuteLen * math.cos(minuteAng), cy + minuteLen * math.sin(minuteAng)), handPaint..strokeWidth = math.max(r * 0.08, 1.5));
    canvas.drawCircle(Offset(cx, cy), math.max(r * 0.07, 1.5), Paint()..color = hands);
    // 테두리 링
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..color = hands
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(r * 0.035, 1));

    // 종 배지 - 원 테두리에 살짝 겹치도록(반지름의 95%, 2시 방향=-45°).
    final badgeR = r * 0.30;
    const overlapK = 0.95;
    final bx = cx + r * overlapK * math.cos(-45 * math.pi / 180);
    final by = cy + r * overlapK * math.sin(-45 * math.pi / 180);
    final borderW = math.max(badgeR * 0.14, 1.0);
    canvas.drawCircle(Offset(bx, by), badgeR + borderW, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(bx, by), badgeR, Paint()..color = bell);
    _drawBell(canvas, bx, by, badgeR * 0.62, Colors.white);
  }

  void _drawBell(Canvas canvas, double cx, double cy, double s, Color color) {
    final paint = Paint()..color = color;
    final bodyTop = cy - s * 0.55;
    final bodyBottom = cy + s * 0.30;
    final domeW = s * 0.62;
    final baseW = s * 0.90;

    // 돔(위쪽 반원)
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, bodyTop), width: domeW, height: domeW), math.pi, math.pi, true, paint);
    // 몸통(사다리꼴)
    final body = Path()
      ..moveTo(cx - domeW / 2, bodyTop)
      ..lineTo(cx + domeW / 2, bodyTop)
      ..lineTo(cx + baseW / 2, bodyBottom)
      ..lineTo(cx - baseW / 2, bodyBottom)
      ..close();
    canvas.drawPath(body, paint);
    // 받침(아래쪽 반원)
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, bodyBottom), width: baseW, height: s * 0.20), 0, math.pi, true, paint);
    // 손잡이
    final knobR = s * 0.07;
    canvas.drawCircle(Offset(cx, bodyTop - domeW / 2), knobR, paint);
    // 추
    final clapR = s * 0.11;
    canvas.drawCircle(Offset(cx, bodyBottom + s * 0.14), clapR, paint);
  }

  @override
  bool shouldRepaint(covariant _AdaptiveIconPainter oldDelegate) => oldDelegate.candidate != candidate;
}
