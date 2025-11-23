import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/database_service.dart';
import '../models/shift_schedule.dart';
import 'onboarding_screen.dart';
import '../services/alarm_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';  // ⭐ 추가
import '../services/alarm_refresh_service.dart';  // ⭐ 추가
import 'package:flutter/services.dart';  // ⭐ 추가
import 'package:shared_preferences/shared_preferences.dart';

class SettingsTab extends ConsumerStatefulWidget {  // ⭐ 변경
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();  // ⭐ 변경
}

class _SettingsTabState extends ConsumerState<SettingsTab> {  // ⭐ 변경
  // ShiftSchedule? _schedule;  ⭐ 삭제 (Provider에서 가져올 것)

  @override
  void initState() {
    super.initState();
    // _loadSchedule() 호출 삭제
  }

  // _loadSchedule() 메서드 삭제

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
    // Native 알람 취소
    final alarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in alarms) {
      if (alarm.id != null) {
        await AlarmService().cancelAlarm(alarm.id!);
      }
    }
    
    // DB 삭제
    await ref.read(scheduleProvider.notifier).resetSchedule();
    
    // ⭐ 알람 Provider도 초기화
    // await ref.read(alarmNotifierProvider.notifier).refresh();
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
      );
    }
  }
}
// _SettingsTabState 클래스 안에 추가

Future<void> _showAlarmListDialog() async {
  final alarms = await DatabaseService.instance.getAllAlarms();
  
  // 날짜순 정렬
  alarms.sort((a, b) => a.date!.compareTo(b.date!));
  
  final now = DateTime.now();
  final futureAlarms = alarms.where((a) => 
    a.date != null && a.date!.isAfter(now)
  ).toList();
  final pastAlarms = alarms.where((a) => 
    a.date != null && a.date!.isBefore(now)
  ).toList();
  
  if (!mounted) return;
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.alarm, color: Colors.blue),
          SizedBox(width: 8.w),
          Text('등록된 알람 목록'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(maxHeight: 500.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 요약 정보
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${futureAlarms.length}',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          Text('미래', style: TextStyle(fontSize: 12.sp)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${pastAlarms.length}',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          Text('과거', style: TextStyle(fontSize: 12.sp)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${alarms.length}',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          Text('전체', style: TextStyle(fontSize: 12.sp)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16.h),
            
            // 알람 리스트
            if (alarms.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32.h),
                  child: Text(
                    '등록된 알람이 없습니다',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: alarms.length,
                  separatorBuilder: (context, index) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final alarm = alarms[index];
                    final isPast = alarm.date!.isBefore(now);
                    final isToday = alarm.date!.year == now.year &&
                                   alarm.date!.month == now.month &&
                                   alarm.date!.day == now.day;
                    
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 4.h,
                      ),
                      leading: Icon(
                        isPast ? Icons.check_circle : Icons.alarm,
                        color: isPast 
                          ? Colors.grey 
                          : (isToday ? Colors.orange : Colors.blue),
                        size: 20.sp,
                      ),
                      title: Text(
                        _formatAlarmDate(alarm.date!),
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isPast ? Colors.grey : Colors.black,
                          decoration: isPast ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        alarm.shiftType ?? '알람',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isPast ? Colors.grey : Colors.black87,
                        ),
                      ),
                      trailing: isToday 
                        ? Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              '오늘',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
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

// 날짜 포맷 함수
String _formatAlarmDate(DateTime date) {
  final year = date.year;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  
  return '$year/$month/$day $hour:$minute';
}

Future<void> _showAlarmHistoryDialog() async {
  final history = await DatabaseService.instance.getAlarmHistory(limit: 50);
  final stats = await DatabaseService.instance.getAlarmStatistics();
  
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 통계
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                children: [
                  Text(
                    '📊 통계',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('전체', stats['total']),
                      _buildStatItem('스와이프', stats['swiped']),
                      _buildStatItem('스누즈', stats['snoozed']),
                      _buildStatItem('놓침', stats['timeout']),
                    ],
                  ),
                  if (stats['avgSnooze'] > 0) ...[
                    SizedBox(height: 8.h),
                    Text(
                      '평균 스누즈: ${stats['avgSnooze']}회',
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            
            SizedBox(height: 16.h),
            
            // 이력 리스트
            if (history.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32.h),
                  child: Text(
                    '알람 이력이 없습니다',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (context, index) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = history[index];
                    final isPast = item.actualRingTime.isBefore(DateTime.now());
                    
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 4.h,
                      ),
                      leading: Icon(
                        _getDismissIcon(item.dismissType),
                        color: _getDismissColor(item.dismissType),
                        size: 20.sp,
                      ),
                      title: Text(
                        '${_formatHistoryDate(item.scheduledDate)} ${item.scheduledTime}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.dismissTypeText,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: _getDismissColor(item.dismissType),
                            ),
                          ),
                          if (item.shiftType != null)
                            Text(
                              item.shiftType!,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Colors.grey,
                              ),
                            ),
                        ],
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

Widget _buildStatItem(String label, int value) {
  return Column(
    children: [
      Text(
        '$value',
        style: TextStyle(
          fontSize: 20.sp,
          fontWeight: FontWeight.bold,
          color: Colors.purple,
        ),
      ),
      Text(
        label,
        style: TextStyle(fontSize: 10.sp, color: Colors.grey),
      ),
    ],
  );
}

IconData _getDismissIcon(String type) {
  switch (type) {
    case 'swiped':
      return Icons.swipe;
    case 'snoozed':
      return Icons.snooze;
    case 'timeout':
      return Icons.alarm_off;
    case 'ringing':
      return Icons.alarm_on;
    default:
      return Icons.help;
  }
}

Color _getDismissColor(String type) {
  switch (type) {
    case 'swiped':
      return Colors.green;
    case 'snoozed':
      return Colors.orange;
    case 'timeout':
      return Colors.red;
    case 'ringing':
      return Colors.blue;
    default:
      return Colors.grey;
  }
}

String _formatHistoryDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(Duration(days: 1));
  final targetDay = DateTime(date.year, date.month, date.day);
  
  if (targetDay == today) {
    return '오늘';
  } else if (targetDay == yesterday) {
    return '어제';
  } else {
    return '${date.month}/${date.day}';
  }
}

  @override
Widget build(BuildContext context) {
  final scheduleAsync = ref.watch(scheduleProvider);
  
  return Scaffold(
    appBar: AppBar(
      title: Text('⚙️ 설정'),
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
                    Text(
                      '📅 교대 스케줄',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                    ),
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
                      // ⭐ 변경: shiftTypes 대신 activeShiftTypes 사용
                      Text('근무 종류: ${(schedule.activeShiftTypes ?? schedule.shiftTypes).join(", ")}'),
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
              subtitle: Text(schedule == null ? 'DB 비어있음' : 'DB 정상'),
            ),
            
            ListTile(
  leading: Icon(Icons.bug_report, color: Colors.red),
  title: Text('DB 알람 개수 확인'),
  onTap: () => _showAlarmListDialog(),  // ⭐ 함수 호출로 변경
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
                  await ref.read(alarmNotifierProvider.notifier).deleteAllAlarms();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ 모든 알람 삭제 완료')),
                    );
                  }
                }
              },
            ),
            ListTile(
  leading: Icon(Icons.list, color: Colors.purple),
  title: Text('DB 알람 전체 목록 (콘솔)'),
  onTap: () async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    print('📊 총 알람: ${alarms.length}개');
    
    final now = DateTime.now();
    final future = alarms.where((a) => a.date != null && a.date!.isAfter(now)).toList();
    final past = alarms.where((a) => a.date != null && a.date!.isBefore(now)).toList();
    
    print('미래: ${future.length}개, 과거: ${past.length}개');
    
    for (var alarm in alarms) {
      final isPast = alarm.date!.isBefore(now) ? '❌과거' : '✅미래';
      print('  $isPast ${alarm.date}: ${alarm.shiftType}');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('콘솔 확인!')),
    );
  },
),
Divider(),

Text('🧪 테스트 도구', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.orange)),

ListTile(
  leading: Icon(Icons.refresh, color: Colors.orange),
  title: Text('갱신 로직 테스트'),
  subtitle: Text('날짜 변경 시뮬레이션'),
  onTap: () async {
    print('\n========== 갱신 테스트 시작 ==========');
    
    final before = await DatabaseService.instance.getAllAlarms();
    print('📊 갱신 전 알람: ${before.length}개');
    
    final prefs = await SharedPreferences.getInstance();
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    await prefs.setInt('last_alarm_refresh', yesterday.millisecondsSinceEpoch);
    print('⏰ 마지막 갱신 시각: 어제로 변경');
    
    await AlarmRefreshService.instance.refreshIfNeeded();
    
    final after = await DatabaseService.instance.getAllAlarms();
    print('📊 갱신 후 알람: ${after.length}개');
    
    print('========== 갱신 테스트 완료 ==========\n');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 갱신: ${before.length}개 → ${after.length}개'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  },
),

ListTile(
  leading: Icon(Icons.repeat, color: Colors.orange),
  title: Text('중복 방지 테스트'),
  subtitle: Text('같은 날 재실행 시 스킵'),
  onTap: () async {
    print('\n========== 중복 방지 테스트 ==========');
    await AlarmRefreshService.instance.refreshIfNeeded();
    print('========== 중복 방지 테스트 완료 ==========\n');
  },
),
// settings_tab.dart의 ListTile들 사이에 추가

Divider(),

Padding(
  padding: EdgeInsets.only(left: 16.w, top: 8.h, bottom: 8.h),
  child: Text(
    '🌙 자정 체크 테스트',
    style: TextStyle(
      fontSize: 16.sp,
      fontWeight: FontWeight.bold,
      color: Colors.purple,
    ),
  ),
),

ListTile(
  leading: Icon(Icons.nightlight_round, color: Colors.purple),
  title: Text('자정 체크 강제 실행'),
  subtitle: Text('AlarmGuardReceiver 수동 트리거'),
  onTap: () async {
    try {
      // AlarmGuardReceiver 트리거
      await MethodChannel('com.example.shiftbell/alarm')
          .invokeMethod('triggerMidnightCheck');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 자정 체크 트리거 완료\n로그 확인: adb logcat | findstr AlarmGuard'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ 자정 체크 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 실패: $e')),
        );
      }
    }
  },
),

ListTile(
  leading: Icon(Icons.calendar_today, color: Colors.orange),
  title: Text('날짜 변경 시뮬레이션'),
  subtitle: Text('last_alarm_refresh를 어제로 변경'),
  onTap: () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final yesterday = DateTime.now().subtract(Duration(days: 1));
      await prefs.setInt('last_alarm_refresh', yesterday.millisecondsSinceEpoch);
      
      print('📅 마지막 갱신 시각: 어제로 변경');
      print('   어제: ${yesterday.year}-${yesterday.month}-${yesterday.day}');
      print('   오늘: ${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}');
      
      // AlarmGuardReceiver 트리거
      await MethodChannel('com.example.shiftbell/alarm')
          .invokeMethod('triggerMidnightCheck');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 날짜 어제로 변경 + 자정 체크 실행\n로그에서 "날짜 변경 감지" 확인'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ 날짜 시뮬레이션 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 실패: $e')),
        );
      }
    }
  },
),

ListTile(
  leading: Icon(Icons.info, color: Colors.blue),
  title: Text('현재 갱신 정보 확인'),
  onTap: () async {
    final prefs = await SharedPreferences.getInstance();
    final lastRefresh = prefs.getInt('last_alarm_refresh') ?? 0;
    final lastDate = DateTime.fromMillisecondsSinceEpoch(lastRefresh);
    final today = DateTime.now();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('갱신 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('마지막 갱신:'),
            Text(
              '  ${lastDate.year}-${lastDate.month}-${lastDate.day}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            Text('현재 날짜:'),
            Text(
              '  ${today.year}-${today.month}-${today.day}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            Text('날짜 변경:'),
            Text(
              lastDate.day != today.day ? '  ✅ 다름 (갱신 필요)' : '  ❌ 같음',
              style: TextStyle(
                color: lastDate.day != today.day ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기'),
          ),
        ],
      ),
    );
  },
),
ListTile(
  leading: Icon(Icons.bug_report, color: Colors.green),
  title: Text('AlarmGuard 수동 실행'),
  onTap: () async {
    try {
      await MethodChannel('com.example.shiftbell/alarm')
          .invokeMethod('triggerGuardCheck');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ AlarmGuardReceiver 실행됨')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 실패: $e')),
      );
    }
  },
),
ListTile(
  leading: Icon(Icons.bug_report, color: Colors.orange),
  title: Text('DB 알람 ID 확인'),
  onTap: () async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    for (final alarm in alarms) {
      print('🔍 알람: ${alarm.time}, ID: ${alarm.id}, Date: ${alarm.date?.millisecondsSinceEpoch}');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('로그 확인!')),
    );
  },
),
ListTile(
  leading: Icon(Icons.history, color: Colors.purple),
  title: Text('알람 이력'),
  subtitle: Text('지난 알람 기록 확인'),
  onTap: () => _showAlarmHistoryDialog(),
),
          ],
        );
      },
    ),
  );
}
}