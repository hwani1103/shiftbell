// lib/widgets/app_button.dart
//
// ⭐ 2026-08-24 추가 - 앱 공용 기본 버튼(주요 액션용, "다음"/"완료"/"시작하기" 등).
//
// 기존엔 ElevatedButton + app_theme.dart의 ElevatedButtonTheme으로 단색 배경
// 버튼을 썼는데, "단색이라 딱딱하다"는 피드백으로 그라데이션 + 옅은 흰 테두리
// 링 + 톤이 들어간 은은한 그림자를 주는 이 위젯으로 교체함. Material의
// ButtonStyle은 배경에 단색만 지정 가능해서(그라데이션 불가) 테마 하나로는
// 이 효과를 낼 수 없었음 - 그래서 커스텀 위젯으로 뺌.
//
// API는 ElevatedButton과 거의 동일하게 맞춤(onPressed, child) - 기존
// ElevatedButton(...) 호출부를 AppButton(...)으로 이름만 바꾸면 대부분 그대로
// 동작함. onPressed가 null이면 ElevatedButton과 똑같이 흐리게 비활성 표시됨.
//
// 적용 범위(2026-08-24 기준): lib/screens/onboarding_screen.dart의 주요 액션
// 버튼들("다음"/"완료"/"시작하기"/"+추가"). 나머지 화면(설정탭 등)은 아직
// ElevatedButton을 그대로 씀 - 추후 확대 적용 예정.
//
// ⭐ 크기 값(padding/radius/fontSize)에 flutter_screenutil의 .w/.h/.r/.sp를
// 일부러 안 씀 - app_theme.dart의 ElevatedButtonTheme(아직 안 바뀐 화면들이
// 쓰는 공용 버튼)도 같은 이유로 원시 숫자를 씀. 두 버튼(AppButton vs 기존
// ElevatedButton)이 같은 화면에 같이 있을 수 있는 과도기라, 한쪽만 ScreenUtil로
// 스케일되면 미세하게 크기가 어긋나 보임 - 전부 AppButton으로 옮겨간 뒤에
// 필요하면 그때 같이 .sp로 통일할 것.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);

    return Material(
      // ⭐ Material 배경은 투명 - 실제 배경은 아래 Ink의 decoration(그라데이션)이
      // 그림. Material을 감싸는 이유는 InkWell의 물결(ripple) 효과가 그리려면
      // Material 조상이 필요해서.
      color: Colors.transparent,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          // ⭐ 비활성 상태는 그라데이션/그림자 없이 밋밋한 회색으로 - Material의
          // 기본 disabled 버튼 관례(onPressed:null이면 흐리게)를 그대로 재현.
          gradient: _enabled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kAppMainAccentLight, kAppMainAccentDark],
                )
              : null,
          color: _enabled ? null : Colors.grey.shade300,
          // ⭐ 옅은 흰 테두리 링 - 그라데이션 버튼 가장자리에 살짝 하이라이트를
          // 줘서 "유리판을 얹은 듯한" 세련된 느낌을 냄. 최근 웹/앱 디자인에서
          // 흔한 "inner highlight ring" 기법.
          border: _enabled
              ? Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2)
              : null,
          // ⭐ 그림자를 검정 대신 버튼 자체 색상 톤으로 - 최근 트렌드인 "톤이
          // 들어간(colored) 그림자". 순수 검정 그림자보다 튀지 않고 버튼과
          // 배경이 한 분위기로 이어짐.
          boxShadow: _enabled
              ? [
                  BoxShadow(
                    color: kAppMainAccent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          splashColor: Colors.white.withValues(alpha: 0.15),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Container(
            // ElevatedButton 기본 padding(대략 24 가로/12 세로)과 맞춤.
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            alignment: Alignment.center,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: _enabled ? Colors.white : Colors.grey.shade600,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: _enabled ? Colors.white : Colors.grey.shade600),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
