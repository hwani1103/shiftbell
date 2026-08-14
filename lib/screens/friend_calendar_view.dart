// screens/friend_calendar_view.dart
//
// ⭐ 친구 달력 보기 - 실제 달력탭(calendar_tab.dart)과 최대한 같은 톤(근무명
// 알약 배지 + 가운데 숫자)으로 만들되, 데이터는 Provider가 아니라 친구의
// FriendScheduleData(Firestore에서 받아온 최신 스케줄)에서만 읽음. 맨 위 배너로
// "지금 내 달력이 아니라 친구 달력을 보고 있다"는 걸 항상 인식시킴. 읽기 전용 -
// 근무 변경 등 편집 기능은 없음(애초에 공유 안 되는 정보이기도 함). 메모는
// 친구공유 v1에서 완전히 제외됨(친구공유_v1_스펙.md 참고).
//
// ⭐ 실제 그리드는 달력탭과 똑같이 table_calendar 패키지를 그대로 씀(전에는
// Column/Row를 직접 쌓은 정적 그리드라 좌우 스와이프가 아예 안 됐음) - 이걸로
// 달과 스와이프 넘김이 진짜 달력탭과 동일하게 동작하고, 셀 디자인(근무 배지 →
// 숫자 → 공휴일)도 _buildDateCell을 최대한 그대로 재현함.
// ⭐ rowHeight는 고정값이 아니라 LayoutBuilder로 매번 남는 높이만큼 계산함(6줄
// 강제(sixWeekMonthsEnforced)라 고정 rowHeight였을 때 짧은 뷰포트(웹뷰어가 특히
// 취약 - 방문자 브라우저 창 높이가 제각각)에서 TableCalendar 자체가 Expanded
// 영역을 넘쳐서 하단 설치 유도 배너와 겹쳐 보이던 문제의 근본 원인이었음).
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
      appBar: AppBar(title: Text('${widget.friendName}님의 교대 스케줄', style: TextStyle(fontSize: 17.sp))),
      // ⭐ 하단 SafeArea 없이 body를 바로 뒀더니 제스처 네비게이션 바/화면 하단
      // 곡면에 마지막 줄(6번째 주 또는 설치 유도 배너)이 잘리는 문제가 있었음 -
      // 실제 앱(main.dart 쪽 Scaffold들)은 전부 SafeArea 하위에서 그려지는데
      // 이 화면만 빠져 있었던 게 원인.
      body: SafeArea(
        child: Column(
          children: [
            // ⭐ 트랙1(웹)만 - PWA 설치 안내 배너. 트랙2(앱 내)는 "읽기 전용" 안내
            // 자체를 없애고(피드백: 뜬금없다) 그만큼 달력을 더 키움(아래 Padding/
            // Builder 쪽 targetCalendarHeight 비율 참고).
            if (widget.showInstallPrompt) _buildPwaInstallBanner(context),
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
            // ⭐ 100% 읽기 전용 - 트랙1(웹)/트랙2(앱) 둘 다 날짜 탭해도 아무 반응 없음
            // (예전엔 "근무: 휴무" 같은 작은 팝업이 떴는데 제거함, onDaySelected 자체를
            // 안 넘기면 TableCalendar가 탭을 그냥 무시함).
            //
            // ⭐ 트랙2(앱 내)는 Expanded로 남는 공간을 전부 채우면 달력이 화면 하단
            // (홈버튼 바로 위)까지 늘어져서 불편하다는 피드백 - 메모도 안 보이는 화면이라
            // 셀이 클 필요가 없음. 화면 높이의 절반 정도로 고정해서 "2026년 8월" 헤더가
            // ~20% 지점일 때 달력 하단이 ~70% 지점에서 끝나도록 함(남는 아래 공간은 그냥
            // 비워둠). 트랙1(웹)은 방문자 브라우저 창 높이가 제각각이라 기존처럼 남는
            // 공간을 다 쓰는 Expanded/LayoutBuilder 방식을 유지함.
            if (widget.showInstallPrompt)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const daysOfWeekHeight = 28.0;
                      final rowHeight = ((constraints.maxHeight - daysOfWeekHeight) / 6).clamp(48.0, 110.0);
                      return _buildTableCalendar(colorScheme, isDarkMode, rowHeight, daysOfWeekHeight);
                    },
                  ),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                child: Builder(
                  builder: (context) {
                    const daysOfWeekHeight = 28.0;
                    // ⭐ "읽기 전용" 배너를 없앤 만큼 + 추가 요청으로 비율을 0.5 → 0.58로
                    // 올림(위아래로 좀 더 크게).
                    final targetCalendarHeight = MediaQuery.of(context).size.height * 0.58;
                    final rowHeight = ((targetCalendarHeight - daysOfWeekHeight) / 6).clamp(40.0, 96.0);
                    return _buildTableCalendar(colorScheme, isDarkMode, rowHeight, daysOfWeekHeight);
                  },
                ),
              ),
            if (widget.showInstallPrompt) _buildInstallBanner(context),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  // ⭐ 트랙1(웹)/트랙2(앱) 둘 다 공유하는 TableCalendar 뼈대 - rowHeight 계산 방식만
  // 호출부(위 build())에서 다르게 넘겨줌.
  Widget _buildTableCalendar(
    ColorScheme colorScheme,
    bool isDarkMode,
    double rowHeight,
    double daysOfWeekHeight,
  ) {
    return TableCalendar(
      // ⭐ 달력탭과 동일한 범위 - 공유 코드는 "과거/미래 상관없이 스와이프해서
      // 둘러볼 수 있는" 하나의 스케줄이라 범위를 좁힐 이유가 없음.
      firstDay: DateTime(_today.year - 3, 1, 1),
      lastDay: DateTime(_today.year + 3, 12, 31),
      focusedDay: _focusedDay,
      locale: 'ko_KR',
      headerVisible: false,
      sixWeekMonthsEnforced: true,
      rowHeight: rowHeight,
      daysOfWeekHeight: daysOfWeekHeight,
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
      // ⭐ onDaySelected 없음 = 날짜 탭해도 아무 반응 없음(100% 읽기 전용, 예전
      // "근무: 휴무" 팝업 제거).
      onPageChanged: (focusedDay) {
        setState(() => _focusedDay = focusedDay);
      },
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

    final shouldHighlightToday = isToday && _focusedDay.year == day.year && _focusedDay.month == day.month;

    // ⭐ 트랙2(앱 내)만 - 달력 높이를 줄인 뒤로 근무명 뱃지가 상대적으로 두꺼워 보인다는
    // 피드백, 폰트 크기는 그대로 두고 배경 영역만 살짝 슬림하게. 트랙1(웹)은 원래
    // 비율이 괜찮다고 확인받아서 기존 18.h 그대로 유지.
    final badgeHeight = widget.showInstallPrompt ? 18.h : 14.h;

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
              height: badgeHeight,
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
            SizedBox(height: badgeHeight),

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
                    padding: EdgeInsets.zero,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 트랙1(웹)만 - PWA(홈 화면 설치) 안내. 원래 아이콘 + 2줄(설치 방법 + "안전하지
  // 않은 앱" 경고 대처법)이었는데, 그만큼 아래 달력이 눌려서 작아진다는 피드백으로
  // 아이콘 없애고 한 줄로 축소함 - "무시하고 설치" 설명은 뺐지만(공간 확보 우선),
  // 이 경고 자체는 우리 쪽에서 못 없애는 Android/Play Protect 동작이라는 사실은
  // 여전히 유효함(친구공유_v1_스펙.md 참고).
  Widget _buildPwaInstallBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Text(
        '홈 화면에서 바로 사용하려면 작업 표시줄의 설치 버튼을 눌러주세요.',
        style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade700, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
              '간편한 스케줄 등록 및 자동 알람 생성 앱',
              style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onPrimaryContainer),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
}
