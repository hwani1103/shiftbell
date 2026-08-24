// lib/widgets/app_shift_chip.dart
//
// ⭐ 2026-08-24 추가 - 근무명 태그를 표시하는 공통 칩 컴포넌트.
//
// 예전엔 근무명을 그냥 ElevatedButton(child: Text(name))로 표시해서 "버튼"과
// "선택 불가능한 이름 태그"가 시각적으로 구분이 안 됐음(둘 다 각진 사각형 +
// 옅은 radius + 파란 배경 + 흰 글씨). 이 위젯은 버튼과는 다른 디자인 언어를
// 씀 - 큰 radius, 두꺼운 테두리(이 앱의 특색으로 삼기로 함), 배경 톤 위에서
// 카드처럼 살짝 뜨는 채움색. 버튼(app_theme.dart의 ElevatedButtonTheme)은
// 그대로 별도로 존재함 - 이 칩으로 대체하는 게 아님.
//
// ⭐ 2026-08-24 두 번째 수정 - 도형이 너무 커 보인다는 피드백으로 패딩/반지름을
// 줄이고 테두리를 더 두껍게 함(1.6→2.2). 글자 크기는 그대로 유지.
// 또한 onTap을 지원하도록 확장함 - 처음엔 "표시 전용(+삭제)" 용도였는데,
// 온보딩의 패턴 완성 화면(_buildPatternInput)처럼 "탭해서 선택"하는 용도로도
// 같은 칩 모양을 쓰기 위함. onDelete/onTap은 동시에 켤 필요가 없는 서로 다른
// 화면의 용도라 하나의 위젯에서 둘 다 지원하되 실제로는 한쪽만 씀.
//
// 적용 범위(2026-08-24 기준): lib/screens/onboarding_screen.dart의
// _buildShiftTypeCreation()(근무명 지정 화면, onDelete 용도)과
// _buildPatternInput()(패턴 완성 화면 상단의 탭-추가 목록, onTap 용도).
// _buildPatternInput() 안의 "이미 완성된 패턴" 그리드(_buildPatternGrid)는
// 이번 범위 아님 - 그대로 둠. _buildShiftTypesInput()(불규칙 화면)의 동일한
// 근무명 태그도 아직 이번 범위 아님(추후 적용 예정).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_colors.dart';

class AppShiftChip extends StatelessWidget {
  const AppShiftChip({
    super.key,
    required this.label,
    this.onDelete,
    this.onTap,
    this.enabled = true,
  });

  final String label;

  /// null이면 삭제 배지(X)를 안 그림 - 삭제 불가능한 표시 전용 칩으로도 쓸 수 있음.
  final VoidCallback? onDelete;

  /// null이 아니면 칩 자체가 탭 가능해짐(예: 패턴에 추가) - onDelete와는 별개.
  final VoidCallback? onTap;

  /// false면 탭 비활성 + 흐리게 표시(기존 ElevatedButton의 onPressed:null과
  /// 같은 시각 효과를 재현) - onTap을 쓸 때만 의미 있음.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final radius = 16.r;
    final borderColor = enabled ? kAppChipBorder : kAppChipBorder.withValues(alpha: 0.35);
    final fillColor = enabled ? kAppChipFill : kAppChipFill.withValues(alpha: 0.6);
    final textColor = enabled ? kAppChipBorder : kAppChipBorder.withValues(alpha: 0.45);

    final chipBody = Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(radius),
        // ⭐ 두꺼운 테두리(2.2) - 이 앱의 칩을 다른 앱과 구분 짓는 특색으로 삼기로 함.
        border: Border.all(color: borderColor, width: 2.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );

    // onTap이 있으면 InkWell로 감싸 눌림 효과를 줌 - 칩의 둥근 모서리와
    // 잉크 이펙트 모양이 어긋나지 않도록 같은 radius를 씀.
    final chip = onTap == null
        ? chipBody
        : Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: enabled ? onTap : null,
              child: chipBody,
            ),
          );

    if (onDelete == null) return chip;

    // ⭐ 삭제 배지 위치/크기는 기존 ElevatedButton 버전과 동일하게 유지
    // (Positioned(right:-4, top:-4), 20.w×20.h 원) - 칩 모양만 바뀌고 삭제
    // 동작의 탭 위치/크기는 그대로라 사용자가 다시 익힐 필요가 없음.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        chip,
        Positioned(
          right: -4,
          top: -4,
          child: GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 20.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 14.sp,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
