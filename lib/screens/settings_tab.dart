import '../providers/data_revision_provider.dart';
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
import 'memo_list_view.dart';
import 'work_hours_settings_screen.dart';
import 'calendar_theme_picker_screen.dart';
import 'help_screen.dart';
import 'privacy_policy_screen.dart';
import '../widgets/tappable_number_picker.dart';
import '../widgets/app_button.dart';
import '../widgets/app_second_button.dart';
import '../widgets/app_third_button.dart';
import '../widgets/day_offset_chip.dart';
import '../widgets/app_shift_chip.dart';
import '../constants/alarm_day_offset.dart';
import '../l10n/l10n_extensions.dart';
import '../constants/shift_name_limits.dart';
import '../services/backup_watcher.dart';
import '../services/backup_storage_service.dart';
import '../models/backup_payload.dart';
import '../providers/tab_visibility_provider.dart';
import '../services/schedule_notification_service.dart';
import '../services/widget_refresh_service.dart';
import '../widgets/disable_tab_button.dart';
import '../services/backup_validator.dart';
import '../services/restore_coordinator.dart';

class SettingsTab extends ConsumerStatefulWidget {
  final VoidCallback? onSwipeToCalendar;  // ⭐ 6번 기능: 스와이프 callback

  const SettingsTab({super.key, this.onSwipeToCalendar});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> with WidgetsBindingObserver {
  // ⭐ 사용자 데이터 백업("A번 요구사항") - 설정 탭 진입점(Layer 4). 저장/복구
  // 로직 자체는 BackupWatcher(자동 트리거와 동일 코드 경로 - "지금 백업"도 그냥
  // force:true로 그 함수를 부르는 것뿐)에 있고, 여기선 버튼 상태/마지막 백업
  // 시각 표시만 관리함.
  bool _isBackingUp = false;
  DateTime? _lastBackupAt;
  bool _isRestoringFromBackup = false;

  @override
  void initState() {
    super.initState();
    _loadLastBackupAt();
    // ⭐ 2026-09-11(사용자 신고 - "자동백업이 안 되고 있는 것 같다") - 이 화면은
    // MainScreen이 `_tabs[_currentIndex]`로 탭을 매번 새로 만드는 구조라(main.dart
    // 참고) 다른 탭으로 갔다가 다시 오면 initState가 새로 돌아 항상 최신값을
    // 보여주지만, "설정 탭을 보고 있는 채로 앱만 배경↔전경을 오간" 경우엔 이
    // 위젯이 그대로 살아있어서 그 사이 자동 백업(main.dart의 didChangeAppLifecycleState)
    // 이 갱신한 "마지막 백업" 시각을 못 따라감 - 실제로는 백업이 잘 되고 있는데도
    // 화면만 안 바뀌어서 "안 되는 것 같다"로 보일 수 있었음. condition_tab.dart가
    // sleepRecordProvider에 쓰는 것과 동일한 패턴으로 resume 시 다시 읽음.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadLastBackupAt();
    }
  }

  Future<void> _loadLastBackupAt() async {
    final at = await BackupWatcher.instance.lastSavedAt();
    if (mounted) setState(() => _lastBackupAt = at);
  }

  Future<void> _backupNow() async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    final success = await BackupWatcher.instance.backupNow(force: true);
    if (!mounted) return;
    setState(() => _isBackingUp = false);
    if (success) await _loadLastBackupAt();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? context.l10n.settingsDataBackupSuccessToast
            : context.l10n.settingsDataBackupFailedToast),
        // ⭐ 문구가 "앱 삭제해도 재설치 시 보관됨"까지 길어져서, 기본 4초보다
        // 읽을 시간을 조금 더 줌.
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String _formatBackupDate(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} $h:$m';
  }

  // ⭐ 2026-09-01 - "설정 탭에서도 다른 백업으로 불러올 수 있게" 추가 요청.
  // 신규 설치 온보딩 경로(permission_intro_screen.dart의 _pickBackupManually)와
  // 달리, 여기는 **이미 사용 중인 데이터가 있는 상태에서 통째로 덮어쓰는**
  // 훨씬 위험한 동작이라 안내 다이얼로그를 두 단계로 나눔:
  // 1) 파일 고르기 전 - 무슨 일이 일어나는지 + 어디서 파일을 찾는지 자세히 안내
  // 2) 파일을 고르고 유효성 검증까지 끝난 후 - 그 백업의 저장 시각을 보여주고
  //    마지막으로 한 번 더 확인
  // restoreAll()은 force:true로 불러야 함(기본은 "스케줄이 이미 있으면 거부"라서).
  // 복구 후엔 화면에 떠 있는 모든 provider/캐시를 일일이 무효화하는 대신
  // 앱 프로세스를 통째로 재시작함(native "restartApp" - MainActivity.kt 참고)
  // - 신규 설치 복구와 동일하게 "깨끗한 시작"을 보장하는 가장 안전한 방법.
  Future<void> _restoreFromBackup() async {
    if (_isRestoringFromBackup) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsRestoreFromBackupWarningTitle),
        content: SingleChildScrollView(
          child: Text(
            context.l10n.settingsRestoreFromBackupWarningBody,
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          AppSecondButton(
            variant: AppSecondButtonVariant.neutral,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          AppSecondButton(
            variant: AppSecondButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.settingsRestoreFromBackupPickButton),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    final json = await BackupStorageService.instance.pickAndRead();
    if (json == null) return; // 선택기에서 취소함 - 조용히 무시
    if (!mounted) return;

    BackupPayload? payload;
    try {
      payload = BackupPayload.decode(json);
    } catch (e) {
      payload = null;
    }
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupRestoreManualPickInvalidToast)),
      );
      return;
    }
    // ⭐ 2026-09-14 (G4 #19) - 근무 일정이 없는 백업으로 지금 데이터를 통째로 비우지 않음
    if (!BackupValidator.hasSchedule(payload)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsRestoreFromBackupEmptyToast)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsRestoreFromBackupConfirmTitle),
        content: Text(
          context.l10n.settingsRestoreFromBackupConfirmBody(
            _formatBackupDate(payload!.exportedAt),
          ),
        ),
        actions: [
          AppSecondButton(
            variant: AppSecondButtonVariant.neutral,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          AppSecondButton(
            variant: AppSecondButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.settingsRestoreFromBackupConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRestoringFromBackup = true);
    try {
      // ⭐ 2026-09-14 (출시전 감사 G4 #9/#19/#25) - 덮어쓰기 복원은 RestoreCoordinator가 검증·작업 사본·잠금·단계 기록으로 실행.
      // 진행 중 알람(울림·스누즈)은 원래 ID로 보존, 이력은 병합, 친구공유 상태는 이 기기 값 유지, 마지막에 알람·일정 알림 재조정까지 함.
      await RestoreCoordinator.instance.start(payload, overwrite: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsRestoreFromBackupSuccessToast)),
      );
      // ⭐ 토스트를 잠깐 보여준 뒤 재시작 - 네이티브 쪽에도 300ms 지연이 한 번 더
      // 있어서(MainActivity.kt) 총 지연은 그리 길지 않음.
      await Future.delayed(const Duration(milliseconds: 600));
      await kAlarmChannel.invokeMethod('restartApp');
    } on BackupValidationException {
      if (!mounted) return;
      setState(() => _isRestoringFromBackup = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupRestoreInvalidToast)),
      );
    } on RestoreIncompleteException {
      // 작업 기록이 남음 - 재시작하면 앱 시작 화면에서 이어서 완료/지금 데이터로 계속을 묻는다
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupRestoreIncompleteToast)),
      );
      await Future.delayed(const Duration(milliseconds: 1200));
      await kAlarmChannel.invokeMethod('restartApp');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRestoringFromBackup = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsRestoreFromBackupFailedToast)),
      );
    }
  }

  Future<void> _resetSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.shiftResetSchedule),
        content: Text(context.l10n.settingsResetScheduleConfirm),
        actions: [
          AppSecondButton(
            variant: AppSecondButtonVariant.neutral,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          AppSecondButton(
            variant: AppSecondButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonReset),
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
      // ⭐ 2026-09-05 - 'all_teams_indices'는 어디서도 안 쓰는 죽은 키였음(실제
      // 저장 키는 all_teams_offsets) - 지워도 orphan으로 안 남게 실제 키로 교체.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('all_teams_names');
      await prefs.remove('all_teams_offsets');
      await prefs.remove('all_teams_my_team');

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

    // ⭐ 2026-08-28 - 좌우 스와이프로 달력탭 이동하는 기능 제거(안 써서).
    // widget.onSwipeToCalendar 자체는 아래 "달력 테마" 진입 시
    // CalendarThemePickerScreen(onApplied: ...)로 여전히 씀(테마 적용 후 달력탭으로
    // 돌아가는 콜백) - 그쪽은 스와이프가 아니라 별개 기능이라 유지.
    return Scaffold(
        appBar: AppBar(
          // ⭐ 2026-09-06(사용자 지적) - 컨디션 탭 등 다른 탭들은 전부 테마
          // 기본값(centerTitle:true, 18px w600, app_theme.dart 참고)을 그대로
          // 쓰는데 이 화면만 Row+Spacer로 오른쪽 정렬 + 20.sp 커스텀 크기를 써서
          // 탭마다 제목 위치/크기가 달라 보였음 - 다른 탭과 동일하게 가운데
          // 정렬·같은 크기가 되도록 커스텀 스타일을 걷어냄.
          title: Text(context.l10n.navSettings),
        ),
        body: scheduleAsync.when(
        loading: () => const SizedBox.shrink(),  // ⭐ 로딩 인디케이터 제거
        error: (error, stack) => Center(child: Text('${context.l10n.statusErrorOccurred}: $error')),
        data: (schedule) {
          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              // 현재 스케줄 정보
              // ⭐ 2026-08-25 - 카드 배경(연보라 kAppSurface)을 흰색으로 바꿈.
              // "교대근무관리" 이름표(헤더, colorScheme.primary)와 근무명
              // 뱃지들(_buildPatternRow/_buildShiftTypesRow, colorScheme.primary)만
              // 색을 유지하고 나머지 불필요한 연보라 배경은 전부 흰색으로
              // 통일해달라는 요청 - 이 헤더는 별도 Container라 그대로 유지됨.
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
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
                                      context.l10n.settingsShiftManagementEditButton,
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
                                      context.l10n.shiftResetSchedule,
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

              // ⭐ "전체 교대조 근무표 작성" 진입점은 여기 없음 - 전체근무표
              // 화면(all_shifts_view.dart) 자체의 년월 표시줄 편집(✏️) 아이콘으로
              // 이동함(2026-09-05, 편집까지 지원하는 화면으로 개편되면서 정리).

              // 알람음 관리
              ListTile(
                tileColor: Colors.white,
                leading: Icon(Icons.notifications_active, color: Theme.of(context).colorScheme.tertiary),
                title: Text(context.l10n.alarmSoundManage),
                subtitle: Text(context.l10n.settingsAlarmSoundManageDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: _showAlarmTypeDialog,
              ),

              // ⭐ "근로"를 전부 "근무"로 통일 (탭 제목/부제 포함).
              ListTile(
                tileColor: Colors.white,
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
              // 여러 테마 중 하나(메인·다크)를 고르면 그게 곧 다크 테마임(정확한
              // 개수는 calendar_theme.dart의 CalendarThemeId 참고 - 여기서
              // 숫자를 하드코딩하면 테마 추가할 때마다 또 어긋남).
              // ⭐ "근무명 색상 변경"도 여기로 흡수됨 - 색상은 더 이상 개별
              // 지정이 아니라 테마 선택 하나로 전부 결정됨.
              ListTile(
                tileColor: Colors.white,
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

              // ⭐ 2026-09-05 - "설정에도 뭐가 너무 많은 게 좋은 건 아니다"는
              // 요청으로 이 진입점을 없앰. 일정 공유(친구 공유)는 이제 달력
              // 탭 헤더의 기존 "default" 친구 아이콘(모든 테마 공통,
              // calendar_tab.dart의 _buildThemedHeaderButtons 참고) +
              // 언더라인/매거진 테마의 6번째 줄 "일정 공유" 버튼으로 충분히
              // 접근 가능 - 설정 탭에 중복 진입점을 두지 않음.

              // ⭐ 2026-09-13 추가(사용자 요청) - 일정관리/컨디션 탭을 각 탭의
              // "OO 화면 사용하지 않기" 버튼으로 껐을 때만 여기 나타나는 복원
              // 진입점. 네비게이션에 이미 그 탭이 있으면(꺼져있지 않으면) 이
              // 항목 자체가 안 보임 - "사용하기" 버튼과 실제 탭이 동시에
              // 존재하지 않도록 하는 규칙(두 UI가 서로 배타적).
              if (!ref.watch(scheduleTabEnabledProvider))
                ListTile(
                  tileColor: Colors.white,
                  leading: Icon(Icons.event_note_outlined, color: Theme.of(context).colorScheme.tertiary),
                  title: const Text('일정관리 화면 사용하기'),
                  subtitle: const Text('하단 탭에 일정관리 화면을 다시 표시합니다'),
                  trailing: Icon(Icons.chevron_right),
                  // ⭐ 2026-09-13 - 숨기는 동안 취소됐던 일정 알림들을 원래
                  // 상태로 그대로 복원(main.dart의 DisableTabButton onConfirmed
                  // 주석 참고 - 대칭 동작).
                  onTap: () async {
                    final changed = await setTabEnabledWithFeedback(
                      context,
                      () => ref.read(scheduleTabEnabledProvider.notifier).setEnabled(true),
                    );
                    if (!changed) return;
                    await ScheduleNotificationService.restoreAllForTabEnable();
                  },
                ),
              if (!ref.watch(conditionTabEnabledProvider))
                ListTile(
                  tileColor: Colors.white,
                  leading: Icon(Icons.self_improvement, color: Theme.of(context).colorScheme.tertiary),
                  title: const Text('컨디션 화면 사용하기'),
                  subtitle: const Text('하단 탭에 컨디션 화면을 다시 표시합니다'),
                  trailing: Icon(Icons.chevron_right),
                  // ⭐ 2026-09-13 - 수면 위젯이 즉시 정상(비회색) 표시로
                  // 돌아오도록 깨움 - 대칭 동작.
                  onTap: () async {
                    await ref.read(conditionTabEnabledProvider.notifier).setEnabled(true);
                    await WidgetRefreshService.refresh();
                  },
                ),

              // ⭐ 2026-09-05 - 항목 그룹 재정리("알람음 관리"/"근무시간 및 OT
              // 설정"은 맨 위 고정 요청대로 위치 그대로, 그 아래부터 의미별로
              // 묶음): 기록 보기(알람 이력/메모 모아보기 - 둘 다 과거 데이터를
              // "조회"하는 화면이라 같은 그룹) → 데이터 백업(백업/복원 한 쌍) →
              // 위험 구역(되돌릴 수 없는 파괴적 작업이라 백업과 분리된 자기
              // 구역) → 도움말/정보. 그룹마다 구분선 하나씩.
              // ⭐ 구분선 - "기록 보기" 섹션
              SizedBox(height: 24.h),
              Divider(),

              // 알람 이력
              ListTile(
                tileColor: Colors.white,
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
                tileColor: Colors.white,
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

              // ⭐ 구분선 - "데이터 백업" 섹션(백업/복원 한 쌍)
              SizedBox(height: 24.h),
              Divider(),

              // ⭐ 사용자 데이터 백업("A번 요구사항") - 지금 기기(MediaStore)에
              // 백업 하나를 저장. 자동 백업(BackupWatcher, main.dart 참고)도 같은
              // 코드 경로를 쓰므로 여기 표시되는 "마지막 백업"은 수동/자동 구분
              // 없이 항상 최신임.
              ListTile(
                tileColor: Colors.white,
                leading: Icon(Icons.backup_outlined, color: Theme.of(context).colorScheme.primary),
                title: Text(context.l10n.settingsDataBackupTitle),
                subtitle: Text(
                  _isBackingUp
                      ? context.l10n.settingsDataBackupInProgress
                      : (_lastBackupAt != null
                          ? context.l10n.settingsDataBackupLastSavedAt(_formatBackupDate(_lastBackupAt!))
                          : context.l10n.settingsDataBackupNeverSaved),
                ),
                trailing: _isBackingUp
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.chevron_right),
                onTap: _isBackingUp ? null : _backupNow,
              ),

              // ⭐ 2026-09-01 - "백업 데이터 불러오기" - 위 "데이터 백업"과 반대
              // 방향(다른 백업 파일로 지금 데이터를 덮어씀). _restoreFromBackup()
              // 주석 참고.
              ListTile(
                tileColor: Colors.white,
                leading: Icon(Icons.settings_backup_restore, color: Theme.of(context).colorScheme.primary),
                title: Text(context.l10n.settingsRestoreFromBackupTitle),
                subtitle: Text(
                  _isRestoringFromBackup
                      ? context.l10n.settingsRestoreFromBackupInProgress
                      : context.l10n.settingsRestoreFromBackupDesc,
                ),
                trailing: _isRestoringFromBackup
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.chevron_right),
                onTap: _isRestoringFromBackup ? null : _restoreFromBackup,
              ),

              // ⭐ 구분선 - "위험 구역"(되돌릴 수 없는 파괴적 작업이라 위
              // 백업/복원 그룹과 분리된 자기 구역으로 뺌)
              SizedBox(height: 24.h),
              Divider(),

              // 모든 알람 완전 삭제
              ListTile(
                tileColor: Colors.white,
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
                        AppSecondButton(
                          variant: AppSecondButtonVariant.neutral,
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(context.l10n.commonCancel),
                        ),
                        AppSecondButton(
                          variant: AppSecondButtonVariant.danger,
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(context.l10n.commonDeletePermanently),
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
                tileColor: Colors.white,
                leading: Icon(Icons.help_outline, color: Theme.of(context).colorScheme.secondary),
                title: Text(context.l10n.settingsHelp),
                subtitle: Text(context.l10n.settingsHelpDesc),
                trailing: Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HelpScreen()),
                ),
              ),

              // 개인정보처리방침
              ListTile(
                tileColor: Colors.white,
                leading: Icon(Icons.privacy_tip_outlined, color: Colors.teal),
                title: Text(context.l10n.settingsPrivacyPolicy),
                trailing: Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
              ),

            ],
          );
        },
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
              AppShiftChip(label: pattern[i], dense: true),
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
          children: shiftTypes.map((type) => AppShiftChip(label: type, dense: true)).toList(),
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
      // ⭐ 2026-08-25 - backgroundColor 미지정 시 기본값이 colorScheme.surface
      // (연보라 kAppSurface)라 안의 ListTile들은 흰색으로 바꿔도 그 위/아래
      // 여백(드래그 핸들 위, 마지막 항목 아래)은 계속 연보라로 보였음 - 시트
      // 자체 배경을 흰색으로 지정해서 해결.
      backgroundColor: Colors.white,
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
                  tileColor: Colors.white,
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
                tileColor: Colors.white,
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
                tileColor: Colors.white,
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
                tileColor: Colors.white,
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

      // ⭐ 2026-09-08 - "조가 바뀌어서 스케줄 변경을 썼는데 전체 근무표는 옛날
      // 값 그대로 남는다"는 지적 반영. 전체 근무표(all_teams_*)는 완전히 별도
      // 저장소라 이 함수가 안 건드리는데, "전체 근무표 설정" 화면은 열 때마다
      // 로스터/다른 조 배정은 그대로 보존한 채 "내 조" 위치만 지금 스케줄
      // 기준으로 새로 계산해서 보여주므로(all_shifts_view.dart의
      // _openAllTeamsSetupScreen 참고) 다시 열어서 저장만 하면 됨 - 그래서
      // "다시 만들라"가 아니라 "다시 저장해달라"는 짧은 안내만 조건부로 붙임
      // (전체 근무표를 아예 안 쓰는 사람에게는 무의미한 안내라 설정된 경우만).
      final hasAllTeamsSetup = (await SharedPreferences.getInstance())
          .getStringList('all_teams_names')
          ?.isNotEmpty ??
          false;

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasAllTeamsSetup
                  ? '✅ ${context.l10n.statusScheduleUpdated} ${context.l10n.settingsScheduleChangedRedoAllTeamsHint}'
                  : '✅ ${context.l10n.statusScheduleUpdated}',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: hasAllTeamsSetup ? const Duration(seconds: 5) : const Duration(seconds: 4),
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
        allShiftTypes: schedule.shiftTypes,
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

    // ⭐ 2026-09-14 (출시전 감사 #11/#12) - 이름 형식·최종 이름 중복은 renameShiftAtomic이 한 번 더 막고(예외),
    // 실패하면 트랜잭션 전체가 롤백되므로 화면 상태도 바꾸지 않고 안내만 함
    try {
      await DatabaseService.instance.renameShiftAtomic(
        renamedShifts: renamedShifts,
        newSchedule: newSchedule,
      );
    } catch (e) {
      print('❌ 근무명 변경 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.statusErrorWithDetail('$e'))),
        );
      }
      return;
    }
    ref.read(scheduleProvider.notifier).applyExternallyPersisted(newSchedule);
    // ⭐ 2026-09-14 (contracts §3) - condition_shift_times의 근무명도 같은 트랜잭션에서 바뀌었으므로 출퇴근 시각 영역도 통지
    ref.read(dataRevisionProvider(DataDomain.shiftTimes).notifier).state++;
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
  // ⭐ 2026-09-14 (#12) - 화면에 안 보이는(비활성) 근무명까지 포함한 전체 목록 - 변경 후 이름 중복 검사용
  final List<String> allShiftTypes;
  final Function(Map<String, String>) onSave;

  const _EditShiftNamesDialog({
    required this.shiftTypes,
    required this.allShiftTypes,
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
        AppSecondButton(
          variant: AppSecondButtonVariant.neutral,
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        AppSecondButton(
          variant: AppSecondButtonVariant.success,
          onPressed: () {
            final renamedShifts = <String, String>{};

            for (var entry in _controllers.entries) {
              final oldName = entry.key;
              final newName = entry.value.text.trim();

              if (newName.isNotEmpty && newName != oldName) {
                renamedShifts[oldName] = newName;
              }
            }

            // ⭐ 2026-09-14 (출시전 감사 #11/#12) - 새 이름 형식(쉼표·예약어·길이) + "변경 후" 이름끼리 중복 검사.
            // 맞바꾸기(A↔B)·순환은 허용하고, 두 근무가 같은 이름이 되는 경우만 거부(예전엔 그대로 저장돼 서로 다른
            // 근무의 알람·이력·출퇴근시각이 한 이름으로 합쳐졌음).
            final finalNames = widget.allShiftTypes.map((s) => renamedShifts[s] ?? s).toList();
            for (final newName in renamedShifts.values) {
              final issue = validateShiftName(newName) ??
                  (finalNames.where((n) => n == newName).length > 1 ? ShiftNameIssue.duplicate : null);
              if (issue != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_shiftNameIssueMessage(context, issue, newName))),
                );
                return;
              }
            }

            Navigator.pop(context);
            widget.onSave(renamedShifts);
          },
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
  // ⭐ 2026-08-25 - VoidCallback(void Function())에서 Future<void> Function()로
  // 변경. VoidCallback으로 선언돼 있으면 async 콜백을 넘겨도 호출부(_saveAndExit)
  // 에서 반환 타입이 void로 보여서 await이 안 먹힘(컴파일 에러) - _saveAndExit가
  // 실제로 이 콜백(=알람 재생성 완료)을 기다렸다가 화면을 닫아야 해서 타입을 바꿈.
  final Future<void> Function() onSave;

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

  // ⭐ 2026-08-31 - 저장 버튼 버그 수정 3종 세트.
  // 1) 변경사항 유무 판단용 최초 로드 스냅샷("불러온 그대로 다시 저장" 방지) -
  //    _hasChanges() 참고.
  // 2) 저장 중 중복 탭 방지 플래그. widget.onSave()(=_regenerateAllAlarms())가
  //    Native 갱신 대기용으로 일부러 800ms를 기다리는데, 그 사이 저장 버튼을
  //    빠르게 두 번 누르면 _saveAndExit이 동시에 두 번 실행돼서(DB 트랜잭션
  //    중복 실행 + Navigator.pop 중복 호출) 크래시가 날 수 있었음 - 저장 중엔
  //    버튼 자체를 비활성화하고 스피너로 바꿔서 원천 차단함.
  Map<String, List<AlarmSetting>> _initialShiftAlarms = {};
  bool _isSaving = false;

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
          dayOffset: t.dayOffset,
        );
      }).toList();
    }

    setState(() {
      _shiftAlarms = loadedAlarms;
      // ⭐ deep copy - _shiftAlarms의 각 List를 이후 수정해도(추가/삭제/변경)
      // 이 스냅샷은 최초 로드 상태 그대로 남아야 "변경 여부" 비교가 정확함.
      _initialShiftAlarms = {
        for (final entry in loadedAlarms.entries) entry.key: List.of(entry.value)
      };
      _isLoading = false;
    });
  }

  // ⭐ 근무명별 알람 목록을 "시각:타입:오프셋" 문자열로 정규화해서 비교 -
  // 순서가 달라져도(예: 같은 알람들을 지웠다 같은 내용으로 다시 추가) 내용이
  // 같으면 "변경 없음"으로 판단함.
  bool _hasChanges() {
    List<String> canonical(List<AlarmSetting> alarms) {
      final list = alarms
          .map((a) => '${a.time.hour}:${a.time.minute}:${a.alarmTypeId}:${a.dayOffset}')
          .toList()
        ..sort();
      return list;
    }

    final shifts = {..._shiftAlarms.keys, ..._initialShiftAlarms.keys};
    for (final shift in shifts) {
      final current = canonical(_shiftAlarms[shift] ?? const []);
      final initial = canonical(_initialShiftAlarms[shift] ?? const []);
      if (current.length != initial.length) return true;
      for (var i = 0; i < current.length; i++) {
        if (current[i] != initial[i]) return true;
      }
    }
    return false;
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
      // ⭐ 2026-08-25 - "저장" 버튼을 카드 바로 아래(스크롤 콘텐츠 안)가 아니라
      // 화면 맨 아래에 고정하고, 색상만 다른 ElevatedButton 대신 앱 공용 메인
      // 버튼(AppButton)으로 교체 - 온보딩의 "다음"/"완료" 버튼과 같은 위치·같은
      // 디자인 언어로 통일함(Column + Expanded(스크롤 영역) + 하단 고정 버튼).
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16.w, 16.w, 16.w, 0),
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
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, MediaQuery.of(context).padding.bottom + 16.h),
                  child: SizedBox(
                    width: double.infinity,
                    // ⭐ 2026-08-31 - 저장 중(_isSaving)엔 버튼을 비활성화하고
                    // 스피너로 바꿔서 연타로 인한 중복 실행/크래시를 막음
                    // (_saveAndExit 주석 참고).
                    child: AppButton(
                      onPressed: _isSaving ? null : _saveAndExit,
                      child: _isSaving
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(context.l10n.commonSave),
                    ),
                  ),
                ),
              ],
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
    // ⭐ 2026-08-31 - 저장 버튼 연타 방지. 이미 저장 진행 중이면 완전히 무시 -
    // 버튼도 저장 중엔 비활성화되지만(build() 참고), 그 사이에 들어온 탭
    // 이벤트가 큐에 남아있다가 뒤늦게 도착하는 경우까지 이중 안전장치로 막음.
    if (_isSaving) return;

    // ⭐ 2026-08-31 - 변경사항이 없으면 그냥 바로 닫는다. DB 재기록도, Native
    // 갱신 트리거도, 800ms 대기도, "변경사항이 저장되었습니다" 토스트도 전부
    // 스킵 - 아무것도 안 바뀌었는데 그런 걸 보여주면 사용자에게 거짓 신호를
    // 주는 셈이라("바뀐 게 없는데 왜 저장됐다고 하지?").
    if (!_hasChanges()) {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);

    try {
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
            'day_offset': alarm.dayOffset,
          });
        }
      }
      await DatabaseService.instance.replaceAllAlarmTemplates(templates);

      // ⭐ 2026-08-25 - await 누락 수정. widget.onSave()(=_regenerateAllAlarms(),
      // 네이티브 diff 갱신 트리거 + 800ms 대기 + Flutter Provider 재조회까지
      // 포함)를 기다리지 않고 바로 화면을 닫으면, 저장 직후(특히 알람이 0개였던
      // 상태에서) 사용자가 곧바로 "다음 알람" 탭으로 이동했을 때 아직 생성이
      // 안 끝나서 잠깐 "예정된 알람 없음"으로 보일 수 있었음(다음알람탭 자체의
      // 4초 폴링으로 결국엔 채워지긴 하지만, 그 몇 초 사이엔 진짜로 비어있었음).
      // await을 붙여서 이 화면이 닫히는 시점엔 이미 최신 알람이 Provider에 반영돼
      // 있도록 보장 - "저장" 버튼이 그만큼(최대 800ms+α) 살짝 늦게 닫히지만,
      // 그 대신 뒤 화면에서 빈 상태를 볼 가능성이 사라짐.
      await widget.onSave();
    } finally {
      // ⭐ 정상 흐름에선 이 직후 화면이 pop되면서 위젯이 dispose되지만, 혹시
      // pop 전에 위젯이 이미 unmount됐거나 위 작업 중 예외가 났을 때를 대비해
      // mounted 체크 후에만 상태를 되돌림.
      if (mounted) setState(() => _isSaving = false);
    }

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

  // ⭐ 2026-08-25 - 온보딩의 동일한 다이얼로그(_AlarmTimeDialog)와 같은 이유/구조 -
  // 그쪽 클래스의 build() 주석 참고.
  static const double _cardHeightEstimate = 118;

  double _listMaxHeight() => (_cardHeightEstimate * 3).h;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.settingsShiftFixedAlarmTitle(widget.shift)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.settingsFixedAlarmRegisterLimit(kMaxAlarmTemplatesPerShift),
              style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: 16.h),

            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _listMaxHeight()),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _alarms.asMap().entries.map((entry) {
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
                              // ⭐ 시간 영역 탭하면 시간 수정 - 전날/당일/다음날 Chip을 시계
                              // 아이콘 대신 놓아서("당일 09:00" 형태) 언제 울리는지 한눈에 보임.
                              InkWell(
                                onTap: () => _editAlarmTime(entry.key),
                                borderRadius: BorderRadius.circular(8.r),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DayOffsetBadge(dayOffset: alarm.dayOffset),
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
                  }).toList(),
                ),
              ),
            ),

            SizedBox(height: 16.h),

            // ⭐ 2026-08-25 - "알람 추가"는 원래 크기(내용물만큼)로 가운데 정렬,
            // 담백한 세 번째 버튼 스타일(AppThirdButton) 사용 - 온보딩과 동일.
            // 최대 개수(5개)에 도달해도 숨기지 않고 비활성 상태로 계속 보여줌.
            Center(
              child: AppThirdButton(
                onPressed: _alarms.length < kMaxAlarmTemplatesPerShift ? _addAlarm : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16.sp),
                    SizedBox(width: 4.w),
                    Text(context.l10n.alarmAdd),
                  ],
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              // ⭐ 2026-08-25 버그 수정 - onboarding_screen.dart의 동일한 다이얼로그와
              // 같은 이유(그쪽 주석 참고) - mainAxisSize.min을 빼야 end 정렬이 실제로
              // 오른쪽 끝에 붙음.
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppSecondButton(
                  variant: AppSecondButtonVariant.neutral,
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
                ),
                SizedBox(width: 8.w),
                AppSecondButton(
                  variant: AppSecondButtonVariant.success,
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
            ),
          ],
        ),
      ),
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
        shiftName: widget.shift,
        initialTime: currentAlarm.time,
        initialDayOffset: currentAlarm.dayOffset,
        onTimeSelected: (time, dayOffset) async {
          // ⭐ 중복 체크 (자기 자신 제외) - 같은 시각이어도 전날/당일/다음날이 다르면
          // 서로 다른 실제 날짜에 울리는 별개의 알람이라 중복이 아님.
          final isDuplicate = _alarms.asMap().entries.any((entry) {
            return entry.key != index &&
                   entry.value.time.hour == time.hour &&
                   entry.value.time.minute == time.minute &&
                   entry.value.dayOffset == dayOffset;
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
            _alarms[index] = currentAlarm.copyWith(time: time, dayOffset: dayOffset);
          });
        },
      ),
    );
  }

  Future<void> _addAlarm() async {
    await showDialog(
      context: context,
      builder: (context) => _SettingsTimePicker(
        shiftName: widget.shift,
        onTimeSelected: (time, dayOffset) async {
          // ⭐ 중복 체크 (시각 + 전날/당일/다음날이 모두 같을 때만 중복)
          final isDuplicate = _alarms.any((alarm) =>
            alarm.time.hour == time.hour && alarm.time.minute == time.minute && alarm.dayOffset == dayOffset
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
            _alarms.add(AlarmSetting(time: time, alarmTypeId: 1, dayOffset: dayOffset));
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
  final String shiftName;  // ⭐ 제목 왼쪽에 "{근무명} - 시간 선택"으로 표시
  final Function(TimeOfDay, int dayOffset) onTimeSelected;
  final TimeOfDay? initialTime;  // ⭐ 초기 시간 (수정 시 사용)
  final int initialDayOffset;    // ⭐ 초기 전날/당일/다음날 (기본값: 당일)

  const _SettingsTimePicker({
    required this.shiftName,
    required this.onTimeSelected,
    this.initialTime,
    this.initialDayOffset = kAlarmDaySame,
  });

  @override
  State<_SettingsTimePicker> createState() => _SettingsTimePickerState();
}

class _SettingsTimePickerState extends State<_SettingsTimePicker> {
  bool _isAM = true;
  int _hour = 9;
  int _minute = 0;
  late int _dayOffset;

  @override
  void initState() {
    super.initState();
    _dayOffset = widget.initialDayOffset;
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
            // ⭐ "{근무명} - 시간 선택" - 근무명이 왼쪽에 오도록
            Text(
              '${widget.shiftName} - ${context.l10n.commonSelectTime}',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),

            // ⭐ 전날/당일/다음날 - 시간 선택 바로 아래, AM/PM+시간 선택 위
            DayOffsetSelector(
              value: _dayOffset,
              onChanged: (value) => setState(() => _dayOffset = value),
            ),
            SizedBox(height: 16.h),

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
                AppSecondButton(
                  variant: AppSecondButtonVariant.neutral,
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
                ),
                SizedBox(width: 8.w),
                AppSecondButton(
                  variant: AppSecondButtonVariant.success,
                  onPressed: () async {
                    int hour24;
                    if (_isAM) {
                      hour24 = _hour == 12 ? 0 : _hour;
                    } else {
                      hour24 = _hour == 12 ? 12 : _hour + 12;
                    }

                    await widget.onTimeSelected(TimeOfDay(hour: hour24, minute: _minute), _dayOffset);
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
        AppSecondButton(
          variant: AppSecondButtonVariant.neutral,
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        AppSecondButton(
          variant: AppSecondButtonVariant.success,
          onPressed: _selectedIndex == null
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onConfirm(_selectedIndex!);
                },
          child: Text(context.l10n.commonSave),
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
        AppSecondButton(
          variant: AppSecondButtonVariant.neutral,
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        AppSecondButton(
          variant: AppSecondButtonVariant.success,
          onPressed: () {
            widget.onSave(_customColors);
            Navigator.pop(context);
          },
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
        AppSecondButton(
          variant: AppSecondButtonVariant.neutral,
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
      ],
    );
  }
}

// ⭐ 2026-09-14 (출시전 감사 #11) - 근무명 검증 결과 → 사용자 안내 문구
String _shiftNameIssueMessage(BuildContext context, ShiftNameIssue issue, String name) {
  switch (issue) {
    case ShiftNameIssue.empty:
      return context.l10n.onboardingEnterShiftName;
    case ShiftNameIssue.tooLong:
      return context.l10n.onboardingCharLimitError(kMaxShiftNameLength);
    case ShiftNameIssue.comma:
      return context.l10n.shiftNameCommaNotAllowed;
    case ShiftNameIssue.reserved:
      return context.l10n.shiftNameReserved(name);
    case ShiftNameIssue.duplicate:
      return context.l10n.onboardingDuplicateShiftName;
  }
}
