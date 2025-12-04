import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import 'onboarding_screen.dart';
import 'all_alarms_history_view.dart';
import '../services/alarm_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../models/alarm_type.dart';
import '../models/shift_schedule.dart';
import 'package:numberpicker/numberpicker.dart';

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
        content: Text('교대 스케줄과 알람을 모두 초기화할까요?\n(전체 교대조 근무표도 초기화됩니다.)'),
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

  Widget _buildDeleteItem(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16.sp, color: Colors.red.shade700),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
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
                            '교대 근무 관리',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
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
                    // ⭐ 수정 | 초기화 버튼 나란히 배치
                    Divider(height: 1, color: Colors.indigo.shade100),
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
                                    Icon(Icons.edit, color: Colors.indigo.shade400, size: 16.sp),
                                    SizedBox(width: 6.w),
                                    Text(
                                      '수정',
                                      style: TextStyle(
                                        color: Colors.indigo.shade600,
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
                          VerticalDivider(width: 1, color: Colors.indigo.shade100),
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
                                    Icon(Icons.refresh, color: Colors.red.shade400, size: 16.sp),
                                    SizedBox(width: 6.w),
                                    Text(
                                      '초기화',
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16.h),

              // ⭐ Production 섹션
              // 전체 교대조 근무표 작성
              ListTile(
                leading: Icon(Icons.groups, color: Colors.purple),
                title: Text('전체 교대조 근무표 작성'),
                subtitle: Text('전체 조 구성 및 근무 패턴 설정'),
                trailing: Icon(Icons.chevron_right),
                onTap: _showAllTeamsSetupDialog,
              ),

              // 알람음 관리
              ListTile(
                leading: Icon(Icons.notifications_active, color: Colors.orange),
                title: Text('알람음 관리'),
                subtitle: Text('소리, 진동, 무음 설정'),
                trailing: Icon(Icons.chevron_right),
                onTap: _showAlarmTypeDialog,
              ),

              // 모든 알람 & 알람 이력
              ListTile(
                leading: Icon(Icons.alarm_on, color: Colors.indigo),
                title: Text('모든 알람 & 알람 이력'),
                subtitle: Text('등록된 알람과 실행 이력 확인'),
                trailing: Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AllAlarmsHistoryView()),
                  );
                },
              ),

              SizedBox(height: 16.h),

              // ⭐ 모든 알람 완전 삭제 (위급 상황용)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.red.shade300, width: 2),
                ),
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 32.sp),
                  title: Text(
                    '모든 알람 완전 삭제',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 15.sp,
                    ),
                  ),
                  subtitle: Text(
                    '⚠️ 위급 상황 전용: 모든 알람과 템플릿이 영구 삭제됩니다.\n정상 이용을 위해서는 다시 알람을 설정해야 합니다.',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12.sp,
                      height: 1.4,
                    ),
                  ),
                  trailing: Icon(Icons.delete_forever, color: Colors.red.shade700, size: 28.sp),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.red.shade50,
                        title: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28.sp),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                '모든 알람 완전 삭제',
                                style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '이 작업은 되돌릴 수 없습니다!',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                            SizedBox(height: 12.h),
                            Text(
                              '다음 항목이 모두 삭제됩니다:',
                              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 8.h),
                            _buildDeleteItem('📱 등록된 모든 알람 (DB + Native)'),
                            _buildDeleteItem('🔔 모든 알람 Notification'),
                            _buildDeleteItem('📋 모든 알람 템플릿'),
                            _buildDeleteItem('⏰ 알람 갱신 프로세스 중단'),
                            SizedBox(height: 12.h),
                            Container(
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Text(
                                '⚠️ 정상 이용을 위해서는 다시 알람을 설정해야 합니다.',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text('취소'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                            ),
                            child: Text('완전 삭제', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              content: Text('🗑️🔥 모든 알람이 완전히 삭제되었습니다'),
                              backgroundColor: Colors.red.shade700,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('❌ 삭제 실패: $e')),
                          );
                        }
                      }
                    }
                  },
                ),
              ),

              SizedBox(height: 24.h),
              Divider(thickness: 2, color: Colors.grey.shade300),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
                child: Text(
                  '테스트 도구',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              Divider(thickness: 2, color: Colors.grey.shade300),
              SizedBox(height: 8.h),

              // ⭐ 테스트 섹션
              // 테스트 알람 (5초 후)
              ListTile(
                leading: Icon(Icons.bug_report, color: Colors.green),
                title: Text('테스트 알람 (5초 후)'),
                subtitle: Text('알람 동작 테스트용'),
                onTap: () async {
                  try {
                    await AlarmService().scheduleTestAlarm(
                      label: '테스트 알람',
                      soundType: 'loud',
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('⏰ 5초 후 알람이 울립니다!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('❌ 테스트 알람 실패: $e')),
                      );
                    }
                  }
                },
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              ListTile(
                leading: Icon(Icons.edit, color: Colors.blue),
                title: Text('근무명 수정'),
                subtitle: Text('근무 이름을 변경합니다'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditShiftNamesDialog();
                },
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.alarm, color: Colors.orange),
                title: Text('고정 알람 수정'),
                subtitle: Text('근무별 알람 시간을 변경합니다'),
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

    // 4. shiftColors 업데이트
    final newShiftColors = <String, int>{};
    schedule.shiftColors?.forEach((key, value) {
      final newKey = renamedShifts[key] ?? key;
      newShiftColors[newKey] = value;
    });

    // 5. assignedDates 업데이트
    final newAssignedDates = <String, String>{};
    schedule.assignedDates?.forEach((date, shift) {
      final newShift = renamedShifts[shift] ?? shift;
      newAssignedDates[date] = newShift;
    });

    // 6. DB 업데이트
    await DatabaseService.instance.updateShiftNames(renamedShifts);

    // 7. Schedule 저장
    final newSchedule = ShiftSchedule(
      id: schedule.id,
      isRegular: schedule.isRegular,
      pattern: newPattern,
      todayIndex: schedule.todayIndex,
      shiftTypes: newShiftTypes,
      activeShiftTypes: newActiveShiftTypes,
      startDate: schedule.startDate,
      shiftColors: newShiftColors,
      assignedDates: newAssignedDates,
    );

    await ref.read(scheduleProvider.notifier).saveSchedule(newSchedule);
    await ref.read(alarmNotifierProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('근무명이 변경되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ⭐ 고정 알람 수정 화면
  void _showEditFixedAlarmsScreen() {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    final activeShifts = schedule.activeShiftTypes ?? schedule.shiftTypes;

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
  Future<void> _regenerateAllAlarms() async {
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;

    // 1. 기존 알람 전체 삭제
    final existingAlarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in existingAlarms) {
      if (alarm.id != null) {
        await AlarmService().cancelAlarm(alarm.id!);
      }
    }
    await DatabaseService.instance.deleteAllAlarms();

    // 2. Notification 취소
    try {
      const platform = MethodChannel('com.example.shiftbell/alarm');
      await platform.invokeMethod('cancelNotification');
    } catch (e) {
      print('⚠️ Notification 삭제 실패: $e');
    }

    // 3. 10일치 알람 재생성
    await _generate10DaysAlarmsFromTemplates(schedule);

    // 4. AlarmGuard 트리거
    try {
      const platform = MethodChannel('com.example.shiftbell/alarm');
      await platform.invokeMethod('triggerGuardCheck');
    } catch (e) {
      print('⚠️ AlarmGuard 트리거 실패: $e');
    }

    // 5. Provider 갱신
    await ref.read(alarmNotifierProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('알람이 업데이트되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ⭐ 템플릿 기반 10일치 알람 생성
  Future<void> _generate10DaysAlarmsFromTemplates(ShiftSchedule schedule) async {
    final today = DateTime.now();
    final db = await DatabaseService.instance.database;

    for (var i = 0; i < 10; i++) {
      final date = today.add(Duration(days: i));
      final shiftType = schedule.getShiftForDate(date);

      if (shiftType == '미설정') continue;

      // 해당 근무의 템플릿 조회
      final templates = await DatabaseService.instance.getAlarmTemplates(shiftType);

      for (var template in templates) {
        final timeParts = template.time.split(':');
        final alarmTime = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );

        // 과거 시간이면 스킵
        if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) continue;

        // DB에 알람 저장
        final alarmId = await db.insert('alarms', {
          'time': template.time,
          'date': alarmTime.toIso8601String(),
          'type': 'fixed',
          'alarm_type_id': template.alarmTypeId,
          'shift_type': shiftType,
        });

        // Native 알람 등록
        await AlarmService().scheduleAlarm(
          id: alarmId,
          dateTime: alarmTime,
          label: shiftType,
          soundType: 'loud',
        );
      }
    }

    print('✅ 10일치 알람 재생성 완료');
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
          title: Text('전체 교대조 근무표 작성'),
          content: Text('이 기능은 규칙적 근무 패턴이 설정된 경우에만 사용할 수 있습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('확인'),
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
          title: Text('전체 교대조 근무표 작성'),
          content: Text('이미 작성된 근무표가 있습니다.\n다시 작성하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('다시 작성', style: TextStyle(color: Colors.purple)),
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
      builder: (context) => _AllTeamsSetupDialog(
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
  static const platform = MethodChannel('com.example.shiftbell/alarm');

  @override
  void initState() {
    super.initState();
    _types = List.from(widget.alarmTypes);

    // DB에 타입이 없으면 프리셋으로 초기화
    if (_types.isEmpty) {
      _initPresets();
    } else {
      // 프리셋 기본값 확인/수정 (백그라운드에서 실행, await 없음)
      DatabaseService.instance.ensurePresetDefaults();
    }
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
                '알람음 설정',
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
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.shade200),
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
                type.isSound ? '소리' : type.isVibrate ? '진동' : '무음',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (type.isSound)
                Text(
                  ' (진동 포함)',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                ),
            ],
          ),
          SizedBox(height: 12.h),

          // 소리 타입: 음악 선택 + 음량 슬라이더
          if (type.isSound) ...[
            _buildSoundSelectRow(type),
            SizedBox(height: 12.h),
            _buildSliderRow(
              label: '음량',
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
          child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
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

  // 알람 사운드 목록 (파일명과 표시명)
  static const List<Map<String, String>> _soundOptions = [
    {'id': 'default', 'name': '기본알람음', 'file': 'default'},
    {'id': 'alarmbell1', 'name': '알람벨 1', 'file': 'alarmbell1.mp3'},
    {'id': 'alarmbell2', 'name': '알람벨 2', 'file': 'alarmbell2.mp3'},
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
          SnackBar(content: Text('알람음 파일을 찾을 수 없습니다')),
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
          child: Text('알람음', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.music_note, size: 18.sp, color: Colors.orange),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            _getSoundName(type.soundFile),  // DB에서 읽은 값 사용
                            style: TextStyle(fontSize: 13.sp),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: Colors.grey),
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
                    color: _isPlaying ? Colors.red.shade50 : Colors.blue.shade50,
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

  String _getSoundName(String soundId) {
    return _soundOptions.firstWhere(
      (s) => s['id'] == soundId,
      orElse: () => {'name': '알람벨 1'},
    )['name']!;
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
            color: Colors.white,
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
                        '알람음 선택',
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
                          sound['name']!,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.orange.shade800 : Colors.black,
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
        SizedBox(
          width: 50.w,
          child: Text('세기', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Row(
            children: [
              _buildVibrationButton(type, 1, '약하게'),
              SizedBox(width: 8.w),
              _buildVibrationButton(type, 3, '강하게'),
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
            color: isSelected ? Colors.orange.shade100 : Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.orange.shade800 : Colors.grey.shade700,
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
        SizedBox(
          width: 50.w,
          child: Text('시간', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
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
            color: isSelected ? Colors.blue.shade100 : Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '${minutes}분',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue.shade800 : Colors.grey.shade700,
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
    return AlertDialog(
      title: Text('근무명 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.shiftTypes.map((shift) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: TextField(
                controller: _controllers[shift],
                maxLength: 4,
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
          child: Text('취소'),
        ),
        TextButton(
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
          child: Text('저장'),
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
    return Scaffold(
      appBar: AppBar(
        title: Text('고정 알람 수정'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '근무별 고정 알람을 설정하세요',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '각 근무당 최대 3개까지 설정 가능',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey),
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
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                      child: Text('저장', style: TextStyle(fontSize: 16.sp)),
                    ),
                  ),
                  SizedBox(height: 16.h),
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
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: alarms.isEmpty ? Colors.red.shade300 : Colors.black,
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
              child: Center(
                child: alarms.isEmpty
                    ? Text(
                        '탭하여 설정',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.grey,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
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
    // 기존 템플릿 삭제 후 새로 저장
    await DatabaseService.instance.deleteAllAlarmTemplates();

    for (var entry in _shiftAlarms.entries) {
      final shift = entry.key;
      final alarms = entry.value;

      for (var alarm in alarms) {
        await DatabaseService.instance.insertAlarmTemplate(
          shiftType: shift,
          time: _formatTime(alarm.time),
          alarmTypeId: alarm.alarmTypeId,
        );
      }
    }

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
    return AlertDialog(
      title: Text('${widget.shift} 고정 알람'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '고정 알람 3개까지 등록 가능',
              style: TextStyle(fontSize: 13.sp, color: Colors.grey),
            ),
            SizedBox(height: 16.h),

            ..._alarms.asMap().entries.map((entry) {
              final alarm = entry.value;
              return Container(
                margin: EdgeInsets.only(bottom: 12.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.grey.shade300),
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
                                Icon(Icons.alarm, size: 20.sp, color: Colors.blue),
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
                          icon: Icon(Icons.delete, color: Colors.red, size: 20.sp),
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
                        _buildTypeButton(entry.key, 1, '🔔', '소리'),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 2, '📳', '진동'),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 3, '🔇', '무음'),
                      ],
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 8.h),

            if (_alarms.length < 3)
              OutlinedButton.icon(
                onPressed: _addAlarm,
                icon: Icon(Icons.add),
                label: Text('알람 추가'),
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
          child: Text('취소'),
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
          child: Text('저장'),
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
            color: isSelected ? Colors.orange.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
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
                  color: isSelected ? Colors.orange.shade800 : Colors.grey.shade600,
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
        onTimeSelected: (time) {
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
        onTimeSelected: (time) {
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
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '시간 선택',
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
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            '오전',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
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
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            '오후',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(width: 16.w),

                NumberPicker(
                  value: _hour,
                  minValue: 1,
                  maxValue: 12,
                  infiniteLoop: true,
                  haptics: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  axis: Axis.vertical,
                  textStyle: TextStyle(fontSize: 16.sp, color: Colors.grey),
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
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),

                Text(':', style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold)),

                NumberPicker(
                  value: _minute,
                  minValue: 0,
                  maxValue: 59,
                  zeroPad: true,
                  infiniteLoop: true,
                  haptics: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  axis: Axis.vertical,
                  textStyle: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      _minute = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
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
                  child: Text('취소'),
                ),
                SizedBox(width: 8.w),
                ElevatedButton(
                  onPressed: () {
                    int hour24;
                    if (_isAM) {
                      hour24 = _hour == 12 ? 0 : _hour;
                    } else {
                      hour24 = _hour == 12 ? 12 : _hour + 12;
                    }

                    widget.onTimeSelected(TimeOfDay(hour: hour24, minute: _minute));
                    Navigator.pop(context);
                  },
                  child: Text('확인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ⭐ 전체 교대조 근무표 작성 다이얼로그
class _AllTeamsSetupDialog extends StatefulWidget {
  final List<String> pattern;

  const _AllTeamsSetupDialog({required this.pattern});

  @override
  State<_AllTeamsSetupDialog> createState() => _AllTeamsSetupDialogState();
}

class _AllTeamsSetupDialogState extends State<_AllTeamsSetupDialog> {
  final PageController _pageController = PageController();
  final TextEditingController _teamInputController = TextEditingController();
  int _currentPage = 0;

  // 사용자 입력 데이터
  List<String> _teamNames = []; // 예: ['A', 'B', 'C', 'D']
  String? _myTeam; // 예: 'C'
  Map<String, int> _teamIndices = {}; // 예: {'A': 1, 'B': 3, 'C': 5, 'D': 7} (오늘의 패턴 인덱스 1~8)

  @override
  void initState() {
    super.initState();
    _teamInputController.addListener(_onTeamInputChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _teamInputController.dispose();
    super.dispose();
  }

  void _onTeamInputChanged() {
    final text = _teamInputController.text.toUpperCase(); // 대문자 변환

    // 먼저 controller의 텍스트를 대문자로 업데이트 (커서 위치 유지)
    if (_teamInputController.text != text) {
      final selection = _teamInputController.selection;
      _teamInputController.value = _teamInputController.value.copyWith(
        text: text,
        selection: selection,
      );
    }

    setState(() {
      final teams = text
          .split(RegExp(r'\s+')) // 공백으로 분리
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e.length == 1)
          .toList();

      // 중복 제거
      _teamNames = teams.toSet().toList();
    });
  }

  void _nextPage() {
    // 키보드 닫기
    FocusScope.of(context).unfocus();

    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    // 키보드 닫기
    FocusScope.of(context).unfocus();

    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      child: Container(
        height: screenHeight * 0.9, // 화면 높이의 90%
        padding: EdgeInsets.all(24.w),
        child: Column(
          children: [
            // 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '전체 교대조 근무표 작성',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            SizedBox(height: 16.h),

            // 진행 상태 표시
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return Row(
                  children: [
                    Container(
                      width: 30.w,
                      height: 30.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index <= _currentPage
                            ? Colors.purple
                            : Colors.grey.shade300,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                    ),
                    if (index < 2)
                      Container(
                        width: 60.w,
                        height: 2.h,
                        color: index < _currentPage
                            ? Colors.purple
                            : Colors.grey.shade300,
                      ),
                  ],
                );
              }),
            ),

            SizedBox(height: 24.h),

            // 페이지 내용
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildStep1_PatternConfirm(),
                  _buildStep2_TeamNamesInput(),
                  _buildStep3_OffsetInput(),
                ],
              ),
            ),

            SizedBox(height: 16.h),

            // 하단 버튼
            Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousPage,
                      child: Text('이전'),
                    ),
                  ),
                if (_currentPage > 0) SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canProceed() ? (_currentPage < 2 ? _nextPage : _complete) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                    ),
                    child: Text(
                      _currentPage < 2 ? '다음' : '완료',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_currentPage) {
      case 0:
        return true; // 패턴 확인만 하면 됨
      case 1:
        return _teamNames.length >= 2; // 최소 2개 조
      case 2:
        return _teamIndices.length == _teamNames.length &&
               _teamIndices.values.every((idx) => idx >= 1 && idx <= widget.pattern.length);
      default:
        return false;
    }
  }

  // 패턴 표시 (화살표 없이 단순 배치)
  Widget _buildPatternCards() {
    return Wrap(
      spacing: 6.w,
      runSpacing: 8.h,
      children: widget.pattern.map((shift) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(color: Colors.purple.shade300),
          ),
          child: Text(
            shift,
            style: TextStyle(
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: Colors.purple.shade700,
            ),
          ),
        );
      }).toList(),
    );
  }

  // 패턴 표시 (표 형식)
  Widget _buildPatternCardsWithIndices() {
    return Wrap(
      spacing: 6.w,
      runSpacing: 8.h,
      children: List.generate(widget.pattern.length, (i) {
        return Container(
          width: (MediaQuery.of(context).size.width - 80.w) / 10,
          padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                widget.pattern[i],
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }),
    );
  }

  // 1단계: 교대 패턴 확인
  Widget _buildStep1_PatternConfirm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1단계: 교대 패턴 확인',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          '현재 설정된 교대 패턴을 확인해주세요.',
          style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
        ),
        SizedBox(height: 24.h),
        Container(
          width: double.infinity,
          height: 200.h, // 고정 높이
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.purple.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '교대 패턴',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade900,
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildPatternCards(),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                '총 ${widget.pattern.length}일 주기',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.purple.shade600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 24.h),
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            children: [
              Icon(Icons.info, color: Colors.blue, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  '이 패턴을 기준으로 전체 조의 근무표를 작성합니다.',
                  style: TextStyle(fontSize: 12.sp, color: Colors.blue.shade900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2단계: 전체 조 구성 입력
  Widget _buildStep2_TeamNamesInput() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '2단계: 전체 조 구성',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '전체 교대조를 입력해주세요. (한 글자로만, 띄어쓰기로 구분)',
            style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
          ),
          SizedBox(height: 24.h),
          TextField(
            controller: _teamInputController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '조 이름 (예: A B C D)',
              hintText: 'A B C D',
              helperText: '한 글자로만 입력하고 띄어쓰기로 구분해주세요',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.purple, width: 2),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          if (_teamNames.isNotEmpty)
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '입력된 조 (${_teamNames.length}개)',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    children: _teamNames.map((team) {
                      return Chip(
                        label: Text(
                          '$team조',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: Colors.white,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange, size: 20.sp),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    '한 글자만 입력 가능합니다. (예: A 가 1)\n최소 2개 조 이상 입력해주세요.',
                    style: TextStyle(fontSize: 12.sp, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3단계: 본인 조 선택
  Widget _buildStep3_MyTeamSelect() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3단계: 본인 조 선택',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '본인이 속한 조를 선택해주세요.',
            style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
          ),
          SizedBox(height: 24.h),
          ...(_teamNames.map((team) {
            final isSelected = _myTeam == team;
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _myTeam = team;
                  });
                },
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.purple.shade50 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: isSelected ? Colors.purple : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.purple : Colors.grey,
                        size: 24.sp,
                      ),
                      SizedBox(width: 12.w),
                      Text(
                        '$team조',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.purple.shade900 : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList()),
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue, size: 20.sp),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    '선택한 조를 기준으로 전체 근무표를 작성합니다.',
                    style: TextStyle(fontSize: 12.sp, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3단계: 각 조 근무 선택
  Widget _buildStep3_OffsetInput() {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3단계: 오늘 각 조의 근무 설정',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '오늘 각 조가 교대근무 패턴의 어떤 근무인지 선택해주세요.',
            style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
          ),
          SizedBox(height: 16.h),

          // 각 조별 근무 선택
          ..._teamNames.map((team) {
            final selectedIndex = _teamIndices[team];
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$team조 - 오늘의 근무 선택',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: List.generate(widget.pattern.length, (i) {
                        final index = i + 1;
                        final shiftName = widget.pattern[i];
                        final isSelected = selectedIndex == index;
                        final isUsedByOther = _teamIndices.entries
                            .any((entry) => entry.key != team && entry.value == index);

                        return GestureDetector(
                          onTap: isUsedByOther ? null : () {
                            setState(() {
                              _teamIndices[team] = index;
                            });
                          },
                          child: Container(
                            width: 50.w,
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
                            decoration: BoxDecoration(
                              color: isUsedByOther
                                  ? Colors.grey.shade300
                                  : (isSelected ? Colors.purple : Colors.white),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: isUsedByOther
                                    ? Colors.grey.shade400
                                    : (isSelected ? Colors.purple : Colors.grey.shade400),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$index',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : Colors.red.shade700,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  shiftName,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Future<void> _complete() async {
    // SharedPreferences에 전체 근무표 데이터 저장
    final prefs = await SharedPreferences.getInstance();

    // JSON 형태로 저장
    await prefs.setStringList('all_teams_names', _teamNames);
    await prefs.setString('all_teams_my_team', _myTeam ?? '');

    // 인덱스를 JSON 문자열로 저장
    final indicesJson = _teamIndices.map((key, value) => MapEntry(key, value.toString()));
    await prefs.setString('all_teams_indices', jsonEncode(indicesJson));

    print('✅ 전체 교대조 근무표 저장 완료:');
    print('  - 조 목록: $_teamNames');
    print('  - 본인 조: $_myTeam');
    print('  - 인덱스: $_teamIndices');

    if (!mounted) return;

    Navigator.pop(context);

    // 성공 메시지
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('전체 교대조 근무표가 설정되었습니다!'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
