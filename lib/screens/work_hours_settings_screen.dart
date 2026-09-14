// lib/screens/work_hours_settings_screen.dart
//
// ⭐ 근무시간 및 OT 관련 설정 화면
// 1. 근무 카드별 기본 근무시간 (1시간/30분 단위)
// 2. 월별 총 근무시간을 합산할 기준 기간 (달력 월 vs 급여일 기준)

import '../providers/data_revision_provider.dart';
import '../services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../models/shift_time_range.dart';
import '../providers/condition_shift_time_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/work_hours_settings_provider.dart';
import '../widgets/tappable_number_picker.dart';
import '../l10n/l10n_extensions.dart';

class WorkHoursSettingsScreen extends ConsumerStatefulWidget {
  const WorkHoursSettingsScreen({super.key});

  @override
  ConsumerState<WorkHoursSettingsScreen> createState() => _WorkHoursSettingsScreenState();
}

class _WorkHoursSettingsScreenState extends ConsumerState<WorkHoursSettingsScreen> {
  // ⭐ 2026-08-25 - "급여 산정일 기준"을 고르면 그 아래로 날짜 피커 등 추가
  // 콘텐츠가 펼쳐지는데, 화면 아래쪽이라 스크롤하지 않으면 안 보임 - 골라도
  // 뭐가 바뀌었는지 못 보고 지나치기 쉬웠음. 그 옵션을 고른 직후 자동으로 맨
  // 아래까지 스크롤해서 펼쳐진 내용이 바로 눈에 들어오게 함.
  final _scrollController = ScrollController();

  // ⭐ 2026-09-11(사용자 신고) - "출근만 입력했는데 퇴근이 멋대로 18:00으로
  // 채워진다" 버그 수정용 - ShiftTimeRange는 start/endMinutes가 둘 다
  // non-nullable이라(모델 그대로 유지, DB 마이그레이션 없이 해결하려고 일부러
  // 안 건드림) "한쪽만 입력된" 상태를 그 자체로는 표현할 수 없다. 그래서 아직
  // provider(condition_shift_times, 실제 저장소)에 커밋하기 전, "한쪽만 입력된"
  // 임시 상태를 이 화면 로컬에만 들고 있다가 둘 다 채워진 순간에만 저장한다 -
  // 이미 완성된(range != null) 근무의 한쪽만 고치는 기존 동작(예: 출근시간만
  // 조정)은 기존 값을 그대로 재사용해 즉시 저장되므로 전혀 안 바뀜.
  final Map<String, int> _pendingStartOnlyMinutes = {};
  final Map<String, int> _pendingEndOnlyMinutes = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final schedule = ref.watch(scheduleProvider).value;
    final workSettings = ref.watch(workHoursSettingsProvider);
    // ⭐ 2026-09-01 - "근무별 실제 근무시간"을 시간(분) 직접입력에서 출퇴근 시각
    // 입력으로 바꾸면서, 컨디션 매니저가 쓰는 condition_shift_times도 같이 씀
    // (shift_time_range.dart 참고 - 하나의 입력으로 두 데이터를 같이 채움).
    // 컨디션 탭은 이 값이 하나라도 있어야 동작하므로, 이 화면이 이제 그 입력
    // 지점이 됨(조건매니저_설계.md, 컨디션 탭 자체의 입력 UI는 삭제함).
    final shiftTimes = ref.watch(conditionShiftTimeProvider).value ?? const <String, ShiftTimeRange>{};

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsWorkHoursAndOt)),
      body: schedule == null
          ? Center(
              child: Text(
                context.l10n.workHoursNoScheduleYet,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          // ⭐ 하단 콘텐츠(급여 산정일 기준 펼쳤을 때)가 기기 네비게이션 바에
          // 가려지는 문제 방지 - SafeArea로 감싸고 리스트 맨 아래 여백도 추가.
          : SafeArea(
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 40.h),
                children: [
                // ⭐ 시인성 때문에 맨 위로 - 제목 줄 우측에 바로 스위치가 붙어있어서
                // 이 화면에 들어오자마자 토글만 바로 켜고 나갈 수도 있음.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.workHoursShiftChangeOtTitle,
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
                  context.l10n.workHoursShiftChangeOtDesc,
                  style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),

                SizedBox(height: 28.h),
                Divider(color: colorScheme.outline.withOpacity(0.4)),
                SizedBox(height: 20.h),

                Text(
                  context.l10n.settingsDefaultWorkHoursPerShift,
                  style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4.h),
                Text(
                  context.l10n.workHoursDefaultDurationDesc,
                  style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),
                SizedBox(height: 16.h),
                ...schedule.shiftTypes.map((shift) => _buildShiftTimeTile(schedule, shift, shiftTimes[shift])),

                SizedBox(height: 28.h),
                Divider(color: colorScheme.outline.withOpacity(0.4)),
                SizedBox(height: 20.h),

                Text(
                  context.l10n.settingsMonthlyPeriodBasis,
                  style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4.h),
                Text(
                  context.l10n.workHoursPeriodBasisDesc,
                  style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),
                SizedBox(height: 12.h),
                _buildPeriodModeOption(
                  mode: MonthlyPeriodMode.calendar,
                  current: workSettings.periodMode,
                  title: context.l10n.settingsCalendarMonthBasis,
                  subtitle: context.l10n.settingsCalendarMonthBasisDesc,
                ),
                SizedBox(height: 8.h),
                _buildPeriodModeOption(
                  mode: MonthlyPeriodMode.payday,
                  current: workSettings.periodMode,
                  title: context.l10n.settingsPaydayBasis,
                  subtitle: context.l10n.settingsPaydayBasisDesc,
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

  // ⭐ 2026-09-01 - 예전엔 "근무당 N시간 M분"을 직접 입력받았는데(NumberPicker 2개
  // 다이얼로그), 출퇴근 "시각"을 입력받는 걸로 바꿈 - 컨디션 탭이 회복시간/추천
  // 수면시간대를 계산하려면 시각 자체가 필요한데, 그걸 이 화면에서 같이
  // 받으면 사용자가 입력을 두 번 할 필요가 없음(ShiftTimeRange.durationMinutes가
  // 자정 넘김까지 포함해서 시간을 자동 계산해줌 - shift_time_range.dart 참고).
  // 저장은 두 곳에 동시에: condition_shift_times(컨디션 탭용, 시각 자체)와
  // schedule.shiftDurations(기존 근로시간/OT 계산용, 계산된 분 단위 값) -
  // 기존 소비자(work_hours_calculator.dart 등)는 여전히 shiftDurations만 읽으므로
  // 한 줄도 안 건드림.
  Widget _buildShiftTimeTile(ShiftSchedule schedule, String shift, ShiftTimeRange? range) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shift,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
              ),
              SizedBox(width: 8.w),
              // ⭐ 2026-09-12(2차, 사용자 피드백) - 소요시간 텍스트를 그냥 맨
              // 글자로 두지 않고 옅은 배지(칩)로 감싸서, 바로 옆 되돌리기
              // 버튼과 한 그룹처럼 보이게 다듬음(예전엔 텍스트+아이콘이 서로
              // 남남처럼 붙어있어 어색했음).
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  range == null ? context.l10n.commonNotSet : _formatDuration(range.durationMinutes),
                  maxLines: 1,
                  style: TextStyle(fontSize: 12.5.sp, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ),
              // ⭐ 2026-09-12(사용자 요청) - "어떤 근무든 한 번 시간을 지정하면
              // 되돌릴 수가 없다" - 출퇴근이 이미 채워진(range != null) 근무에만
              // 보여주는 되돌리기 버튼. 눌러도 별도 확인 없이 바로 --:--/--:--로
              // 되돌림(값 자체를 지우는 거라 그 근무의 근로시간/OT 계산이
              // 그때부터 0으로 빠짐 - 실수로 눌렀으면 다시 출퇴근을 입력하면
              // 그만이라 삭제 확인 다이얼로그까지는 과함).
              // ⭐ 2026-09-12(2차) - 배치가 어색하다는 피드백으로 다듬음: 맨
              // 아이콘(delete_outline, 근무 자체를 지우는 것처럼 오해될 수
              // 있음)을 "되돌리기"를 뜻하는 replay 아이콘으로 바꾸고, 옅은
              // 원형 배경(Material+InkWell 리플)을 줘서 위 배지와 한 세트로
              // 보이게, 배지와의 간격도 넉넉히 줌.
              if (range != null) ...[
                SizedBox(width: 6.w),
                Tooltip(
                  message: context.l10n.workHoursResetShiftTime,
                  child: Material(
                    color: colorScheme.error.withValues(alpha: 0.1),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _resetShiftTime(schedule, shift),
                      child: Padding(
                        padding: EdgeInsets.all(6.w),
                        child: Icon(Icons.replay_rounded, size: 15.sp, color: colorScheme.error),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickShiftTime(schedule, shift, range, isStart: true),
                  child: Text(
                    '${context.l10n.workHoursShiftTimeClockIn} '
                    '${_fmtRangeTime(range?.startMinutes ?? _pendingStartOnlyMinutes[shift])}',
                    style: TextStyle(fontSize: 12.5.sp),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickShiftTime(schedule, shift, range, isStart: false),
                  child: Text(
                    '${context.l10n.workHoursShiftTimeClockOut} '
                    '${_fmtRangeTime(range?.endMinutes ?? _pendingEndOnlyMinutes[shift])}',
                    style: TextStyle(fontSize: 12.5.sp),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtRangeTime(int? minutes) {
    if (minutes == null) return '--:--';
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    // ⭐ 영어 UI 레이아웃 수정: 0분은 "설정 안 함" 의미인데(위 getDurationMinutes
    // 주석 참고), 원래 workHoursDurationExcluded("0 hours (not counted as work
    // time)")가 영어에서 너무 길어서 근무명 Expanded 영역을 밀어내 "Day"/
    // "Morning" 같은 짧은 근무명까지 줄바꿈되는 원인이었음. 의미가 사실상 같은
    // commonNotSet("Not Set"/"미설정")으로 교체 - 훨씬 짧아서 레이아웃도 안정됨.
    if (minutes == 0) return context.l10n.commonNotSet;
    if (m == 0) return context.l10n.workHoursDurationHoursOnly(h);
    return context.l10n.workHoursDurationHoursMinutes(h, m);
  }

  Future<void> _pickShiftTime(
    ShiftSchedule schedule,
    String shift,
    ShiftTimeRange? range, {
    required bool isStart,
  }) async {
    // ⭐ 2026-09-11 - 아직 완성 안 된(range == null) 근무는 피커의 초기값으로
    // "9시/18시"를 그냥 들이밀지 않고, 이미 한쪽을 입력해뒀다면(_pendingXOnlyMinutes)
    // 그 값을 그대로 초기값으로 써서 "방금 고른 값이 사라진 것처럼" 보이지 않게 함.
    final currentMinutes = range != null
        ? (isStart ? range.startMinutes : range.endMinutes)
        : (isStart ? (_pendingStartOnlyMinutes[shift] ?? 9 * 60) : (_pendingEndOnlyMinutes[shift] ?? 18 * 60));
    final initial = TimeOfDay(hour: (currentMinutes ~/ 60) % 24, minute: currentMinutes % 60);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    final newMinutes = picked.hour * 60 + picked.minute;
    final startMinutes = isStart ? newMinutes : (range?.startMinutes ?? _pendingStartOnlyMinutes[shift]);
    final endMinutes = isStart ? (range?.endMinutes ?? _pendingEndOnlyMinutes[shift]) : newMinutes;

    if (startMinutes == null || endMinutes == null) {
      // ⭐ 아직 한쪽만 입력됨 - "기록하지 않기" 원칙과 동일하게, 나머지 한쪽을
      // 마저 입력하기 전까지는 DB에 아무 것도 저장하지 않고 화면에만 반영한다
      // (사용자가 신고한 "출근만 입력했는데 퇴근이 멋대로 채워진다" 버그의
      // 원인 - 예전엔 여기서 무조건 기본값(9시/18시)으로 채워 바로 저장했음).
      setState(() {
        if (isStart) {
          _pendingStartOnlyMinutes[shift] = newMinutes;
        } else {
          _pendingEndOnlyMinutes[shift] = newMinutes;
        }
      });
      return;
    }

    // 둘 다 채워졌으니 실제로 저장하고, 로컬 임시 상태는 더 이상 필요 없으니 정리.
    _pendingStartOnlyMinutes.remove(shift);
    _pendingEndOnlyMinutes.remove(shift);
    final newRange = ShiftTimeRange(shiftName: shift, startMinutes: startMinutes, endMinutes: endMinutes);

    await _persistShiftTime(shift, newRange);
  }

  // ⭐ 2026-09-14 (출시전 감사 #28, G1) - 출퇴근 시각(condition_shift_times)과 근로시간(shift_schedule.shift_durations)을
  // 한 트랜잭션으로, DB의 최신 근무표 기준 "이 근무 키만" 저장(DatabaseService.saveShiftTimeRange). 예전엔 두 곳을 따로
  // 저장하고 화면이 들고 있던 옛 schedule 스냅샷의 근로시간 맵 전체를 다시 써서, 한쪽 실패 시 불일치·연속 수정/초기화 시
  // 방금 바꾼 다른 근무 값이 옛 값으로 덮어써졌음. 저장 성공 뒤에만 화면 상태와 변경 통지(contracts §3)를 반영.
  // [range]가 null이면 되돌리기.
  Future<void> _persistShiftTime(String shift, ShiftTimeRange? range) async {
    final saved = await DatabaseService.instance.saveShiftTimeRange(shift, range);
    ref.read(conditionShiftTimeProvider.notifier).applyExternallyPersisted(shift, range, notify: true);
    if (saved != null) {
      ref.read(scheduleProvider.notifier).applyExternallyPersisted(
        saved,
        notifyDomains: const {DataDomain.workHoursSettings},
      );
    }
  }

  // ⭐ 2026-09-12(사용자 요청) - 이미 출퇴근이 채워진 근무를 다시 --:--/--:--로
  // 되돌리는 기능(그동안 한 번 채우면 되돌릴 방법이 아예 없었음). 세 곳을
  // 전부 원상복구해야 함: 1) 임시 상태(_pending...) - 이미 null이지만 방어적으로
  // 같이 지움, 2) 컨디션 탭용 condition_shift_times(ConditionShiftTimeNotifier.remove),
  // 3) 근로시간/OT 계산용 schedule.shiftDurations - 컬럼 삭제가 안 되니(DB_스키마_
  // 변경_가이드.md) 0으로 되돌림(_formatDuration이 0을 "설정 안 함"으로 표시하는
  // 기존 sentinel 그대로 재사용 - 새 마이그레이션 불필요).
  Future<void> _resetShiftTime(ShiftSchedule schedule, String shift) async {
    setState(() {
      _pendingStartOnlyMinutes.remove(shift);
      _pendingEndOnlyMinutes.remove(shift);
    });

    await _persistShiftTime(shift, null);
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
        onTap: () async {
          await ref.read(workHoursSettingsProvider.notifier).setPeriodMode(mode);
          // ⭐ "급여 산정일 기준"을 고르면 그 아래로 날짜 피커 등이 새로 펼쳐짐 -
          // 스크롤 안 하면 화면 밖이라 안 보이므로 고른 직후 맨 아래로 스크롤.
          if (mode == MonthlyPeriodMode.payday) {
            _scrollToBottomNextFrame();
          }
        },
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
          Text(context.l10n.workHoursCutoffDayPrefix, style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurface)),
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
          Text(context.l10n.workHoursCutoffDaySuffix, style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurface)),
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
            label: context.l10n.settingsPeriodStartBasis,
            selected: settings.cutoffAnchor == PaydayCutoffAnchor.periodStart,
            onTap: () => ref.read(workHoursSettingsProvider.notifier).setCutoffAnchor(PaydayCutoffAnchor.periodStart),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _buildAnchorChip(
            label: context.l10n.settingsPeriodEndBasis,
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
        context.l10n.settingsPreviewThisMonth(range),
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: colorScheme.primary),
      ),
    );
  }
}
