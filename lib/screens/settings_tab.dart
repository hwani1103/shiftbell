import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/database_service.dart';
import 'onboarding_screen.dart';
import '../services/alarm_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {

  Future<void> _resetSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('완전 초기화'),
        content: Text('스케줄, 알람, 템플릿을 모두 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('삭제', style: TextStyle(color: Colors.red)),
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

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => OnboardingScreen()),
        );
      }
    }
  }

  Future<void> _showAlarmListDialog() async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    alarms.sort((a, b) => a.date!.compareTo(b.date!));

    final now = DateTime.now();
    final futureAlarms = alarms.where((a) => a.date != null && a.date!.isAfter(now)).toList();
    final pastAlarms = alarms.where((a) => a.date != null && a.date!.isBefore(now)).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.alarm, color: Colors.blue),
            SizedBox(width: 8.w),
            Text('등록된 알람'),
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
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCountItem('미래', futureAlarms.length, Colors.green),
                    _buildCountItem('과거', pastAlarms.length, Colors.grey),
                    _buildCountItem('전체', alarms.length, Colors.blue),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              if (alarms.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.h),
                    child: Text('등록된 알람이 없습니다', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: alarms.length,
                    itemBuilder: (context, index) {
                      final alarm = alarms[index];
                      final isPast = alarm.date!.isBefore(now);
                      final isToday = alarm.date!.year == now.year &&
                                     alarm.date!.month == now.month &&
                                     alarm.date!.day == now.day;

                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 2.h),
                        child: Text(
                          '${_formatDate(alarm.date!)} ${alarm.shiftType ?? "알람"}${isToday ? " (오늘)" : ""}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontFamily: 'monospace',
                            color: isPast ? Colors.grey : (isToday ? Colors.orange : Colors.black),
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
            child: Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAlarmHistoryDialog() async {
    final history = await DatabaseService.instance.getAlarmHistory(limit: 100);

    // 한 달 이상 지난 이력 삭제
    final oneMonthAgo = DateTime.now().subtract(Duration(days: 30));
    await DatabaseService.instance.deleteOldHistory(oneMonthAgo);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.history, color: Colors.purple),
            SizedBox(width: 8.w),
            Text('알람 이력'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: 500.h),
          child: history.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(32.h),
                  child: Text('알람 이력이 없습니다', style: TextStyle(color: Colors.grey)),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: history.map((item) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Text(
                        '${_formatHistoryLine(item)}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontFamily: 'monospace',
                          color: _getTypeColor(item.dismissType),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('이력 삭제'),
                  content: Text('모든 알람 이력을 삭제할까요?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('취소')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('삭제', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await DatabaseService.instance.clearAlarmHistory();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ 알람 이력 삭제 완료')),
                );
              }
            },
            child: Text('전체 삭제', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기'),
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

  String _formatHistoryLine(dynamic item) {
    final date = item.scheduledDate;
    final time = item.scheduledTime;
    final type = _getTypeText(item.dismissType);
    final shift = item.shiftType ?? '';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $time $shift $type';
  }

  String _getTypeText(String type) {
    switch (type) {
      case 'swiped': return 'check';
      case 'snoozed': return 'snooze';
      case 'timeout': return 'timeout';
      case 'ringing': return 'ringing';
      default: return type;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'swiped': return Colors.green;
      case 'snoozed': return Colors.orange;
      case 'timeout': return Colors.red;
      case 'ringing': return Colors.blue;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('설정'),
      ),
      body: scheduleAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('에러 발생: $error')),
        data: (schedule) {
          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              // 현재 스케줄 정보
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('교대 스케줄', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                      SizedBox(height: 12.h),
                      if (schedule == null)
                        Text('설정 안 됨', style: TextStyle(color: Colors.grey))
                      else ...[
                        Text('근무 형태: ${schedule.isRegular ? "규칙적" : "불규칙"}'),
                        if (schedule.isRegular && schedule.pattern != null) ...[
                          SizedBox(height: 8.h),
                          Text('패턴: ${schedule.pattern!.join(", ")}'),
                          Text('오늘 인덱스: ${schedule.todayIndex ?? "?"}'),
                        ],
                        SizedBox(height: 8.h),
                        Text('근무 종류: ${(schedule.activeShiftTypes ?? schedule.shiftTypes).join(", ")}'),
                      ],
                    ],
                  ),
                ),
              ),

              SizedBox(height: 16.h),

              // 스케줄 초기화
              ListTile(
                leading: Icon(Icons.refresh, color: Colors.orange),
                title: Text('교대 스케줄 초기화'),
                subtitle: Text('온보딩으로 다시 설정'),
                onTap: _resetSchedule,
              ),

              Divider(),

              // 등록된 알람
              ListTile(
                leading: Icon(Icons.alarm, color: Colors.blue),
                title: Text('등록된 알람'),
                subtitle: Text('현재 등록된 알람 목록'),
                onTap: _showAlarmListDialog,
              ),

              // 모든 알람 삭제
              ListTile(
                leading: Icon(Icons.delete_sweep, color: Colors.red),
                title: Text('모든 알람 삭제'),
                subtitle: Text('DB + Native 알람 전부 삭제'),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('모든 알람 삭제'),
                      content: Text('정말로 모든 알람을 삭제할까요?\n(스케줄은 유지됩니다)'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('취소'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('삭제', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await ref.read(alarmNotifierProvider.notifier).deleteAllAlarms();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ 모든 알람 삭제 완료')),
                      );
                    }
                  }
                },
              ),

              Divider(),

              // 알람 이력
              ListTile(
                leading: Icon(Icons.history, color: Colors.purple),
                title: Text('알람 이력'),
                subtitle: Text('지난 알람 기록 (30일)'),
                onTap: _showAlarmHistoryDialog,
              ),
            ],
          );
        },
      ),
    );
  }
}
