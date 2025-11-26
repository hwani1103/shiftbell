import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/shift_schedule.dart';
import '../models/alarm.dart';
import '../models/date_memo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../providers/memo_provider.dart';
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
                        rowHeight: (90.h).clamp(60.0, 95.0),  // ⭐ 70→73→78→83→87→90 (하단 여백 최소화, 셀 확대)

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
                            color: Colors.transparent,  // ⭐ 배경 제거, 날짜 숫자만 표시
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
    final patternShift = schedule.getPatternShiftForDate(day);

    // ⭐ 패턴과 다른 경우 표시 (패턴이 있고, 현재가 다르고, 둘 다 유효한 경우)
    final isModified = patternShift.isNotEmpty &&
                       shiftText.isNotEmpty &&
                       shiftText != '미설정' &&
                       patternShift != shiftText;

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
      ),
      padding: EdgeInsets.only(left: 2.w, right: 2.w, top: 2.h),  // ⭐ 모든 날짜 동일한 padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⭐ 근무명 (맨 위에 붙임)
          if (shiftText.isNotEmpty && shiftText != '미설정')
            Container(
              height: 18.h,
              decoration: BoxDecoration(
                color: _getShiftBackgroundColor(shiftText, schedule),
                // ⭐ 패턴과 다른 경우 좌측만 각지게
                borderRadius: isModified
                    ? BorderRadius.only(
                        topRight: Radius.circular(3.r),
                        bottomRight: Radius.circular(3.r),
                      )
                    : BorderRadius.circular(3.r),
                // ⭐ 패턴과 다른 경우 좌측에 검정 세로 줄 표시
                border: isModified
                    ? Border(left: BorderSide(color: Colors.black, width: 3))
                    : null,
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

          // ⭐ 날짜 숫자 + 메모 영역 (날짜 위로, 메모 공간 확보)
          Expanded(
            child: Column(
              children: [
                Spacer(flex: 1),  // 위쪽 공간 25%
                // ⭐ 오늘 날짜는 배경으로 표시 (vertical padding 0)
                Container(
                  padding: isToday ? EdgeInsets.symmetric(horizontal: 6.w) : EdgeInsets.zero,
                  decoration: isToday
                      ? BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(3.r),
                        )
                      : null,
                  child: Text(
                    '${day.day}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: isToday ? Colors.blue.shade700 : dateColor,
                      height: 1.0,
                    ),
                  ),
                ),
                Spacer(flex: 3),  // 아래쪽 공간 75% (메모 공간)
                // TODO: 메모 기능 구현 시 Spacer 위에 추가
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _showDayDetailPopup(DateTime day, ShiftSchedule schedule) {
    final currentShift = schedule.getShiftForDate(day);
    final patternShift = schedule.getPatternShiftForDate(day);
    final isModified = patternShift.isNotEmpty &&
                       currentShift.isNotEmpty &&
                       currentShift != '미설정' &&
                       patternShift != currentShift;

    final screenHeight = MediaQuery.of(context).size.height;
    final popupHeight = (screenHeight * 0.7).clamp(400.0, 650.0);  // ⭐ 0.5 → 0.7

    final dateStr = day.toIso8601String().split('T')[0];

    // ⭐ 팝업 열기 전에 메모 로드
    ref.read(memoProvider.notifier).loadMemosForDate(dateStr);

    // ⭐ TextEditingController를 밖에서 생성 (키보드 문제 해결)
    final memoController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // ⭐ 키보드 높이의 일부만 padding으로 적용 (팝업이 조금만 올라가게)
            final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            final paddingBottom = keyboardHeight > 0
                ? (keyboardHeight * 0.2).clamp(0.0, 100.h).toDouble()  // 키보드 높이의 20%만 올리기 (최대 100.h)
                : 0.0;

            return PopScope(
              canPop: false,  // ⭐ 직접 제어
              onPopInvoked: (didPop) async {
                if (!didPop) {
                  // ⭐ 먼저 키보드 포커스 해제
                  FocusScope.of(context).unfocus();
                  // 약간의 딜레이 후 팝업 닫기
                  await Future.delayed(Duration(milliseconds: 100));
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
              child: Padding(
                padding: EdgeInsets.only(bottom: paddingBottom),
                child: Container(
                  height: popupHeight,
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${day.month}월 ${day.day}일 (${_getWeekday(day)})',
                        style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 16.h),

                      // ⭐ 근무 정보
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('근무 :', style: TextStyle(fontSize: 16.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                          SizedBox(width: 8.w),
                          if (isModified) ...[
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('기존', style: TextStyle(fontSize: 12.sp, color: Colors.black, fontWeight: FontWeight.w500)),
                                SizedBox(height: 4.h),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(color: Colors.grey.shade600, width: 1.5),
                                  ),
                                  child: Text(patternShift, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                                ),
                              ],
                            ),
                            Padding(
                              padding: EdgeInsets.only(left: 6.w, right: 6.w, top: 16.h),
                              child: Icon(Icons.arrow_forward, color: Colors.grey.shade700, size: 18.sp),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('현재', style: TextStyle(fontSize: 12.sp, color: Colors.black, fontWeight: FontWeight.w500)),
                                SizedBox(height: 4.h),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: _getShiftBackgroundColor(currentShift, schedule),
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(color: _getShiftTextColor(currentShift, schedule), width: 2),
                                  ),
                                  child: Text(currentShift, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: _getShiftTextColor(currentShift, schedule))),
                                ),
                              ],
                            ),
                          ] else
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: _getShiftBackgroundColor(currentShift, schedule),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: _getShiftTextColor(currentShift, schedule), width: 2),
                              ),
                              child: Text(currentShift, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: _getShiftTextColor(currentShift, schedule))),
                            ),
                        ],
                      ),

                      SizedBox(height: 16.h),

                      // ⭐ 고정 알람
                      Text('고정 알람 :', style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                      SizedBox(height: 8.h),
                      FutureBuilder<List<Alarm>>(
                        future: DatabaseService.instance.getAlarmsByDate(day),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return Text('오류', style: TextStyle(fontSize: 14.sp, color: Colors.red));
                          if (!snapshot.hasData) return SizedBox(height: 20.h, width: 20.w, child: CircularProgressIndicator(strokeWidth: 2));

                          final fixedAlarms = snapshot.data!.where((a) => a.type == 'fixed').toList();
                          if (fixedAlarms.isEmpty) return Text('(없음)', style: TextStyle(fontSize: 14.sp, color: Colors.grey));

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
                                    Text(alarm.time, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),

                      SizedBox(height: 20.h),

                      // ⭐ 메모 입력창 (라벨과 같은 라인)
                      Consumer(
                        builder: (context, ref, child) {
                          final currentMemos = ref.watch(memoProvider)[dateStr] ?? [];
                          final isFull = currentMemos.length >= 3;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text('메모 :', style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: isFull
                                    ? Container(
                                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(8.r),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Text(
                                          '메모는 3개만 등록 가능합니다',
                                          style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
                                        ),
                                      )
                                    : TextField(
                                        controller: memoController,
                                        maxLines: 1,
                                        scrollPhysics: BouncingScrollPhysics(),
                                        decoration: InputDecoration(
                                          hintText: '메모 입력',
                                          hintStyle: TextStyle(fontSize: 14.sp, color: Colors.grey.shade400),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8.r),
                                            borderSide: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8.r),
                                            borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
                                          ),
                                        ),
                                        style: TextStyle(fontSize: 14.sp),
                                      ),
                              ),
                              SizedBox(width: 6.w),
                              ElevatedButton(
                                onPressed: isFull
                                    ? null
                                    : () async {
                                        if (memoController.text.trim().isEmpty) return;

                                        // ⭐ 키보드 내리기
                                        FocusScope.of(context).unfocus();

                                        final success = await ref.read(memoProvider.notifier).createMemo(dateStr, memoController.text.trim());
                                        if (success) {
                                          memoController.clear();
                                          setState(() {});  // ⭐ 팝업 새로고침
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade600,
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                                  minimumSize: Size(0, 0),
                                ),
                                child: Text('저장', style: TextStyle(fontSize: 13.sp, color: Colors.white)),
                              ),
                            ],
                          );
                        },
                      ),

                      SizedBox(height: 12.h),

                      // ⭐ 메모 목록 (최대 3개, 스크롤 가능, 키보드에 가려도 됨)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Consumer(
                            builder: (context, ref, child) {
                              final memos = ref.watch(memoProvider)[dateStr] ?? [];

                              if (memos.isEmpty) {
                                return SizedBox.shrink();
                              }

                              return Column(
                                children: memos.map((memo) {
                                  return GestureDetector(
                                    onTap: () {
                                      _showMemoDetailPopup(day, memo);
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      margin: EdgeInsets.only(bottom: 8.h),
                                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8.r),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Text(
                                        memo.memoText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 14.sp, color: Colors.black87),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),  // ⭐ Container 닫기
              ),  // ⭐ Padding 닫기
            );
          },
        );
      },
    ).then((_) {
      // ⭐ 팝업 닫힐 때 컨트롤러 dispose
      memoController.dispose();
    });
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

  // ⭐ 메모 상세 팝업 (수정/삭제)
  void _showMemoDetailPopup(DateTime day, DateMemo memo) {
    final dateStr = day.toIso8601String().split('T')[0];
    bool isEditing = false;  // ⭐ builder 밖으로 이동
    final editController = TextEditingController(text: memo.memoText);  // ⭐ builder 밖으로 이동

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('메모 상세', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
            content: Container(
              width: double.maxFinite,
              constraints: BoxConstraints(maxHeight: 300.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isEditing)
                    // ⭐ 수정 모드
                    Expanded(
                      child: TextField(
                        controller: editController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          hintText: '메모 내용...',
                          hintStyle: TextStyle(fontSize: 14.sp, color: Colors.grey.shade400),
                          contentPadding: EdgeInsets.all(12.w),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.r),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.r),
                            borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
                          ),
                        ),
                        style: TextStyle(fontSize: 14.sp),
                      ),
                    )
                  else
                    // ⭐ 보기 모드
                    Expanded(
                      child: SingleChildScrollView(
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            memo.memoText,
                            style: TextStyle(fontSize: 14.sp, color: Colors.black87, height: 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (isEditing) ...[
                // ⭐ 수정 모드 버튼
                TextButton(
                  onPressed: () {
                    setState(() {
                      isEditing = false;
                      editController.text = memo.memoText;
                    });
                  },
                  child: Text('취소', style: TextStyle(color: Colors.grey.shade600)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (editController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('메모 내용을 입력해주세요')),
                      );
                      return;
                    }

                    // ⭐ 메모 업데이트 (Provider가 자동으로 메인 팝업 갱신)
                    await ref.read(memoProvider.notifier).updateMemo(memo.id!, dateStr, editController.text.trim());

                    // ⭐ 상세 팝업만 닫기 (메인 팝업은 Consumer로 자동 갱신됨)
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600),
                  child: Text('저장', style: TextStyle(color: Colors.white)),
                ),
              ] else ...[
                // ⭐ 보기 모드 버튼
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('메모 삭제', style: TextStyle(fontSize: 18.sp)),
                        content: Text('이 메모를 삭제하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text('취소'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
                            child: Text('삭제', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      // ⭐ 메모 삭제 (Provider가 자동으로 메인 팝업 갱신)
                      await ref.read(memoProvider.notifier).deleteMemo(memo.id!, dateStr);

                      // ⭐ 상세 팝업만 닫기 (메인 팝업은 Consumer로 자동 갱신됨)
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                  child: Text('삭제', style: TextStyle(color: Colors.red.shade600)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      isEditing = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600),
                  child: Text('수정', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          );
        },
      ),
    ).then((_) {
      // ⭐ 다이얼로그 닫힐 때 컨트롤러 dispose
      editController.dispose();
    });
  }
}