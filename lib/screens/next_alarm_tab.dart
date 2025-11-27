// lib/screens/next_alarm_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import '../models/alarm.dart';
import '../models/alarm_type.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
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
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
  
  String _getTimeUntil(DateTime alarmTime) {
  final now = DateTime.now();
  final diff = alarmTime.difference(now);
  
  // ⭐ 과거 알람 방어
  if (diff.isNegative) {
    return '곧';
  }
  
  // ⭐ 핵심: 초 단위 올림 처리
  // 21:00:01 ~ 21:00:59 → 1분으로 올림
  final totalSeconds = diff.inSeconds;
  final totalMinutes = (totalSeconds / 60).ceil();  // ⭐ ceil()로 올림!
  
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  
  if (hours > 0) {
    // 1시간 이상
    if (minutes > 0) {
      return '${hours}시간 ${minutes}분 후에';
    } else {
      return '${hours}시간 후에';
    }
  } else if (minutes > 0) {
    // 1시간 미만
    return '${minutes}분 후에';
  } else {
    return '곧';
  }
}
  
  String _getDateText(DateTime alarmDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final alarmDay = DateTime(alarmDate.year, alarmDate.month, alarmDate.day);
    
    if (alarmDay == today) {
      return '오늘 (${alarmDate.month}/${alarmDate.day})';
    } else if (alarmDay == tomorrow) {
      return '내일 (${alarmDate.month}/${alarmDate.day})';
    } else {
      return '${alarmDate.month}/${alarmDate.day}';
    }
  }
  
  Future<void> _dismissAlarm(int id, DateTime? date) async {
    // ⭐ Overlay가 울리고 있을 수 있으므로 먼저 종료 신호 발송
    try {
      await platform.invokeMethod('dismissOverlay', {'alarmId': id});
      print('✅ Overlay 종료 신호 발송');
    } catch (e) {
      print('⚠️ Overlay 종료 신호 실패: $e');
    }

    await ref.read(alarmNotifierProvider.notifier).deleteAlarm(id, date);

    // Notification 삭제
    try {
      await platform.invokeMethod('cancelNotification');
      print('✅ Notification 삭제 완료');
    } catch (e) {
      print('⚠️ Notification 삭제 실패: $e');
    }

    // ⭐ AlarmGuardReceiver 트리거 → 다음 알람 Notification 표시
    try {
      await platform.invokeMethod('triggerGuardCheck');
      print('✅ AlarmGuardReceiver 트리거 완료');
    } catch (e) {
      print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 알람이 취소되었습니다'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final nextAlarmAsync = ref.watch(nextAlarmProvider);
    
    return nextAlarmAsync.when(
      loading: () => Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            '에러 발생',
            style: TextStyle(color: Colors.white, fontSize: 20.sp),
          ),
        ),
      ),
      data: (nextAlarm) {
        return FutureBuilder<int>(
          future: DatabaseService.instance.getAllAlarms().then((list) => list.length),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data == 0) {
              return _buildNoAlarmScreen();
            }
            
            if (nextAlarm == null) {
              return _buildNoAlarmScreen();
            }
            
            return _AlarmScreenWidget(
              alarmId: nextAlarm.id!,
              onDismiss: () => _dismissAlarm(nextAlarm.id!, nextAlarm.date),
            );
          },
        );
      },
    );
  }
  
  Widget _buildNoAlarmScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('⏰', style: TextStyle(fontSize: 100.sp)),
            SizedBox(height: 24.h),
            Text(
              '예정된 알람이 없습니다',
              style: TextStyle(fontSize: 20.sp, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlarmScreenWidget extends ConsumerStatefulWidget {
  final int alarmId;
  final VoidCallback onDismiss;

  const _AlarmScreenWidget({
    required this.alarmId,
    required this.onDismiss,
  });

  @override
  ConsumerState<_AlarmScreenWidget> createState() => _AlarmScreenWidgetState();
}

class _AlarmScreenWidgetState extends ConsumerState<_AlarmScreenWidget> {
  String _getTimeUntil(DateTime alarmTime) {
    final now = DateTime.now();
    final diff = alarmTime.difference(now);

    // 과거 알람 방어
    if (diff.isNegative) {
      return '곧';
    }

    // ⭐ 초 단위 올림 처리
    // 20:45:00 ~ 20:45:59 → 5분 (알람 20:50 기준)
    // 20:46:00 ~ 20:46:59 → 4분
    final totalSeconds = diff.inSeconds;
    final totalMinutes = (totalSeconds / 60).ceil();  // ceil()로 올림!

    // 1분 이내 = "곧"
    if (totalMinutes <= 1) {
      return '곧';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours > 0) {
      if (minutes > 0) {
        return '${hours}시간 ${minutes}분 후에';
      } else {
        return '${hours}시간 후에';
      }
    } else {
      return '${minutes}분 후에';
    }
  }
  
  String _getDateText(DateTime alarmDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final alarmDay = DateTime(alarmDate.year, alarmDate.month, alarmDate.day);
    
    if (alarmDay == today) {
      return '오늘 (${alarmDate.month}/${alarmDate.day})';
    } else if (alarmDay == tomorrow) {
      return '내일 (${alarmDate.month}/${alarmDate.day})';
    } else {
      return '${alarmDate.month}/${alarmDate.day}';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final alarmsAsync = ref.watch(alarmNotifierProvider);
    
    return alarmsAsync.when(
      loading: () => Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            '에러 발생',
            style: TextStyle(color: Colors.white, fontSize: 20.sp),
          ),
        ),
      ),
      data: (alarms) {
        return FutureBuilder<Alarm?>(
          key: ValueKey('alarm_${widget.alarmId}_${alarms.length}_${DateTime.now().millisecondsSinceEpoch}'),
          future: _loadAlarmFromDB(widget.alarmId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Scaffold(
                backgroundColor: Colors.black,
                body: Center(child: CircularProgressIndicator(color: Colors.white)),
              );
            }
            
            final alarm = snapshot.data!;
            final actualTime = alarm.date != null
                ? '${alarm.date!.hour.toString().padLeft(2, '0')}:${alarm.date!.minute.toString().padLeft(2, '0')}'
                : alarm.time;
            return FutureBuilder<AlarmType?>(
              future: DatabaseService.instance.getAlarmType(alarm.alarmTypeId),
              builder: (context, alarmTypeSnapshot) {
                if (!alarmTypeSnapshot.hasData) {
                  return Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(child: CircularProgressIndicator(color: Colors.white)),
                  );
                }
                
                final alarmType = alarmTypeSnapshot.data!;
                final timeUntil = _getTimeUntil(alarm.date!);
                final dateText = _getDateText(alarm.date!);
                
                return Scaffold(
                  backgroundColor: Colors.black,
                  body: SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dateText,
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w400,
                              color: Colors.white70,
                            ),
                          ),
                          
                          SizedBox(height: 8.h),
                          
                          Text(
                            actualTime,
                            style: TextStyle(
                              fontSize: 72.sp,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                            ),
                          ),
                          
                          SizedBox(height: 16.h),
                          
                          if (alarm.shiftType != null)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: BorderRadius.circular(20.r),
                              ),
                              child: Text(
                                alarm.shiftType!,
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          
                          SizedBox(height: 24.h),
                          
                          Text(
                            '$timeUntil 알람이 울립니다',
                            style: TextStyle(fontSize: 18.sp, color: Colors.white70),
                          ),
                          
                          SizedBox(height: 32.h),
                          
                          Container(
                            padding: EdgeInsets.all(24.w),
                            margin: EdgeInsets.symmetric(horizontal: 32.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  alarmType.emoji,
                                  style: TextStyle(fontSize: 48.sp),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  '소리: ${alarmType.volume > 0 ? "켜짐" : "꺼짐"}',
                                  style: TextStyle(fontSize: 14.sp, color: Colors.white70),
                                ),
                                Text(
                                  '진동: ${alarmType.soundFile == "vibrate" ? "켜짐" : "꺼짐"}',
                                  style: TextStyle(fontSize: 14.sp, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          
                          SizedBox(height: 32.h),
                          
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32.w),
                            child: ElevatedButton(
                              onPressed: widget.onDismiss,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                minimumSize: Size(double.infinity, 50.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                              ),
                              child: Text(
                                '끄기',
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  
  Future<Alarm?> _loadAlarmFromDB(int alarmId) async {
    try {
      print('🔍 DB에서 알람 읽기: ID=$alarmId');
      final allAlarms = await DatabaseService.instance.getAllAlarms();
      
      final alarm = allAlarms.firstWhere(
        (a) => a.id == alarmId,
        orElse: () => throw Exception('알람을 찾을 수 없습니다'),
      );
      
      print('✅ DB 알람 로드: ${alarm.time} (${alarm.date})');
      return alarm;
    } catch (e) {
      print('❌ DB 알람 로드 실패: $e');
      rethrow;
    }
  }
}