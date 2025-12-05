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

/// 알람 + 이력 통합 데이터 클래스
class AlarmWithHistory {
  final DateTime date;
  final String time;
  final String? shiftType;
  final AlarmHistory? latestHistory;
  final bool isFuture;

  AlarmWithHistory({
    required this.date,
    required this.time,
    this.shiftType,
    this.latestHistory,
    required this.isFuture,
  });

  // 유니크 키 생성 (날짜 + 시간)
  String get uniqueKey => '${date.year}-${date.month}-${date.day}_$time';
}

class _AllAlarmsHistoryViewState extends State<AllAlarmsHistoryView> {
  List<AlarmWithHistory> _alarmsWithHistory = [];
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
      final now = DateTime.now();

      // 1. 모든 알람 이력 가져오기
      final allHistory = await DatabaseService.instance.getAllAlarmHistory();

      // 2. 유니크 알람별로 그룹화 (날짜 + 시간 기준)
      final Map<String, AlarmWithHistory> alarmMap = {};

      for (var history in allHistory) {
        final key = '${history.scheduledDate.year}-${history.scheduledDate.month}-${history.scheduledDate.day}_${history.scheduledTime}';

        // 이미 존재하면 최신 이력으로 업데이트 (created_at DESC로 정렬되어 첫 번째가 최신)
        if (!alarmMap.containsKey(key)) {
          alarmMap[key] = AlarmWithHistory(
            date: history.scheduledDate,
            time: history.scheduledTime,
            shiftType: history.shiftType,
            latestHistory: history,
            isFuture: history.scheduledDate.isAfter(DateTime(now.year, now.month, now.day)),
          );
        }
      }

      // 3. 미래 알람 가져오기 (아직 실행되지 않은 알람)
      final futureAlarms = await DatabaseService.instance.getAllAlarms();

      for (var alarm in futureAlarms) {
        if (alarm.date != null) {
          final key = '${alarm.date!.year}-${alarm.date!.month}-${alarm.date!.day}_${alarm.time ?? '00:00'}';

          // 이미 이력이 있으면 건너뛰기 (이력이 우선)
          if (!alarmMap.containsKey(key)) {
            alarmMap[key] = AlarmWithHistory(
              date: alarm.date!,
              time: alarm.time ?? '00:00',
              shiftType: alarm.shiftType,
              latestHistory: null,
              isFuture: alarm.date!.isAfter(DateTime(now.year, now.month, now.day)),
            );
          }
        }
      }

      // 4. 날짜순 정렬
      final sortedAlarms = alarmMap.values.toList();
      sortedAlarms.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.time.compareTo(b.time);
      });

      setState(() {
        _alarmsWithHistory = sortedAlarms;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(DateTime date, String time) {
    // 요일 한글 변환
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1]; // weekday는 1(월)~7(일)

    // YY/MM/DD (요일) 형식
    final year = date.year.toString().substring(2); // 2025 -> 25
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year/$month/$day ($weekday) $time';
  }

  String _getHistoryText(AlarmHistory? history) {
    if (history == null) return '';

    switch (history.dismissType) {
      case 'swiped':
        return '알람 확인';
      case 'snoozed':
        final count = history.snoozeCount;
        return count > 1 ? '알람 ${count}회 연장' : '알람 5분 연장';
      case 'timeout':
        return '알람 무응답';
      case 'ringing':
        return '울리는 중...';
      case 'cancelled_before_ring':
        return '울기 전 제거';
      case 'deleted_by_user':
        return '알람 삭제됨';
      default:
        return history.dismissType;
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
      case 'cancelled_before_ring':
        return Colors.purple.shade600;
      case 'deleted_by_user':
        return Colors.brown.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  Future<void> _deleteAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('전체 이력 삭제'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚠️ 테스트 전용 기능',
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            SizedBox(height: 12.h),
            Text('모든 알람 이력이 삭제됩니다.'),
            SizedBox(height: 8.h),
            Text('이 작업은 되돌릴 수 없습니다.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '삭제',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await DatabaseService.instance.deleteAllAlarmHistory();
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🗑️ 모든 알람 이력이 삭제되었습니다')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ 이력 삭제 실패: $e')),
          );
        }
      }
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
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep, color: Colors.red.shade700),
            tooltip: '전체 이력 삭제 (테스트용)',
            onPressed: _deleteAllHistory,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _alarmsWithHistory.isEmpty
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
                  itemCount: _alarmsWithHistory.length,
                  itemBuilder: (context, index) {
                    final alarmWithHistory = _alarmsWithHistory[index];
                    final history = alarmWithHistory.latestHistory;
                    final historyText = _getHistoryText(history);
                    final historyColor = _getHistoryColor(history);
                    final isFuture = alarmWithHistory.isFuture;

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
                                    _formatDateTime(alarmWithHistory.date, alarmWithHistory.time),
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: isFuture ? Colors.indigo.shade700 : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (alarmWithHistory.shiftType != null) ...[
                                    SizedBox(height: 4.h),
                                    Text(
                                      alarmWithHistory.shiftType!,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
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
