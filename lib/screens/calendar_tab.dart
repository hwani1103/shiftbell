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
import 'all_shifts_view.dart';

// ⭐ 고정 공휴일 (매년 동일 - MM-DD)
const Map<String, String> _fixedHolidays = {
  '01-01': '신정',
  '03-01': '삼일절',
  '05-05': '어린이날',
  '06-06': '현충일',
  '08-15': '광복절',
  '10-03': '개천절',
  '10-09': '한글날',
  '12-25': '크리스마스',
};

// ⭐ 음력/변동 공휴일 (연도별 하드코딩 - YYYY-MM-DD)
const Map<String, String> _lunarHolidays = {
  // 2025년
  '2025-01-28': '설날',
  '2025-01-29': '설날',
  '2025-01-30': '설날',
  '2025-03-03': '대체공휴일',
  '2025-05-06': '대체공휴일',
  '2025-10-05': '추석',
  '2025-10-06': '추석',
  '2025-10-07': '추석',
  '2025-10-08': '대체공휴일',
  // 2026년
  '2026-02-16': '설날',
  '2026-02-17': '설날',
  '2026-02-18': '설날',
  '2026-03-02': '대체공휴일',
  '2026-05-24': '부처님오신날',
  '2026-05-25': '대체공휴일',
  '2026-06-03': '지방선거',
  '2026-08-17': '대체공휴일',
  '2026-09-24': '추석',
  '2026-09-25': '추석',
  '2026-09-26': '추석',
  '2026-10-05': '대체공휴일',
  // 2027년
  '2027-02-06': '설날',
  '2027-02-07': '설날',
  '2027-02-08': '설날',
  '2027-02-09': '대체공휴일',
  '2027-05-13': '부처님오신날',
  '2027-08-16': '대체공휴일',
  '2027-09-14': '추석',
  '2027-09-15': '추석',
  '2027-09-16': '추석',
  '2027-10-04': '대체공휴일',
  '2027-10-11': '대체공휴일',
  '2027-12-27': '대체공휴일',
  // 2028년
  '2028-01-26': '설날',
  '2028-01-27': '설날',
  '2028-01-28': '설날',
  '2028-05-02': '부처님오신날',
  '2028-10-02': '추석',
  '2028-10-03': '추석',
  '2028-10-04': '추석',
  '2028-10-05': '대체공휴일',
  // 2029년
  '2029-02-12': '설날',
  '2029-02-13': '설날',
  '2029-02-14': '설날',
  '2029-05-07': '대체공휴일',
  '2029-05-20': '부처님오신날',
  '2029-05-21': '대체공휴일',
  '2029-09-21': '추석',
  '2029-09-22': '추석',
  '2029-09-23': '추석',
  '2029-09-24': '대체공휴일',
};

// 공휴일 여부 확인
String? _getHolidayName(DateTime date) {
  // 1. 고정 공휴일 체크 (매년 동일)
  final fixedKey = '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  if (_fixedHolidays.containsKey(fixedKey)) {
    return _fixedHolidays[fixedKey];
  }

  // 2. 음력/변동 공휴일 체크 (연도별)
  final lunarKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return _lunarHolidays[lunarKey];
}

// StatefulWidget → ConsumerStatefulWidget으로 변경
class CalendarTab extends ConsumerStatefulWidget {  // ⭐ 변경
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();  // ⭐ 변경
}

class _CalendarTabState extends ConsumerState<CalendarTab> {  // ⭐ 변경
  static const platform = MethodChannel('com.hwani1103.shiftbell/alarm');  // ⭐ 추가

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

  final colorScheme = Theme.of(context).colorScheme;
  return colorScheme.surfaceVariant;
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

  final colorScheme = Theme.of(context).colorScheme;
  return colorScheme.onSurfaceVariant;
}

  @override
  void initState() {
    super.initState();
    // ⭐ 앱 시작 시 현재 달의 메모 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMemosForMonth(_focusedDay);
    });
  }

  // ⭐ 6번째 줄 여부 판단 (해당 날짜가 6번째 줄에 있는지)
  bool _isSixthRow(DateTime day, DateTime focusedMonth) {
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);

    int daysFromSunday;
    if (firstDayOfMonth.weekday == 7) {
      daysFromSunday = 0;
    } else {
      daysFromSunday = firstDayOfMonth.weekday;
    }

    final calendarStart = firstDayOfMonth.subtract(Duration(days: daysFromSunday));
    final daysDifference = day.difference(calendarStart).inDays;

    // 6번째 줄은 35일 ~ 41일 (5주 * 7일 = 35일부터)
    return daysDifference >= 35 && daysDifference < 42;
  }

  // ⭐ 6번째 줄 화~토(col 2~6) 여부 판단
  bool _isSixthRowEmptyCell(DateTime day, DateTime focusedMonth) {
    if (!_isSixthRow(day, focusedMonth)) return false;

    // 요일 체크: 화(2) ~ 토(6)
    final weekday = day.weekday;
    return weekday >= 2 && weekday <= 6;
  }

  // ⭐ 특정 달의 메모 미리 로드 (달력에 보이는 이전/다음 달 날짜 포함)
  void _loadMemosForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1).subtract(Duration(days: 7));
    final lastDay = DateTime(month.year, month.month + 1, 0).add(Duration(days: 7));
    ref.read(memoProvider.notifier).loadMemosForDateRange(firstDay, lastDay);
  }

  // ⭐ 4번 기능: 년/월 선택 다이얼로그
  void _showMonthYearPicker() {
    int selectedYear = _focusedDay.year;
    int selectedMonth = _focusedDay.month;

    // ⭐ 달력 초기화 범위 확인 (3년 전후)
    final minYear = DateTime.now().year - 3;
    final maxYear = DateTime.now().year + 3;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              // ⭐ 타이틀에 X 버튼 추가
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('날짜 선택', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: Icon(Icons.close, size: 24.sp),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 년도 선택 (범위 제한)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left),
                          onPressed: selectedYear > minYear
                              ? () => setState(() => selectedYear--)
                              : null,
                        ),
                        SizedBox(
                          width: 100.w,
                          child: Text(
                            '$selectedYear년',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right),
                          onPressed: selectedYear < maxYear
                              ? () => setState(() => selectedYear++)
                              : null,
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    // 월 선택 (그리드) - 탭하면 즉시 이동, 모든 월 동일한 스타일
                    SizedBox(
                      height: 200.h,
                      child: GridView.builder(
                        physics: NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8.h,
                          crossAxisSpacing: 8.w,
                          childAspectRatio: 1.8,
                        ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final month = index + 1;
                          return GestureDetector(
                            // ⭐ 탭하면 즉시 이동
                            onTap: () {
                              this.setState(() {
                                _focusedDay = DateTime(selectedYear, month, 1);
                              });
                              _loadMemosForMonth(_focusedDay);
                              Navigator.pop(context);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$month월',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.normal,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // ⭐ 액션 버튼 제거 (X 버튼으로 충분, 월 탭하면 즉시 이동)
            );
          },
        );
      },
    );
  }

  @override
Widget build(BuildContext context) {
  final scheduleAsync = ref.watch(scheduleProvider);
  
  return scheduleAsync.when(
    loading: () => const Scaffold(
      body: SizedBox.shrink(),  // ⭐ 로딩 인디케이터 제거
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
              Column(
                children: [
                  // ⭐ 헤더 영역 - 최소화
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: SizedBox(
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
                                : GestureDetector(
                                    // ⭐ 4번 기능: 헤더 클릭으로 년/월 선택 다이얼로그
                                    onTap: () => _showMonthYearPicker(),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${_focusedDay.year}년 ${_focusedDay.month}월',
                                          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(width: 4.w),
                                        Icon(Icons.arrow_drop_down, size: 24.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ],
                                    ),
                                  ),
                            if (!_isMultiSelectMode)
                              Row(
                                children: [
                                  // ⭐ 전체근무표 버튼 (규칙적 근무자만 표시)
                                  if (schedule.isRegular)
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => AllShiftsView()),
                                        );
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                                        margin: EdgeInsets.only(right: 8.w),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(6.r),
                                          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 0.8),
                                        ),
                                        child: Text(
                                          '전체근무표',
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // ⭐ today 버튼 (전체근무표와 동일 스타일)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _focusedDay = DateTime.now();
                                        _selectedDay = null;
                                      });
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(6.r),
                                        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 0.8),
                                      ),
                                      child: Text(
                                        'today',
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ⭐ 달력 (하나의 TableCalendar, 6줄 고정)
                  Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6.w),
                        child: TableCalendar(
                      firstDay: DateTime(DateTime.now().year - 3, 1, 1),
                      lastDay: DateTime(DateTime.now().year + 3, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) {
                        if (_isMultiSelectMode) {
                          return _selectedDates.any((d) => isSameDay(d, day));
                        }
                        return isSameDay(_selectedDay, day);
                      },
                      locale: 'ko_KR',

                      headerVisible: false,
                      sixWeekMonthsEnforced: true,  // ⭐ 항상 6줄 고정
                      rowHeight: 83.h,

                      daysOfWeekHeight: 28.h,
                      daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                        weekendStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                      ),

                      calendarStyle: CalendarStyle(
                        cellMargin: EdgeInsets.all(0),
                        cellPadding: EdgeInsets.all(0),

                        tableBorder: TableBorder.all(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
                          width: 1.0,
                        ),

                        defaultTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        weekendTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        outsideTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),

                        todayDecoration: BoxDecoration(
                          color: Colors.transparent,  // ⭐ 배경 제거, 날짜 숫자만 표시
                        ),
                        todayTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),

                        selectedDecoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary.withOpacity(_isMultiSelectMode ? 0.3 : 1.0),
                          shape: BoxShape.circle,
                        ),
                        selectedTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSecondary),
                      ),

                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, focusedDay) {
                          // ⭐ 6번째 줄 화~토는 빈 Container
                          if (_isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          return _buildDateCell(day, false, false, schedule);
                        },
                        outsideBuilder: (context, day, focusedDay) {
                          // ⭐ 6번째 줄 화~토는 빈 Container
                          if (_isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          return _buildDateCell(day, false, true, schedule);
                        },
                        todayBuilder: (context, day, focusedDay) {
                          // ⭐ 6번째 줄 화~토는 빈 Container
                          if (_isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          final isOutsideMonth = day.month != _focusedDay.month || day.year != _focusedDay.year;
                          return _buildDateCell(day, true, isOutsideMonth, schedule);
                        },
                        selectedBuilder: (context, day, focusedDay) {
                          // ⭐ 6번째 줄 화~토는 빈 Container
                          if (_isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          return _buildDateCell(day, isSameDay(day, DateTime.now()), false, schedule, isSelected: true);
                        },
                      ),

                      onDaySelected: (selectedDay, focusedDay) {
                        // ⭐ 이전/다음 달 날짜는 탭 무시
                        if (selectedDay.month != _focusedDay.month || selectedDay.year != _focusedDay.year) {
                          return;
                        }

                        // ⭐ 6번째 줄 빈 칸은 탭 무시
                        if (_isSixthRowEmptyCell(selectedDay, focusedDay)) {
                          return;
                        }

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
                        // ⭐ 이전/다음 달 날짜는 길게 누르기 무시
                        if (selectedDay.month != _focusedDay.month || selectedDay.year != _focusedDay.year) {
                          return;
                        }

                        // ⭐ 6번째 줄 빈 칸은 길게 누르기 무시
                        if (_isSixthRowEmptyCell(selectedDay, focusedDay)) {
                          return;
                        }

                        if (!_isMultiSelectMode) {
                          _enterMultiSelectMode(selectedDay);
                        }
                      },

                      onPageChanged: (focusedDay) {
                        setState(() {
                          _focusedDay = focusedDay;
                        });
                        // ⭐ 새 달의 메모 로드
                        _loadMemosForMonth(focusedDay);
                      },
                        ),
                      ),

                      // ⭐ 6번째 줄 화~토 테두리 제거 (흰색 덮개)
                      Positioned(
                        top: 28.h + 83.h * 5,  // 요일 헤더 + 5줄
                        left: 6.w,
                        right: 6.w,
                        height: 83.h,
                        child: IgnorePointer(  // ⭐ 제스처를 아래 TableCalendar로 전달
                          child: Row(
                            children: [
                              // 일요일 + 월요일 칸 (비워둠)
                              Expanded(flex: 2, child: SizedBox()),
                              // 화~토 칸 (흰색으로 덮되 상단/좌측 테두리는 유지)
                              Expanded(
                                flex: 5,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                    border: Border(
                                      top: BorderSide(color: Theme.of(context).colorScheme.outline, width: 0.3),
                                      left: BorderSide(color: Theme.of(context).colorScheme.outline, width: 0.3),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('근무 변경', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('탭하여 날짜 추가 선택', style: TextStyle(fontSize: 10.sp)),
                        ],
                      ),
                      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      elevation: 3,
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

    // ⭐ 오늘이면서 현재 보고 있는 달과 같을 때만 강조
    final shouldHighlightToday = isToday &&
                                 _focusedDay.year == day.year &&
                                 _focusedDay.month == day.month;

    final isHoliday = _getHolidayName(day) != null;  // ⭐ 공휴일 체크

    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    Color dateColor;
    if (isSunday || isHoliday) {  // ⭐ 일요일 또는 공휴일
      dateColor = isOutside
          ? (isDarkMode ? Colors.red.shade300.withOpacity(0.5) : Colors.red.withOpacity(0.3))
          : (isDarkMode ? Colors.red.shade300 : Colors.red);
    } else {
      dateColor = isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : colorScheme.onSurface;
    }

    return Container(
      decoration: BoxDecoration(
        color: isSelected && _isMultiSelectMode
            ? Theme.of(context).colorScheme.secondary.withOpacity(0.2)
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
                    ? Border(left: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 3))
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

          // ⭐ 날짜 숫자 + 공휴일 이름 + 메모 영역 (Stack으로 독립 배치)
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final dateStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                final memos = ref.watch(memoProvider)[dateStr] ?? [];
                final memoCount = memos.length;

                return Stack(
                  children: [
                    // ⭐ 공휴일 이름 (상단 고정, 글자 수에 따라 크기 자동 조절)
                    if (_getHolidayName(day) != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 11.h,
                          padding: EdgeInsets.symmetric(horizontal: 1.w),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _getHolidayName(day)!,
                              style: TextStyle(
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w600,
                                color: isOutside
                                    ? (isDarkMode ? Colors.red.shade300.withOpacity(0.5) : Colors.red.withOpacity(0.3))
                                    : (isDarkMode ? Colors.red.shade300 : Colors.red),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // ⭐ 날짜 숫자 (항상 중앙, 3개일 때만 살짝 위로)
                    // 오늘 + 빨간날 = 라임배경 + 빨간텍스트
                    // 오늘 + 일반날 = 인디고배경 + 흰텍스트
                    // 오늘 아닌 빨간날 = 빨간텍스트만
                    // 오늘 아닌 일반날 = 검정텍스트
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: memoCount >= 3 ? 20.h : 0),
                        child: Container(
                          padding: shouldHighlightToday ? EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h) : EdgeInsets.zero,
                          decoration: shouldHighlightToday
                              ? BoxDecoration(
                                  color: (isSunday || isHoliday) ? Colors.lime.shade300 : Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4.r),
                                )
                              : null,
                          child: Text(
                            '${day.day}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: shouldHighlightToday
                                  ? ((isSunday || isHoliday) ? (isDarkMode ? Colors.red.shade700 : Colors.red) : Theme.of(context).colorScheme.onPrimary)
                                  : dateColor,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ⭐ 메모 표시 (하단 고정, 날짜와 독립)
                    if (memos.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 1.5.h,  // ⭐ 바닥에서 살짝 띄움
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: memos.take(3).map((memo) {
                            return Container(
                              width: double.infinity,
                              margin: EdgeInsets.only(bottom: 0.5.h),
                              padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                  ? colorScheme.primary.withOpacity(0.3)
                                  : colorScheme.surfaceVariant,
                                border: Border.all(
                                  color: isDarkMode
                                    ? colorScheme.primary.withOpacity(0.5)
                                    : colorScheme.outline,
                                  width: 0.5
                                ),
                                borderRadius: BorderRadius.circular(2.r),
                              ),
                              child: Text(
                                memo.memoText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 8.sp,  // ⭐ 7 → 8 (살짝 크게)
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,  // ⭐ ellipsis → clip (더 많이 표시)
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                );
              },
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
    final popupHeight = screenHeight * 0.72;  // ⭐ 화면의 72%

    final dateStr = day.toIso8601String().split('T')[0];

    // ⭐ 팝업 열기 전에 알람 데이터 새로고침 (dismiss/snooze/timeout 후 최신 데이터 반영)
    ref.invalidate(alarmNotifierProvider);

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
            // ⭐ 키보드 감지 시 고정 패딩 적용 (점진적 변화 방지)
            final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            final isKeyboardVisible = keyboardHeight > 50;  // 키보드 감지 임계값
            final paddingBottom = isKeyboardVisible ? 60.h : 0.0;  // 고정 패딩

            // ignore: deprecated_member_use
            return WillPopScope(
              onWillPop: () async {
                // ⭐ 뒤로가기 시 키보드 포커스 해제
                FocusScope.of(context).unfocus();
                await Future.delayed(Duration(milliseconds: 150));
                return true;
              },
              child: Padding(
                padding: EdgeInsets.only(bottom: paddingBottom),
                child: Container(
                  height: popupHeight,
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ⭐ 날짜
                      Text(
                        '${day.month}월 ${day.day}일 (${_getWeekday(day)})',
                        style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 16.h),

                      // ⭐ 근무 정보
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('근무 :', style: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
                          SizedBox(width: 8.w),
                          if (isModified) ...[
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('기존', style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
                                SizedBox(height: 4.h),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.5),
                                  ),
                                  child: Text(patternShift, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ),
                              ],
                            ),
                            Padding(
                              padding: EdgeInsets.only(left: 6.w, right: 6.w, top: 16.h),
                              child: Icon(Icons.arrow_forward, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18.sp),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('현재', style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
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
                      Text('고정 알람 :', style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
                      SizedBox(height: 8.h),
                      Consumer(
                        builder: (context, ref, child) {
                          final alarmsAsync = ref.watch(alarmNotifierProvider);

                          return alarmsAsync.when(
                            loading: () => SizedBox(height: 20.h, width: 20.w, child: CircularProgressIndicator(strokeWidth: 2)),
                            error: (_, __) => Text('오류', style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.error)),
                            data: (allAlarms) {
                              final dayStr = day.toIso8601String().split('T')[0];
                              final fixedAlarms = allAlarms
                                  .where((a) => a.type == 'fixed' && a.date != null && a.date!.toIso8601String().startsWith(dayStr))
                                  .toList();

                              if (fixedAlarms.isEmpty) {
                                return Text('(없음)', style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant));
                              }

                              return Row(
                                children: fixedAlarms.map((alarm) {
                                  final typeInfo = _getAlarmTypeInfo(alarm.alarmTypeId);
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => _showAlarmTypeSelectionPopup(alarm, setState),
                                      child: Container(
                                        margin: EdgeInsets.only(right: alarm != fixedAlarms.last ? 8.w : 0),
                                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(8.r),
                                          border: Border.all(color: Theme.of(context).colorScheme.secondary.withOpacity(0.3)),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(typeInfo['emoji']!, style: TextStyle(fontSize: 14.sp)),
                                                SizedBox(width: 4.w),
                                                Text(alarm.time, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSecondaryContainer)),
                                              ],
                                            ),
                                            SizedBox(height: 4.h),
                                            Text(
                                              typeInfo['label']!,
                                              style: TextStyle(fontSize: 10.sp, color: Theme.of(context).colorScheme.onSecondaryContainer),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
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
                              Text('메모 :', style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: isFull
                                    ? Container(
                                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceVariant,
                                          borderRadius: BorderRadius.circular(8.r),
                                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                                        ),
                                        child: Text(
                                          '메모는 3개만 등록 가능합니다',
                                          style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      )
                                    : TextField(
                                        controller: memoController,
                                        maxLines: 1,
                                        scrollPhysics: BouncingScrollPhysics(),
                                        decoration: InputDecoration(
                                          hintText: '메모 입력',
                                          hintStyle: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6)),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8.r),
                                            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8.r),
                                            borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
                                          ),
                                        ),
                                        style: TextStyle(fontSize: 14.sp),
                                      ),
                              ),
                              SizedBox(width: 6.w),
                              ElevatedButton(
                                onPressed: isFull
                                    ? null
                                    : () {
                                        if (memoController.text.trim().isEmpty) return;

                                        // ⭐ 키보드 내리기
                                        FocusScope.of(context).unfocus();

                                        // ⭐ 메모 텍스트를 결과로 전달하며 팝업 닫기
                                        // 실제 저장은 .then()에서 처리 (Consumer dispose 후)
                                        Navigator.of(context).pop(memoController.text.trim());
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.secondary,
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                                  minimumSize: Size(0, 0),
                                ),
                                child: Text('저장', style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSecondary)),
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
                                  return Container(
                                    width: double.infinity,
                                    margin: EdgeInsets.only(bottom: 8.h),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceVariant,
                                      borderRadius: BorderRadius.circular(8.r),
                                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                                    ),
                                    child: Row(
                                      children: [
                                        // ⭐ 텍스트 영역 (탭하면 상세 팝업)
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              _showMemoDetailPopup(day, memo);
                                            },
                                            child: Container(
                                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                                              child: Text(
                                                memo.memoText,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // ⭐ 삭제 버튼 (바로 삭제)
                                        GestureDetector(
                                          onTap: () async {
                                            await ref.read(memoProvider.notifier).deleteMemo(memo.id!, dateStr);
                                          },
                                          child: Container(
                                            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
                                            child: Icon(
                                              Icons.delete,
                                              size: 18.sp,
                                              color: Theme.of(context).colorScheme.error,
                                            ),
                                          ),
                                        ),
                                      ],
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
    ).then((result) {
      // ⭐ 팝업 애니메이션 완료 대기 후 저장 + dispose
      Future.delayed(const Duration(milliseconds: 500), () {
        // ⭐ 메모 저장
        if (result != null && result is String && result.isNotEmpty) {
          ref.read(memoProvider.notifier).createMemo(dateStr, result);
        }

        // ⭐ 컨트롤러 dispose
        memoController.dispose();
      });
    });
  }

  String _getWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  // ⭐ 알람 타입 정보 반환
  Map<String, String> _getAlarmTypeInfo(int typeId) {
    switch (typeId) {
      case 1:
        return {'emoji': '🔔', 'label': '소리+진동'};
      case 2:
        return {'emoji': '📳', 'label': '진동'};
      case 3:
        return {'emoji': '🔇', 'label': '무음'};
      default:
        return {'emoji': '🔔', 'label': '소리+진동'};
    }
  }

  // ⭐ 알람 타입 선택 팝업
  void _showAlarmTypeSelectionPopup(Alarm alarm, StateSetter parentSetState) {
    print('🔍 알람 타입 선택 팝업 열림 - alarm.id: ${alarm.id}, alarmTypeId: ${alarm.alarmTypeId}');
    showDialog(
      context: context,
      builder: (context) {
        print('🏗️ AlertDialog 빌드 시작');
        return AlertDialog(
          title: Text(
            '알람 타입 선택',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,  // ⭐ 명시적 width 지정
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${alarm.time} 알람',
                  style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 16.h),
                Row(
                  mainAxisSize: MainAxisSize.max,  // ⭐ 명시적 설정
                  children: [
                    _buildAlarmTypeOption(
                      typeId: 1,
                      icon: Icons.volume_up_rounded,
                      label: '소리+진동',
                      isSelected: alarm.alarmTypeId == 1,
                      onTap: () async {
                        await ref.read(alarmNotifierProvider.notifier).updateAlarmType(alarm.id!, 1);
                        Navigator.pop(context);
                        parentSetState(() {});
                      },
                    ),
                    SizedBox(width: 8.w),
                    _buildAlarmTypeOption(
                      typeId: 2,
                      icon: Icons.vibration_rounded,
                      label: '진동',
                      isSelected: alarm.alarmTypeId == 2,
                      onTap: () async {
                        await ref.read(alarmNotifierProvider.notifier).updateAlarmType(alarm.id!, 2);
                        Navigator.pop(context);
                        parentSetState(() {});
                      },
                    ),
                    SizedBox(width: 8.w),
                    _buildAlarmTypeOption(
                      typeId: 3,
                      icon: Icons.notifications_off_rounded,
                      label: '무음',
                      isSelected: alarm.alarmTypeId == 3,
                      onTap: () async {
                        await ref.read(alarmNotifierProvider.notifier).updateAlarmType(alarm.id!, 3);
                        Navigator.pop(context);
                        parentSetState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,  // ⭐ Spacer() 대신 사용
          actions: [
            // ⭐ 삭제 버튼
            TextButton(
              onPressed: () => _showDeleteAlarmConfirmation(alarm, parentSetState),
              child: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14.sp)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('취소'),
            ),
          ],
        );
      },
    );
  }

  // ⭐ 알람 삭제 확인 팝업
  void _showDeleteAlarmConfirmation(Alarm alarm, StateSetter parentSetState) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '알람 삭제',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '${alarm.time} 알람을 삭제하시겠습니까?',
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);  // 확인 팝업 닫기
                Navigator.pop(context);  // 타입 선택 팝업 닫기
                await _deleteAlarm(alarm);
                parentSetState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.onError)),
            ),
          ],
        );
      },
    );
  }

  // ⭐ 알람 삭제 (울리는 중이면 Overlay도 종료)
  Future<void> _deleteAlarm(Alarm alarm) async {
    try {
      // 1. 울리는 중인 Overlay 종료
      await platform.invokeMethod('dismissOverlay', {'alarmId': alarm.id});
    } catch (e) {
      print('⚠️ Overlay 종료 신호 실패: $e');
    }

    try {
      // 2. DB에서 알람 삭제 + Native 알람 취소
      await ref.read(alarmNotifierProvider.notifier).deleteAlarm(alarm.id!, alarm.date);

      // 3. Notification 취소
      try {
        await platform.invokeMethod('cancelNotification');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }

      // 4. AlarmGuardReceiver 트리거 (다음 알람 Notification 표시)
      try {
        await platform.invokeMethod('triggerGuardCheck');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 알람 삭제 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('❌ _deleteAlarm 실패: $e');
      rethrow;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('알람이 삭제되었습니다'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    }
  }

  // ⭐ 알람 타입 옵션 버튼
  Widget _buildAlarmTypeOption({
    required int typeId,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    print('🎨 빌드: typeId=$typeId, label=$label, isSelected=$isSelected');
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24.sp,
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(height: 4.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        // ⭐ 0개가 되면 자동으로 일반 모드로 돌아가기
        if (_selectedDates.isEmpty) {
          _isMultiSelectMode = false;
        }
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
              '${_selectedDates.length}일 근무 변경',
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

    try {
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
    } catch (e) {
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 근무 할당 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('❌ _bulkAssignShift 실패: $e');
    }
  }
  
  Future<void> _changeShift(DateTime date, String newShiftType, ShiftSchedule schedule) async {
    try {
      await ref.read(scheduleProvider.notifier).changeShiftWithAlarms(date, newShiftType);

      // ⭐ 알람 Provider도 수동 갱신
      await ref.read(alarmNotifierProvider.notifier).refresh();

      try {
        await platform.invokeMethod('cancelNotification');
        print('✅ Notification 삭제 완료 (근무일 변경)');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 근무 변경 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('❌ _changeShift 실패: $e');
    }
  }

  // ⭐ 메모 상세 팝업 (수정/삭제)
  void _showMemoDetailPopup(DateTime day, DateMemo memo) {
    final dateStr = day.toIso8601String().split('T')[0];
    bool isEditing = false;  // ⭐ builder 밖으로 이동
    final editController = TextEditingController(text: memo.memoText);  // ⭐ builder 밖으로 이동

    showDialog(
      context: context,
      // ignore: deprecated_member_use
      builder: (context) => WillPopScope(
        onWillPop: () async {
          // ⭐ 뒤로가기 시 키보드 포커스 해제
          FocusScope.of(context).unfocus();
          await Future.delayed(Duration(milliseconds: 150));
          return true;
        },
        child: StatefulBuilder(
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
                          hintStyle: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6)),
                          contentPadding: EdgeInsets.all(12.w),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.r),
                            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.r),
                            borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
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
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                          ),
                          child: Text(
                            memo.memoText,
                            style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface, height: 1.5),
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
                  child: Text('취소', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (editController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('메모 내용을 입력해주세요')),
                      );
                      return;
                    }

                    // ⭐ 키보드 포커스 해제
                    FocusScope.of(context).unfocus();
                    await Future.delayed(Duration(milliseconds: 100));

                    // ⭐ 메모 업데이트 (Provider가 자동으로 메인 팝업 갱신)
                    await ref.read(memoProvider.notifier).updateMemo(memo.id!, dateStr, editController.text.trim());

                    // ⭐ 상세 팝업만 닫기 (메인 팝업은 Consumer로 자동 갱신됨)
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary),
                  child: Text('저장', style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
                ),
              ] else ...[
                // ⭐ 보기 모드 버튼 - 바로 삭제 (확인 팝업 제거)
                TextButton(
                  onPressed: () async {
                    // ⭐ 메모 삭제 (Provider가 자동으로 메인 팝업 갱신)
                    await ref.read(memoProvider.notifier).deleteMemo(memo.id!, dateStr);

                    // ⭐ 상세 팝업만 닫기 (메인 팝업은 Consumer로 자동 갱신됨)
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      isEditing = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary),
                  child: Text('수정', style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
                ),
              ],
            ],
            );
          },
        ),
      ),
    ).then((_) {
      // ⭐ MEDIUM FIX: 팝업 닫힐 때 메모리 누수 방지 (약간의 지연으로 rebuild 충돌 방지)
      Future.delayed(const Duration(milliseconds: 100), () {
        editController.dispose();
      });
    });
  }
}