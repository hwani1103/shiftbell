// lib/widgets/app_shift_chip.dart
//
// ⭐ 2026-08-24 추가 - 근무명 태그를 표시하는 공통 칩 컴포넌트.
//
// 예전엔 근무명을 그냥 ElevatedButton(child: Text(name))로 표시해서 "버튼"과
// "선택 불가능한 이름 태그"가 시각적으로 구분이 안 됐음(둘 다 각진 사각형 +
// 옅은 radius + 파란 배경 + 흰 글씨). 이 위젯은 버튼과는 다른 디자인 언어를
// 씀 - 훨씬 큰 radius(타원까진 아닌 중간 정도), 두꺼운 테두리, 배경 톤 위에서
// 카드처럼 살짝 뜨는 채움색. 버튼(app_theme.dart의 ElevatedButtonTheme)은
// 그대로 별도로 존재함 - 이 칩으로 대체하는 게 아님.
//
// ⭐ 지금은 lib/screens/onboarding_screen.dart의 _buildShiftTypeCreation()
// (첫 화면으로 승격된 "규칙적" 근무명 지정 화면)에만 적용됨. 같은 모양의
// 근무명 태그가 _buildShiftTypesInput()(불규칙 화면)에도 있는데, 이번 범위에는
// 포함하지 않았음 - 나중에 일관성을 위해 그쪽도 이 위젯으로 옮기는 걸 고려할 것.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_colors.dart';

class AppShiftChip extends StatelessWidget {
  const AppShiftChip({
    super.key,
    required this.label,
    this.onDelete,
  });

  final String label;

  /// null이면 삭제 배지(X)를 안 그림 - 삭제 불가능한 표시 전용 칩으로도 쓸 수 있음.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: kAppChipFill,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: kAppChipBorder, width: 1.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.w600,
          color: kAppChipBorder,
        ),
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
