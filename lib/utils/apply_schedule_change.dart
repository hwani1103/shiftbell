import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/platform_channel.dart';
import '../l10n/l10n_extensions.dart';
import '../models/shift_schedule.dart';
import '../models/team_schedule_config.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../services/database_service.dart';
import '../widgets/schedule_change_dialog.dart';

Future<bool> applyScheduleChange(
    BuildContext context,
    WidgetRef ref,
    ScheduleChangeSelection selection,
    DateTime date,
    TeamScheduleConfig? teams) async {
  final schedule = ref.read(scheduleProvider).value;
  if (schedule == null) return false;

  // 로딩 표시
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Theme.of(context).colorScheme.surface),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(context.l10n.settingsScheduleChanging)),
          ],
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  try {
    if (selection.team != null && (teams == null || !teams.names.contains(selection.team))) {
      throw StateError('Unknown team');
    }
    if (selection.team == null && (selection.index < 0 || selection.index >= (schedule.pattern?.length ?? 0))) {
      throw StateError('Invalid pattern position');
    }
    final target = selection.team == null
        ? null
        : teams?.ruleFor(selection.team!, schedule.pattern!);
    final nextTeams = target == null
        ? null
        : teams!.materialize(schedule.pattern!).withMyTeam(selection.team!);
    // 1. 스케줄 업데이트 (startDate = 오늘, todayIndex = 선택한 인덱스)
    final newSchedule = ShiftSchedule(
      id: schedule.id,
      isRegular: schedule.isRegular,
      pattern: target?.shifts ?? schedule.pattern,
      todayIndex: target?.indexOn(date) ?? selection.index,
      shiftTypes: schedule.shiftTypes,
      activeShiftTypes:
          target?.shifts.toSet().toList() ?? schedule.activeShiftTypes,
      startDate: DateTime(date.year, date.month, date.day),
      shiftColors: schedule.shiftColors,
      customShiftColors: schedule.customShiftColors,
      assignedDates: {}, // ⭐ 수동 할당 초기화
      shiftDurations: schedule.shiftDurations,
    );

    await DatabaseService.instance.applyTeamScheduleChange(
        before: schedule,
        after: newSchedule,
        expectedTeams: teams,
        nextTeams: nextTeams);
    ref.read(scheduleProvider.notifier).applyExternallyPersisted(newSchedule);
    // 2. ⭐ Dart에서 직접 전체 삭제 후 재생성하지 않고 Native의 diff 기반
    // 갱신 엔진에 위임함. Dart가 직접 전체를 지우고 다시 만들면, 실제로는
    // 안 바뀐 알람까지도 "일정 변경"으로 이력에 잘못 찍히는 문제가 있었음
    // (Native 엔진은 실제로 달라진 것만 골라서 건드림).
    const platform = kAlarmChannel;
    var refreshCompleted = false;
    try {
      refreshCompleted =
          await platform.invokeMethod<bool>('forceNativeRefreshAndWait') ??
              false;
    } catch (e) {
      print('⚠️ Native 갱신 실패: $e');
    }

    // 3. Notification 취소
    try {
      await platform.invokeMethod('cancelNotification');
    } catch (e) {
      print('⚠️ Notification 삭제 실패: $e');
    }

    // 4. 완료가 확인된 갱신 결과를 UI에 반영
    await ref.read(alarmNotifierProvider.notifier).refresh();

    // 5. diff 갱신이 끝난 "이후" 상태 기준으로 20분 전 알림(8888) 재계산
    // (위 cancelNotification은 diff가 끝나기 전이라 낡은 상태로 계산될 수 있음)
    try {
      await platform.invokeMethod('triggerGuardCheck');
    } catch (e) {
      print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
    }

    if (!context.mounted) return true;
    final successMessage = teams != null &&
            selection.team != null &&
            teams.myTeam != selection.team
        ? context.l10n.scheduleTeamChanged(teams.myTeam, selection.team!)
        : context.l10n.statusScheduleUpdated;

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !refreshCompleted
                ? context.l10n.scheduleRefreshUnconfirmed
                : successMessage,
          ),
          backgroundColor: refreshCompleted ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    return true;
  } catch (e) {
    print('❌ 스케줄 변경 실패: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '❌ ${context.l10n.settingsScheduleChangeFailedWithError(context.localizedErrorDetail(e))}'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }
}
