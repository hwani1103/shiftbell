// lib/widgets/day_offset_chip.dart
//
// ⭐ 2026-08-24 추가 - 고정 알람의 "전날/당일/다음날"(day_offset, -1/0/1)을
// 다루는 공용 Chip 두 종류. 하나의 내부 모양(_DayOffsetChipShape)을 재사용해서
// 두 위젯을 만듦 - 화면마다 새로 그리지 않고 항상 같은 모양으로 보이게 함:
//
//   - DayOffsetSelector: 알람 추가/수정 다이얼로그에서 3개를 나란히 놓고 하나를
//     고르는 토글 그룹(선택된 것만 채워짐). 온보딩/설정 두 다이얼로그가 공유.
//   - DayOffsetBadge: 이미 정해진 값을 "09:00" 같은 시간 옆에 작게 붙여서
//     보여주는 표시 전용 칩. 달력 팝업의 알람 카드, "알람 타입 선택" 팝업,
//     알람 이력 화면이 공유. 숫자(시간 텍스트)와 나란히 있어도 크기가 튀지
//     않도록 패딩/글자 크기를 작게 줌("Chip 크기는 숫자랑 비슷하게").
//
// alarm_day_offset.dart의 -1/0/1 정수를 그대로 받음 - 별도 enum을 안 쓰는 이유는
// DB 컬럼/Kotlin 쪽과 전부 이 정수로 직접 주고받아서, enum으로 감쌌다가 다시
// 풀어내는 변환 지점을 화면마다 늘리고 싶지 않아서.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants/alarm_day_offset.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_colors.dart';

String dayOffsetLabel(BuildContext context, int dayOffset) {
  switch (dayOffset) {
    case kAlarmDayBefore:
      return context.l10n.alarmDayBefore;
    case kAlarmDayAfter:
      return context.l10n.alarmDayAfter;
    default:
      return context.l10n.alarmDaySame;
  }
}

class _DayOffsetChipShape extends StatelessWidget {
  const _DayOffsetChipShape({
    required this.label,
    required this.selected,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final radius = (dense ? 8.r : 16.r);
    final body = Container(
      padding: dense
          ? EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h)
          : EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? kAppMainAccent : kAppChipFill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? kAppMainAccent : kAppChipBorder.withValues(alpha: 0.5),
          width: dense ? 1.2 : 2.0,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 11.sp : 14.sp,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : kAppChipBorder,
        ),
      ),
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        splashColor: kAppMainAccent.withValues(alpha: 0.25),
        highlightColor: kAppMainAccent.withValues(alpha: 0.15),
        child: body,
      ),
    );
  }
}

/// 전날/당일/다음날 중 하나를 고르는 토글 그룹. [value]/[onChanged]는 항상
/// alarm_day_offset.dart의 -1/0/1을 씀.
class DayOffsetSelector extends StatelessWidget {
  const DayOffsetSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: kAlarmDayOffsets.map((offset) {
        final isLast = offset == kAlarmDayOffsets.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 8.w),
            child: _DayOffsetChipShape(
              label: dayOffsetLabel(context, offset),
              selected: value == offset,
              onTap: () => onChanged(offset),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 이미 정해진 전날/당일/다음날 값을 시간 텍스트 옆에 작게 붙여 보여주는
/// 표시 전용 칩(탭 불가).
class DayOffsetBadge extends StatelessWidget {
  const DayOffsetBadge({super.key, required this.dayOffset});

  final int dayOffset;

  @override
  Widget build(BuildContext context) {
    return _DayOffsetChipShape(
      label: dayOffsetLabel(context, dayOffset),
      selected: true,
      dense: true,
    );
  }
}
