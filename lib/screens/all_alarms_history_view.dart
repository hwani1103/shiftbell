import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/database_service.dart';
import '../models/alarm.dart';
import '../models/alarm_history.dart';

/// 모든 알람 & 알람 이력 - 등록된 알람과 실행 이력을 한눈에 보는 화면
class AllAlarmsHistoryView extends StatefulWidget {
  const AllAlarmsHistoryView({super.key});

  @override
  State<AllAlarmsHistoryView> createState() => _AllAlarmsHistoryViewState();
}

class _AllAlarmsHistoryViewState extends State<AllAlarmsHistoryView> {
  List<Alarm> _alarms = [];
  Map<int, AlarmHistory?> _historyMap = {}; // alarmId -> history
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 모든 알람 가져오기 (날짜순 정렬)
      final alarms = await DatabaseService.instance.getAllAlarms();
      alarms.sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return a.date!.compareTo(b.date!);
      });

      // 각 알람의 이력 가져오기
      final Map<int, AlarmHistory?> historyMap = {};
      for (var alarm in alarms) {
        if (alarm.id != null) {
          // 해당 알람의 가장 최근 이력 1개만 가져오기
          final histories = await DatabaseService.instance.getAlarmHistoryByAlarmId(alarm.id!);
          historyMap[alarm.id!] = histories.isNotEmpty ? histories.first : null;
        }
      }

      setState(() {
        _alarms = alarms;
        _historyMap = historyMap;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(DateTime? date, String? time) {
    if (date == null) return '날짜 없음';
    final timeStr = time ?? '00:00';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $timeStr';
  }

  String _getHistoryText(AlarmHistory? history) {
    if (history == null) return '';

    switch (history.dismissType) {
      case 'swiped':
        return '알람 확인';
      case 'snoozed':
        final count = history.snoozeCount ?? 0;
        return count > 1 ? '알람 ${count}회 연장' : '알람 5분 연장';
      case 'timeout':
        return '알람 무응답';
      case 'ringing':
        return '울리는 중...';
      default:
        return history.dismissType ?? '';
    }
  }

  Color _getHistoryColor(AlarmHistory? history) {
    if (history == null) return Colors.grey.shade400;

    switch (history.dismissType) {
      case 'swiped':
        return Colors.green.shade600;
      case 'snoozed':
        return Colors.orange.shade600;
      case 'timeout':
        return Colors.red.shade600;
      case 'ringing':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('모든 알람 & 알람 이력'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _alarms.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.alarm_off,
                          size: 64.sp,
                          color: Colors.grey.shade400,
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          '등록된 알람이 없습니다',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16.w),
                  itemCount: _alarms.length,
                  itemBuilder: (context, index) {
                    final alarm = _alarms[index];
                    final history = alarm.id != null ? _historyMap[alarm.id!] : null;
                    final historyText = _getHistoryText(history);
                    final historyColor = _getHistoryColor(history);
                    final now = DateTime.now();
                    final isFuture = alarm.date != null && alarm.date!.isAfter(now);

                    return Card(
                      margin: EdgeInsets.only(bottom: 12.h),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        side: BorderSide(
                          color: isFuture ? Colors.indigo.shade200 : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Row(
                          children: [
                            // 날짜/시간 & 근무명
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatDateTime(alarm.date, alarm.time),
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: isFuture ? Colors.indigo.shade700 : Colors.black87,
                                    ),
                                  ),
                                  if (alarm.shiftType != null) ...[
                                    SizedBox(height: 4.h),
                                    Text(
                                      alarm.shiftType!,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(width: 12.w),
                            // 이력
                            Expanded(
                              flex: 2,
                              child: historyText.isEmpty
                                  ? Text(
                                      '-',
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        color: Colors.grey.shade400,
                                      ),
                                      textAlign: TextAlign.right,
                                    )
                                  : Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                                      decoration: BoxDecoration(
                                        color: historyColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6.r),
                                        border: Border.all(color: historyColor.withOpacity(0.3), width: 1),
                                      ),
                                      child: Text(
                                        historyText,
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          fontWeight: FontWeight.w600,
                                          color: historyColor,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
