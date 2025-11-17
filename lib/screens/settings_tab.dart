import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/database_service.dart';
import '../models/shift_schedule.dart';
import 'onboarding_screen.dart';
import '../services/alarm_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  ShiftSchedule? _schedule;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final schedule = await DatabaseService.instance.getShiftSchedule();
    setState(() => _schedule = schedule);
  }

  // _resetSchedule() 함수 수정

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
    final db = await DatabaseService.instance.database;
    await db.delete('shift_schedule');
    await db.delete('alarms');
    await db.delete('shift_alarm_templates');  // ⭐ 추가
    
    // Native 알람 취소
    final alarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in alarms) {
      if (alarm.date != null) {
        final id = alarm.date!.millisecondsSinceEpoch ~/ 1000;
        await AlarmService().cancelAlarm(id);
      }
    }
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('⚙️ 설정'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          // 현재 스케줄 정보
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📅 교대 스케줄',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12.h),
                  if (_schedule == null)
                    Text('설정 안 됨', style: TextStyle(color: Colors.grey))
                  else ...[
                    Text('근무 형태: ${_schedule!.isRegular ? "규칙적" : "불규칙"}'),
                    if (_schedule!.isRegular && _schedule!.pattern != null) ...[
                      SizedBox(height: 8.h),
                      Text('패턴: ${_schedule!.pattern!.join(", ")}'),
                      Text('오늘 인덱스: ${_schedule!.todayIndex ?? "?"}'),
                    ],
                    SizedBox(height: 8.h),
                    Text('근무 종류: ${_schedule!.shiftTypes.join(", ")}'),
                  ],
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // 스케줄 초기화 버튼
          ListTile(
            leading: Icon(Icons.refresh, color: Colors.orange),
            title: Text('교대 스케줄 초기화'),
            subtitle: Text('온보딩으로 다시 설정'),
            onTap: _resetSchedule,
          ),

          Divider(),

          // 테스트용 DB 확인
          ListTile(
            leading: Icon(Icons.storage, color: Colors.blue),
            title: Text('DB 상태'),
            subtitle: Text(_schedule == null ? 'DB 비어있음' : 'DB 정상'),
          ),
          ListTile(
  leading: Icon(Icons.bug_report, color: Colors.red),
  title: Text('DB 알람 개수 확인'),
  onTap: () async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    print('📊 총 알람: ${alarms.length}개');
    
    for (var alarm in alarms) {
      print('  - ${alarm.date}: ${alarm.time} (${alarm.shiftType})');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('총 ${alarms.length}개 알람 (콘솔 확인)')),
    );
  },
),
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
      // DB에서 모든 알람 가져오기
      final alarms = await DatabaseService.instance.getAllAlarms();
      
      // Native 알람 취소
      for (var alarm in alarms) {
        if (alarm.date != null) {
          final id = alarm.date!.millisecondsSinceEpoch ~/ 1000;
          await AlarmService().cancelAlarm(id);
        }
      }
      
      // DB 알람 삭제
      await DatabaseService.instance.deleteAllAlarms();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ ${alarms.length}개 알람 삭제 완료')),
        );
      }
    }
  },
),
        ],
      ),
    );
    
  }
  
}
