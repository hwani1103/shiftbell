// lib/widgets/app_button.dart
//
// ⭐ 2026-08-24 추가 - 앱 공용 기본 버튼(주요 액션용, "다음"/"완료"/"시작하기" 등).
//
// 기존엔 ElevatedButton + app_theme.dart의 ElevatedButtonTheme으로 단색 배경
// 버튼을 썼는데, "단색이라 딱딱하다"는 피드백으로 그라데이션 + 흰 테두리 링 +
// 톤이 들어간 은은한 그림자를 주는 이 위젯으로 교체함. Material의 ButtonStyle은
// 배경에 단색만 지정 가능해서(그라데이션 불가) 테마 하나로는 이 효과를 낼 수
// 없었음 - 그래서 커스텀 위젯으로 뺌.
//
// API는 ElevatedButton과 거의 동일하게 맞춤(onPressed, child) - 기존
// ElevatedButton(...) 호출부를 AppButton(...)으로 이름만 바꾸면 대부분 그대로
// 동작함. onPressed가 null이면 ElevatedButton과 똑같이 흐리게 비활성 표시됨.
//
// 적용 범위(2026-08-24 기준): lib/screens/onboarding_screen.dart의 주요 액션
// 버튼들("다음"/"완료"/"시작하기"). "+추가"는 이 버튼으로 바꿨다가 Wrap 안에서
// 가로 전체를 차지해버려서("메인 버튼으로 하니까 가로를 다 잡아먹는다") 다시
// ElevatedButton.icon으로 되돌림 - AppButton은 항상 SizedBox(width:
// double.infinity)로 감싸 "화면 전체 폭 CTA" 용도로만 쓸 것.
//
// ⭐ 크기 값(padding/radius/fontSize)에 flutter_screenutil의 .w/.h/.r/.sp를
// 일부러 안 씀 - app_theme.dart의 ElevatedButtonTheme(아직 안 바뀐 화면들이
// 쓰는 공용 버튼)도 같은 이유로 원시 숫자를 씀. 두 버튼(AppButton vs 기존
// ElevatedButton)이 같은 화면에 같이 있을 수 있는 과도기라, 한쪽만 ScreenUtil로
// 스케일되면 미세하게 크기가 어긋나 보임 - 전부 AppButton으로 옮겨간 뒤에
// 필요하면 그때 같이 .sp로 통일할 것.
//
// ⭐ 2026-08-24 구조 재작성 - "둥근 버튼 뒤에 각진 연회색 사각형이 같이 보인다"는
// 버그 신고. 원인: Material(color: Colors.transparent, borderRadius: ...)만으로는
// Material3의 기본 표면 틴트/그림자 처리가 완전히 안 꺼져서, 버튼의 둥근 모서리
// 밖으로 각진 Material 표면의 흔적이 살짝 비쳤던 것으로 보임. 지금은 그라데이션/
// 테두리/그림자를 그리는 최상위 Container(일반 위젯, Material 아님)를 두고, 그
// 안쪽에 ClipRRect로 완전히 둥글게 잘라낸 Material(type: transparency - "자기
// 표면을 아예 그리지 않는" 전용 타입, canvas 타입의 기본 틴트/그림자 걱정 자체가
// 없음)을 넣는 구조로 바꿈 - 바깥 Container 밖으로는 아무것도 안 그려지고,
// 안쪽 Material은 애초에 아무것도 스스로 그리지 않으므로 각진 잔상이 생길
// 여지가 구조적으로 없음.

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
    final radius = BorderRadius.circular(14);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        // ⭐ "그라데이션이 약하다"는 피드백으로 양 끝 색 차이를 크게 벌림
        // (kAppMainAccentLight/Dark 값 자체를 app_colors.dart에서 더 밝게/
        // 어둡게 재조정함 - 여기서 두 색을 바꾼 게 아니라 그 값들을 키움).
        gradient: _enabled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kAppMainAccentLight, kAppMainAccentDark],
              )
            : null,
        // ⭐ 비활성 상태 - "노란빛이 돌아서 잘 안 보인다"는 피드백으로 채움/
        // 테두리/글자색 전부 명도差가 뚜렷한 회색 계열로 다시 잡음(테두리가
        // 아예 없었던 것도 원인 중 하나 - 배경과 거의 안 구분됐음).
        color: _enabled ? null : const Color(0xFFDADFE6),
        border: Border.all(
          // ⭐ "링이 안 보인다"는 피드백으로 두께(1.2→2.4)와 불투명도(0.28→0.55)
          // 둘 다 크게 키움 - 흰 테두리 링이 또렷하게 보여야 하는 포인트라
          // 어중간하게 옅으면 있으나 마나임.
          color: _enabled ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF9AA3B0),
          width: _enabled ? 2.4 : 1.4,
        ),
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
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          // ⭐ transparency 타입 - Material이 자기 표면을 아예 그리지 않음
          // (canvas 타입의 기본 틴트/그림자 자체가 없는 전용 모드). 위 주석의
          // "각진 잔상" 버그를 구조적으로 막는 핵심.
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              alignment: Alignment.center,
              child: DefaultTextStyle.merge(
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
            ),
          ),
        ),
      ),
    );
  }
}
