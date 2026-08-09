// lib/screens/work_hours_settings_screen.dart
//
// ⭐ 근로시간 및 OT 관련 설정 화면
// 1. 근무 카드별 기본 근로시간 (1시간/30분 단위)
// 2. 월별 총 근로시간을 합산할 기준 기간 (달력 월 vs 급여일 기준)

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../providers/schedule_provider.dart';
import '../providers/work_hours_settings_provider.dart';
import '../widgets/tappable_number_picker.dart';

class WorkHoursSettingsScreen extends ConsumerStatefulWidget {
  const WorkHoursSettingsScreen({super.key});

  @override
  ConsumerState<WorkHoursSettingsScreen> createState() => _WorkHoursSettingsScreenState();
}

class _WorkHoursSettingsScreenState extends ConsumerState<WorkHoursSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final schedule = ref.watch(scheduleProvider).value;
    final workSettings = ref.watch(workHoursSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('근로시간 및 OT 설정')),
      body: schedule == null
          ? Center(
              child: Text(
                '근무 스케줄을 먼저 설정해주세요',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          // ⭐ 하단 콘텐츠(급여 산정일 기준 펼쳤을 때)가 기기 네비게이션 바에
          // 가려지는 문제 방지 - SafeArea로 감싸고 리스트 맨 아래 여백도 추가.
          : SafeArea(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 40.h),
                children: [
                // ⭐ 시인성 때문에 맨 위로 - 제목 줄 우측에 바로 스위치가 붙어있어서
                // 이 화면에 들어오자마자 토글만 바로 켜고 나갈 수도 있음.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '근무 변경 시 OT 처리',
                        style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Switch(
                      value: workSettings.shiftChangeCountsAsOt,
                      onChanged: (v) => ref.read(workHoursSettingsProvider.notifier).setShiftChangeCountsAsOt(v),
                      activeColor: colorScheme.primary,
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  '달력에서 근무를 바꾸면(예: 휴무 → 주간), 원래 패턴보다 늘어난 시간을 "이번 달 OT"에 자동으로 더해서 보여줄지 정해요. 월별/주별 총 근로시간 자체는 이 설정과 무관하게 항상 동일해요.',
                  style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),

                SizedBox(height: 28.h),
                Divider(color: colorScheme.outline.withOpacity(0.4)),
                SizedBox(height: 20.h),

                Text(
                  '근무별 기본 근로시간',
                  style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4.h),
                Text(
                  '달력의 "이번 달 총 근로시간"과 "주별 근무시간"이 여기 값을 기준으로 계산돼요.',
                  style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),
                SizedBox(height: 16.h),
                ...schedule.shiftTypes.map((shift) => _buildDurationTile(schedule, shift)),

                SizedBox(height: 28.h),
                Divider(color: colorScheme.outline.withOpacity(0.4)),
                SizedBox(height: 20.h),

                Text(
                  '월별 총 근로시간 기준 기간',
                  style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4.h),
                Text(
                  '이번 달의 총 근로시간 및 OT 합산 기준을 정해요.',
                  style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),
                SizedBox(height: 12.h),
                _buildPeriodModeOption(
                  mode: MonthlyPeriodMode.calendar,
                  current: workSettings.periodMode,
                  title: '달력 월 기준',
                  subtitle: '매월 1일 ~ 말일',
                ),
                SizedBox(height: 8.h),
                _buildPeriodModeOption(
                  mode: MonthlyPeriodMode.payday,
                  current: workSettings.periodMode,
                  title: '급여 산정일 기준',
                  subtitle: '직접 정한 날짜를 기준으로 매달 합산',
                ),

                if (workSettings.periodMode == MonthlyPeriodMode.payday) ...[
                  SizedBox(height: 16.h),
                  _buildCutoffDayPicker(workSettings.paydayCutoffDay),
                  SizedBox(height: 12.h),
                  _buildCutoffAnchorToggle(workSettings),
                  SizedBox(height: 12.h),
                  _buildPeriodPreview(workSettings),
                ],
                ],
              ),
            ),
    );
  }

  Widget _buildDurationTile(ShiftSchedule schedule, String shift) {
    final colorScheme = Theme.of(context).colorScheme;
    final minutes = schedule.getDurationMinutes(shift);

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: () => _editDuration(schedule, shift, minutes),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shift,
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                  ),
                ),
                Text(
                  _formatDuration(minutes),
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
                SizedBox(width: 6.w),
                Icon(Icons.chevron_right, size: 20.sp, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (minutes == 0) return '0시간 (근로시간 미포함)';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  Future<void> _editDuration(ShiftSchedule schedule, String shift, int currentMinutes) async {
    int hour = (currentMinutes ~/ 60).clamp(0, 23);
    int minute = (currentMinutes % 60) >= 30 ? 30 : 0;

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: Text('"$shift" 기본 근로시간'),
              content: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TappableNumberPicker(
                    value: hour,
                    minValue: 0,
                    maxValue: 23,
                    itemHeight: 44.h,
                    itemWidth: 56.w,
                    textStyle: TextStyle(fontSize: 15.sp, color: colorScheme.onSurfaceVariant),
                    selectedTextStyle: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colorScheme.outline),
                        bottom: BorderSide(color: colorScheme.outline),
                      ),
                    ),
                    onChanged: (v) => setDialogState(() => hour = v),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: Text('시간', style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant)),
                  ),
                  TappableNumberPicker(
                    value: minute,
                    minValue: 0,
                    maxValue: 30,
                    step: 30,
                    itemHeight: 44.h,
                    itemWidth: 56.w,
                    textStyle: TextStyle(fontSize: 15.sp, color: colorScheme.onSurfaceVariant),
                    selectedTextStyle: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colorScheme.outline),
                        bottom: BorderSide(color: colorScheme.outline),
                      ),
                    ),
                    onChanged: (v) => setDialogState(() => minute = v),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Text('분', style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, hour * 60 + minute),
                  child: Text('확인'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final newDurations = Map<String, int>.from(schedule.shiftDurations ?? {});
    newDurations[shift] = result;

    final newSchedule = ShiftSchedule(
      id: schedule.id,
      isRegular: schedule.isRegular,
      pattern: schedule.pattern,
      todayIndex: schedule.todayIndex,
      shiftTypes: schedule.shiftTypes,
      activeShiftTypes: schedule.activeShiftTypes,
      startDate: schedule.startDate,
      shiftColors: schedule.shiftColors,
      assignedDates: schedule.assignedDates,
      shiftDurations: newDurations,
    );

    await ref.read(scheduleProvider.notifier).updateSchedule(newSchedule);
  }

  // ⭐ 선택된 상태 배경색. 라이트 모드에서 colorScheme.primaryContainer가
  // 별도로 지정되어 있지 않아 primary(진한 인디고)로 대체되는 바람에
  // withOpacity를 걸어도 여전히 진하고 글씨(같은 primary색)와 대비가
  // 잘 안 됐던 문제 - 라이트/다크를 나눠서 라이트는 primary를 아주 옅게만
  // 깔아 확실히 밝게, 다크는 기존 방식(이미 괜찮다고 확인됨) 그대로 유지.
  Color _selectedBg(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? colorScheme.primaryContainer.withOpacity(0.5) : colorScheme.primary.withOpacity(0.08);
  }

  Widget _buildPeriodModeOption({
    required MonthlyPeriodMode mode,
    required MonthlyPeriodMode current,
    required String title,
    required String subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = mode == current;

    return Material(
      color: isSelected ? _selectedBg(context) : colorScheme.surfaceVariant.withOpacity(0.3),
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => ref.read(workHoursSettingsProvider.notifier).setPeriodMode(mode),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outline.withOpacity(0.4),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isSelected ? colorScheme.primary : colorScheme.outline,
                size: 20.sp,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                    SizedBox(height: 2.h),
                    Text(subtitle, style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCutoffDayPicker(int currentDay) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: colorScheme.outline.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Text('매월', style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurface)),
          // ⭐ "일"을 피커 바로 옆에 좁게 붙이지 않고, "매월"과 대칭되게 오른쪽
          // 끝에 독립적으로 배치 - 매월 [ 가운데 피커 ] 일, 형태로 균형 잡음.
          Expanded(
            child: Center(
              child: TappableNumberPicker(
                value: currentDay,
                minValue: 1,
                maxValue: 31,
                axis: Axis.horizontal,
                itemHeight: 40.h,
                itemWidth: 48.w,
                textStyle: TextStyle(fontSize: 13.sp, color: colorScheme.onSurfaceVariant),
                selectedTextStyle: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colorScheme.outline),
                    right: BorderSide(color: colorScheme.outline),
                  ),
                ),
                onChanged: (v) => ref.read(workHoursSettingsProvider.notifier).setPaydayCutoffDay(v),
              ),
            ),
          ),
          Text('일', style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurface)),
        ],
      ),
    );
  }

  // ⭐ 회사마다 "기준일"을 기간의 어느 쪽으로 보는지가 달라서 (예: 20일 기준 →
  // "전월21~당월20" / "전월20~당월19") 두 방식 중 고를 수 있게 함.
  Widget _buildCutoffAnchorToggle(WorkHoursSettings settings) {
    return Row(
      children: [
        Expanded(
          child: _buildAnchorChip(
            label: '시작일 기준',
            selected: settings.cutoffAnchor == PaydayCutoffAnchor.periodStart,
            onTap: () => ref.read(workHoursSettingsProvider.notifier).setCutoffAnchor(PaydayCutoffAnchor.periodStart),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _buildAnchorChip(
            label: '종료일 기준',
            selected: settings.cutoffAnchor == PaydayCutoffAnchor.periodEnd,
            onTap: () => ref.read(workHoursSettingsProvider.notifier).setCutoffAnchor(PaydayCutoffAnchor.periodEnd),
          ),
        ),
      ],
    );
  }

  Widget _buildAnchorChip({required String label, required bool selected, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? _selectedBg(context) : colorScheme.surfaceVariant.withOpacity(0.3),
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: selected ? colorScheme.primary : colorScheme.outline.withOpacity(0.4),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  // ⭐ 지금 설정대로면 이번 달 기준 기간이 실제로 며칠~며칠이 되는지 바로
  // 보여줌 - 기준일/시작·종료·모두포함 조합이 헷갈릴 수 있어서 즉시 확인
  // 가능하게 함. 연도와 "기준" 접미사는 빼고 날짜만 짧게 보여줌.
  Widget _buildPeriodPreview(WorkHoursSettings settings) {
    final colorScheme = Theme.of(context).colorScheme;
    final range = settings.periodRangeShort(DateTime.now());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.primaryContainer.withOpacity(0.25) : colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Text(
        '미리보기: 이번 달 기준 $range',
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: colorScheme.primary),
      ),
    );
  }
}
