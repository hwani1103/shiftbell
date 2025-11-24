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
        title: Text('스케줄 초기화'),
        content: Text('교대 스케줄과 알람을 모두 초기화할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('초기화', style: TextStyle(color: Colors.red)),
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
        title: Row(
          children: [
            Spacer(),
            Padding(
              padding: EdgeInsets.only(right: 16.w),
              child: Text('설정'),
            ),
          ],
        ),
      ),
      body: scheduleAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('에러 발생: $error')),
        data: (schedule) {
          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              // 현재 스케줄 정보
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.indigo.shade200, width: 1.5),
                ),
                child: Column(
                  children: [
                    // 헤더
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(10.r),
                          topRight: Radius.circular(10.r),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month, color: Colors.indigo, size: 20.sp),
                          SizedBox(width: 8.w),
                          Text(
                            '교대 스케줄',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                          Spacer(),
                          // 스케줄 설정 버튼
                          InkWell(
                            onTap: () {
                              // TODO: 스케줄 설정 화면으로 이동
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('스케줄 설정 (준비 중)')),
                              );
                            },
                            borderRadius: BorderRadius.circular(8.r),
                            child: Padding(
                              padding: EdgeInsets.all(4.w),
                              child: Icon(Icons.settings, color: Colors.indigo.shade400, size: 20.sp),
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
                            Text('설정 안 됨', style: TextStyle(color: Colors.grey))
                          else if (schedule.isRegular && schedule.pattern != null)
                            _buildPatternRow(schedule.pattern!)
                          else
                            _buildShiftTypesRow((schedule.activeShiftTypes ?? schedule.shiftTypes)),
                        ],
                      ),
                    ),
                    // 초기화 버튼
                    Divider(height: 1, color: Colors.indigo.shade100),
                    InkWell(
                      onTap: _resetSchedule,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(10.r),
                        bottomRight: Radius.circular(10.r),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh, color: Colors.red.shade400, size: 16.sp),
                            SizedBox(width: 6.w),
                            Text(
                              '스케줄 초기화',
                              style: TextStyle(
                                color: Colors.red.shade400,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16.h),

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

  // 교대 패턴 표시 (규칙적)
  Widget _buildPatternRow(List<String> pattern) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '교대 패턴',
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey.shade600,
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
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Text(
                  pattern[i],
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
              if (i < pattern.length - 1)
                Icon(Icons.arrow_forward, size: 14.sp, color: Colors.grey.shade400),
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
          '근무명',
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 6.w,
          runSpacing: 6.h,
          children: shiftTypes.map((type) => Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(6.r),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Text(
              type,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade700,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
}
