// lib/widgets/app_button.dart
//
// ⭐ 2026-08-24 추가 - 앱 공용 기본 버튼(주요 액션용, "다음"/"완료"/"시작하기"/
// "+추가" 등).
//
// 기존엔 ElevatedButton + app_theme.dart의 ElevatedButtonTheme으로 단색 배경
// 버튼을 썼는데, "단색이라 딱딱하다"는 피드백으로 그라데이션 + 링 + 톤이 들어간
// 은은한 그림자를 주는 이 위젯으로 교체함. Material의 ButtonStyle은 배경에
// 단색만 지정 가능해서(그라데이션 불가) 테마 하나로는 이 효과를 낼 수 없었음 -
// 그래서 커스텀 위젯으로 뺌.
//
// API는 ElevatedButton과 거의 동일하게 맞춤(onPressed, child) - 기존
// ElevatedButton(...) 호출부를 AppButton(...)으로 이름만 바꾸면 대부분 그대로
// 동작함. onPressed가 null이면 ElevatedButton과 똑같이 흐리게 비활성 표시됨.
//
// ⭐ 크기가 스스로 결정되는 방식: 이 위젯 자체는 폭을 강제하지 않음(내용물
// 크기만큼만 차지) - `SizedBox(width: double.infinity, child: AppButton(...))`로
// 감싸면 그 폭에 맞게 늘어나 내용이 가운데 정렬되고("다음"/"완료" 같은 화면
// 전체 CTA용), 그냥 Wrap 등에 다른 위젯과 나란히 놓으면 내용물 크기만큼만
// 차지함("+추가" 같은 인라인 버튼용). 내부적으로 Row(mainAxisSize: min,
// mainAxisAlignment: center)로 감싸서 처리 - Container의 alignment는 "루즈
// 제약이어도 최대 폭까지 확장"하는 성질이 있어서 Wrap 안에서 의도치 않게
// 가로를 다 차지해버렸던 적이 있음(2026-08-24, 되돌렸다가 이 방식으로 재수정).
//
// ⭐ 크기 값(padding/radius/fontSize)에 flutter_screenutil의 .w/.h/.r/.sp를
// 일부러 안 씀 - app_theme.dart의 ElevatedButtonTheme(아직 안 바뀐 화면들이
// 쓰는 공용 버튼)도 같은 이유로 원시 숫자를 씀. 두 버튼(AppButton vs 기존
// ElevatedButton)이 같은 화면에 같이 있을 수 있는 과도기라, 한쪽만 ScreenUtil로
// 스케일되면 미세하게 크기가 어긋나 보임 - 전부 AppButton으로 옮겨간 뒤에
// 필요하면 그때 같이 .sp로 통일할 것.
//
// ⭐ 구조 - "둥근 버튼 뒤에 각진 연회색 사각형이 같이 보인다"는 버그가 있었음.
// 원인을 Flutter 소스(material.dart)에서 직접 확인함: Material에 borderRadius를
// 주면(shape가 non-null이 되어) 빠른 경로(AnimatedPhysicalModel, 완전히
// 투명 보장)를 안 타고 _MaterialInterior라는 다른 경로로 빠지는데, 그쪽은
// color가 transparent여도 완전히 안 보인다는 보장이 없음. 지금은 그 문제를
// 구조적으로 피함: 그라데이션/링/그림자는 전부 일반 Container(Material 아님)가
// 그리고, 그 안쪽을 ClipRRect로 잘라낸 뒤에야 Material(type: transparency -
// "자기 표면을 아예 안 그리는" 전용 타입, 이 문제 자체가 없음)을 넣음.
//
// ⭐ 링 디자인: 흰 반투명 테두리 하나였다가 "안 보인다"는 피드백으로, 버튼
// 자체 그라데이션을 좌우 반전한 "그라데이션 링"으로 바꿈 - 버튼이 밝은 모서리는
// 링이 어둡게, 버튼이 어두운 모서리는 링이 밝게 겹쳐서 모든 지점에서 버튼과
// 링 사이에 대비가 생기게 함(단색 반투명보다 훨씬 잘 보임). 바깥쪽 Container가
// 이 링 그라데이션을 그리고, 그만큼 안쪽으로 패딩을 줘서 링 두께를 만든 뒤
// 그 안에 버튼 본체(원래 방향 그라데이션)를 얹는 2겹 구조.

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

  static const double _ringWidth = 4.0;  // ⭐ 3.0→4.0, "링을 아주 살짝만 더 두껍게"
  static const _outerRadius = BorderRadius.all(Radius.circular(14));
  static const _innerRadius = BorderRadius.all(Radius.circular(11));

  @override
  Widget build(BuildContext context) {
    // ⭐ 링(바깥) - 버튼 본체 그라데이션을 좌우 반전(begin/end를 서로 바꿈)해서
    // 모든 지점에서 본체와 대비가 생기게 함.
    return Container(
      padding: const EdgeInsets.all(_ringWidth),
      decoration: BoxDecoration(
        borderRadius: _outerRadius,
        gradient: _enabled
            ? const LinearGradient(
                begin: Alignment.bottomRight,
                end: Alignment.topLeft,
                colors: [kAppMainAccentLight, kAppMainAccentDark],
              )
            : null,
        color: _enabled ? null : const Color(0xFF9AA3B0),
        boxShadow: _enabled
            ? [
                // ⭐ 그림자를 검정 대신 버튼 자체 색상 톤으로 - 최근 트렌드인
                // "톤이 들어간(colored) 그림자". 순수 검정 그림자보다 튀지
                // 않고 버튼과 배경이 한 분위기로 이어짐.
                BoxShadow(
                  color: kAppMainAccent.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      // ⭐ 본체(안쪽) - 원래 방향 그라데이션.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: _innerRadius,
          gradient: _enabled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kAppMainAccentLight, kAppMainAccentDark],
                )
              : null,
          color: _enabled ? null : const Color(0xFFDADFE6),
        ),
        child: ClipRRect(
          borderRadius: _innerRadius,
          child: Material(
            // ⭐ transparency 타입 - Material이 자기 표면을 아예 그리지 않음.
            // 위 클래스 주석의 "각진 잔상" 버그를 구조적으로 막는 핵심.
            type: MaterialType.transparency,
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
                        color: _enabled ? Colors.white : const Color(0xFF6B7280),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      child: IconTheme.merge(
                        data: IconThemeData(color: _enabled ? Colors.white : const Color(0xFF6B7280)),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
