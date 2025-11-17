import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import '../models/alarm.dart';
import '../models/alarm_type.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';

class NextAlarmTab extends StatefulWidget {
  const NextAlarmTab({super.key});

  @override
  State<NextAlarmTab> createState() => _NextAlarmTabState();
}

class _NextAlarmTabState extends State<NextAlarmTab> {
  Alarm? _nextAlarm;
  AlarmType? _alarmType;
  Timer? _countdownTimer;
  String _timeUntilText = '';
  
  @override
  void initState() {
    super.initState();
    _loadNextAlarm();
    
    // ⭐ 1분마다 카운트다운만 갱신
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_nextAlarm != null && mounted) {
        // 알람 시각이 지났으면 DB 다시 읽기
        if (DateTime.now().isAfter(_nextAlarm!.date!)) {
          _loadNextAlarm();
        } else {
          // 카운트다운만 갱신
          setState(() {
            _timeUntilText = _getTimeUntil(_nextAlarm!.date!);
          });
        }
      }
    });
  }
  
  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
  
  // ⭐ 외부에서 호출 가능하도록 public 메서드
  Future<void> refresh() async {
    await _loadNextAlarm();
  }
  
  Future<void> _loadNextAlarm() async {
    final alarms = await DatabaseService.instance.getNextAlarms(limit: 1);
    
    if (alarms.isEmpty) {
      setState(() {
        _nextAlarm = null;
        _alarmType = null;
        _timeUntilText = '';
      });
      return;
    }
    
    final alarm = alarms.first;
    final type = await DatabaseService.instance.getAlarmType(alarm.alarmTypeId);
    
    setState(() {
      _nextAlarm = alarm;
      _alarmType = type;
      _timeUntilText = _getTimeUntil(alarm.date!);
    });
  }
  
  String _getTimeUntil(DateTime alarmTime) {
    final diff = alarmTime.difference(DateTime.now());
    
    if (diff.inHours > 0) {
      return '${diff.inHours}시간 ${diff.inMinutes % 60}분 후에';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}분 후에';
    } else {
      return '곧';
    }
  }
  
  Future<void> _dismissAlarm() async {
    if (_nextAlarm == null) return;
    
    // DB에서 삭제
    await DatabaseService.instance.deleteAlarm(_nextAlarm!.id!);
    
    // Native 알람 취소
    await AlarmService().cancelAlarm(_nextAlarm!.id!);
    
    // 재로딩
    _loadNextAlarm();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알람이 취소되었습니다')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_nextAlarm == null || _alarmType == null) {
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
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 시간 (가장 크게)
              Text(
                _nextAlarm!.time,
                style: TextStyle(
                  fontSize: 96.sp,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                ),
              ),
              
              SizedBox(height: 24.h),
              
              // 카운트다운 (⭐ _timeUntilText 사용)
              Text(
                '$_timeUntilText 알람이 울립니다',
                style: TextStyle(fontSize: 20.sp, color: Colors.white70),
              ),
              
              SizedBox(height: 64.h),
              
              // 알람 타입 정보
              Container(
                padding: EdgeInsets.all(32.w),
                margin: EdgeInsets.symmetric(horizontal: 32.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Column(
                  children: [
                    Text(
                      _alarmType!.emoji,
                      style: TextStyle(fontSize: 64.sp),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      '소리: ${_alarmType!.volume > 0 ? "켜짐" : "꺼짐"}',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white70),
                    ),
                    Text(
                      '진동: ${_alarmType!.soundFile == "vibrate" ? "켜짐" : "꺼짐"}',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white70),
                    ),
                    Text(
                      '다시 알림: 5분 후 / 3회',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 64.h),
              
              // 끄기 버튼
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: ElevatedButton(
                  onPressed: _dismissAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    minimumSize: Size(double.infinity, 60.h),
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
  }
}