// lib/screens/ui_theme_lab_screen.dart
//
// ⭐ 2026-08-25 5차 개정 - 아이콘 픽커 두 가지 버그 수정 + 후보마다 진짜
// 디자인(바늘 길이/굵기, 종 크기/위치, 테두리 유무)도 다르게 만듦.
//
// 버그 1) "시계가 안 보인다" - 시계 얼굴은 항상 흰색으로 그리는데, 예전
// 팔레트(30개 갤러리) 시절엔 "clock색"이 단색 아이콘 글자 자체의 색이라
// 흰색이 흔했음. 지금은 얼굴이 흰 원 + 그 위에 바늘을 얹는 2단 구조라, 바늘
// 색을 흰색으로 두면 흰 바탕 위에 흰 바늘 = 안 보임. 예전 팔레트를 그대로
// 옮기면서 이 차이를 놓쳤던 것 - 이번엔 모든 후보의 바늘 색을 흰 얼굴 위에서
// 또렷이 보이는 짙은 색으로 다시 골랐음(금색 2곳만 의도적으로 유지 - 실제
// 렌더링해서 확인해보니 흰색보다는 대비가 확실히 있음).
//
// 버그 2) 그리드 오버플로 - GridView가 childAspectRatio(비율)로 셀 높이를
// 정했는데, 후보 이름 텍스트가 2줄까지 늘어나면 그 비율로 확보된 높이를
// 넘기는 경우가 있었음. childAspectRatio 대신 mainAxisExtent(셀 높이를
// 절대값으로 고정)로 바꾸고, 이름도 1줄+말줄임으로 제한해서 원천 차단.
//
// 디자인 변형 - 5가지 스타일을 순환시켜서 색깔뿐 아니라 구조도 다르게 함:
//   A(클래식) - 기본 비율, 테두리 링 있음
//   B(미니멀) - 짧고 얇은 바늘, 작은 종, 테두리 없음
//   C(볼드)   - 길고 두꺼운 바늘, 큰 종, 테두리 있음
//   D(종 강조) - 종을 크게 키우고 조금 더 겹치게, 테두리 없음
//   E(바늘 강조) - 바늘을 굵고 길게, 종은 작게, 테두리 있음

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum _Style { classic, minimal, bold, bellFocus, handFocus }

class _StyleSpec {
  final double handLen; // 바늘 길이 배율
  final double handWidth; // 바늘 굵기 배율
  final double bellScale; // 종 크기 배율
  final double bellOverlap; // 종이 시계 원과 겹치는 정도(반지름 대비)
  final bool ring; // 시계 테두리 링 유무
  const _StyleSpec({required this.handLen, required this.handWidth, required this.bellScale, required this.bellOverlap, required this.ring});
}

const Map<_Style, _StyleSpec> _styleSpecs = {
  _Style.classic: _StyleSpec(handLen: 1.0, handWidth: 1.0, bellScale: 1.0, bellOverlap: 0.95, ring: true),
  _Style.minimal: _StyleSpec(handLen: 0.82, handWidth: 0.7, bellScale: 0.8, bellOverlap: 0.82, ring: false),
  _Style.bold: _StyleSpec(handLen: 1.15, handWidth: 1.45, bellScale: 1.25, bellOverlap: 1.0, ring: true),
  _Style.bellFocus: _StyleSpec(handLen: 0.95, handWidth: 0.9, bellScale: 1.4, bellOverlap: 1.05, ring: false),
  _Style.handFocus: _StyleSpec(handLen: 1.12, handWidth: 1.35, bellScale: 0.7, bellOverlap: 0.85, ring: true),
};

/// 후보 하나 - 배경(단색 또는 그라데이션) / 시계 바늘 / 종 배지 색 + 디자인 스타일.
class _IconCandidate {
  final int number;
  final String name;
  final Color? bg;
  final List<Color>? gradient;
  final Color hands;
  final Color bell;
  final _Style style;
  const _IconCandidate({required this.number, required this.name, this.bg, this.gradient, required this.hands, required this.bell, this.style = _Style.classic});
}

// ⭐ 1~3번 = 지난번 마지막까지 남았던 3개 후보(부활). 1,2번은 흰 바늘이 얼굴과
// 겹쳐 안 보이던 버그가 있어서 바늘 색만 짙게 고침(배경/종은 그대로).
// 3번(네이비·골드·코랄)은 실제로 적용 중인 디자인이라 완전히 그대로 유지.
const List<_IconCandidate> _candidates = [
  _IconCandidate(number: 1, name: '오로라 그라데이션', gradient: [Color(0xFF6A3DE8), Color(0xFF3D7BF5), Color(0xFF00D9C7)], hands: Color(0xFF1A1A3D), bell: Color(0xFF00E5C7)),
  _IconCandidate(number: 2, name: '인디고·앰버', bg: Color(0xFF3F51B5), hands: Color(0xFF1A237E), bell: Color(0xFFFFC107)),
  _IconCandidate(number: 3, name: '네이비·골드·코랄(현재 적용중)', bg: Color(0xFF1A237E), hands: Color(0xFFFFD700), bell: Color(0xFFFF7043)),

  _IconCandidate(number: 4, name: '틸·코랄', bg: Color(0xFF00695C), hands: Color(0xFF0D2B4E), bell: Color(0xFFFF7043), style: _Style.minimal),
  _IconCandidate(number: 5, name: '포레스트그린·앰버', bg: Color(0xFF1B5E20), hands: Color(0xFF3E2723), bell: Color(0xFFFFC107), style: _Style.bold),
  _IconCandidate(number: 6, name: '버건디·골드', bg: Color(0xFF880E4F), hands: Color(0xFF1A237E), bell: Color(0xFFFFCA28), style: _Style.bellFocus),
  _IconCandidate(number: 7, name: '오션블루·코랄', bg: Color(0xFF0277BD), hands: Color(0xFF0D1B4C), bell: Color(0xFFFF8A65), style: _Style.handFocus),
  _IconCandidate(number: 8, name: '딥바이올렛·아쿠아', bg: Color(0xFF4527A0), hands: Color(0xFF2E0854), bell: Color(0xFF26C6DA)),
  _IconCandidate(number: 9, name: '차콜·코랄', bg: Color(0xFF263238), hands: Color(0xFF00332B), bell: Color(0xFFFF7043), style: _Style.minimal),
  _IconCandidate(number: 10, name: '번트오렌지·딥틸', bg: Color(0xFFE65100), hands: Color(0xFF3E2723), bell: Color(0xFF00796B), style: _Style.bold),
  _IconCandidate(number: 11, name: '플럼·민트', bg: Color(0xFF6A1B9A), hands: Color(0xFF1A237E), bell: Color(0xFF4DD0E1), style: _Style.bellFocus),
  _IconCandidate(number: 12, name: '올리브·코랄', bg: Color(0xFF827717), hands: Color(0xFF4E342E), bell: Color(0xFFFF7043), style: _Style.handFocus),
  _IconCandidate(number: 13, name: '스카이블루·앰버', bg: Color(0xFF0288D1), hands: Color(0xFF0D47A1), bell: Color(0xFFFFB300)),
  _IconCandidate(number: 14, name: '러스트·탠', bg: Color(0xFFBF360C), hands: Color(0xFF3E2723), bell: Color(0xFFFFB74D), style: _Style.minimal),
  _IconCandidate(number: 15, name: '딥인디고·핑크', bg: Color(0xFF283593), hands: Color(0xFF4A0E2E), bell: Color(0xFFFF80AB), style: _Style.bold),
  _IconCandidate(number: 16, name: '에메랄드·살몬', bg: Color(0xFF00897B), hands: Color(0xFF33210B), bell: Color(0xFFFF8A80), style: _Style.bellFocus),
  _IconCandidate(number: 17, name: '마룬·골드', bg: Color(0xFFB71C1C), hands: Color(0xFF1A237E), bell: Color(0xFFFFC107), style: _Style.handFocus),
  _IconCandidate(number: 18, name: '코발트·오렌지', bg: Color(0xFF1565C0), hands: Color(0xFF0B2545), bell: Color(0xFFFF9800)),
  _IconCandidate(number: 19, name: '에스프레소·앰버', bg: Color(0xFF4E342E), hands: Color(0xFF3E0C1F), bell: Color(0xFFFFC107), style: _Style.minimal),
  _IconCandidate(number: 20, name: '사파이어·코랄', bg: Color(0xFF01579B), hands: Color(0xFFFFD700), bell: Color(0xFFFF7043), style: _Style.bold),
  _IconCandidate(number: 21, name: '자수정·라임', bg: Color(0xFF7B1FA2), hands: Color(0xFF2A0845), bell: Color(0xFFC0CA33), style: _Style.bellFocus),
  _IconCandidate(number: 22, name: '딥로즈·스카이', bg: Color(0xFFAD1457), hands: Color(0xFF14213D), bell: Color(0xFF4FC3F7), style: _Style.handFocus),
  _IconCandidate(number: 23, name: '잉크블루·선플라워', bg: Color(0xFF0D47A1), hands: Color(0xFF0A1F44), bell: Color(0xFFFFEB3B)),
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
              '실제 적응형 아이콘 파이프라인(16% 인셋 → 108dp 중 중앙 70dp만 노출 → 원형 마스크)을 '
              '그대로 재현한 그림이라 여기 보이는 대로 실제 홈 화면에도 나와요. 색뿐 아니라 바늘 '
              '길이·굵기, 종 크기·위치도 후보마다 조금씩 다르게 그렸어요.',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700, height: 1.4),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(16.w),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 20.h,
                crossAxisSpacing: 10.w,
                mainAxisExtent: 128.h,
              ),
              itemCount: _candidates.length,
              itemBuilder: (context, index) {
                final c = _candidates[index];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AdaptiveIconPreview(candidate: c, size: 76.w),
                    SizedBox(height: 8.h),
                    Text('${c.number}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                    SizedBox(height: 2.h),
                    Text(c.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.sp, color: Colors.grey.shade600)),
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
    final visible = size.width;
    final s = visible / (_visibleWindowDp / _canvasDp);
    final cropOffset = (s - visible) / 2;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, visible, visible)));
    canvas.translate(-cropOffset, -cropOffset);

    // 1) 배경
    final bgPaint = Paint();
    final bgRect = Rect.fromLTWH(0, 0, s, s);
    if (candidate.gradient != null) {
      bgPaint.shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: candidate.gradient!).createShader(bgRect);
    } else {
      bgPaint.color = candidate.bg!;
    }
    canvas.drawRect(bgRect, bgPaint);

    // 2) 전경(시계+종) - <inset 16%> 시뮬레이션으로 전체를 68% 크기로 중앙 축소.
    final sourceRatio = _adaptiveTargetFinalRatio / ((1 - 2 * _autoInset) * (_canvasDp / _visibleWindowDp));
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(1 - 2 * _autoInset);
    canvas.translate(-s / 2, -s / 2);
    _drawForeground(canvas, s, sourceRatio, candidate.hands, candidate.bell, _styleSpecs[candidate.style]!);
    canvas.restore();

    canvas.restore();
  }

  void _drawForeground(Canvas canvas, double s, double faceDRatio, Color hands, Color bell, _StyleSpec style) {
    final cx = s / 2, cy = s / 2;
    final r = s * faceDRatio / 2;

    // 시계 얼굴(흰 원)
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.white);

    // 바늘 - 4시 정각(시침=4, 분침=12), 스타일별 길이/굵기 배율 적용.
    final hourLen = r * 0.42 * style.handLen;
    final minuteLen = r * 0.62 * style.handLen;
    final hourAng = (-90 + 4 * 30) * math.pi / 180;
    final minuteAng = (-90 + 0) * math.pi / 180;
    final handPaint = Paint()
      ..color = hands
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), Offset(cx + hourLen * math.cos(hourAng), cy + hourLen * math.sin(hourAng)), handPaint..strokeWidth = math.max(r * 0.11 * style.handWidth, 2));
    canvas.drawLine(Offset(cx, cy), Offset(cx + minuteLen * math.cos(minuteAng), cy + minuteLen * math.sin(minuteAng)), handPaint..strokeWidth = math.max(r * 0.08 * style.handWidth, 1.5));
    canvas.drawCircle(Offset(cx, cy), math.max(r * 0.07 * style.handWidth, 1.5), Paint()..color = hands);
    if (style.ring) {
      canvas.drawCircle(Offset(cx, cy), r, Paint()
        ..color = hands
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(r * 0.035, 1));
    }

    // 종 배지 - 스타일별 크기/겹침 배율 적용(2시 방향=-45°).
    final badgeR = r * 0.30 * style.bellScale;
    final bx = cx + r * style.bellOverlap * math.cos(-45 * math.pi / 180);
    final by = cy + r * style.bellOverlap * math.sin(-45 * math.pi / 180);
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

    canvas.drawArc(Rect.fromCenter(center: Offset(cx, bodyTop), width: domeW, height: domeW), math.pi, math.pi, true, paint);
    final body = Path()
      ..moveTo(cx - domeW / 2, bodyTop)
      ..lineTo(cx + domeW / 2, bodyTop)
      ..lineTo(cx + baseW / 2, bodyBottom)
      ..lineTo(cx - baseW / 2, bodyBottom)
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, bodyBottom), width: baseW, height: s * 0.20), 0, math.pi, true, paint);
    final knobR = s * 0.07;
    canvas.drawCircle(Offset(cx, bodyTop - domeW / 2), knobR, paint);
    final clapR = s * 0.11;
    canvas.drawCircle(Offset(cx, bodyBottom + s * 0.14), clapR, paint);
  }

  @override
  bool shouldRepaint(covariant _AdaptiveIconPainter oldDelegate) => oldDelegate.candidate != candidate;
}
