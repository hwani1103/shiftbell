// lib/widgets/app_third_button.dart
//
// ⭐ 2026-08-25 추가 - 세 번째 버튼 스타일. 지금 두 공용 버튼의 자리:
//   - AppButton(app_button.dart): 화면의 "가장 중요한 한 가지 액션" - 그라데이션+
//     링+톤 그림자, 시각적으로 화려함.
//   - AppSecondButton(app_second_button.dart): 취소/삭제/저장처럼 짝을 이루는
//     보조 액션 - 단색 채움이라 화려하진 않지만 여전히 존재감이 묵직함(빨강/초록).
//
// 이 둘 다에 안 맞는 자리(예: 다이얼로그 안의 "알람 추가"처럼 목록에 항목을
// 늘리는 가벼운 액션, 설정 탭의 부차적인 액션들)를 위한 세 번째 스타일 -
// 흰색(또는 연회색) 배경 + 얇은 테두리 선 + 배경과 대비되는 심플한 글자색
// (검정에 가까운 톤). 그라데이션도 단색 채움도 아닌, 존재감을 최대한 낮춘
// "여기 눌러도 된다"는 정도의 담백한 버튼.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppThirdButton extends StatelessWidget {
  const AppThirdButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final Widget child;

  /// true면 좁은 자리에 맞게 패딩/글자를 줄인 작은 버전(AppSecondButton의
  /// compact와 동일한 개념).
  final bool compact;

  bool get _enabled => onPressed != null;

  static const _radius = BorderRadius.all(Radius.circular(11));

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // ⭐ AppButton/AppSecondButton과 동일한 이유로 ClipRRect + Material(type:
      // transparency) 구조를 씀(app_button.dart 클래스 주석 참고).
      borderRadius: _radius,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: _radius,
            color: _enabled ? const Color(0xFFFCFCFD) : const Color(0xFFF2F2F3),
            border: Border.all(
              color: _enabled ? kAppChipBorder.withValues(alpha: 0.25) : const Color(0xFFDADFE6),
              width: 1.2,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            splashColor: kAppMainAccent.withValues(alpha: 0.08),
            highlightColor: kAppMainAccent.withValues(alpha: 0.06),
            child: Container(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: _enabled ? const Color(0xFF20242B) : const Color(0xFFAEB4BD),
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(color: _enabled ? const Color(0xFF20242B) : const Color(0xFFAEB4BD)),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
