// lib/screens/next_alarm_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import '../models/alarm.dart';
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
        child: Column(
          children: [
            SizedBox(height: 12.h),

            // 메인 알람 카드
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 22.h),
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
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  SizedBox(height: 14.h),

                  // 시간 표시
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 60.sp,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),

                  SizedBox(height: 14.h),

                  // 근무 타입 뱃지
                  if (alarm.shiftType != null)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 9.h),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        alarm.shiftType!,
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: 18.h),

            // 남은 시간 카드
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(18.w),
              decoration: BoxDecoration(
                color: timeData['isImminent']
                    ? Colors.orange.shade50
                    : Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: timeData['isImminent']
                      ? Colors.orange.shade200
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46.w,
                    height: 46.w,
                    decoration: BoxDecoration(
                      color: timeData['isImminent']
                          ? Colors.orange.shade100
                          : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.timer_outlined,
                      size: 24.sp,
                      color: timeData['isImminent']
                          ? Colors.orange.shade600
                          : Colors.indigo.shade400,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '알람까지',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          timeData['text'],
                          style: TextStyle(
                            fontSize: 19.sp,
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

            SizedBox(height: 14.h),

            // 알람 타입 선택 카드
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(18.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '알람 타입',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 14.h),
                  Row(
                    children: [
                      _buildTypeSelectButton(
                        typeId: 1,
                        icon: Icons.volume_up_rounded,
                        label: '소리+진동',
                        isSelected: alarm.alarmTypeId == 1,
                        onTap: () => _onTypeSelected(alarm.id!, 1),
                      ),
                      SizedBox(width: 10.w),
                      _buildTypeSelectButton(
                        typeId: 2,
                        icon: Icons.vibration_rounded,
                        label: '진동',
                        isSelected: alarm.alarmTypeId == 2,
                        onTap: () => _onTypeSelected(alarm.id!, 2),
                      ),
                      SizedBox(width: 10.w),
                      _buildTypeSelectButton(
                        typeId: 3,
                        icon: Icons.notifications_off_rounded,
                        label: '무음',
                        isSelected: alarm.alarmTypeId == 3,
                        onTap: () => _onTypeSelected(alarm.id!, 3),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: 12.h),

            // ⭐ 전체 알람 보기 버튼 (알람 타입 카드 아래, 우측 정렬)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _showAllAlarmsSheet(context),
                child: Text(
                  '등록된 모든 알람 보기',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.grey.shade500,
                  ),
                ),
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
                  padding: EdgeInsets.symmetric(vertical: 13.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
            ),

            SizedBox(height: 12.h),
          ],
        ),
      ),
    );
  }

  // ⭐ 전체 알람 목록 바텀시트
  void _showAllAlarmsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Consumer(
              builder: (context, ref, child) {
                final alarmsAsync = ref.watch(alarmNotifierProvider);

                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 핸들
                      Center(
                        child: Container(
                          width: 40.w,
                          height: 4.h,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                      ),
                      SizedBox(height: 16.h),

                      // 제목
                      Text(
                        '등록된 알람',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      SizedBox(height: 16.h),

                      // 알람 목록
                      Expanded(
                        child: alarmsAsync.when(
                          loading: () => Center(child: CircularProgressIndicator()),
                          error: (_, __) => Center(child: Text('오류 발생')),
                          data: (alarms) {
                            // 미래 알람만 필터링하고 시간순 정렬
                            final now = DateTime.now();
                            final futureAlarms = alarms
                                .where((a) => a.date != null && a.date!.isAfter(now))
                                .toList()
                              ..sort((a, b) => a.date!.compareTo(b.date!));

                            if (futureAlarms.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.alarm_off_rounded,
                                      size: 48.sp,
                                      color: Colors.grey.shade400,
                                    ),
                                    SizedBox(height: 12.h),
                                    Text(
                                      '등록된 알람이 없습니다',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.builder(
                              controller: scrollController,
                              itemCount: futureAlarms.length,
                              itemBuilder: (context, index) {
                                final alarm = futureAlarms[index];
                                return _buildAlarmListItem(alarm, index == 0);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ⭐ 알람 목록 아이템
  Widget _buildAlarmListItem(Alarm alarm, bool isNext) {
    final date = alarm.date!;
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateStr = '${date.month}/${date.day} (${weekdays[date.weekday - 1]})';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: isNext ? Colors.indigo.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isNext ? Colors.indigo.shade200 : Colors.grey.shade200,
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // 날짜
          Container(
            width: 75.w,
            child: Text(
              dateStr,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          SizedBox(width: 8.w),

          // 시간
          Container(
            width: 60.w,
            child: Text(
              timeStr,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: isNext ? Colors.indigo.shade700 : Colors.grey.shade800,
              ),
            ),
          ),
          SizedBox(width: 12.w),

          // 근무 타입
          if (alarm.shiftType != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: isNext ? Colors.indigo.shade100 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                alarm.shiftType!,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: isNext ? Colors.indigo.shade700 : Colors.grey.shade700,
                ),
              ),
            ),

          Spacer(),

          // 다음 알람 표시
          if (isNext)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: Colors.indigo.shade400,
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Text(
                '다음',
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onTypeSelected(int alarmId, int typeId) async {
    await ref.read(alarmNotifierProvider.notifier).updateAlarmType(alarmId, typeId);
  }

  Widget _buildTypeSelectButton({
    required int typeId,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? Colors.indigo.shade400 : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24.sp,
                color: isSelected ? Colors.indigo.shade500 : Colors.grey.shade400,
              ),
              SizedBox(height: 6.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.indigo.shade700 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
