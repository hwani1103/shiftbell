// lib/widgets/app_second_button.dart
//
// ⭐ 2026-08-24 추가 - 취소/저장/삭제처럼 "짝을 이루는 보조 액션" 전용 공용 버튼.
//
// app_button.dart(AppButton)는 화면의 "가장 중요한 한 가지 액션"(다음/완료/시작하기)
// 용으로 그라데이션+링+톤 그림자를 갖춘 무거운 디자인 - 다이얼로그 안에서 "취소"
// "삭제" 같은 보조 액션까지 전부 그 스타일로 쓰면 우선순위가 없어 보이고 다이얼로그
// 안에서는 과함. 이 위젯은 반대로 아주 단순하게(테두리 없음, 단색 채움, 그림자 없음)
// 만들되, 색으로 의도를 명확히 구분함:
//   - danger(빨강): 삭제/초기화처럼 되돌리기 어려운 파괴적 액션
//   - success(초록): 저장/확인처럼 긍정적으로 완료하는 액션
//   - neutral(연한 메인색): 취소/뒤로처럼 위험하지도 확정적이지도 않은 액션 -
//     빨강도 초록도 아닌 애매한 위치라 앱의 메인 색상(kAppMainAccent) 계열을
//     연하게 써서 "이 앱의 버튼"이라는 톤은 유지하면서 danger/success와는
//     확실히 구분되게 함.
//
// 모양은 AppButton과 통일감을 유지하기 위해 같은 radius(11)와 같은 내부 패딩을
// 씀 - 두 버튼이 나란히 놓여도 크기가 어긋나 보이지 않음. 다만 링/그라데이션/
// 그림자는 전부 뺐음(요청: "border도 없음. 아주 심플하되 의도가 명확하게").
//
// 재사용 지점(2026-08-24 기준): 고정 알람 편집 다이얼로그의 취소/저장,
// 달력 탭의 "알람 타입 선택" 팝업의 삭제/확인, 알람 이력 화면의 전체 삭제 확인,
// 설정 탭의 스케줄 초기화 확인, 온보딩 첫 화면의 "+ 추가" 버튼.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum AppSecondButtonVariant { danger, success, neutral }

class AppSecondButton extends StatelessWidget {
  const AppSecondButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppSecondButtonVariant.neutral,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final AppSecondButtonVariant variant;

  bool get _enabled => onPressed != null;

  static const _radius = BorderRadius.all(Radius.circular(11));

  // ⭐ danger/success는 흰 글씨가 바로 잘 보이는 진한 톤. neutral은 배경 자체가
  // 이미 밝은 파스텔이라(kAppMainAccentLight) 흰 글씨 대신 앱의 짙은 남색 텍스트
  // 톤(kAppChipBorder - 칩 텍스트와 동일 계열)을 써야 대비가 남 - AppShiftChip이
  // "밝은 채움 + 짙은 텍스트"로 이미 쓰고 있는 조합을 그대로 재사용.
  Color get _fillColor {
    switch (variant) {
      case AppSecondButtonVariant.danger:
        return const Color(0xFFD64545);
      case AppSecondButtonVariant.success:
        return const Color(0xFF2F9E5B);
      case AppSecondButtonVariant.neutral:
        return kAppMainAccentLight;
    }
  }

  Color get _textColor {
    switch (variant) {
      case AppSecondButtonVariant.danger:
      case AppSecondButtonVariant.success:
        return Colors.white;
      case AppSecondButtonVariant.neutral:
        return kAppChipBorder;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // ⭐ AppButton과 동일한 이유(class 주석 참고)로 ClipRRect + Material(type:
      // transparency) 구조를 씀 - Material에 borderRadius를 직접 주면 "각진
      // 잔상"이 남을 수 있는 다른 렌더 경로를 타는 문제를 구조적으로 피함.
      borderRadius: _radius,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: _radius,
            color: _enabled ? _fillColor : const Color(0xFFDADFE6),
          ),
          child: InkWell(
            onTap: onPressed,
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: _enabled ? _textColor : const Color(0xFF6B7280),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(color: _enabled ? _textColor : const Color(0xFF6B7280)),
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
