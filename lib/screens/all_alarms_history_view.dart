import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/database_service.dart';
import '../models/alarm_history.dart';

/// 알람 이력 - "사용자 의도상 생겼던 모든 알람"을 기록하는 화면.
/// ⭐ 현재 alarms 테이블(살아있는 알람)과 대조하지 않음 - 살아있는 알람과 비교하면
/// 알람이 수정/삭제되는 순간 화면에서도 같이 사라져서 "이게 원래 있었는지" 알 수가 없었음.
/// 대신 alarm_creation_log(생성됐다는 사실, 영구 보존) + alarm_history(그 결과, 영구 보존)
/// 두 개의 영구 로그 테이블만으로 구성함 - 어떤 알람이 지금 살아있는지와 무관하게, 한 번
/// 생성됐던 알람은 여기서 절대 사라지지 않음.
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

      // 3. ⭐ 아직 결과(이력)가 없는 알람도 놓치지 않기 위해 생성 로그를 사용.
      // 예전엔 여기서 "현재 등록된 알람"(alarms 테이블)을 읽었는데, 그러면 알람이
      // 수정되거나 삭제되는 순간 화면에서도 같이 사라져서 "생성된 적은 있었다"는
      // 사실 자체를 확인할 수 없었음. alarm_creation_log는 영구 보존되므로, 아직
      // 결과가 없는(=아직 안 울렸거나 예정된) 알람도 계속 남아서 보임.
      final creationLogs = await DatabaseService.instance.getAlarmCreationLog(limit: 5000);

      for (var log in creationLogs) {
        final dateRaw = log['scheduled_date'];
        if (dateRaw == null) continue;
        DateTime? date;
        try {
          date = DateTime.parse(dateRaw.toString());
        } catch (e) {
          continue;
        }
        final time = log['scheduled_time']?.toString() ?? '00:00';
        final key = '${date.year}-${date.month}-${date.day}_$time';

        // 이미 이력(결과)이 있으면 건너뛰기 (이력이 우선)
        if (!alarmMap.containsKey(key)) {
          alarmMap[key] = AlarmWithHistory(
            date: date,
            time: time,
            shiftType: log['shift_type'] as String?,
            latestHistory: null,
            isFuture: date.isAfter(DateTime(now.year, now.month, now.day)),
          );
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
        return '5분 연장';
      case 'timeout':
        return '무응답';
      case 'cancelled_before_ring':
        return '알람 제거';
      case 'superseded':
        return '일정 변경';
      default:
        return '기타';
    }
  }

  Color _getHistoryColor(AlarmHistory? history, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // ⭐ outline은 배지 배경(연한 틴트) 위 텍스트로 쓰기엔 라이트/다크 모두 대비가
    // 너무 약함 - onSurfaceVariant로 통일 (다른 화면의 "비활성" 텍스트와 동일한 처방)
    if (history == null) return colorScheme.onSurfaceVariant;

    switch (history.dismissType) {
      case 'swiped':
        return Colors.green.shade600;
      case 'snoozed':
        return colorScheme.tertiary;
      case 'timeout':
        return colorScheme.error;
      case 'cancelled_before_ring':
        return colorScheme.primary;
      case 'superseded':
        return colorScheme.onSurfaceVariant;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  Future<void> _deleteAllHistory() async {
    final colorScheme = Theme.of(context).colorScheme;
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
                color: colorScheme.error,
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
              style: TextStyle(color: colorScheme.error),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('알람 이력'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
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
                          color: colorScheme.outline,
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          '알람 이력이 없습니다',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16.w,
                    16.w,
                    16.w,
                    16.w + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: _alarmsWithHistory.length,
                  itemBuilder: (context, index) {
                    final alarmWithHistory = _alarmsWithHistory[index];
                    final history = alarmWithHistory.latestHistory;
                    final historyText = _getHistoryText(history);
                    final historyColor = _getHistoryColor(history, context);
                    final isFuture = alarmWithHistory.isFuture;

                    return Card(
                      margin: EdgeInsets.only(bottom: 12.h),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        side: BorderSide(
                          color: isFuture ? colorScheme.primary.withOpacity(0.3) : colorScheme.outline,
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
                                      color: isFuture ? colorScheme.primary : colorScheme.onSurface,
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
                                        color: colorScheme.onSurfaceVariant,
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
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
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
