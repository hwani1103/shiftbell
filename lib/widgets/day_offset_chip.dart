// lib/widgets/day_offset_chip.dart
//
// ⭐ 2026-08-24 추가, 2026-08-25 재작성 - 고정 알람의 "전날/당일/다음날"
// (day_offset, -1/0/1)을 다루는 공용 Chip 두 종류.
//
// ⭐ 2026-08-25 - 처음엔 자체 도형(_DayOffsetChipShape)을 새로 그렸는데,
// "선택됨"을 진하게 꽉 채운 배경으로 표시하다 보니 second button(빨강/초록
// 단색 버튼)과 구분이 안 된다는 피드백을 받음. 이 앱엔 이미 "선택 불가능한
// 태그"용 공용 칩(app_shift_chip.dart, 근무명 태그에 사용 중)이 있으므로 새로
// 만들지 않고 그걸 그대로 재사용하도록 고침 - AppShiftChip의 selected/dense
// 파라미터가 이번에 그 목적으로 추가됨. 두 위젯은 이제 얇은 래퍼일 뿐임:
//
//   - DayOffsetSelector: 알람 추가/수정 다이얼로그에서 3개를 나란히 놓고 하나를
//     고르는 토글 그룹(AppShiftChip(selected: ...) + onTap). 온보딩/설정 두
//     다이얼로그가 공유.
//   - DayOffsetBadge: 이미 정해진 값을 "09:00" 같은 시간 옆이나 근무명 옆에
//     작게 붙여서 보여주는 표시 전용 칩(AppShiftChip(dense: true), 탭 불가).
//     달력 팝업의 알람 카드, "알람 타입 선택" 팝업, 알람 이력 화면이 공유.
//
// alarm_day_offset.dart의 -1/0/1 정수를 그대로 받음 - 별도 enum을 안 쓰는 이유는
// DB 컬럼/Kotlin 쪽과 전부 이 정수로 직접 주고받아서, enum으로 감쌌다가 다시
// 풀어내는 변환 지점을 화면마다 늘리고 싶지 않아서.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants/alarm_day_offset.dart';
import '../l10n/l10n_extensions.dart';
import 'app_shift_chip.dart';

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

/// 전날/당일/다음날 중 하나를 고르는 토글 그룹. [value]/[onChanged]는 항상
/// alarm_day_offset.dart의 -1/0/1을 씀. 세 칩을 가로 중앙에 자연스러운
/// 크기로 배치함(다이얼로그 폭을 억지로 다 채우지 않음).
class DayOffsetSelector extends StatelessWidget {
  const DayOffsetSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: kAlarmDayOffsets.map((offset) {
        final isLast = offset == kAlarmDayOffsets.last;
        return Padding(
          padding: EdgeInsets.only(right: isLast ? 0 : 8.w),
          child: AppShiftChip(
            label: dayOffsetLabel(context, offset),
            dense: true,
            selected: value == offset,
            onTap: () => onChanged(offset),
          ),
        );
      }).toList(),
    );
  }
}

/// 이미 정해진 전날/당일/다음날 값을 시간/근무명 텍스트 옆에 작게 붙여
/// 보여주는 표시 전용 칩(탭 불가) - 근무명 태그와 같은 모양(AppShiftChip)을
/// dense 크기로 재사용.
class DayOffsetBadge extends StatelessWidget {
  const DayOffsetBadge({super.key, required this.dayOffset});

  final int dayOffset;

  @override
  Widget build(BuildContext context) {
    return AppShiftChip(
      label: dayOffsetLabel(context, dayOffset),
      dense: true,
    );
  }
}
