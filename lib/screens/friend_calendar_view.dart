// screens/friend_calendar_view.dart
//
// ⭐ 친구 달력 보기 - 실제 달력탭(calendar_tab.dart)과 최대한 같은 톤(근무명
// 알약 배지 + 가운데 숫자 + 하단 메모)으로 만들되, 데이터는 Provider가 아니라
// 친구의 FriendScheduleData 스냅샷에서만 읽음. 맨 위 배너로 "지금 내 달력이
// 아니라 친구 달력을 보고 있다"는 걸 항상 인식시킴. 읽기 전용 - 근무 변경/
// 메모 추가/OT 입력 등 편집 기능은 없음(애초에 공유 안 되는 정보이기도 함).
//
// ⭐ 실제 그리드는 달력탭과 똑같이 table_calendar 패키지를 그대로 씀(전에는
// Column/Row를 직접 쌓은 정적 그리드라 좌우 스와이프가 아예 안 됐음) - 이걸로
// 달과 스와이프 넘김이 진짜 달력탭과 동일하게 동작하고, 셀 디자인(근무 배지 →
// 숫자 → 공휴일/메모)도 _buildDateCell을 최대한 그대로 재현함. 공유 시점의
// "스냅샷"만 보여주면 되므로 실시간으로 테마를 따라갈 필요는 없음.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/friend_schedule.dart';
import '../models/shift_schedule.dart';
import '../utils/holiday_util.dart';

class FriendCalendarView extends StatefulWidget {
  final String friendName;
  final FriendScheduleData data;
  // ⭐ 웹(트랙1)에서만 true로 넘어옴 - 링크 받은 사람이 앱 미설치자일 수 있어서
  // "앱 설치하고 실시간으로 보기" 유도 배너를 하단에 추가로 보여줌. 앱 안(트랙2,
  // 친구 목록에서 열 때)에서는 이미 앱을 쓰고 있으니 당연히 안 보여줌.
  final bool showInstallPrompt;
  final VoidCallback? onInstallTap;

  const FriendCalendarView({
    super.key,
    required this.friendName,
    required this.data,
    this.showInstallPrompt = false,
    this.onInstallTap,
  });

  @override
  State<FriendCalendarView> createState() => _FriendCalendarViewState();
}

class _FriendCalendarViewState extends State<FriendCalendarView> {
  // ⭐ table_calendar가 요구하는 "지금 보고 있는 달"의 기준일. 화살표 버튼으로
  // 바꾸면 TableCalendar가 알아서 그 달로 애니메이션 넘김 - 달력탭의 "오늘"
  // 버튼과 동일한 방식(값만 바꾸면 페이지가 따라옴).
  late DateTime _focusedDay;
  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime(_today.year, _today.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + delta, 1));
  }

  Color _shiftColor(String shiftName) {
    final v = widget.data.shiftColors[shiftName];
    if (v == null) return Colors.grey.shade300;
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.friendName}님의 근무표', style: TextStyle(fontSize: 17.sp))),
      // ⭐ 하단 SafeArea 없이 body를 바로 뒀더니 제스처 네비게이션 바/화면 하단
      // 곡면에 마지막 줄(6번째 주 또는 설치 유도 배너)이 잘리는 문제가 있었음 -
      // 실제 앱(main.dart 쪽 Scaffold들)은 전부 SafeArea 하위에서 그려지는데
      // 이 화면만 빠져 있었던 게 원인.
      body: SafeArea(
        child: Column(
          children: [
            // ⭐ 항상 눈에 띄는 배너 - "내 달력이 아니다"를 계속 인식시킴
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 16.sp, color: Colors.brown.shade600),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      '${widget.friendName}님의 근무표를 보는 중입니다 (읽기 전용)',
                      style: TextStyle(fontSize: 12.sp, color: Colors.brown.shade700, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!widget.data.hasMemos)
                    Text('메모 비공개', style: TextStyle(fontSize: 10.5.sp, color: Colors.brown.shade400)),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
              child: Row(
                children: [
                  IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_focusedDay.year}년 ${_focusedDay.month}월',
                        style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                child: TableCalendar(
                  // ⭐ 달력탭과 동일한 범위 - 공유 코드는 "과거/미래 상관없이 스와이프해서
                  // 둘러볼 수 있는" 하나의 스케줄 스냅샷이라 범위를 좁힐 이유가 없음.
                  firstDay: DateTime(_today.year - 3, 1, 1),
                  lastDay: DateTime(_today.year + 3, 12, 31),
                  focusedDay: _focusedDay,
                  locale: 'ko_KR',
                  headerVisible: false,
                  sixWeekMonthsEnforced: true,
                  rowHeight: 83.h,
                  daysOfWeekHeight: 28.h,
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    weekendStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  calendarStyle: CalendarStyle(
                    cellMargin: EdgeInsets.zero,
                    cellPadding: EdgeInsets.zero,
                    tableBorder: TableBorder.all(
                      color: isDarkMode
                          ? colorScheme.onSurface.withOpacity(0.4)
                          : colorScheme.onSurface.withOpacity(0.15),
                      width: 1.0,
                    ),
                  ),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) => _buildFriendDateCell(day, false, false),
                    outsideBuilder: (context, day, focusedDay) => _buildFriendDateCell(day, false, true),
                    todayBuilder: (context, day, focusedDay) {
                      final isOutsideMonth = day.month != _focusedDay.month || day.year != _focusedDay.year;
                      return _buildFriendDateCell(day, true, isOutsideMonth);
                    },
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    // ⭐ 다른 달 날짜 탭은 무시 - 달력탭과 동일한 동작
                    if (selectedDay.month != _focusedDay.month || selectedDay.year != _focusedDay.year) return;
                    setState(() => _focusedDay = focusedDay);
                    _showDaySheet(context, selectedDay);
                  },
                  onPageChanged: (focusedDay) {
                    setState(() => _focusedDay = focusedDay);
                  },
                ),
              ),
            ),
            if (widget.showInstallPrompt) _buildInstallBanner(context),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  // ⭐ calendar_tab.dart의 _buildDateCell과 최대한 같은 시각 언어(근무 배지 →
  // 날짜 숫자(오늘=강조 배경) → 공휴일 이름/메모)로 재현. Provider를 못 쓰니
  // widget.data에서 동기로 바로 읽음 - Consumer로 감쌀 필요가 없어서 오히려 더 단순함.
  Widget _buildFriendDateCell(DateTime day, bool isToday, bool isOutside) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final shiftText = widget.data.getShiftForDate(day);
    final hasShift = shiftText.isNotEmpty && shiftText != '미설정';
    final patternShift = widget.data.getPatternShiftForDate(day);
    final isModified = patternShift.isNotEmpty && hasShift && patternShift != shiftText;

    final isSunday = day.weekday == DateTime.sunday;
    final holidayName = getHolidayName(day);
    final isHoliday = holidayName != null;
    final memos = widget.data.memosForDate(day);

    final shouldHighlightToday = isToday && _focusedDay.year == day.year && _focusedDay.month == day.month;

    final Color dateColor = (isSunday || isHoliday)
        ? (isOutside
            ? (isDarkMode ? Colors.red.shade300.withOpacity(0.5) : Colors.red.withOpacity(0.3))
            : (isDarkMode ? Colors.red.shade300 : Colors.red))
        : (isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : colorScheme.onSurface);

    return Container(
      padding: EdgeInsets.only(left: 2.w, right: 2.w, top: 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⭐ 근무명 뱃지 (맨 위)
          if (hasShift)
            Container(
              height: 18.h,
              decoration: BoxDecoration(
                color: _shiftColor(shiftText),
                borderRadius: isModified
                    ? BorderRadius.only(topRight: Radius.circular(3.r), bottomRight: Radius.circular(3.r))
                    : BorderRadius.circular(3.r),
                border: isModified ? Border(left: BorderSide(color: colorScheme.onSurface, width: 3)) : null,
              ),
              child: Center(
                child: Text(
                  shiftText,
                  style: TextStyle(fontSize: 9.sp, color: ShiftSchedule.getTextColor(_shiftColor(shiftText)), fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          else
            SizedBox(height: 18.h),

          Expanded(
            child: Stack(
              children: [
                if (holidayName != null)
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
                          holidayName,
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
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: memos.length >= 3 ? 20.h : 0),
                    child: Container(
                      padding: shouldHighlightToday ? EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h) : EdgeInsets.zero,
                      decoration: shouldHighlightToday
                          ? BoxDecoration(
                              color: (isSunday || isHoliday)
                                  ? (isDarkMode ? Colors.amber.shade300 : Colors.lime.shade300)
                                  : (isDarkMode ? const Color(0xFFB4BFFF) : colorScheme.primary),
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
                              ? ((isSunday || isHoliday)
                                  ? (isDarkMode ? Colors.red.shade900 : Colors.red)
                                  : (isDarkMode ? Colors.white : colorScheme.onPrimary))
                              : dateColor,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
                if (memos.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 1.5.h,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: memos.take(3).map((memo) {
                        return Container(
                          width: double.infinity,
                          margin: EdgeInsets.only(bottom: 0.5.h),
                          padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
                          decoration: BoxDecoration(
                            color: isDarkMode ? colorScheme.primary.withOpacity(0.3) : colorScheme.surfaceVariant,
                            border: Border.all(
                              color: isDarkMode ? colorScheme.primary.withOpacity(0.5) : colorScheme.outline,
                              width: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                          child: Text(
                            memo,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 8.sp, color: colorScheme.onSurface, fontWeight: FontWeight.w500, height: 1.0),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 웹→앱 설치 funnel의 2단계("더 편하게 보기" 유도). 3단계(딥링크로 설치 후
  // 자동으로 친구 데이터까지 들어오는 것)는 스토어/딥링크 실배포가 필요해서
  // 지금은 스토어로만 연결하고, 최종 정리 문서에 딥링크 설정 방법을 남겨둠.
  Widget _buildInstallBanner(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '앱을 설치하면 내 근무표도 등록하고, 친구와 실시간으로 비교할 수 있어요',
              style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          SizedBox(width: 10.w),
          ElevatedButton(
            onPressed: widget.onInstallTap,
            style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h)),
            child: Text('앱 설치', style: TextStyle(fontSize: 12.sp)),
          ),
        ],
      ),
    );
  }

  void _showDaySheet(BuildContext context, DateTime day) {
    final shiftName = widget.data.getShiftForDate(day);
    final memos = widget.data.memosForDate(day);
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${day.month}월 ${day.day}일', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 10.h),
              Row(children: [
                Container(width: 12.w, height: 12.w, decoration: BoxDecoration(color: _shiftColor(shiftName), shape: BoxShape.circle)),
                SizedBox(width: 8.w),
                Text('근무: $shiftName', style: TextStyle(fontSize: 15.sp)),
              ]),
              if (memos.isNotEmpty) ...[
                SizedBox(height: 12.h),
                Text('메모', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline)),
                SizedBox(height: 4.h),
                ...memos.map((m) => Padding(
                  padding: EdgeInsets.only(bottom: 4.h),
                  child: Text('· $m', style: TextStyle(fontSize: 13.sp)),
                )),
              ],
            ],
          ),
        );
      },
    );
  }
}
