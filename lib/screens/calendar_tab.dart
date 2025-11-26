import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/shift_schedule.dart';
import '../models/alarm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import 'package:flutter/services.dart';

// StatefulWidget → ConsumerStatefulWidget으로 변경
class CalendarTab extends ConsumerStatefulWidget {  // ⭐ 변경
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();  // ⭐ 변경
}

class _CalendarTabState extends ConsumerState<CalendarTab> {  // ⭐ 변경
  static const platform = MethodChannel('com.example.shiftbell/alarm');  // ⭐ 추가

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // ShiftSchedule? _schedule;  ⭐ 삭제 (Provider에서 가져올 것)
  
  bool _isMultiSelectMode = false;
  Set<DateTime> _selectedDates = {};

  // _loadSchedule() 메서드 삭제 (Provider가 자동으로 관리)
  
  // 색상 메서드는 그대로 유지
  // calendar_tab.dart의 _getShiftBackgroundColor() 함수 수정

Color _getShiftBackgroundColor(String shift, ShiftSchedule? schedule) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  final colorValue = schedule?.shiftColors?[shift];
  
  if (colorValue != null) {
    // ⭐ 휴무는 더 진한 빨강
    if (shift.contains('휴')) {
      return Color(colorValue);  // 0xFFEF5350 그대로 사용
    }
    
    // ⭐ 나머지는 팔레트 색상 그대로
    return Color(colorValue);
  }
  
  return Colors.grey.shade100;
}

  // calendar_tab.dart의 _getShiftTextColor() 함수 수정

Color _getShiftTextColor(String shift, ShiftSchedule? schedule) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  final colorValue = schedule?.shiftColors?[shift];
  
  if (colorValue != null) {
    final bgColor = Color(colorValue);
    
    // ⭐ 신규: 자동 계산
    return ShiftSchedule.getTextColor(bgColor);
  }
  
  return Colors.grey.shade700;
}

  @override
  void initState() {
    super.initState();
    // _loadSchedule() 호출 삭제
  }
  
  @override
Widget build(BuildContext context) {
  final scheduleAsync = ref.watch(scheduleProvider);
  
  return scheduleAsync.when(
    loading: () => Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    error: (error, stack) => Scaffold(
      body: Center(child: Text('에러 발생: $error')),
    ),
    data: (schedule) {
      if (schedule == null) {
        return Scaffold(
          body: Center(child: Text('스케줄이 없습니다')),
        );
      }
      
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                child: Column(
                  children: [
                    // ⭐ 헤더 영역 - 최소화
                    SizedBox(
                      height: 48.h,  // 60.h → 32.h → 48.h (조정)
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),  // 12.h → 4.h
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _isMultiSelectMode
                                ? Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.close, size: 20.sp),
                                        onPressed: _exitMultiSelectMode,
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(),
                                      ),
                                      SizedBox(width: 8.w),
                                      Text(
                                        '${_selectedDates.length}개 선택',
                                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  )
                                : Text(
                                    '${_focusedDay.year}년 ${_focusedDay.month}월',
                                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                  ),
                            if (!_isMultiSelectMode)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _focusedDay = DateTime.now();
                                    _selectedDay = null;
                                  });
                                },
                                child: Text(
                                  'today',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    
                    // 달력
                    Expanded(
                      child: TableCalendar(
                        firstDay: DateTime.utc(2024, 1, 1),
                        lastDay: DateTime.utc(2026, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) {
                          if (_isMultiSelectMode) {
                            return _selectedDates.any((d) => isSameDay(d, day));
                          }
                          return isSameDay(_selectedDay, day);
                        },
                        locale: 'ko_KR',
                        
                        headerVisible: false,
                        rowHeight: (83.h).clamp(60.0, 90.0),  // ⭐ 70→73→78→83 (하단 여백 줄이고 셀 확대)

                        daysOfWeekHeight: 28.h,  // ⭐ 45→28 (최소화)
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.black),
                          weekendStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        
                        calendarStyle: CalendarStyle(
                          cellMargin: EdgeInsets.all(0),
                          cellPadding: EdgeInsets.all(0),
                          
                          tableBorder: TableBorder.all(
                            color: Colors.black,
                            width: 0.3,
                          ),
                          
                          defaultTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.black),
                          weekendTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.black),
                          outsideTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.grey),
                          
                          todayDecoration: BoxDecoration(
                            color: Color(0xFFFFF8DC),
                          ),
                          todayTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.black),
                          
                          selectedDecoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(_isMultiSelectMode ? 0.3 : 1.0),
                            shape: BoxShape.circle,
                          ),
                          selectedTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        
                        calendarBuilders: CalendarBuilders(
                          defaultBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, false, false, schedule);
                          },
                          outsideBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, false, true, schedule);
                          },
                          todayBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, true, false, schedule);
                          },
                          selectedBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, isSameDay(day, DateTime.now()), false, schedule, isSelected: true);
                          },
                        ),
                        
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _focusedDay = focusedDay;
                          });
                          
                          if (_isMultiSelectMode) {
                            _toggleDateSelection(selectedDay);
                          } else {
                            _showDayDetailPopup(selectedDay, schedule);
                          }
                        },
                        
                        onDayLongPressed: (selectedDay, focusedDay) {
                          if (!_isMultiSelectMode) {
                            _enterMultiSelectMode(selectedDay);
                          }
                        },
                        
                        onPageChanged: (focusedDay) {
                          setState(() {
                            _focusedDay = focusedDay;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              // 플로팅 버튼
              if (_isMultiSelectMode && _selectedDates.isNotEmpty)
                Positioned(
                  bottom: 24.h,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FloatingActionButton.extended(
                      onPressed: () => _showBulkAssignSheet(schedule),
                      icon: Icon(Icons.edit_calendar),
                      label: Text('근무 일괄 할당'),
                      backgroundColor: Colors.grey.shade200,  // ⭐ 진한 회색
        foregroundColor: Colors.black,  // ⭐ 흰색 글씨
        elevation : 3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
  
  Widget _buildDateCell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule, {bool isSelected = false}) {
    final shiftText = schedule.getShiftForDate(day);
    final isSunday = day.weekday == DateTime.sunday;

    Color dateColor;
    if (isSunday) {
      dateColor = isOutside ? Colors.red.withOpacity(0.3) : Colors.red;
    } else {
      dateColor = isOutside ? Colors.grey : Colors.black;
    }

    return Container(
      decoration: BoxDecoration(
        color: isSelected && _isMultiSelectMode
            ? Colors.blue.withOpacity(0.2)
            : Colors.transparent,
        // ⭐ 오늘 날짜는 검정 테두리 (얇게)
        border: isToday
            ? Border.all(color: Colors.black, width: 1.5)
            : null,
      ),
      padding: EdgeInsets.only(left: 2.w, right: 2.w, top: 2.h),  // ⭐ 상좌우 여백
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⭐ 근무명 (맨 위에 붙임)
          if (shiftText.isNotEmpty && shiftText != '미설정')
            Container(
              height: 18.h,
              decoration: BoxDecoration(
                color: _getShiftBackgroundColor(shiftText, schedule),
              ),
              child: Center(
                child: Text(
                  shiftText,
                  style: TextStyle(
                    fontSize: 9.sp,
                    color: _getShiftTextColor(shiftText, schedule),
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          else
            SizedBox(height: 18.h),

          // ⭐ 날짜 숫자 (center에 가깝게 배치)
          Padding(
            padding: EdgeInsets.only(top: 2.h),
            child: Text(
              '${day.day}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: dateColor,
              ),
            ),
          ),

          // ⭐ 메모 영역 (3줄 예약, 나중에 구현)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2.h, bottom: 2.h),
              child: Text(
                '', // TODO: 메모 기능 구현 시 사용
                style: TextStyle(
                  fontSize: 7.sp,
                  color: Colors.grey.shade600,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showDayDetailPopup(DateTime day, ShiftSchedule schedule) {
    final currentShift = schedule.getShiftForDate(day);
    final displayShifts = schedule.activeShiftTypes ?? schedule.shiftTypes;
    
    final screenHeight = MediaQuery.of(context).size.height;
    final popupHeight = (screenHeight * 0.65).clamp(400.0, 600.0);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: popupHeight,
        padding: EdgeInsets.all(24.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${day.month}월 ${day.day}일 (${_getWeekday(day)})',
                      style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16.h),
                    
                    Row(
                      children: [
                        Text('현재:', style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
                        SizedBox(width: 8.w),
                        Flexible(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                            decoration: BoxDecoration(
                              color: _getShiftBackgroundColor(currentShift, schedule),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: _getShiftTextColor(currentShift, schedule),
                                width: 2,
                              ),
                            ),
                            child: Text(
                              currentShift,
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: _getShiftTextColor(currentShift, schedule),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: 16.h),
                    
                    Text('고정 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    SizedBox(height: 8.h),
                    FutureBuilder<List<Alarm>>(
                      future: DatabaseService.instance.getAlarmsByDate(day),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('오류', style: TextStyle(fontSize: 14.sp, color: Colors.red));
                        }
                        if (!snapshot.hasData) {
                          return SizedBox(
                            height: 20.h,
                            width: 20.w,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }

                        final fixedAlarms = snapshot.data!.where((a) => a.type == 'fixed').toList();
                        
                        if (fixedAlarms.isEmpty) {
                          return Text('없음', style: TextStyle(fontSize: 14.sp, color: Colors.grey));
                        }
                        
                        return Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: fixedAlarms.map((alarm) {
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('🔊', style: TextStyle(fontSize: 14.sp)),
                                  SizedBox(width: 4.w),
                                  Text(
                                    alarm.time,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    
                    SizedBox(height: 16.h),
                    
                    Text('커스텀 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    SizedBox(height: 8.h),
                    FutureBuilder<List<Alarm>>(
                      future: DatabaseService.instance.getAlarmsByDate(day),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return SizedBox.shrink();
                        
                        final customAlarms = snapshot.data!.where((a) => a.type == 'custom').toList();
                        
                        if (customAlarms.isEmpty) {
                          return Text('없음', style: TextStyle(fontSize: 14.sp, color: Colors.grey));
                        }
                        
                        return Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: customAlarms.map((alarm) {
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('📳', style: TextStyle(fontSize: 14.sp)),
                                  SizedBox(width: 4.w),
                                  Text(
                                    alarm.time,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            Divider(height: 24.h),
            
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '근무일 변경',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12.h),
                  
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8.w,
                        mainAxisSpacing: 8.h,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: displayShifts.length,
                      itemBuilder: (context, index) {
                        final shiftType = displayShifts[index];
                        final isSelected = currentShift == shiftType;
                        
                        return ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            
                            // ⭐ scheduleProvider 사용
                            await ref.read(scheduleProvider.notifier).changeShiftWithAlarms(day, shiftType);
                            
                            // ⭐ alarmNotifier 강제 갱신
                            await ref.read(alarmNotifierProvider.notifier).refresh();
                            
                            // ⭐ AlarmGuardReceiver 트리거 (Notification 표시)
                            try {
                              await platform.invokeMethod('triggerGuardCheck');
                              print('✅ AlarmGuardReceiver 트리거 완료');
                            } catch (e) {
                              print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
                            }
                            
                            if (mounted) {
                              setState(() {});
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected 
                                ? Colors.blue.shade700 
                                : _getShiftBackgroundColor(shiftType, schedule),
                            foregroundColor: isSelected 
                                ? Colors.white 
                                : _getShiftTextColor(shiftType, schedule),
                            elevation: isSelected ? 4 : 1,
                            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              shiftType,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }
  
  void _enterMultiSelectMode(DateTime firstDate) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedDates.clear();
      _selectedDates.add(firstDate);
    });
  }
  
  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedDates.clear();
    });
  }
  
  void _toggleDateSelection(DateTime date) {
    setState(() {
      if (_selectedDates.any((d) => isSameDay(d, date))) {
        _selectedDates.removeWhere((d) => isSameDay(d, date));
      } else {
        _selectedDates.add(date);
      }
    });
  }
  
  void _showBulkAssignSheet(ShiftSchedule schedule) {
  final displayShifts = schedule.activeShiftTypes ?? schedule.shiftTypes;
  final screenWidth = MediaQuery.of(context).size.width;
  final screenHeight = MediaQuery.of(context).size.height;
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Container(
      height: screenHeight * 0.4,
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ⭐ 제목 텍스트 - 센터 정렬
          Center(
            child: Text(
              '${_selectedDates.length}개 날짜에 할당할 근무',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 24.h),
          
          // ⭐ 버튼들 - 세로 센터 정렬
          Expanded(
            child: Center(  // ⭐ Center 추가
              child: GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12.w,
                  mainAxisSpacing: 12.h,
                  childAspectRatio: 1.8,
                ),
                itemCount: displayShifts.length,
                itemBuilder: (context, index) {
                  final shiftType = displayShifts[index];
                  
                  return ElevatedButton(
                    onPressed: () {
                      _bulkAssignShift(shiftType, schedule);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getShiftBackgroundColor(shiftType, schedule),
                      foregroundColor: _getShiftTextColor(shiftType, schedule),
                      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        shiftType,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
  
  // ⭐ Provider 사용으로 변경
  Future<void> _bulkAssignShift(String shiftType, ShiftSchedule schedule) async {
    if (_selectedDates.isEmpty) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );
    
    // ⭐ Provider의 bulkAssignShift 사용
    await ref.read(scheduleProvider.notifier).bulkAssignShift(
      _selectedDates.toList(),
      shiftType,
    );
    
    // ⭐ 각 날짜의 고정 알람 재생성
    for (var date in _selectedDates) {
      await ref.read(alarmNotifierProvider.notifier).regenerateFixedAlarms(
        date,
        shiftType,
      );
    }
    
    Navigator.pop(context);
    _exitMultiSelectMode();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 근무가 할당되었습니다')),
      );
    }
  }
  
  Future<void> _changeShift(DateTime date, String newShiftType, ShiftSchedule schedule) async {
  await ref.read(scheduleProvider.notifier).changeShiftWithAlarms(date, newShiftType);
  
  // ⭐ 알람 Provider도 수동 갱신
  await ref.read(alarmNotifierProvider.notifier).refresh();

  try {
    await platform.invokeMethod('cancelNotification');
    print('✅ Notification 삭제 완료 (근무일 변경)');
  } catch (e) {
    print('⚠️ Notification 삭제 실패: $e');
  }

}
}