import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/platform_channel.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import 'onboarding_screen.dart';
import 'all_alarms_history_view.dart';
import '../services/alarm_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../providers/calendar_theme_provider.dart';
import '../models/calendar_theme.dart';
import '../models/alarm_type.dart';
import '../models/alarm.dart';
import '../constants/alarm_limits.dart';
import '../models/shift_schedule.dart';
import 'all_teams_setup_dialog.dart';
import 'memo_list_view.dart';
import 'work_hours_settings_screen.dart';
import 'calendar_theme_picker_screen.dart';
import '../widgets/tappable_number_picker.dart';
import '../l10n/l10n_extensions.dart';
import '../constants/shift_name_limits.dart';

class SettingsTab extends ConsumerStatefulWidget {
  final VoidCallback? onSwipeToCalendar;  // ⭐ 6번 기능: 스와이프 callback

  const SettingsTab({super.key, this.onSwipeToCalendar});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {

  Future<void> _resetSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.shiftResetSchedule),
        content: Text(context.l10n.settingsResetScheduleConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonReset, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final alarms = await DatabaseService.instance.getAllAlarms();
      for (var alarm in alarms) {
        if (alarm.id != null) {
          await AlarmService().cancelAlarm(alarm.id!);
        }
      }

      await ref.read(scheduleProvider.notifier).resetSchedule();

      // ⭐ 전체 교대조 근무표 데이터 초기화
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('all_teams_names');
      await prefs.remove('all_teams_indices');
      print('✅ 전체 교대조 근무표 데이터 초기화 완료');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => OnboardingScreen()),
        );
      }
    }
  }

  Future<void> _showAlarmListDialog() async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    // ⭐ Null 체크 추가: date가 null인 알람은 맨 뒤로
    alarms.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return a.date!.compareTo(b.date!);
    });

    final now = DateTime.now();
    final futureAlarms = alarms.where((a) => a.date != null && a.date!.isAfter(now)).toList();
    final pastAlarms = alarms.where((a) => a.date != null && a.date!.isBefore(now)).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.alarm, color: Theme.of(context).colorScheme.secondary),
            SizedBox(width: 8.w),
            Text(context.l10n.alarmRegistered),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: 500.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCountItem(context.l10n.alarmCountFuture, futureAlarms.length, Colors.green),
                    _buildCountItem(context.l10n.alarmCountPast, pastAlarms.length, Colors.grey),
                    _buildCountItem(context.l10n.alarmCountAll, alarms.length, Colors.blue),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              if (alarms.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.h),
                    child: Text(context.l10n.alarmNoneRegistered, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: alarms.length,
                    itemBuilder: (context, index) {
                      final alarm = alarms[index];
                      // ⭐ CRITICAL FIX: null 체크 추가
                      if (alarm.date == null) {
                        return SizedBox.shrink();
                      }

                      final isPast = alarm.date!.isBefore(now);
                      final isToday = alarm.date!.year == now.year &&
                                     alarm.date!.month == now.month &&
                                     alarm.date!.day == now.day;

                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 2.h),
                        child: Text(
                          '${_formatDate(alarm.date!)} ${alarm.shiftType ?? context.l10n.alarmTitle}${isToday ? " (${context.l10n.commonToday})" : ""}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontFamily: 'monospace',
                            color: isPast ? Colors.grey : (isToday ? Colors.orange : Theme.of(context).colorScheme.onSurface),
                            decoration: isPast ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }

  Widget _buildCountItem(String label, int count, Color color) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11.sp)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showAlarmTypeDialog() async {
    final alarmTypes = await DatabaseService.instance.getAllAlarmTypes();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AlarmTypeSettingsSheet(
        alarmTypes: alarmTypes,
        onUpdate: () {
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scheduleAsync = ref.watch(scheduleProvider);

    return GestureDetector(
      // ⭐ 6번 기능: 좌→우 스와이프로 달력탭 이동
      onHorizontalDragEnd: (details) {
        if (widget.onSwipeToCalendar != null && details.primaryVelocity != null) {
          // 좌→우 스와이프 (velocity > 0)
          if (details.primaryVelocity! > 500) {
            widget.onSwipeToCalendar!();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Spacer(),
              Padding(
                padding: EdgeInsets.only(right: 16.w),
                child: Text(context.l10n.navSettings),
              ),
            ],
          ),
        ),
        body: scheduleAsync.when(
        loading: () => const SizedBox.shrink(),  // ⭐ 로딩 인디케이터 제거
        error: (error, stack) => Center(child: Text('${context.l10n.statusErrorOccurred}: $error')),
        data: (schedule) {
          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              // 현재 스케줄 정보
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5),
                ),
                child: Column(
                  children: [
                    // 헤더
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(10.r),
                          topRight: Radius.circular(10.r),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.onPrimary, size: 20.sp),
                          SizedBox(width: 8.w),
                          Text(
                            context.l10n.settingsShiftManagement,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 내용
                    Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (schedule == null)
                            Text(context.l10n.settingsNotSet, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                          else if (schedule.isRegular && schedule.pattern != null)
                            _buildPatternRow(schedule.pattern!)
                          else
                            _buildShiftTypesRow((schedule.activeShiftTypes ?? schedule.shiftTypes)),
                        ],
                      ),
                    ),
                    // ⭐ 수정 | 초기화 버튼 나란히 배치
                    Divider(height: 1, color: Theme.of(context).colorScheme.primary),
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          // 수정 버튼
                          Expanded(
                            child: InkWell(
                              onTap: () => _showScheduleSettingsMenu(),
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(10.r),
                              ),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit, color: Theme.of(context).colorScheme.primary, size: 16.sp),
                                    SizedBox(width: 6.w),
                                    Text(
                                      context.l10n.commonEdit,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 구분선
                          VerticalDivider(width: 1, color: Theme.of(context).colorScheme.primary),
                          // 초기화 버튼
                          Expanded(
                            child: InkWell(
                              onTap: _resetSchedule,
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(10.r),
                              ),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.refresh, color: Theme.of(context).colorScheme.error, size: 16.sp),
                                    SizedBox(width: 6.w),
                                    Text(
                                      context.l10n.commonReset,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.error,
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16.h),

              // ⭐ "전체 교대조 근무표 작성" 진입점 삭제 - 그 기능은 앞으로
              // 메인 달력탭에서 직접 탭해서 설정하는 방식으로 옮길 예정(별도
              // 작업). 지금은 여기 진입점만 없앰 - _showAllTeamsSetupDialog()
              // 등 관련 함수/다이얼로그는 나중에 재사용할 수 있어 그대로 둠.

              // 알람음 관리
              ListTile(
                leading: Icon(Icons.notifications_active, color: Theme.of(context).colorScheme.tertiary),
                title: Text(context.l10n.alarmSoundManage),
                subtitle: Text(context.l10n.settingsAlarmSoundManageDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: _showAlarmTypeDialog,
              ),

              // ⭐ "근로"를 전부 "근무"로 통일 (탭 제목/부제 포함).
              ListTile(
                leading: Icon(Icons.work_history_outlined, color: Theme.of(context).colorScheme.tertiary),
                title: Text(context.l10n.settingsWorkHoursAndOt),
                subtitle: Text(context.l10n.settingsWorkHoursAndOtDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WorkHoursSettingsScreen()),
                  );
                },
              ),

              // ⭐ "달력 테마랑 친구 공유 순서를 바꿔서 달력 테마를 3번으로"
              // 요청으로 순서 교체(달력 테마가 이제 3번째, 친구 공유가 4번째).
              // ⭐ 다크모드 토글 삭제됨 - "다크모드"라는 전역 개념 자체가
              // 없어지고 아래 "달력 테마" 선택(캐러셀)으로 완전히 흡수됨.
              // 9개 테마 중 하나(메인·다크)를 고르면 그게 곧 다크 테마임.
              // ⭐ "근무명 색상 변경"도 여기로 흡수됨 - 색상은 더 이상 개별
              // 지정이 아니라 테마 선택 하나로 전부 결정됨.
              ListTile(
                leading: Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.primary),
                title: Text(context.l10n.calendarTheme),
                subtitle: Text(ref.watch(calendarThemeProvider).label(context)),
                trailing: Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CalendarThemePickerScreen(onApplied: widget.onSwipeToCalendar),
                  ));
                },
              ),

              // ⭐ 일정 공유(구 "친구 공유")는 메인 바텀 네비게이션 4번째 탭으로
              // 승격돼서 여기서는 빠짐 (lib/main.dart 참고).

              // ⭐ 구분선 - "이력/데이터" 섹션
              SizedBox(height: 24.h),
              Divider(),

              // 알람 이력
              ListTile(
                leading: Icon(Icons.alarm_on, color: Theme.of(context).colorScheme.primary),
                title: Text(context.l10n.alarmHistory),
                subtitle: Text(context.l10n.settingsAlarmHistoryDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AllAlarmsHistoryView()),
                  );
                },
              ),

              // 메모 모아보기
              ListTile(
                leading: Icon(Icons.note_outlined, color: Colors.amber.shade700),
                title: Text(context.l10n.calendarMemoAll),
                subtitle: Text(context.l10n.settingsMemoAllDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => MemoListView()),
                  );
                },
              ),

              // ⭐ 모든 알람 완전 삭제
              ListTile(
                leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                title: Text(
                  context.l10n.alarmDeleteAllPermanently,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: Text(context.l10n.settingsDeleteAllAlarmsDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.l10n.alarmDeleteAllPermanently),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.settingsActionCannotBeUndone,
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Text(context.l10n.settingsAllAlarmsWillBeDeleted),
                          SizedBox(height: 8.h),
                          Text(context.l10n.settingsMustRecreateAlarms),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(context.l10n.commonCancel),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                          child: Text(context.l10n.commonDeletePermanently, style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    try {
                      await ref.read(alarmNotifierProvider.notifier).deleteAllAlarmsCompletely();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('🗑️ ${context.l10n.settingsAllAlarmsDeletedToast}'),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('❌ ${context.l10n.statusDeleteFailed}: $e')),
                        );
                      }
                    }
                  }
                },
              ),

              // ⭐ 구분선 (도움말 섹션)
              SizedBox(height: 24.h),
              Divider(),
              SizedBox(height: 8.h),

              // 도움말
              ListTile(
                leading: Icon(Icons.help_outline, color: Theme.of(context).colorScheme.secondary),
                title: Text(context.l10n.settingsHelp),
                subtitle: Text(context.l10n.settingsHelpDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: () => _showHelpDialog(),
              ),

              // 개인정보처리방침
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined, color: Colors.teal),
                title: Text(context.l10n.settingsPrivacyPolicy),
                trailing: Icon(Icons.chevron_right),
                onTap: () => _openPrivacyPolicy(),
              ),

            ],
          );
        },
      ),
      ),  // ⭐ GestureDetector child 닫기
    );
  }

  // ⭐ 도움말 다이얼로그
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Theme.of(context).colorScheme.secondary),
            SizedBox(width: 8.w),
            Text(context.l10n.settingsHelp),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpItem(
                number: '1',
                title: context.l10n.settingsHelpRefreshCycleTitle,
                description: context.l10n.settingsHelpRefreshCycleDesc,
              ),
              SizedBox(height: 16.h),
              _buildHelpItem(
                number: '2',
                title: context.l10n.settingsHelpChangeShiftTitle,
                description: context.l10n.settingsHelpChangeShiftDesc,
              ),
              SizedBox(height: 16.h),
              _buildHelpItem(
                number: '3',
                title: context.l10n.settingsHelpTeamChangeTitle,
                description: context.l10n.settingsHelpTeamChangeDesc,
              ),
              SizedBox(height: 16.h),
              _buildHelpItem(
                number: '4',
                title: context.l10n.settingsHelpDataStorageTitle,
                description: context.l10n.settingsHelpDataStorageDesc,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonOk),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem({
    required String number,
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24.w,
              height: 24.w,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.surface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.only(left: 32.w),
          child: Text(
            description,
            style: TextStyle(
              fontSize: 14.sp,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ⭐ 개인정보처리방침 열기
  void _openPrivacyPolicy() {
    // TODO: 실제 URL로 변경
    const url = 'https://YOUR_GITHUB_USERNAME.github.io/shiftbell-privacy/';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsPrivacyPolicy),
        content: SingleChildScrollView(
          child: Text(
            context.l10n.settingsPrivacyPolicyBody,
            style: TextStyle(fontSize: 13.sp, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }

  // 교대 패턴 표시 (규칙적)
  Widget _buildPatternRow(List<String> pattern) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.shiftPattern,
          style: TextStyle(
            fontSize: 12.sp,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 4.w,
          runSpacing: 6.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (int i = 0; i < pattern.length; i++) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(color: Theme.of(context).colorScheme.primary),
                ),
                child: Text(
                  pattern[i],
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              if (i < pattern.length - 1)
                Icon(Icons.arrow_forward, size: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ],
    );
  }

  // 근무명 표시 (불규칙)
  Widget _buildShiftTypesRow(List<String> shiftTypes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.shiftName,
          style: TextStyle(
            fontSize: 12.sp,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 6.w,
          runSpacing: 6.h,
          children: shiftTypes.map((type) => Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(6.r),
              border: Border.all(color: Theme.of(context).colorScheme.primary),
            ),
            child: Text(
              type,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  // ⭐ 스케줄 설정 메뉴 (바텀시트)
  void _showScheduleSettingsMenu() {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              // ⭐ 스케줄 변경 (규칙적 근무자만)
              if (schedule.isRegular && schedule.pattern != null)
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: Colors.teal.shade600),
                  title: Text(context.l10n.shiftChangeSchedule),
                  subtitle: Text(context.l10n.settingsChangeScheduleDesc),
                  onTap: () {
                    Navigator.pop(context);
                    _showChangeScheduleDialog();
                  },
                ),
              if (schedule.isRegular && schedule.pattern != null)
                Divider(height: 1),
              ListTile(
                leading: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                title: Text(context.l10n.settingsEditShiftNameTitle),
                subtitle: Text(context.l10n.settingsRenameShiftDesc),
                onTap: () {
                  Navigator.pop(context);
                  _showEditShiftNamesDialog();
                },
              ),
              // ⭐ 2026-08-19 "근무명 색상 변경" 기능 복원 - "달력 테마" 선택은
              // 여전히 근무별 디폴트 색을 정하지만, 여기서 사용자가 특정 근무의
              // 색을 직접 바꾸면 그 근무는 테마를 바꿔도 그 색으로 고정됨
              // (models/calendar_theme.dart의 effectiveShiftColors 참고).
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.palette, color: Colors.purple.shade400),
                title: Text(context.l10n.settingsEditShiftColorTitle),
                subtitle: Text(context.l10n.settingsEditShiftColorDesc),
                onTap: () {
                  Navigator.pop(context);
                  _showEditShiftColorsDialog();
                },
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.alarm, color: Theme.of(context).colorScheme.tertiary),
                title: Text(context.l10n.settingsEditFixedAlarmTitle),
                subtitle: Text(context.l10n.settingsChangeAlarmTimeDesc),
                onTap: () {
                  Navigator.pop(context);
                  _showEditFixedAlarmsScreen();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 스케줄 변경 다이얼로그 (조 변경 시 사용)
  void _showChangeScheduleDialog() {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null || schedule.pattern == null) return;

    showDialog(
      context: context,
      builder: (context) => _ChangeScheduleDialog(
        pattern: schedule.pattern!,
        onConfirm: (selectedIndex) async {
          await _applyScheduleChange(selectedIndex);
        },
      ),
    );
  }

  // ⭐ 스케줄 변경 적용
  Future<void> _applyScheduleChange(int selectedIndex) async {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    // 로딩 표시
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.surface),
              ),
              SizedBox(width: 12),
              Text(context.l10n.settingsScheduleChanging),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }

    try {
      // 1. 스케줄 업데이트 (startDate = 오늘, todayIndex = 선택한 인덱스)
      final newSchedule = ShiftSchedule(
        id: schedule.id,
        isRegular: schedule.isRegular,
        pattern: schedule.pattern,
        todayIndex: selectedIndex,
        shiftTypes: schedule.shiftTypes,
        activeShiftTypes: schedule.activeShiftTypes,
        startDate: DateTime.now(),  // ⭐ 오늘로 변경
        shiftColors: schedule.shiftColors,
        customShiftColors: schedule.customShiftColors,
        assignedDates: {},  // ⭐ 수동 할당 초기화
        shiftDurations: schedule.shiftDurations,
      );

      await ref.read(scheduleProvider.notifier).saveSchedule(newSchedule);

      // 2. ⭐ Dart에서 직접 전체 삭제 후 재생성하지 않고 Native의 diff 기반
      // 갱신 엔진에 위임함. Dart가 직접 전체를 지우고 다시 만들면, 실제로는
      // 안 바뀐 알람까지도 "일정 변경"으로 이력에 잘못 찍히는 문제가 있었음
      // (Native 엔진은 실제로 달라진 것만 골라서 건드림).
      const platform = kAlarmChannel;
      try {
        await platform.invokeMethod('forceNativeRefresh');
      } catch (e) {
        print('⚠️ Native 갱신 실패: $e');
      }

      // 3. Notification 취소
      try {
        await platform.invokeMethod('cancelNotification');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }

      // 4. Native가 비동기로 diff 갱신을 마칠 시간을 잠깐 기다린 후 UI 갱신
      await Future.delayed(Duration(milliseconds: 800));
      await ref.read(alarmNotifierProvider.notifier).refresh();

      // 5. diff 갱신이 끝난 "이후" 상태 기준으로 20분 전 알림(8888) 재계산
      // (위 cancelNotification은 diff가 끝나기 전이라 낡은 상태로 계산될 수 있음)
      try {
        await platform.invokeMethod('triggerGuardCheck');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${context.l10n.statusScheduleUpdated}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('❌ 스케줄 변경 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${context.l10n.settingsScheduleChangeFailedWithError(e.toString())}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ⭐ 근무명 수정 다이얼로그
  void _showEditShiftNamesDialog() {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    final activeShifts = schedule.activeShiftTypes ?? schedule.shiftTypes;

    showDialog(
      context: context,
      builder: (context) => _EditShiftNamesDialog(
        shiftTypes: activeShifts,
        onSave: (Map<String, String> renamedShifts) async {
          await _applyShiftNameChanges(renamedShifts);
        },
      ),
    );
  }

  // ⭐ 근무명 변경 적용
  Future<void> _applyShiftNameChanges(Map<String, String> renamedShifts) async {
    if (renamedShifts.isEmpty) return;

    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    // 1. shiftTypes 업데이트
    final newShiftTypes = schedule.shiftTypes.map((s) {
      return renamedShifts[s] ?? s;
    }).toList();

    // 2. activeShiftTypes 업데이트
    final newActiveShiftTypes = schedule.activeShiftTypes?.map((s) {
      return renamedShifts[s] ?? s;
    }).toList();

    // 3. pattern 업데이트 (규칙적인 경우)
    final newPattern = schedule.pattern?.map((s) {
      return renamedShifts[s] ?? s;
    }).toList();

    // 4. customShiftColors 업데이트 (사용자가 직접 지정한 색 - 이름이 바뀌어도
    // 그 근무를 계속 가리켜야 하므로 키만 새 이름으로 옮김, 값은 그대로 유지)
    final newCustomShiftColors = <String, int>{};
    schedule.customShiftColors?.forEach((key, value) {
      final newKey = renamedShifts[key] ?? key;
      newCustomShiftColors[newKey] = value;
    });

    // 4-1. shiftColors(위젯/전체근무표용 캐시) 재계산 - 이름이 바뀐 키 기준으로
    // 테마 디폴트 + 방금 옮긴 customShiftColors를 다시 합침.
    final newShiftColors = effectiveShiftColors(
      newShiftTypes,
      ref.read(calendarThemeProvider),
      newCustomShiftColors,
    ).map((name, color) => MapEntry(name, color.value));

    // 5. assignedDates 업데이트
    final newAssignedDates = <String, String>{};
    schedule.assignedDates?.forEach((date, shift) {
      final newShift = renamedShifts[shift] ?? shift;
      newAssignedDates[date] = newShift;
    });

    // 6. shiftDurations 업데이트 (근무명이 키라서 이것도 같이 옮겨줘야 함)
    final newShiftDurations = <String, int>{};
    schedule.shiftDurations?.forEach((key, value) {
      final newKey = renamedShifts[key] ?? key;
      newShiftDurations[newKey] = value;
    });

    // 6+7. DB 갱신(alarms/템플릿/이력/생성로그 4개 테이블 + shift_schedule 행)을
    // 하나의 트랜잭션으로 묶어서 원자적으로 처리 - 크래시가 나도 "알람 테이블은 새
    // 이름인데 스케줄 패턴은 옛 이름"인 모순된 상태가 안 생기게 함.
    final newSchedule = ShiftSchedule(
      id: schedule.id,
      isRegular: schedule.isRegular,
      pattern: newPattern,
      todayIndex: schedule.todayIndex,
      shiftTypes: newShiftTypes,
      activeShiftTypes: newActiveShiftTypes,
      startDate: schedule.startDate,
      shiftColors: newShiftColors,
      customShiftColors: newCustomShiftColors,
      assignedDates: newAssignedDates,
      shiftDurations: newShiftDurations,
    );

    await DatabaseService.instance.renameShiftAtomic(
      renamedShifts: renamedShifts,
      newSchedule: newSchedule,
    );
    ref.read(scheduleProvider.notifier).applyExternallyPersisted(newSchedule);
    await ref.read(alarmNotifierProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.statusShiftNameUpdated),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ⭐ 근무명 색상 변경 다이얼로그
  void _showEditShiftColorsDialog() {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    // ⭐ CRITICAL FIX: 패턴에 없는 카드도 색상을 지정할 수 있어야 함 - 온보딩 때
    // 자동으로 색이 안 배정됐던 기존 사용자도 여기서 직접 채울 수 있게.
    final activeShifts = schedule.shiftTypes;
    final theme = ref.read(calendarThemeProvider);
    // ⭐ 2026-08-19 기능 복원 - 다이얼로그 미리보기는 "지금 실제로 보이는 색"
    // (테마 디폴트 + 사용자 오버라이드를 합친 값)을 보여줘야 하지만, 저장은
    // 사용자가 이번에 실제로 건드린 근무만 customShiftColors에 남겨야 함
    // (안 건드린 근무는 계속 테마를 따라가야 하므로) - 그래서 두 맵을 따로 넘김.
    final effectiveColors = effectiveShiftColors(activeShifts, theme, schedule.customShiftColors)
        .map((name, color) => MapEntry(name, color.value));
    final customColors = schedule.customShiftColors ?? {};

    showDialog(
      context: context,
      builder: (context) => _EditShiftColorsDialog(
        shiftTypes: activeShifts,
        effectiveColors: effectiveColors,
        customColors: customColors,
        onSave: (newCustomColors) => _applyShiftColorChanges(newCustomColors),
      ),
    );
  }

  // ⭐ 근무명 색상 변경 적용. newCustomColors는 사용자가 이번 다이얼로그에서
  // 실제로 지정한 오버라이드만 담김(안 건드린 근무는 안 들어있음) - 그래서 이후
  // 테마를 바꿔도 여기 없는 근무는 계속 테마 디폴트를 따라감.
  Future<void> _applyShiftColorChanges(Map<String, int> newCustomColors) async {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    final theme = ref.read(calendarThemeProvider);
    // shiftColors(위젯/전체근무표용 캐시)는 테마 디폴트 + 방금 저장한
    // 오버라이드를 합친 "최종" 값으로 재계산.
    final effectiveColors = effectiveShiftColors(schedule.shiftTypes, theme, newCustomColors)
        .map((name, color) => MapEntry(name, color.value));

    final updatedSchedule = ShiftSchedule(
      id: schedule.id,
      isRegular: schedule.isRegular,
      pattern: schedule.pattern,
      todayIndex: schedule.todayIndex,
      shiftTypes: schedule.shiftTypes,
      activeShiftTypes: schedule.activeShiftTypes,
      startDate: schedule.startDate,
      shiftColors: effectiveColors,
      customShiftColors: newCustomColors,
      assignedDates: schedule.assignedDates,
      shiftDurations: schedule.shiftDurations,
    );

    // ⭐ DatabaseService 직접 호출 + ref.invalidate 대신 scheduleProvider.notifier를
    // 거침 - 이래야 WidgetRefreshService.refresh()/FriendSyncService가 같이 불려서
    // 홈 화면 위젯도 색 변경을 즉시 반영함(예전 코드엔 이게 빠져있었음).
    await ref.read(scheduleProvider.notifier).updateSchedule(updatedSchedule);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.statusShiftColorUpdated),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ⭐ 고정 알람 수정 화면
  void _showEditFixedAlarmsScreen() {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    // ⭐ CRITICAL FIX: activeShiftTypes(패턴에 실제로 쓰이는 근무만)로 제한하지 않고
    // shiftTypes(온보딩에서 만든 모든 근무 카드)를 그대로 씀. 패턴에 안 쓰는 근무(예:
    // 평소엔 주간/야간/휴무만 쓰지만 카드로는 오전/오후도 만들어둔 경우)도 고정 알람을
    // 미리 설정해둘 수 있어야, 나중에 달력에서 그 날만 오전/오후로 근무 변경했을 때
    // 알람이 제대로 생성됨.
    final activeShifts = schedule.shiftTypes;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _EditFixedAlarmsScreen(
          shiftTypes: activeShifts,
          onSave: () async {
            // 알람 재생성
            await _regenerateAllAlarms();
          },
        ),
      ),
    );
  }

  // ⭐ 모든 알람 재생성
  // Dart에서 직접 전체 삭제 후 재생성하지 않고 Native의 diff 기반 갱신 엔진에
  // 위임함 (안 바뀐 알람까지 "일정 변경"으로 이력에 잘못 찍히는 문제 방지).
  Future<void> _regenerateAllAlarms() async {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    const platform = kAlarmChannel;

    // 1. Native diff 갱신 트리거
    try {
      await platform.invokeMethod('forceNativeRefresh');
    } catch (e) {
      print('⚠️ Native 갱신 실패: $e');
    }

    // 2. Notification 취소
    try {
      await platform.invokeMethod('cancelNotification');
    } catch (e) {
      print('⚠️ Notification 삭제 실패: $e');
    }

    // 3. Native가 비동기로 diff 갱신을 마칠 시간을 잠깐 기다린 후 UI 갱신
    await Future.delayed(Duration(milliseconds: 800));
    await ref.read(alarmNotifierProvider.notifier).refresh();

    // 4. diff 갱신이 끝난 "이후" 상태 기준으로 20분 전 알림(8888) 재계산
    try {
      await platform.invokeMethod('triggerGuardCheck');
    } catch (e) {
      print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.alarmUpdatedToast),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ⭐ 전체 교대조 근무표 작성 다이얼로그
  Future<void> _showAllTeamsSetupDialog() async {
    final schedule = ref.read(scheduleProvider).value;

    // 규칙적 근무자만 사용 가능
    if (schedule == null || !schedule.isRegular || schedule.pattern == null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.settingsAllTeamsScheduleTitle),
          content: Text(context.l10n.settingsAllTeamsRegularOnly),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonOk),
            ),
          ],
        ),
      );
      return;
    }

    // 이미 작성된 근무표가 있는지 확인
    final prefs = await SharedPreferences.getInstance();
    final existingTeams = prefs.getStringList('all_teams_names');

    if (existingTeams != null && existingTeams.isNotEmpty) {
      if (!mounted) return;

      // 확인 대화상자 표시
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.settingsAllTeamsScheduleTitle),
          content: Text(context.l10n.statusScheduleExistsRewrite),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.commonRewrite, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    if (!mounted) return;

    // 온보딩 스타일 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AllTeamsSetupDialog(
        pattern: schedule.pattern!,
      ),
    );
  }
}

// 알람 타입 설정 BottomSheet
class _AlarmTypeSettingsSheet extends StatefulWidget {
  final List<AlarmType> alarmTypes;
  final VoidCallback onUpdate;

  const _AlarmTypeSettingsSheet({
    required this.alarmTypes,
    required this.onUpdate,
  });

  @override
  State<_AlarmTypeSettingsSheet> createState() => _AlarmTypeSettingsSheetState();
}

class _AlarmTypeSettingsSheetState extends State<_AlarmTypeSettingsSheet> {
  late List<AlarmType> _types;

  // ⭐ Native 미리듣기 사용 (STREAM_ALARM)
  bool _isPlaying = false;

  // MethodChannel
  static const platform = kAlarmChannel;

  @override
  void initState() {
    super.initState();
    _types = List.from(widget.alarmTypes);

    // DB에 타입이 없으면 프리셋으로 초기화
    if (_types.isEmpty) {
      _initPresets();
    }
    // ⭐ 주의: 예전엔 여기서 ensurePresetDefaults()를 매번 호출해서
    // 사용자가 볼륨을 정확히 100%(1.0)로 맞추면 다음에 이 화면을 열 때마다
    // "마이그레이션 안 된 값"으로 오인되어 70%로 되돌아가는 버그가 있었음.
    // 버전 마이그레이션(_onUpgrade v8~v11)이 이미 1회성으로 처리하므로 여기선 호출 안 함.
  }

  @override
  void dispose() {
    // ⭐ Native 미리듣기 중지
    platform.invokeMethod('stopPreviewSound');
    super.dispose();
  }

  Future<void> _initPresets() async {
    for (var preset in AlarmType.presets) {
      await DatabaseService.instance.insertAlarmType(preset);
    }
    final types = await DatabaseService.instance.getAllAlarmTypes();
    setState(() {
      _types = types;
    });
  }

  Future<void> _updateType(AlarmType type) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'alarm_types',
      type.toMap(),
      where: 'id = ?',
      whereArgs: [type.id],
    );

    final types = await DatabaseService.instance.getAllAlarmTypes();
    setState(() {
      _types = types;
    });
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Text(
                context.l10n.settingsAlarmSoundSettings,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          SizedBox(height: 16.h),

          // 타입 목록
          ..._types.map((type) => _buildTypeCard(type)).toList(),

          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  Widget _buildTypeCard(AlarmType type) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타입 헤더 (이모지 + 이름)
          Row(
            children: [
              Text(type.emoji, style: TextStyle(fontSize: 28.sp)),
              SizedBox(width: 12.w),
              Text(
                type.isSound ? context.l10n.alarmSoundVibration : type.isVibrate ? context.l10n.alarmVibration : context.l10n.alarmSilent,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (type.isSound)
                Text(
                  ' (${context.l10n.settingsIncludesVibration})',
                  style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          SizedBox(height: 12.h),

          // 소리 타입: 음악 선택 + 음량 슬라이더
          if (type.isSound) ...[
            _buildSoundSelectRow(type),
            SizedBox(height: 12.h),
            _buildSliderRow(
              label: context.l10n.alarmVolume,
              value: type.volume,
              onChanged: (v) {
                // ⭐ 실시간 볼륨 적용 (Native STREAM_ALARM)
                if (_isPlaying) {
                  platform.invokeMethod('updatePreviewVolume', {'volume': v});
                }
                _updateType(AlarmType(
                  id: type.id,
                  name: type.name,
                  emoji: type.emoji,
                  soundFile: type.soundFile,
                  volume: v,
                  vibrationStrength: type.vibrationStrength,
                  isPreset: type.isPreset,
                  duration: type.duration,
                ));
              },
              suffix: '${(type.volume * 100).round()}%',
            ),
            SizedBox(height: 8.h),
          ],

          // 진동 타입: 진동 세기
          if (type.isVibrate) ...[
            _buildVibrationRow(type),
            SizedBox(height: 8.h),
          ],

          // 모든 타입: 지속 시간
          _buildDurationRow(type),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required String suffix,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 50.w,
          child: Text(label, style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 45.w,
          child: Text(suffix, style: TextStyle(fontSize: 13.sp)),
        ),
      ],
    );
  }

  // 알람 사운드 목록 (파일명, id) - 표시명은 로케일에 맞게 _getSoundName(context, id)로 계산
  static const List<Map<String, String>> _soundOptions = [
    {'id': 'default', 'file': 'default'},
    {'id': 'alarmbell1', 'file': 'alarmbell1.mp3'},
    {'id': 'alarmbell2', 'file': 'alarmbell2.mp3'},
    {'id': 'alarmbell3', 'file': 'alarmbell3.mp3'},
    {'id': 'alarmbell4', 'file': 'alarmbell4.mp3'},
    {'id': 'alarmbell5', 'file': 'alarmbell5.mp3'},
    {'id': 'alarmbell6', 'file': 'alarmbell6.mp3'},
    {'id': 'alarmbell7', 'file': 'alarmbell7.mp3'},
  ];

  // ⭐ 소리 미리듣기 재생 (Native STREAM_ALARM 사용 - 실제 알람과 동일 음량)
  Future<void> _playSound(String soundId, double volume) async {
    try {
      await platform.invokeMethod('playPreviewSound', {
        'soundFile': soundId,
        'volume': volume,
      });
      setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('소리 재생 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.soundFileNotFound)),
        );
      }
    }
  }

  // ⭐ 소리 정지 (Native)
  Future<void> _stopSound() async {
    try {
      await platform.invokeMethod('stopPreviewSound');
    } catch (e) {
      debugPrint('소리 정지 실패: $e');
    }
    setState(() => _isPlaying = false);
  }

  // 진동 테스트 (약 1초)
  Future<void> _testVibration(int strength) async {
    try {
      await platform.invokeMethod('testVibration', {'strength': strength});
    } catch (e) {
      debugPrint('진동 테스트 실패: $e');
    }
  }

  Widget _buildSoundSelectRow(AlarmType type) {
    return Row(
      children: [
        SizedBox(
          width: 50.w,
          child: Text(context.l10n.alarmSound, style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Row(
            children: [
              // 알람음 선택 드롭다운
              Expanded(
                child: GestureDetector(
                  onTap: () => _showSoundPicker(type),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.music_note, size: 18.sp, color: Theme.of(context).colorScheme.tertiary),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            _getSoundName(context, type.soundFile),  // DB에서 읽은 값 사용
                            style: TextStyle(fontSize: 13.sp),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              // 재생/정지 버튼
              GestureDetector(
                onTap: () {
                  if (_isPlaying) {
                    _stopSound();
                  } else {
                    _playSound(type.soundFile, type.volume);  // DB에서 읽은 값 사용
                  }
                },
                child: Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: _isPlaying ? (Theme.of(context).brightness == Brightness.dark ? Colors.red.shade900.withOpacity(0.2) : Colors.red.shade50) : (Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade900.withOpacity(0.2) : Colors.blue.shade50),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: _isPlaying ? Colors.red : Colors.blue,
                    ),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.stop : Icons.play_arrow,
                    color: _isPlaying ? Colors.red : Colors.blue,
                    size: 20.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getSoundName(BuildContext context, String soundId) {
    if (soundId == 'default') return context.l10n.soundDefault;
    final n = int.tryParse(soundId.replaceFirst('alarmbell', '')) ?? 1;
    return context.l10n.soundBellN(n);
  }

  void _showSoundPicker(AlarmType type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,  // 스크롤 가능하게
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,  // 화면의 50% 높이
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Row(
                    children: [
                      Text(
                        context.l10n.alarmSoundChoose,
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                // 스크롤 가능한 목록
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _soundOptions.length,
                    itemBuilder: (context, index) {
                      final sound = _soundOptions[index];
                      final isSelected = type.soundFile == sound['id'];
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                          color: isSelected ? Colors.orange : Colors.grey,
                        ),
                        title: Text(
                          _getSoundName(context, sound['id']!),
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.orange.shade800 : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        onTap: () {
                          final newSoundId = sound['id']!;
                          // DB에 저장
                          _updateType(AlarmType(
                            id: type.id,
                            name: type.name,
                            emoji: type.emoji,
                            soundFile: newSoundId,  // 새로운 사운드 파일명
                            volume: type.volume,
                            vibrationStrength: type.vibrationStrength,
                            isPreset: type.isPreset,
                            duration: type.duration,
                          ));
                          setModalState(() {});
                          Navigator.pop(context);
                          // 재생 중이면 새 소리로 자동 전환
                          if (_isPlaying) {
                            _playSound(newSoundId, type.volume);
                          }
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVibrationRow(AlarmType type) {
    return Row(
      children: [
        // ⭐ 영어 UI 레이아웃 수정: 원래 50.w 고정폭이 한국어("세기" 2글자)
        // 기준이라 영어("Intensity" 9글자)에서 "Duratio"/"n"처럼 단어 중간이
        // 줄바꿈됐음. 폭을 넉넉히 늘리고 혹시 몰라 줄바꿈 자체도 막음.
        SizedBox(
          width: 78.w,
          child: Text(
            context.l10n.alarmIntensity,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _buildVibrationButton(type, 1, context.l10n.alarmVibrationWeak),
              SizedBox(width: 8.w),
              _buildVibrationButton(type, 3, context.l10n.alarmVibrationStrong),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVibrationButton(AlarmType type, int strength, String label) {
    final isSelected = type.vibrationStrength == strength;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _updateType(AlarmType(
            id: type.id,
            name: type.name,
            emoji: type.emoji,
            soundFile: type.soundFile,
            volume: type.volume,
            vibrationStrength: strength,
            isPreset: type.isPreset,
            duration: type.duration,
          ));
          // 진동 미리보기 (1초)
          _testVibration(strength);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected
              ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.shade800  // 다크모드: 진한 주황 (대비율 6.74:1)
                  : Colors.orange.shade700)  // 화이트모드: 진한 주황 (대비율 5.73:1)
              : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,  // 선택 시 흰색으로 통일
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDurationRow(AlarmType type) {
    return Row(
      children: [
        // ⭐ 영어 UI 레이아웃 수정: 위 _buildVibrationRow와 동일한 이유(영어
        // "Duration"이 원래 50.w 고정폭에 안 맞아 줄바꿈됨).
        SizedBox(
          width: 78.w,
          child: Text(
            context.l10n.alarmDuration,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _buildDurationButton(type, 1),
              SizedBox(width: 8.w),
              _buildDurationButton(type, 3),
              SizedBox(width: 8.w),
              _buildDurationButton(type, 5),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDurationButton(AlarmType type, int minutes) {
    final isSelected = type.duration == minutes;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateType(AlarmType(
          id: type.id,
          name: type.name,
          emoji: type.emoji,
          soundFile: type.soundFile,
          volume: type.volume,
          vibrationStrength: type.vibrationStrength,
          isPreset: type.isPreset,
          duration: minutes,
        )),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected ? (Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.secondary.withOpacity(0.25) : Colors.blue.shade100) : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              context.l10n.alarmDurationMinutes(minutes),
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? (Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.secondary : Colors.blue.shade800) : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ⭐ 근무명 수정 다이얼로그
// ============================================================
class _EditShiftNamesDialog extends StatefulWidget {
  final List<String> shiftTypes;
  final Function(Map<String, String>) onSave;

  const _EditShiftNamesDialog({
    required this.shiftTypes,
    required this.onSave,
  });

  @override
  State<_EditShiftNamesDialog> createState() => _EditShiftNamesDialogState();
}

class _EditShiftNamesDialogState extends State<_EditShiftNamesDialog> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (var shift in widget.shiftTypes) {
      _controllers[shift] = TextEditingController(text: shift);
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit, color: colorScheme.primary),
          SizedBox(width: 8.w),
          Text(context.l10n.settingsEditShiftNameTitle),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.shiftTypes.map((shift) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: TextField(
                controller: _controllers[shift],
                maxLength: kMaxShiftNameLength,
                decoration: InputDecoration(
                  labelText: shift,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
          child: Text(context.l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: () {
            final renamedShifts = <String, String>{};

            for (var entry in _controllers.entries) {
              final oldName = entry.key;
              final newName = entry.value.text.trim();

              if (newName.isNotEmpty && newName != oldName) {
                renamedShifts[oldName] = newName;
              }
            }

            Navigator.pop(context);
            widget.onSave(renamedShifts);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.secondary,
            foregroundColor: colorScheme.onSecondary,
          ),
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}

// ============================================================
// ⭐ 고정 알람 수정 화면 (새 페이지)
// ============================================================
class _EditFixedAlarmsScreen extends StatefulWidget {
  final List<String> shiftTypes;
  final VoidCallback onSave;

  const _EditFixedAlarmsScreen({
    required this.shiftTypes,
    required this.onSave,
  });

  @override
  State<_EditFixedAlarmsScreen> createState() => _EditFixedAlarmsScreenState();
}

class _EditFixedAlarmsScreenState extends State<_EditFixedAlarmsScreen> {
  Map<String, List<AlarmSetting>> _shiftAlarms = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentTemplates();
  }

  Future<void> _loadCurrentTemplates() async {
    final Map<String, List<AlarmSetting>> loadedAlarms = {};

    for (var shift in widget.shiftTypes) {
      final templates = await DatabaseService.instance.getAlarmTemplates(shift);
      loadedAlarms[shift] = templates.map((t) {
        final parts = t.time.split(':');
        return AlarmSetting(
          time: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
          alarmTypeId: t.alarmTypeId,
        );
      }).toList();
    }

    setState(() {
      _shiftAlarms = loadedAlarms;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.alarm, color: colorScheme.tertiary, size: 24.sp),
            SizedBox(width: 8.w),
            Text(context.l10n.settingsEditFixedAlarmTitle),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.onboardingSetFixedAlarmPerShift,
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    context.l10n.onboardingMaxAlarmsPerShift(kMaxAlarmTemplatesPerShift),
                    style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  SizedBox(height: 16.h),
                  // ⭐ shrinkWrap으로 카드 크기에 맞게 조절
                  GridView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 120.w,
                      crossAxisSpacing: 12.w,
                      mainAxisSpacing: 12.h,
                      childAspectRatio: 0.70,
                    ),
                    itemCount: widget.shiftTypes.length,
                    itemBuilder: (context, index) {
                      final shift = widget.shiftTypes[index];
                      final alarms = _shiftAlarms[shift] ?? [];
                      return _buildShiftAlarmCard(shift, alarms);
                    },
                  ),
                  // ⭐ 저장 버튼 (카드 바로 아래)
                  SizedBox(height: 24.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveAndExit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.secondary,
                        foregroundColor: colorScheme.onSecondary,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                      child: Text(context.l10n.commonSave, style: TextStyle(fontSize: 16.sp)),
                    ),
                  ),
                  // ⭐ SafeArea 확보 (홈 버튼 영역 고려)
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16.h),
                ],
              ),
            ),
    );
  }

  Widget _buildShiftAlarmCard(String shift, List<AlarmSetting> alarms) {
    return InkWell(
      onTap: () => _showAlarmEditDialog(shift),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: alarms.isEmpty ? Colors.red.shade300 : Theme.of(context).colorScheme.onSurface,
            width: 2,
          ),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          children: [
            Text(
              shift,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12.h),
            Expanded(
              // ⭐ onboarding_screen.dart의 동일 카드와 같은 문제/같은 수정 - 알람이
              // kMaxAlarmTemplatesPerShift(5)개까지 늘어나면 고정 높이 카드에서
              // Center+Column(비스크롤)이 세로로 넘쳤음. 스크롤 가능하게 변경.
              child: alarms.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.onboardingTapToSet,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: alarms.map((alarm) => Padding(
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getAlarmTypeEmoji(alarm.alarmTypeId),
                                style: TextStyle(fontSize: 12.sp),
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                _formatTime(alarm.time),
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getAlarmTypeEmoji(int alarmTypeId) {
    switch (alarmTypeId) {
      case 1: return '🔔';
      case 2: return '📳';
      case 3: return '🔇';
      default: return '🔔';
    }
  }

  void _showAlarmEditDialog(String shift) {
    showDialog(
      context: context,
      builder: (context) => _ShiftAlarmEditDialog(
        shift: shift,
        initialAlarms: _shiftAlarms[shift] ?? [],
        onSave: (alarms) {
          setState(() {
            _shiftAlarms[shift] = alarms;
          });
        },
      ),
    );
  }

  Future<void> _saveAndExit() async {
    // ⭐ 삭제+재삽입을 하나의 트랜잭션으로 묶어서, Native 갱신 엔진이 그 사이에
    // 끼어들어도 "일부만 지워진" 중간 상태를 절대 못 보게 함 (원인 불명이던
    // "수정 전 알람이 그대로 같이 울리는" 버그의 유력한 경로 중 하나였음).
    final templates = <Map<String, dynamic>>[];
    for (var entry in _shiftAlarms.entries) {
      final shift = entry.key;
      for (var alarm in entry.value) {
        templates.add({
          'shift_type': shift,
          'time': _formatTime(alarm.time),
          'alarm_type_id': alarm.alarmTypeId,
        });
      }
    }
    await DatabaseService.instance.replaceAllAlarmTemplates(templates);

    widget.onSave();

    if (mounted) {
      Navigator.pop(context);
    }
  }
}

// ============================================================
// ⭐ 알람 설정 다이얼로그 (온보딩과 동일한 UI)
// ============================================================
class _ShiftAlarmEditDialog extends StatefulWidget {
  final String shift;
  final List<AlarmSetting> initialAlarms;
  final Function(List<AlarmSetting>) onSave;

  const _ShiftAlarmEditDialog({
    required this.shift,
    required this.initialAlarms,
    required this.onSave,
  });

  @override
  State<_ShiftAlarmEditDialog> createState() => _ShiftAlarmEditDialogState();
}

class _ShiftAlarmEditDialogState extends State<_ShiftAlarmEditDialog> {
  late List<AlarmSetting> _alarms;

  @override
  void initState() {
    super.initState();
    _alarms = List.from(widget.initialAlarms);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.l10n.settingsShiftFixedAlarmTitle(widget.shift)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.settingsFixedAlarmRegisterLimit(kMaxAlarmTemplatesPerShift),
              style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: 16.h),

            ..._alarms.asMap().entries.map((entry) {
              final alarm = entry.value;
              return Container(
                margin: EdgeInsets.only(bottom: 12.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // ⭐ 시간 영역 탭하면 시간 수정
                        InkWell(
                          onTap: () => _editAlarmTime(entry.key),
                          borderRadius: BorderRadius.circular(8.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.alarm, size: 20.sp, color: Theme.of(context).colorScheme.secondary),
                                SizedBox(width: 8.w),
                                Text(
                                  '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error, size: 20.sp),
                          onPressed: () {
                            setState(() {
                              _alarms.removeAt(entry.key);
                            });
                          },
                          constraints: BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        _buildTypeButton(entry.key, 1, '🔔', context.l10n.alarmSoundVibration),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 2, '📳', context.l10n.alarmVibration),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 3, '🔇', context.l10n.alarmSilent),
                      ],
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 8.h),

            if (_alarms.length < kMaxAlarmTemplatesPerShift)
              OutlinedButton.icon(
                onPressed: _addAlarm,
                icon: Icon(Icons.add),
                label: Text(context.l10n.alarmAdd),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 44.h),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () {
            _alarms.sort((a, b) {
              final aMinutes = a.time.hour * 60 + a.time.minute;
              final bMinutes = b.time.hour * 60 + b.time.minute;
              return aMinutes.compareTo(bMinutes);
            });

            widget.onSave(_alarms);
            Navigator.pop(context);
          },
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }

  Widget _buildTypeButton(int index, int typeId, String emoji, String label) {
    final isSelected = _alarms[index].alarmTypeId == typeId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _alarms[index] = _alarms[index].copyWith(alarmTypeId: typeId);
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected
              ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.shade800  // 다크모드: 진한 주황 (대비율 6.74:1)
                  : Colors.orange.shade700)  // 화이트모드: 진한 주황 (대비율 5.73:1)
              : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: TextStyle(fontSize: 16.sp)),
              SizedBox(height: 2.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,  // 선택 시 흰색으로 통일
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 알람 시간 수정
  Future<void> _editAlarmTime(int index) async {
    final currentAlarm = _alarms[index];
    await showDialog(
      context: context,
      builder: (context) => _SettingsTimePicker(
        initialTime: currentAlarm.time,
        onTimeSelected: (time) async {
          // ⭐ 중복 체크 (자기 자신 제외)
          final isDuplicate = _alarms.asMap().entries.any((entry) {
            return entry.key != index &&
                   entry.value.time.hour == time.hour &&
                   entry.value.time.minute == time.minute;
          });

          if (isDuplicate) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.tertiary, size: 28),
                    SizedBox(width: 8),
                    Text(context.l10n.alarmDuplicate),
                  ],
                ),
                content: Text(
                  context.l10n.alarmAlreadyExistsAtTime('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
                  style: TextStyle(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.commonOk, style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
            return;
          }

          setState(() {
            _alarms[index] = currentAlarm.copyWith(time: time);
          });
        },
      ),
    );
  }

  Future<void> _addAlarm() async {
    await showDialog(
      context: context,
      builder: (context) => _SettingsTimePicker(
        onTimeSelected: (time) async {
          // ⭐ 중복 체크
          final isDuplicate = _alarms.any((alarm) =>
            alarm.time.hour == time.hour && alarm.time.minute == time.minute
          );

          if (isDuplicate) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.tertiary, size: 28),
                    SizedBox(width: 8),
                    Text(context.l10n.alarmDuplicate),
                  ],
                ),
                content: Text(
                  context.l10n.alarmAlreadyExistsAtTime('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
                  style: TextStyle(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.commonOk, style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
            return;
          }

          setState(() {
            _alarms.add(AlarmSetting(time: time, alarmTypeId: 1));
          });
        },
      ),
    );
  }
}

// ============================================================
// ⭐ 삼성 스타일 시간 선택기 (온보딩과 동일)
// ============================================================
class _SettingsTimePicker extends StatefulWidget {
  final Function(TimeOfDay) onTimeSelected;
  final TimeOfDay? initialTime;  // ⭐ 초기 시간 (수정 시 사용)

  const _SettingsTimePicker({
    required this.onTimeSelected,
    this.initialTime,
  });

  @override
  State<_SettingsTimePicker> createState() => _SettingsTimePickerState();
}

class _SettingsTimePickerState extends State<_SettingsTimePicker> {
  bool _isAM = true;
  int _hour = 9;
  int _minute = 0;

  @override
  void initState() {
    super.initState();
    // ⭐ 초기 시간이 있으면 설정
    if (widget.initialTime != null) {
      final t = widget.initialTime!;
      _minute = t.minute;
      if (t.hour == 0) {
        _isAM = true;
        _hour = 12;
      } else if (t.hour < 12) {
        _isAM = true;
        _hour = t.hour;
      } else if (t.hour == 12) {
        _isAM = false;
        _hour = 12;
      } else {
        _isAM = false;
        _hour = t.hour - 12;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.commonSelectTime,
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = true;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isAM ? Colors.blue : Colors.grey.shade300,
                            width: _isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        child: Center(
                          child: Text(
                            context.l10n.commonAm,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 8.h),

                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = false;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: !_isAM ? Colors.blue : Colors.grey.shade300,
                            width: !_isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        child: Center(
                          child: Text(
                            context.l10n.commonPm,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(width: 16.w),

                TappableNumberPicker(
                  value: _hour,
                  minValue: 1,
                  maxValue: 12,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      if (_hour == 11 && value == 12) {
                        _isAM = !_isAM;
                      } else if (_hour == 12 && value == 11) {
                        _isAM = !_isAM;
                      }
                      _hour = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Theme.of(context).colorScheme.outline),
                      bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),

                Text(':', style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold)),

                TappableNumberPicker(
                  value: _minute,
                  minValue: 0,
                  maxValue: 59,
                  zeroPad: true,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      _minute = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Theme.of(context).colorScheme.outline),
                      bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 24.h),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
                ),
                SizedBox(width: 8.w),
                ElevatedButton(
                  onPressed: () async {
                    int hour24;
                    if (_isAM) {
                      hour24 = _hour == 12 ? 0 : _hour;
                    } else {
                      hour24 = _hour == 12 ? 12 : _hour + 12;
                    }

                    await widget.onTimeSelected(TimeOfDay(hour: hour24, minute: _minute));
                    if (mounted) Navigator.pop(context);
                  },
                  child: Text(context.l10n.commonOk),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ⭐ 스케줄 변경 다이얼로그 (온보딩 UI 재사용)
// ============================================================
class _ChangeScheduleDialog extends StatefulWidget {
  final List<String> pattern;
  final Function(int) onConfirm;

  const _ChangeScheduleDialog({
    required this.pattern,
    required this.onConfirm,
  });

  @override
  State<_ChangeScheduleDialog> createState() => _ChangeScheduleDialogState();
}

class _ChangeScheduleDialogState extends State<_ChangeScheduleDialog> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final dateText = '${today.month}/${today.day}';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.swap_horiz, color: Colors.teal.shade600),
          SizedBox(width: 8.w),
          Text(context.l10n.shiftChangeSchedule),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(maxHeight: 450.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.onboardingTodayShiftQuestion(dateText),
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            Text(
              context.l10n.settingsSelectTodayShiftFromPattern,
              style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: 16.h),

            // 패턴 그리드
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 6.w,
                  mainAxisSpacing: 6.h,
                  childAspectRatio: 1.0,
                ),
                itemCount: widget.pattern.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedIndex == index;

                  return InkWell(
                    onTap: () {
                      setState(() => _selectedIndex = index);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        // ⭐ 선택 안 됨: surfaceVariant, 선택됨: primary
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(
                          // ⭐ 선택 안 됨: outline, 선택됨: primary (진하게)
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outline,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: 4.w, top: 2.h),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  // ⭐ 선택됨: onPrimary, 선택 안 됨: onSurfaceVariant
                                  color: isSelected
                                      ? colorScheme.onPrimary.withOpacity(0.7)
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                widget.pattern[index],
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.bold,
                                  // ⭐ 선택됨: onPrimary, 선택 안 됨: onSurface (명확하게)
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            SizedBox(height: 12.h),

            // 안내 문구
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade900.withOpacity(0.2) : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade700 : Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade400 : Colors.amber.shade700, size: 20.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      context.l10n.settingsScheduleChangeWarning,
                      style: TextStyle(fontSize: 12.sp, color: Colors.amber.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
          child: Text(context.l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _selectedIndex == null
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onConfirm(_selectedIndex!);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.secondary,
            foregroundColor: colorScheme.onSecondary,
          ),
          child: Text(context.l10n.commonChange),
        ),
      ],
    );
  }
}

// ============================================================
// ⭐ 근무명 색상 변경 다이얼로그
// ============================================================
class _EditShiftColorsDialog extends StatefulWidget {
  final List<String> shiftTypes;
  // ⭐ "지금 실제로 보이는 색"(테마 디폴트 + 기존 오버라이드) - 미리보기/중복
  // 체크 전용. 그대로 저장하면 안 됨(그러면 안 건드린 근무까지 전부 오버라이드로
  // 굳어버려서 테마를 안 따라가게 됨) - 저장은 아래 initialCustomColors 기반의
  // _customColors만 씀.
  final Map<String, int> effectiveColors;
  // ⭐ 사용자가 예전에 실제로 지정해둔 오버라이드만(테마 디폴트는 제외).
  final Map<String, int> customColors;
  final Function(Map<String, int>) onSave;

  const _EditShiftColorsDialog({
    required this.shiftTypes,
    required this.effectiveColors,
    required this.customColors,
    required this.onSave,
  });

  @override
  State<_EditShiftColorsDialog> createState() => _EditShiftColorsDialogState();
}

class _EditShiftColorsDialogState extends State<_EditShiftColorsDialog> {
  late Map<String, int> _previewColors;  // 화면 표시용 (테마 디폴트 포함)
  late Map<String, int> _customColors;   // 저장용 (사용자가 이번에 지정한 것만)

  @override
  void initState() {
    super.initState();
    _previewColors = Map.from(widget.effectiveColors);
    _customColors = Map.from(widget.customColors);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.palette, color: Colors.purple.shade400),
          SizedBox(width: 8.w),
          Text(context.l10n.settingsEditShiftColorTitle),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: widget.shiftTypes.length,
          separatorBuilder: (context, index) => Divider(height: 1),
          itemBuilder: (context, index) {
            final shift = widget.shiftTypes[index];
            final colorValue = _previewColors[shift] ?? 0xFFCCCCCC;
            final bgColor = Color(colorValue);
            final textColor = ShiftSchedule.getTextColor(bgColor);

            return ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              // 왼쪽: 현재 색상으로 미리보기 (달력 셀과 동일)
              leading: Container(
                width: 60.w,
                height: 18.h,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(3.r),
                ),
                child: Center(
                  child: Text(
                    shift,
                    style: TextStyle(
                      fontSize: 9.sp,
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              title: Text(
                shift,
                style: TextStyle(fontSize: 14.sp),
              ),
              trailing: Icon(Icons.chevron_right, size: 20.sp),
              onTap: () => _showColorPicker(shift),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
          child: Text(context.l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_customColors);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.secondary,
            foregroundColor: colorScheme.onSecondary,
          ),
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }

  void _showColorPicker(String shift) async {
    // 현재 근무 제외한 다른 근무들의 색상 목록 (지금 화면에 실제로 보이는 색 기준)
    final usedColors = _previewColors.entries
        .where((entry) => entry.key != shift)
        .map((entry) => entry.value)
        .toSet();

    final result = await showDialog<int>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        shiftName: shift,
        usedColors: usedColors,
      ),
    );

    if (result != null) {
      setState(() {
        _previewColors[shift] = result;
        _customColors[shift] = result;  // ⭐ 사용자가 직접 고른 순간 이 근무는 "고정"됨
      });
    }
  }
}

// ============================================================
// ⭐ 색상 팔레트 선택 다이얼로그
// ============================================================
class _ColorPickerDialog extends StatelessWidget {
  final String shiftName;
  final Set<int> usedColors;

  const _ColorPickerDialog({
    required this.shiftName,
    required this.usedColors,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 팔레트(테마 디폴트 색 포함, ShiftSchedule.shiftPalette 참고) + 빨강(휴무용)
    final colors = [
      ...ShiftSchedule.shiftPalette,
      ShiftSchedule.offColor,
    ];

    // 반응형: 화면 크기에 따라 높이 조정 (최대 70%, 최소 300.h)
    final dialogHeight = (MediaQuery.of(context).size.height * 0.7).clamp(300.h, 600.h);

    return AlertDialog(
      title: Text(
        context.l10n.settingsColorPickerTitle(shiftName),
        style: TextStyle(fontSize: 16.sp),
      ),
      content: SizedBox(
        width: 300.w,
        height: dialogHeight,
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12.h,
            crossAxisSpacing: 12.w,
            childAspectRatio: 3,  // 가로로 긴 형태
          ),
          itemCount: colors.length,
          itemBuilder: (context, index) {
            final bgColor = colors[index];
            final textColor = ShiftSchedule.getTextColor(bgColor);
            final isUsed = usedColors.contains(bgColor.value);

            return GestureDetector(
              onTap: () {
                if (isUsed) {
                  // 이미 사용 중인 색상이면 경고
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.statusColorAlreadyUsed),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  Navigator.pop(context, bgColor.value);
                }
              },
              child: Opacity(
                opacity: isUsed ? 0.3 : 1.0,  // 사용 중이면 반투명
                child: Container(
                  height: 18.h,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(3.r),
                    border: Border.all(
                      color: isUsed ? Colors.red : Theme.of(context).colorScheme.outline,
                      width: isUsed ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          shiftName,
                          style: TextStyle(
                            fontSize: 9.sp,
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 사용 중이면 X 아이콘 표시
                      if (isUsed)
                        Positioned(
                          top: 2.h,
                          right: 4.w,
                          child: Icon(
                            Icons.close,
                            size: 12.sp,
                            color: textColor,  // 배경색에 따라 자동으로 대비색 사용
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
          child: Text(context.l10n.commonCancel),
        ),
      ],
    );
  }
}
