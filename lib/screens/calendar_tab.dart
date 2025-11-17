import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/database_service.dart';
import '../models/shift_schedule.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  ShiftSchedule? _schedule;
  // 중복 제거된 근무 종류 목록
List<String> get _uniqueShifts {
  if (_schedule?.pattern == null) return [];
  return _schedule!.pattern!.toSet().toList();
}
// 배경: 밝은 파스텔
Color _getShiftBackgroundColor(String shift) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  // ⭐ DB에서 색상 사용
  final hue = _schedule?.shiftColors?[shift]?.toDouble();
  
  if (hue != null) {
    return HSLColor.fromAHSL(1.0, hue, 0.5, 0.90).toColor();
  }
  
  // Fallback (DB 색상 없으면)
  return Colors.grey.shade100;
}

Color _getShiftTextColor(String shift) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  // ⭐ DB에서 색상 사용
  final hue = _schedule?.shiftColors?[shift]?.toDouble();
  
  if (hue != null) {
    return HSLColor.fromAHSL(1.0, hue, 0.8, 0.25).toColor();
  }
  
  // Fallback
  return Colors.grey.shade700;
}


  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }
  
  Future<void> _loadSchedule() async {
    final schedule = await DatabaseService.instance.getShiftSchedule();
    setState(() => _schedule = schedule);
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6.w),
          child: Column(
            children: [
              // 커스텀 헤더
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 18.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_focusedDay.year}년 ${_focusedDay.month}월',
                      style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                    ),
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
                          fontSize: 14.sp,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 달력
              Expanded(
                child: TableCalendar(
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2026, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  locale: 'ko_KR',
                  
                  headerVisible: false,
                  rowHeight: 70.h,
                  
                  daysOfWeekHeight: 45.h,
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black),
                    weekendStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black),
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
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) {
                      return _buildDateCell(day, false, false);
                    },
                    outsideBuilder: (context, day, focusedDay) {
                      return _buildDateCell(day, false, true);
                    },
                    todayBuilder: (context, day, focusedDay) {
                      return _buildDateCell(day, true, false);
                    },
                  ),
                  
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                    _showDayDetailPopup(selectedDay);
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
      ),
    );
  }
  
 // _buildDateCell 함수 수정

Widget _buildDateCell(DateTime day, bool isToday, bool isOutside) {
  final shiftText = _schedule?.getShiftForDate(day) ?? '';
  final isSunday = day.weekday == DateTime.sunday;
  
  Color dateColor;
  if (isSunday) {
    dateColor = isOutside ? Colors.red.withOpacity(0.3) : Colors.red;
  } else {
    dateColor = isOutside ? Colors.grey : Colors.black;
  }
  
  return Container(
    // ⭐ 배경 제거
    padding: EdgeInsets.all(4.w),
    child: Column(
      children: [
        // 상단: 근무 종류
        if (shiftText.isNotEmpty && shiftText != '미설정')
          Container(
            width: double.infinity,
            height: 18.h,
            decoration: BoxDecoration(
              color: _getShiftBackgroundColor(shiftText),
              borderRadius: BorderRadius.circular(2.r),
            ),
            child: Center(
              child: Text(
                shiftText,
                style: TextStyle(
                  fontSize: 9.sp,
                  color: _getShiftTextColor(shiftText),
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
        else
          SizedBox(height: 18.h),
        
        Expanded(
  child: Center(
    child: isToday
        ? Container(
            width: 28.w,  // ⭐ 고정 크기
            height: 28.w,
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          )
        : Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: dateColor,
            ),
          ),
  ),
),
      ],
    ),
  );
}
  
  void _showDayDetailPopup(DateTime day) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: EdgeInsets.all(24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📅 ${day.month}월 ${day.day}일',
                      style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16.h),
                    Text('현재: [${_schedule?.getShiftForDate(day) ?? '미설정'}]', style: TextStyle(fontSize: 16.sp)),
                    SizedBox(height: 16.h),
                    Text('고정 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    Text('없음', style: TextStyle(fontSize: 16.sp)),
                    SizedBox(height: 16.h),
                    Text('커스텀 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    Text('없음', style: TextStyle(fontSize: 16.sp)),
                  ],
                ),
              ),
              
              const Divider(),
              
              Expanded(
                flex: 6,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '근무일 변경',
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 12.h),
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('주간'),
                          ),
                          SizedBox(height: 8.h),
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('야간'),
                          ),
                          SizedBox(height: 8.h),
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('휴무'),
                          ),
                        ],
                      ),
                    ),
                    
                    const VerticalDivider(),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '커스텀 알람',
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 12.h),
                          Text('(없음)', style: TextStyle(color: Colors.grey, fontSize: 14.sp)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}