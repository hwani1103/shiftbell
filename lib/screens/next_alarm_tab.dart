// lib/screens/next_alarm_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import '../models/alarm.dart';
import '../models/alarm_type.dart';
import '../services/database_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alarm_provider.dart';


class NextAlarmTab extends ConsumerStatefulWidget {
  const NextAlarmTab({super.key});

  @override
  ConsumerState<NextAlarmTab> createState() => _NextAlarmTabState();
}

class _NextAlarmTabState extends ConsumerState<NextAlarmTab> {
  Timer? _countdownTimer;
  static const platform = MethodChannel('com.example.shiftbell/alarm');

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _dismissAlarm(int id, DateTime? date) async {
    try {
      await platform.invokeMethod('dismissOverlay', {'alarmId': id});
    } catch (e) {
      print('⚠️ Overlay 종료 신호 실패: $e');
    }

    await ref.read(alarmNotifierProvider.notifier).deleteAlarm(id, date);

    try {
      await platform.invokeMethod('cancelNotification');
    } catch (e) {
      print('⚠️ Notification 삭제 실패: $e');
    }

    try {
      await platform.invokeMethod('triggerGuardCheck');
    } catch (e) {
      print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('알람이 취소되었습니다'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextAlarmAsync = ref.watch(nextAlarmProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: nextAlarmAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: Colors.indigo),
        ),
        error: (error, stack) => _buildEmptyState(),
        data: (nextAlarm) {
          if (nextAlarm == null) {
            return _buildEmptyState();
          }
          return _AlarmDisplayWidget(
            alarm: nextAlarm,
            onDismiss: () => _dismissAlarm(nextAlarm.id!, nextAlarm.date),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120.w,
              height: 120.w,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.alarm_off_rounded,
                size: 60.sp,
                color: Colors.grey.shade400,
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              '예정된 알람이 없습니다',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '달력에서 근무를 설정하면\n알람이 자동으로 생성됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlarmDisplayWidget extends ConsumerStatefulWidget {
  final Alarm alarm;
  final VoidCallback onDismiss;

  const _AlarmDisplayWidget({
    required this.alarm,
    required this.onDismiss,
  });

  @override
  ConsumerState<_AlarmDisplayWidget> createState() => _AlarmDisplayWidgetState();
}

class _AlarmDisplayWidgetState extends ConsumerState<_AlarmDisplayWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _getTimeUntilData(DateTime alarmTime) {
    final now = DateTime.now();
    final diff = alarmTime.difference(now);

    if (diff.isNegative) {
      return {'text': '곧 울립니다', 'isImminent': true};
    }

    final totalSeconds = diff.inSeconds;
    final totalMinutes = (totalSeconds / 60).ceil();

    if (totalMinutes <= 1) {
      return {'text': '곧 울립니다', 'isImminent': true};
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    String text;
    if (hours > 0) {
      if (minutes > 0) {
        text = '${hours}시간 ${minutes}분 후';
      } else {
        text = '${hours}시간 후';
      }
    } else {
      text = '${minutes}분 후';
    }

    return {
      'text': text,
      'isImminent': totalMinutes <= 30,
    };
  }

  String _getDateLabel(DateTime alarmDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final alarmDay = DateTime(alarmDate.year, alarmDate.month, alarmDate.day);

    if (alarmDay == today) {
      return '오늘';
    } else if (alarmDay == tomorrow) {
      return '내일';
    } else {
      final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return '${alarmDate.month}/${alarmDate.day} (${weekdays[alarmDate.weekday - 1]})';
    }
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final timeStr = alarm.date != null
        ? '${alarm.date!.hour.toString().padLeft(2, '0')}:${alarm.date!.minute.toString().padLeft(2, '0')}'
        : alarm.time;

    final timeData = _getTimeUntilData(alarm.date!);
    final dateLabel = _getDateLabel(alarm.date!);

    return FutureBuilder<AlarmType?>(
      future: DatabaseService.instance.getAlarmType(alarm.alarmTypeId),
      builder: (context, snapshot) {
        final alarmType = snapshot.data;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
            child: Column(
              children: [
                SizedBox(height: 8.h),

                // 메인 알람 카드
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.indigo.shade400,
                        Colors.indigo.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withOpacity(0.3),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 날짜 라벨
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 5.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      SizedBox(height: 12.h),

                      // 시간 표시
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 56.sp,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),

                      SizedBox(height: 12.h),

                      // 근무 타입 뱃지
                      if (alarm.shiftType != null)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 8.h),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            alarm.shiftType!,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                SizedBox(height: 16.h),

                // 남은 시간 카드
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: timeData['isImminent']
                        ? Colors.orange.shade50
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color: timeData['isImminent']
                          ? Colors.orange.shade200
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44.w,
                        height: 44.w,
                        decoration: BoxDecoration(
                          color: timeData['isImminent']
                              ? Colors.orange.shade100
                              : Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Icon(
                          Icons.timer_outlined,
                          size: 22.sp,
                          color: timeData['isImminent']
                              ? Colors.orange.shade600
                              : Colors.indigo.shade400,
                        ),
                      ),
                      SizedBox(width: 14.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '알람까지',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              timeData['text'],
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: timeData['isImminent']
                                    ? Colors.orange.shade700
                                    : Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 12.h),

                // 알람 설정 정보 카드
                if (alarmType != null)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '알람 설정',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Row(
                          children: [
                            _buildSettingItem(
                              icon: alarmType.isSound
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              label: '소리',
                              value: alarmType.isSound ? '켜짐' : '꺼짐',
                              isEnabled: alarmType.isSound,
                            ),
                            SizedBox(width: 10.w),
                            _buildSettingItem(
                              icon: Icons.vibration_rounded,
                              label: '진동',
                              value: alarmType.isVibrate ? '켜짐' : '꺼짐',
                              isEnabled: alarmType.isVibrate,
                            ),
                            SizedBox(width: 10.w),
                            _buildSettingItem(
                              icon: Icons.timelapse_rounded,
                              label: '지속',
                              value: '${alarmType.duration}분',
                              isEnabled: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                Spacer(),

                // 알람 취소 버튼
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onDismiss,
                    icon: Icon(Icons.alarm_off_rounded, size: 18.sp),
                    label: Text(
                      '이 알람 끄기',
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade300, width: 1.5),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 8.h),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isEnabled,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
        decoration: BoxDecoration(
          color: isEnabled ? Colors.indigo.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20.sp,
              color: isEnabled ? Colors.indigo.shade400 : Colors.grey.shade400,
            ),
            SizedBox(height: 4.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.sp,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: isEnabled ? Colors.indigo.shade700 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
