import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:table_calendar/table_calendar.dart';
// ⭐ intl 패키지도 자체 TextDirection을 export해서 material의 TextDirection과
// 이름이 충돌함(_fitText의 TextPainter가 TextDirection.ltr을 쓰는데, 충돌 상태에서는
// intl 쪽 TextDirection이 우선시돼 .ltr getter가 없다는 컴파일 에러가 남) - hide로
// intl 쪽 TextDirection만 감춰서 material(dart:ui)의 TextDirection.ltr을 그대로 씀.
import 'package:intl/intl.dart' hide TextDirection;
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/shift_schedule.dart';
import '../models/alarm.dart';
import '../models/date_memo.dart';
import '../models/date_overtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../providers/memo_provider.dart';
import '../providers/overtime_provider.dart';
import '../providers/work_hours_settings_provider.dart';
import '../services/work_hours_calculator.dart';
import 'package:flutter/services.dart';
import '../constants/platform_channel.dart';
import 'all_shifts_view.dart';
import '../utils/holiday_util.dart';
import '../utils/weekday_util.dart';
import '../l10n/l10n_extensions.dart';
import '../constants/alarm_limits.dart';
import '../models/calendar_theme.dart';
import '../providers/calendar_theme_provider.dart';

// ⭐ 공휴일 판정 로직은 utils/holiday_util.dart로 이동함 (friend_calendar_view.dart도
// 똑같은 공휴일 표시가 필요해져서 공용화 - 두 파일 이름만 다르게 감싸서 기존 호출부
// (_getHolidayName(...))는 하나도 안 건드림).
// ⭐ 영어 현지화: 영어 로케일에서는 한국 고유 공휴일을 표시하지 않기로 결정됨
// (holiday_util.dart의 isKorean 파라미터 참고) - 호출부에서 현재 로케일을 넘겨줌.
String? _getHolidayName(DateTime date, BuildContext context) =>
    getHolidayName(date, isKorean: Localizations.localeOf(context).languageCode == 'ko');

// ⭐ 테마별 헤더/요일행 표기에 쓰는 공용 상수 - calendar_theme_lab_screen.dart의
// 동명 상수(그 파일 안에서만 쓰이는 private const)와 값은 같지만 별도 파일이라
// 충돌 없음.
// ⭐ 영어 현지화: 예전엔 여기 _weekdayKr(일/월/화...) 배열이 따로 있었지만,
// 로케일에 따라 바뀌어야 하는 요일 표시는 utils/weekday_util.dart의
// weekdayLabel(context, i)로 통일됨(사용부 참고) - 이 배열은 삭제. 아래
// _weekdayEn3/_weekdayEn1은 "그 테마 디자인 자체가 항상 영어 약자로 보이는"
// 의도적 스타일이라 로케일과 무관하게 그대로 둠.
const List<String> _weekdayEn3 = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const List<String> _weekdayEn1 = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const List<String> _monthEn3 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> _monthEnFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

// StatefulWidget → ConsumerStatefulWidget으로 변경
class CalendarTab extends ConsumerStatefulWidget {  // ⭐ 변경
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();  // ⭐ 변경
}

class _CalendarTabState extends ConsumerState<CalendarTab> {  // ⭐ 변경
  static const platform = kAlarmChannel;  // ⭐ 추가

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // ShiftSchedule? _schedule;  ⭐ 삭제 (Provider에서 가져올 것)

  bool _isMultiSelectMode = false;
  Set<DateTime> _selectedDates = {};

  // _loadSchedule() 메서드 삭제 (Provider가 자동으로 관리)
  
  // 색상 메서드는 그대로 유지
  // calendar_tab.dart의 _getShiftBackgroundColor() 함수 수정

// ⭐ 선택된 달력 테마의 확정 팔레트로 근무 색상을 계산함(models/calendar_theme.dart의
// assignShiftColorsForTheme - "휴무=고정 빨강, 나머지는 생성 순서대로 팔레트 배정"
// 규칙). ref.watch라 테마가 바뀌면 색도 즉시 다시 계산됨.
// ⭐ "비슷한 톤 테마끼리 근무 색상까지 똑같아서 차별점이 없다"는 지적으로
// 테마별 전용 팔레트/로테이션(assignShiftColorsForTheme)을 쓰도록 변경 -
// 예전엔 라이트/다크 두 팔레트만 있었지만 이제 테마마다(그룹별로) 다른
// 팔레트/시작 순서를 씀.
// ⭐ 2026-08-19 "근무명 색상 변경" 기능 복원 - 여기서 테마 디폴트 위에
// schedule.customShiftColors(사용자가 직접 고정한 색)를 덮어씀
// (effectiveShiftColors 참고) - 이래야 사용자가 색을 지정한 근무는 테마를
// 바꿔도 그 색 그대로 유지됨.
Map<String, Color> _shiftColorMap(ShiftSchedule? schedule) {
  if (schedule == null) return {};
  final theme = ref.watch(calendarThemeProvider);
  return effectiveShiftColors(schedule.shiftTypes, theme, schedule.customShiftColors);
}

Color _getShiftBackgroundColor(String shift, ShiftSchedule? schedule) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;

  // ⭐ "없음" 옵션 색상 (회색)
  if (shift == '없음') {
    return Theme.of(context).colorScheme.surfaceVariant;
  }

  final color = _shiftColorMap(schedule)[shift];
  if (color != null) return color;

  final colorScheme = Theme.of(context).colorScheme;
  return colorScheme.surfaceVariant;
}

  // calendar_tab.dart의 _getShiftTextColor() 함수 수정

Color _getShiftTextColor(String shift, ShiftSchedule? schedule) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;

  // ⭐ "없음" 옵션 텍스트 색상
  if (shift == '없음') {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  final color = _shiftColorMap(schedule)[shift];
  if (color != null) return ShiftSchedule.getTextColor(color);

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

  // ⭐ 1번 테마 전용 - 첫 번째 줄(0~6일째) 여부. _isSixthRow와 동일한 계산을
  // 위쪽 경계에 대해 적용함 - "맨 윗줄 근무명이랑 요일행 밑 구분선 사이에
  // 미세한 여백이 있다"는 지적을 고치기 위해, 첫 줄만 위쪽 패딩을 없애서
  // 뱃지가 구분선에 딱 붙게 함(lab 원본의 isFirstRow와 동일한 목적).
  bool _isFirstRow(DateTime day, DateTime focusedMonth) {
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysFromSunday = firstDayOfMonth.weekday == 7 ? 0 : firstDayOfMonth.weekday;
    final calendarStart = firstDayOfMonth.subtract(Duration(days: daysFromSunday));
    final daysDifference = day.difference(calendarStart).inDays;
    return daysDifference >= 0 && daysDifference < 7;
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
    // ⭐ 같은 범위로 OT도 같이 로드 (달력에 보이는 달 전체 커버)
    ref.read(overtimeProvider.notifier).loadForRange(firstDay, lastDay);
  }

  // ⭐ 4번 기능: 년/월 선택 다이얼로그
  void _showMonthYearPicker() {
    int selectedYear = _focusedDay.year;
    int selectedMonth = _focusedDay.month;

    // ⭐ 달력 초기화 범위 확인 (3년 전후)
    final minYear = DateTime.now().year - 3;
    final maxYear = DateTime.now().year + 3;

    // ⭐ 영어 현지화: '$year년'/'$month월' 조립은 로케일에 따라 표기가 달라져야 함
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final monthFormat = DateFormat.MMM(isKorean ? 'ko' : 'en');

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
                  Text(context.l10n.calendarSelectDate, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
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
                            isKorean ? '$selectedYear년' : '$selectedYear',
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
                                  isKorean ? '$month월' : monthFormat.format(DateTime(selectedYear, month)),
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
      body: Center(child: Text('${context.l10n.statusErrorOccurred}: $error')),
    ),
    data: (schedule) {
      if (schedule == null) {
        return Scaffold(
          body: Center(child: Text(context.l10n.statusNoSchedule)),
        );
      }
      final theme = ref.watch(calendarThemeProvider);
      final reclaimsSixthRow = _themeReclaimsSixthRow(theme);
      final isMainTheme = theme == CalendarThemeId.mainWhite || theme == CalendarThemeId.mainDark;

      return Scaffold(
        body: SafeArea(
          // ⭐⭐ "달력 테마 만들 때 가장 중요했던 전제 하나를 빼먹었다"는 지적 - lab에서
          // 맨 아래(네비게이션 바로 위)를 "테마 번호+설명" 고정 높이 띠로 항상
          // 남겨뒀던 건 나중에 애드몹 배너를 넣기 위해 일부러 비워둔 자리였는데,
          // 그 띠를 없앨 때 "용도"(광고 자리 확보)까지 같이 잊고 실제 달력탭에선
          // 그 공간을 전부 그리드로 덮어써버렸음. 메인·화이트/다크는 원래
          // rowHeight(83.h)가 고정값이라 우연히 이 공간이 자동으로 남아있었을
          // 뿐이고(별도로 챙긴 게 아니라 그냥 그 아래로 그릴 게 없어서 비어있던
          // 것), 나머지 7개 테마는 LayoutBuilder로 "남는 공간을 전부" 채우게
          // 고쳤던 게 오히려 이 자리까지 없애버린 원인이었음. 이제 바깥쪽에서
          // LayoutBuilder로 SafeArea 전체 높이를 재서, 메인 테마가 자연스럽게
          // 남기는 그 정확한 여백만큼을 모든 테마가 동일하게 확보하도록 함.
          child: LayoutBuilder(
            builder: (context, outerConstraints) {
              // ⭐ 메인 테마의 고정 레이아웃(헤더 48.h + 요일 28.h + 6줄*83.h)을
              // 기준으로 "그 외 남는 공간"을 계산 - 이게 바로 메인 테마가 항상
              // 자연스럽게 비워두던 애드몹 자리의 정확한 높이. 화면이 유난히
              // 작아 이 값이 음수가 나오는 극단적인 경우에만 0으로 방어.
              final adSpaceHeight = (outerConstraints.maxHeight - 48.h - 28.h - 83.h * 6).clamp(0.0, double.infinity);
              return Stack(
            children: [
              Container(
                // ⭐ "2번은 원래 배경색으로 흰 카드 셀들을 구분했었다"는 지적 -
                // lab이 페이지 전체를 옅은 회색으로 감쌌던 것을 그대로 재현.
                color: _themeBodyBackground(context, theme),
                child: Column(
                children: [
                  // ⭐ 헤더 영역 - 최소화
                  // ⭐ "헤더가 안 보인다"는 지적의 실제 원인 - 4번(굵은 격자형)은
                  // lab에서 어두운 배경(Color(0xFF263238)) 위에 흰 글씨로 디자인돼
                  // 있는데, 이 헤더 슬롯 자체는 배경색이 없어서(투명) 흰 글씨가
                  // 흰 배경 위에 그대로 겹쳐 안 보이는 문제였음 - 텍스트는 항상
                  // 있었지만 "흰 글씨 on 흰 배경"이라 안 보였던 것. 요일행
                  // (dowBuilder)은 이미 자기 배경을 스스로 그려서 문제 없었음.
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Container(
                      color: _themeHeaderBackground(theme),
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
                                        context.l10n.calendarNSelected(_selectedDates.length),
                                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  )
                                : _buildThemedHeaderTitle(theme),
                            if (!_isMultiSelectMode)
                              _buildThemedHeaderButtons(theme, schedule),
                          ],
                        ),
                      ),
                      ),
                    ),
                  ),

                  // ⭐ 달력 (하나의 TableCalendar, 6줄 고정) - Expanded+LayoutBuilder로
                  // 감싸서 헤더/푸터를 뺀 "실제로 남는 높이"를 직접 재고, 그 안에서
                  // 6등분한 값을 rowHeight로 씀(lab의 Expanded 6분할과 동일한 계산).
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final rowH = _themeRowHeight(theme, constraints.maxHeight);
                        return Stack(
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
                      locale: Localizations.localeOf(context).languageCode == 'ko' ? 'ko_KR' : 'en_US',

                      headerVisible: false,
                      sixWeekMonthsEnforced: true,  // ⭐ 항상 6줄 고정
                      rowHeight: rowH,

                      daysOfWeekHeight: 28.h,

                      calendarStyle: CalendarStyle(
                        cellMargin: EdgeInsets.all(0),
                        cellPadding: EdgeInsets.all(0),

                        // ⭐ "어떤 테마는 그리드가 아예 없고 가로줄만 있고 각자 다른데
                        // 결국 다 같은 격자 틀 안에서 그려진다"는 지적 - table_calendar가
                        // 셀마다 무조건 그려주던 격자선(tableBorder)을 메인·화이트/다크
                        // (원래부터 이 격자에 의존하던 디자인)에서만 켜고, 나머지 7개
                        // 테마는 각자 셀 위젯 자신이 이미 필요한 만큼만 테두리를 그리고
                        // 있으므로(1번=칸 왼쪽 얇은 선만, 2번=카드+그림자, 4번=칸마다
                        // 굵은 테두리, 5번=둥근 테두리, 8/9번=테두리 없음, 10번=칸마다
                        // 얇은 테두리) table_calendar 쪽 격자는 완전히 꺼서 이중으로
                        // 그려지거나 안 어울리는 격자가 겹치지 않게 함.
                        tableBorder: (theme == CalendarThemeId.mainWhite || theme == CalendarThemeId.mainDark)
                            ? TableBorder.all(
                                color: Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)  // 다크모드: 더 밝게
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.15),  // 화이트모드: 더 진하게
                                width: 1.0,
                              )
                            : const TableBorder(),

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
                        // ⭐ "그리드/요일 표기까지 테마마다 다 다르게 만들어놓고 실제로는
                        // 그 틀 안에서만 그린다"는 지적 - 요일 헤더 표기(일/월/... vs
                        // Sun/Mon/... vs S/M/...)도 테마별로 다르므로 daysOfWeekStyle(같은
                        // 로케일 문구에 스타일만 입히는 것) 대신 dowBuilder로 완전히
                        // 테마마다 다른 위젯을 그림.
                        dowBuilder: (context, day) => _buildThemedDow(theme, day),
                        // ⭐ 여기 4개 콜백만 _buildDateCell → _buildThemedCell로 교체함 -
                        // 선택된 테마에 따라 셀 디자인을 바꿔주는 유일한 진입점.
                        // onDaySelected/onDayLongPressed 등 나머지 로직은 전혀 안 건드림.
                        defaultBuilder: (context, day, focusedDay) {
                          // ⭐ 6번째 줄 화~토는 빈 Container (범례/OT 카드가 그 자리를
                          // 대신 차지하는 테마에서만 - 아래 reclaimsSixthRow 참고)
                          if (reclaimsSixthRow && _isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          return _buildThemedCell(day, false, false, schedule, focusedDay);
                        },
                        outsideBuilder: (context, day, focusedDay) {
                          if (reclaimsSixthRow && _isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          return _buildThemedCell(day, false, true, schedule, focusedDay);
                        },
                        todayBuilder: (context, day, focusedDay) {
                          if (reclaimsSixthRow && _isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          // ⭐ 위 _buildThemedCell 주석과 동일한 이유로, "오늘이 지금 이
                          // 페이지 기준 바깥달 날짜인가"도 상태(_focusedDay)가 아니라 이
                          // 콜백이 실제로 받은 focusedDay(그 페이지가 나타내는 달) 기준으로.
                          final isOutsideMonth = day.month != focusedDay.month || day.year != focusedDay.year;
                          return _buildThemedCell(day, true, isOutsideMonth, schedule, focusedDay);
                        },
                        selectedBuilder: (context, day, focusedDay) {
                          if (reclaimsSixthRow && _isSixthRowEmptyCell(day, focusedDay)) {
                            return Container();
                          }
                          return _buildThemedCell(day, isSameDay(day, DateTime.now()), false, schedule, focusedDay, isSelected: true);
                        },
                      ),

                      onDaySelected: (selectedDay, focusedDay) {
                        // ⭐ 이전/다음 달 날짜는 탭 무시
                        if (selectedDay.month != _focusedDay.month || selectedDay.year != _focusedDay.year) {
                          return;
                        }

                        // ⭐ 6번째 줄 빈 칸은 탭 무시 (범례/OT 카드가 있는 테마만)
                        if (reclaimsSixthRow && _isSixthRowEmptyCell(selectedDay, focusedDay)) {
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

                        // ⭐ 6번째 줄 빈 칸은 길게 누르기 무시 (범례/OT 카드가 있는 테마만)
                        if (reclaimsSixthRow && _isSixthRowEmptyCell(selectedDay, focusedDay)) {
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

                      // ⭐ 6번째 줄 화~토 (원래 빈 공간이었던 곳) - 이 자리를 재활용하는
                      // 테마(메인·화이트/다크 = OT/주별근무시간 카드, 8/10번 = 범례)만
                      // 그려줌. 나머지 7개 테마는 6번째 줄도 그냥 평범한 다음 달
                      // 스필오버 날짜로 실제로 보여줌(재활용 안 함 - reclaimsSixthRow=false).
                      if (reclaimsSixthRow)
                        Positioned(
                          top: 28.h + rowH * 5,  // 요일 헤더 + 5줄
                          left: 6.w,
                          right: 6.w,
                          height: rowH,
                          child: Row(
                            children: [
                              // 일요일 + 월요일 칸 (다음 달 날짜 표시 - 제스처를 아래 TableCalendar로 전달)
                              Expanded(
                                flex: 2,
                                child: IgnorePointer(child: SizedBox()),
                              ),
                              // 화~토 칸 - 테마에 따라 월별 OT 카드 또는 범례
                              Expanded(
                                flex: 5,
                                child: (theme == CalendarThemeId.mainWhite || theme == CalendarThemeId.mainDark)
                                    ? _buildMonthlyOvertimeCard()
                                    : _buildThemedLegend(theme, schedule),
                              ),
                            ],
                          ),
                        ),
                      // ⭐ "맨 아랫줄은 가로줄이 없어서 부자연스럽다"는 지적 - 1번은
                      // 세로선(칸 왼쪽 테두리)만 있고 가로선은 요일행 밑 구분선
                      // 하나뿐이라, 그리드 맨 밑을 닫아주는 선이 없어 어색해
                      // 보였음. 요일행 밑 구분선과 같은 톤으로 6번째 줄 맨
                      // 밑에도 하나 그어서 사각형 그리드처럼 딱 닫히게 함.
                      if (theme == CalendarThemeId.minimal)
                        Positioned(
                          top: 28.h + rowH * 6 - 1,
                          left: 6.w,
                          right: 6.w,
                          height: 1,
                          child: Container(color: Colors.grey.shade200),
                        ),
                    ],
                        );
                      },
                    ),
                  ),
                  // ⭐ "OT/주별 근무시간까지 테마마다 디자인이 다 다르게 만들어놓고
                  // 실제 반영 시엔 그대로 안 썼다"는 지적 - 6번째 줄을 재활용하지
                  // 않는 7개 테마는 그 정보를 달력 그리드 아래 별도 푸터 바로 보여줌
                  // (각 테마 실험판의 원래 디자인 그대로, 실제 데이터로).
                  if (_themeHasSeparateFooter(theme))
                    _buildThemedFooter(theme, schedule),
                  // ⭐ 애드몹 자리 확보 - 메인 테마는 고정 rowHeight(83.h)라 이 공간이
                  // 이미 자연스럽게 비어있으므로(SizedBox 안 넣어도 그냥 안 채워짐)
                  // 여기서는 나머지 7개 테마에만 명시적으로 같은 높이만큼 비워줌.
                  if (!isMainTheme) SizedBox(height: adSpaceHeight),
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
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(context.l10n.shiftChange, style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(context.l10n.calendarTapToAddMoreDates, style: TextStyle(fontSize: 10.sp)),
                        ],
                      ),
                      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      elevation: 3,
                    ),
                  ),
                ),
            ],
              );
            },
          ),
        ),
      );
    },
  );
}

  // ⭐ 6번째 줄 빈 공간에 들어가는 카드 - 위 절반 "이번 달 OT" / 아래 절반
  // "주별 근무시간"으로 나눔 (각각 독립적으로 탭하면 다른 팝업이 뜸).
  Widget _buildMonthlyOvertimeCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer(
      builder: (context, ref, child) {
        final otByDate = ref.watch(overtimeProvider); // 값 바뀌면 다시 그리기 위한 구독
        final workSettings = ref.watch(workHoursSettingsProvider);
        final schedule = ref.watch(scheduleProvider).value;
        final period = workSettings.periodForMonth(_focusedDay);
        // ⭐ "이번 달 OT"는 수동 OT + (설정 켜져 있으면) 근무변경으로 늘어난 시간까지
        // 합친 값 - 월별/주별 "총 근무시간" 계산과는 완전히 별개(그쪽은 안 바뀜).
        final totalMinutes = schedule == null
            ? 0
            : computeOtDisplayTotal(computeOtDisplayEntries(
                schedule: schedule,
                start: period.start,
                end: period.end,
                manualOtByDate: otByDate,
                countShiftChangeAsOt: workSettings.shiftChangeCountsAsOt,
              ));
        final hasOvertime = totalMinutes > 0;

        // ⭐ 안쪽에 칸을 나누는 grid 느낌 없이, 5칸 전체를 감싸는 테두리 하나짜리
        // 가로로 긴 직사각형 하나로. 이 영역에서도 좌우 스와이프로 월 이동 가능하게 함
        // (탭하면 팝업, 스와이프하면 달력 자체를 스와이프한 것과 동일하게 월 이동).
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity;
            if (velocity == null) return;
            if (velocity < -300) {
              _changeMonthBySwipe(1); // 왼쪽으로 스와이프 → 다음 달
            } else if (velocity > 300) {
              _changeMonthBySwipe(-1); // 오른쪽으로 스와이프 → 이전 달
            }
          },
          child: Container(
            // ⭐ 배경을 불투명하게: 반투명(withOpacity)이면 아래 TableCalendar의
            // 격자 테두리 선이 카드 밑으로 그대로 비쳐 보임 (세로줄이 무시된 채로
            // 글씨만 그 위에 그려지는 것처럼 보이는 원인이었음)
            decoration: BoxDecoration(
              color: isDark ? colorScheme.surface : colorScheme.surfaceVariant,
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.4),
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                // ⭐ 위 절반: 이번 달 OT
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showMonthlyOvertimeSheet(period),
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.l10n.shiftThisMonthOt,
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              hasOvertime ? formatOvertimeMinutes(context, totalMinutes) : context.l10n.calendarTapDateToEnter,
                              style: TextStyle(
                                fontSize: hasOvertime ? 13.sp : 11.sp,
                                fontWeight: hasOvertime ? FontWeight.bold : FontWeight.w600,
                                color: hasOvertime ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // ⭐ 두 영역이 나뉘어있음을 시각적으로 인지되게 하는 구분선
                Container(height: 1, color: colorScheme.outline.withOpacity(0.3)),
                // ⭐ 아래 절반: 주별 근무시간 (색을 살짝 다르게 줘서 구분감을 한 번 더 줌)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showWeeklyWorkHoursSheet,
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      color: isDark
                          ? colorScheme.surfaceVariant.withOpacity(0.25)
                          : colorScheme.surface.withOpacity(0.5),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.l10n.shiftWeeklyWorkHours,
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            SizedBox(width: 4.w),
                            Icon(Icons.chevron_right, size: 14.sp, color: colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
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

  // ⭐ 이번 달 누적 OT 카드에서의 좌우 스와이프 → 달력 자체를 스와이프한 것과
  // 동일하게 월 이동 (onPageChanged와 동일한 처리)
  void _changeMonthBySwipe(int direction) {
    final newMonth = DateTime(_focusedDay.year, _focusedDay.month + direction, 1);
    setState(() {
      _focusedDay = newMonth;
    });
    _loadMemosForMonth(newMonth);
  }

  // ⭐ 이번 달 OT 상세 목록 시트 (기준 기간은 달력 월 기준일 수도, 급여일 기준일
  // 수도 있음 - work_hours_settings_provider의 periodForMonth()가 결정)
  void _showMonthlyOvertimeSheet(DateTimeRange period) {
    // ⭐ 영어 현지화: '$month월' 조립 대신 로케일 인식 월 이름(예: "8월" / "August")
    final monthLabel = DateFormat.MMMM(Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en').format(_focusedDay);

    // ⭐ 급여일 기준 기간은 달력에 보이는 달 범위보다 넓거나 다를 수 있어서
    // 팝업을 열기 전에 그 기간을 명시적으로 로드해 캐시 누락을 방지함
    ref.read(overtimeProvider.notifier).loadForRange(period.start, period.end);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final otByDate = ref.watch(overtimeProvider);
            final schedule = ref.watch(scheduleProvider).value;
            final workSettings = ref.watch(workHoursSettingsProvider);
            // ⭐ "이번 달 OT" 목록/합계 = 수동 OT + (설정 켜져 있으면) 근무변경으로
            // 늘어난 시간. "총 근무(예정) 시간 합산"(아래)은 이 값과 무관하게 항상
            // 그대로(중복 합산 없음).
            final entries = schedule == null
                ? <OtDisplayEntry>[]
                : computeOtDisplayEntries(
                    schedule: schedule,
                    start: period.start,
                    end: period.end,
                    manualOtByDate: otByDate,
                    countShiftChangeAsOt: workSettings.shiftChangeCountsAsOt,
                  );
            final totalMinutes = computeOtDisplayTotal(entries);
            final periodLabel = workSettings.periodLabel(_focusedDay, isKorean: Localizations.localeOf(context).languageCode == 'ko');
            final colorScheme = Theme.of(context).colorScheme;
            final totalWorkMinutes = schedule == null
                ? 0
                : computeTotalWorkMinutes(
                    schedule: schedule,
                    start: period.start,
                    end: period.end,
                    otByDate: otByDate,
                  );

            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 핸들
                      Center(
                        child: Container(
                          width: 40.w,
                          height: 4.h,
                          decoration: BoxDecoration(
                            color: colorScheme.outline,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                      ),
                      SizedBox(height: 16.h),

                      Text(
                        context.l10n.calendarMonthlyOtTitle(monthLabel),
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '($periodLabel)',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        context.l10n.calendarOtTotal(formatOvertimeMinutes(context, totalMinutes)),
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        context.l10n.calendarMonthlyWorkTotal(monthLabel, formatOvertimeMinutes(context, totalWorkMinutes)),
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      // ⭐ 근무카드에 근무시간이 하나도 설정 안 돼 있으면 위 합산은
                      // 사실상 OT만 반영된 값 - 오해 없게 안내 문구를 추가함
                      if (schedule != null && !schedule.hasAnyWorkDuration) ...[
                        SizedBox(height: 2.h),
                        Text(
                          context.l10n.calendarSetWorkHoursInSettingsHint,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      SizedBox(height: 16.h),

                      Expanded(
                        child: entries.isEmpty
                            ? Center(
                                child: Text(
                                  context.l10n.calendarNoOtRegistered,
                                  style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: entries.length,
                                separatorBuilder: (_, __) => SizedBox(height: 8.h),
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  final date = entry.date;
                                  final weekdayStr = _getWeekday(date, context);

                                  // ⭐ 근무변경으로 늘어난 시간이 있으면 "휴무 → 주간 (12시간)"
                                  // 부제목 추가, 수동 OT까지 있으면 옆에 "OT 3시간"도 같이 표기
                                  // (우측 총합은 항상 entry.totalMinutes = 이 둘의 합)
                                  final hasManual = entry.hasImplied && entry.manualMinutes > 0;
                                  final shiftChangeLabel = entry.hasImplied
                                      ? '${entry.fromShift} → ${entry.toShift} (${formatOvertimeMinutes(context, entry.impliedMinutes)})${hasManual ? ',' : ''}'
                                      : null;
                                  final manualLabel = hasManual
                                      ? '+ OT ${formatOvertimeMinutes(context, entry.manualMinutes)}'
                                      : null;

                                  return Container(
                                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceVariant.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(10.r),
                                      border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '${DateFormat.MMMd(Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en').format(date)} ($weekdayStr)',
                                              style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurface),
                                            ),
                                            Spacer(),
                                            Text(
                                              formatOvertimeMinutes(context, entry.totalMinutes),
                                              style: TextStyle(
                                                fontSize: 14.sp,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (shiftChangeLabel != null) ...[
                                          SizedBox(height: 4.h),
                                          Row(
                                            children: [
                                              Text(
                                                shiftChangeLabel,
                                                style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant),
                                              ),
                                              if (manualLabel != null) ...[
                                                SizedBox(width: 10.w),
                                                Text(
                                                  manualLabel,
                                                  style: TextStyle(
                                                    fontSize: 12.sp,
                                                    fontWeight: FontWeight.w600,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ⭐ 주별(항상 월~일) 누적 근무시간 시트. 급여 산정일 기준 설정과 무관하게
  // 항상 달력 월요일~일요일 기준이며, OT와 근무일 변경(assignedDates)도 반영됨.
  void _showWeeklyWorkHoursSheet() {
    // ⭐ 영어 현지화: '$month월' 조립 대신 로케일 인식 월 이름
    final monthLabel = DateFormat.MMMM(Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en').format(_focusedDay);
    final weeks = weeksCoveringMonth(_focusedDay);
    final rangeStart = weeks.first.start;
    final rangeEnd = weeks.last.end;

    // ⭐ 이 시트가 보여주는 범위(월 앞뒤로 걸친 주 포함)를 명시적으로 로드
    ref.read(overtimeProvider.notifier).loadForRange(rangeStart, rangeEnd);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final otByDate = ref.watch(overtimeProvider);
            final schedule = ref.watch(scheduleProvider).value;
            final colorScheme = Theme.of(context).colorScheme;

            final summaries = schedule == null
                ? <WeekWorkSummary>[]
                : weeks
                    .map((w) => computeWeekSummary(
                          schedule: schedule,
                          weekStart: w.start,
                          weekEnd: w.end,
                          otByDate: otByDate,
                        ))
                    .toList();
            // ⭐ 여기 "OT 몇시간"은 수동 OT만 표시함(의도적) - 근무변경으로 늘어난
            // 시간은 이미 위의 "주간 3일, 휴무 3일..." 근무별 일수 나열에 그 변경된
            // 근무 그대로 반영되어 있어서, 여기에 또 더해서 보여주면 이중으로 잡힌
            // 것처럼 보임 ("이번 달 OT" 목록/카드와는 다른 판단 - 거긴 근무별 일수
            // 나열이 없어서 명시적으로 보여줘야 함).

            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 핸들
                      Center(
                        child: Container(
                          width: 40.w,
                          height: 4.h,
                          decoration: BoxDecoration(
                            color: colorScheme.outline,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                      ),
                      SizedBox(height: 16.h),

                      Text(
                        context.l10n.calendarWeeklyWorkHoursTitle(monthLabel),
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        context.l10n.calendarWeeklyBasisHint,
                        style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant),
                      ),
                      SizedBox(height: 16.h),

                      Expanded(
                        child: schedule == null
                            ? Center(
                                child: Text(
                                  context.l10n.calendarSetScheduleFirst,
                                  style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            // ⭐ 근무카드에 근무시간이 하나도 설정 안 돼 있으면 누적할
                            // 근거가 없으므로 (전부 0시간) 리스트 대신 설정 안내만 보여줌
                            : !schedule.hasAnyWorkDuration
                            ? Center(
                                child: Text(
                                  context.l10n.calendarSpecifyWorkHoursInSettings,
                                  style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: summaries.length,
                                separatorBuilder: (_, __) => SizedBox(height: 8.h),
                                itemBuilder: (context, index) {
                                  final s = summaries[index];

                                  // ⭐ "주간 2일, 야간 3일, ..." 형태로 근무명별 일수 나열
                                  // (일수가 많은 순 → 이름 가나다순으로 안정적인 정렬)
                                  final countEntries = s.shiftDayCounts.entries.toList()
                                    ..sort((a, b) {
                                      final byCount = b.value.compareTo(a.value);
                                      return byCount != 0 ? byCount : a.key.compareTo(b.key);
                                    });
                                  final countsStr =
                                      countEntries.map((e) => context.l10n.calendarShiftDayCount(e.key, e.value)).join(', ');
                                  final otSuffix = s.otMinutes > 0
                                      ? ', OT ${formatOvertimeMinutes(context, s.otMinutes)}'
                                      : '';

                                  return Container(
                                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceVariant.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(10.r),
                                      border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '${s.start.month}/${s.start.day} ~ ${s.end.month}/${s.end.day}',
                                              style: TextStyle(
                                                fontSize: 14.sp,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                            Spacer(),
                                            Text(
                                              formatOvertimeMinutes(context, s.totalMinutes),
                                              style: TextStyle(
                                                fontSize: 14.sp,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (countsStr.isNotEmpty) ...[
                                          SizedBox(height: 4.h),
                                          Text(
                                            '$countsStr$otSuffix',
                                            style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ⭐ 달력 팝업 헤더에 들어가는 OT 30분 토글 컨트롤
  Widget _buildOvertimeToggle(String dateStr) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer(
      builder: (context, ref, child) {
        ref.watch(overtimeProvider);
        final notifier = ref.read(overtimeProvider.notifier);
        final minutes = notifier.getForDate(dateStr);
        final hasOvertime = minutes > 0;

        // ⭐ 시간 텍스트는 버튼 두 줄(OT 라벨 제외) 사이 수직 중앙에, OT 라벨은 그
        // 버튼 두 줄(폭이 서로 같음) 가로 중앙 위에 오도록 배치. 전체적으로 간격을
        // 최대한 줄여서(6h→4h, 4h→2h) 버튼이 한 줄 늘어난 만큼 날짜 줄이 아래로
        // 밀리는 걸 최소화함.
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              hasOvertime ? formatOvertimeMinutes(context, minutes) : context.l10n.commonNone,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
                color: hasOvertime ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: 8.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'OT',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 4.h),
                // 1시간 단위 (위, 큰 아이콘)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildOvertimeStepButton(
                      icon: Icons.remove_rounded,
                      enabled: hasOvertime,
                      size: 26.w,
                      iconSize: 20.sp,
                      onTap: () => notifier.adjust(dateStr, -60),
                    ),
                    SizedBox(width: 6.w),
                    _buildOvertimeStepButton(
                      icon: Icons.add_rounded,
                      enabled: true,
                      size: 26.w,
                      iconSize: 20.sp,
                      onTap: () => notifier.adjust(dateStr, 60),
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                // 30분 단위 (아래, 작은 아이콘)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildOvertimeStepButton(
                      icon: Icons.remove_rounded,
                      enabled: hasOvertime,
                      size: 26.w,
                      iconSize: 13.sp,
                      onTap: () => notifier.adjust(dateStr, -30),
                    ),
                    SizedBox(width: 6.w),
                    _buildOvertimeStepButton(
                      icon: Icons.add_rounded,
                      enabled: true,
                      size: 26.w,
                      iconSize: 13.sp,
                      onTap: () => notifier.adjust(dateStr, 30),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildOvertimeStepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required double size,
    required double iconSize,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: enabled ? colorScheme.secondaryContainer : colorScheme.surfaceVariant.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: enabled ? colorScheme.onSecondaryContainer : colorScheme.outline,
        ),
      ),
    );
  }

  // ============================================================
  // ⭐ 테마별 화면 구성(헤더/요일행/6번째 줄 재활용 여부/그리드 높이/푸터) -
  // "셀 디자인만 바뀌고 나머지는 예전 메인 달력 틀 그대로 그려진다"는 지적을
  // 반영해서, 셀뿐 아니라 화면 전체 구성 요소를 테마별로 분기함. 단, 날짜 탭/
  // 길게 누르기/월 스와이프/팝업 등 상호작용 로직 자체(TableCalendar의
  // onDaySelected 등)는 여기서 전혀 건드리지 않음 - build()의 TableCalendar는
  // 그대로 하나만 쓰고, 이 함수들은 그 주변 위젯(헤더/요일행/6번째 줄/푸터)만
  // 테마에 맞게 다시 그려줌.
  // ============================================================

  // ⭐ 6번째 줄(화~토 5칸)을 OT카드/범례로 재활용하는 테마 - 메인 화이트/다크는
  // OT+주별근무시간 카드, 8/10번은 범례(색상만으로 근무를 구분하는 테마라
  // 범례가 필수). 나머지 7개 테마는 재활용하지 않고 6번째 줄도 평범하게 다음
  // 달 스필오버 날짜를 그대로 보여줌(대신 OT/주별근무시간은 아래 별도 푸터로).
  bool _themeReclaimsSixthRow(CalendarThemeId t) =>
      t == CalendarThemeId.mainWhite || t == CalendarThemeId.mainDark ||
      t == CalendarThemeId.underline || t == CalendarThemeId.editorial;

  // ⭐ "왜 5번만 이렇게 고생하냐, 다른 테마처럼 그리드에 맞게 미리 고정된
  // 적절한 크기로 만들어야지, lab에서 테스트한 디자인 그대로 100% 똑같이
  // 적용하라"는 지적 - 근본 원인은 75.h라는 값을 감으로 고정해서 쓴 것.
  // lab(calendar_theme_lab_screen.dart)의 7개 실험 테마는 전부 6줄을
  // Expanded로 감싸서 "화면에서 남는 공간을 6등분"하는 방식이라, 실제로
  // 받는 한 줄 높이가 기기/헤더/푸터 구성에 따라 자동으로 달라짐 - 그런데
  // 실제 달력탭에서는 table_calendar가 rowHeight를 픽셀 고정값으로 미리
  // 알아야 해서 75.h라는 값 하나를 임의로 못박아 썼던 게 문제였음(테마마다
  // 헤더/푸터 실제 높이가 달라서 딱 맞을 수가 없음). 그래서 이제 감으로
  // 고정하는 대신, build()에서 LayoutBuilder로 "헤더/푸터를 제외하고 실제로
  // 남는 높이"를 직접 재서 6등분함 - lab의 Expanded와 정확히 같은 계산을
  // 그대로 재현하는 것이라 헤더/푸터가 몇 픽셀이든 항상 6줄이 딱 맞게 꽉
  // 채워짐(더 이상 "남는 빈 공간"이 생기지 않음). 메인 화이트/다크만 예외 -
  // 이미 실기기에서 검증 끝난 고정 83.h 그대로 유지(건드리지 않음).
  double _themeRowHeight(CalendarThemeId t, double availableHeight) {
    if (t == CalendarThemeId.mainWhite || t == CalendarThemeId.mainDark) return 83.h;
    return (availableHeight - 28.h) / 6; // 28.h = daysOfWeekHeight
  }

  bool _themeHasSeparateFooter(CalendarThemeId t) =>
      t != CalendarThemeId.mainWhite && t != CalendarThemeId.mainDark;

  // ⭐ 헤더 슬롯 배경색 - 4번(굵은 격자형)만 어두운 배경 위에 흰 글씨로 디자인돼
  // 있어서 필요함. 나머지는 전부 null(투명, 흰 페이지 배경 그대로).
  Color? _themeHeaderBackground(CalendarThemeId t) =>
      t == CalendarThemeId.boldGrid ? const Color(0xFF263238) : null;

  // ⭐ "2번(머티리얼 카드형) 셀 테두리가 거의 없다시피 한데, 원래는 테두리 대신
  // 배경색으로 흰 카드들을 구분했었다"는 지적 - lab의 2번 페이지는 실제로
  // Container(color: Color(0xFFF7F7FA), ...)로 페이지 전체를 옅은 회색으로
  // 감쌌었는데, 실제 달력탭으로 옮길 때 셀 디자인만 챙기고 이 배경은 안
  // 옮겼었음. "이번 달 OT/주별 근무시간" 카드 배경색(colorScheme.
  // surfaceVariant)보다 더 연한 톤으로, 흰 카드형 셀들이 그 위에서 자연스럽게
  // 도드라져 보이게 함. 다른 테마는 전부 null(기존처럼 흰 배경 그대로).
  // ⭐ 고정색 0xFFE4E8F5가 "너무 부담스럽게 진하다"는 재지적 - 그 진한 고정색과
  // 그 이전 단계(연한 lerp) 딱 중간 톤으로 조정.
  Color? _themeBodyBackground(BuildContext context, CalendarThemeId t) {
    if (t != CalendarThemeId.materialCard) return null;
    return const Color(0xFFF5F6FB); // "조금 더 연하게" 재지적 - EEF0F9보다 밝게
  }

  // ⭐ "전체근무표"/"오늘" 버튼은 테마마다 디자인(위치/모양)만 다르고 실제
  // 동작은 항상 동일 - 진짜 이동 로직을 한 곳에 모아 모든 테마 헤더가 공유함.
  void _openAllShiftsView() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AllShiftsView()));
  }

  void _jumpToToday() {
    setState(() {
      _focusedDay = DateTime.now();
      _selectedDay = null;
    });
  }

  // ⭐ 이번 달 OT 합계 - _buildMonthlyOvertimeCard()와 완전히 같은 계산식(수동
  // OT + (설정 켜져 있으면) 근무변경으로 늘어난 시간). 테마별 푸터들이 전부
  // 이 값 하나를 공유해서 씀.
  ({int totalMinutes, DateTimeRange period}) _monthlyOtSummary(ShiftSchedule schedule) {
    final otByDate = ref.watch(overtimeProvider);
    final workSettings = ref.watch(workHoursSettingsProvider);
    final period = workSettings.periodForMonth(_focusedDay);
    final totalMinutes = computeOtDisplayTotal(computeOtDisplayEntries(
      schedule: schedule,
      start: period.start,
      end: period.end,
      manualOtByDate: otByDate,
      countShiftChangeAsOt: workSettings.shiftChangeCountsAsOt,
    ));
    return (totalMinutes: totalMinutes, period: period);
  }

  // ⭐ 헤더 좌측 "년/월" 타이틀 - calendar_theme_lab_screen.dart의 각 테마
  // 헤더 타이포를 그대로 이식(테마마다 표기 형식 자체가 다름: "Aug 2026" /
  // "8월 2026" / "2026-08" / "2026.08" / "AUGUST 2026" / "2026. 8" /
  // "August 2026" / "2026년 8월"). 탭하면 항상 동일하게 _showMonthYearPicker
  // (기존 년/월 선택 다이얼로그)를 씀 - 디자인만 다르고 동작은 그대로.
  Widget _buildThemedHeaderTitle(CalendarThemeId theme) {
    final y = _focusedDay.year;
    final m = _focusedDay.month;
    // ⭐ 영어 현지화: '$m월'/'$y년 $m월' 같은 Korean-particle 조립은 로케일에
    // 따라 표기가 달라져야 함 - materialCard/mainWhite/mainDark에서 사용.
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final shortMonthLabel = DateFormat.MMM(isKorean ? 'ko' : 'en').format(_focusedDay);
    switch (theme) {
      case CalendarThemeId.minimal:
        return GestureDetector(onTap: _showMonthYearPicker, child: Text('${_monthEn3[m - 1]} $y', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w600, color: Colors.black87)));
      case CalendarThemeId.materialCard:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(shortMonthLabel, style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w300, color: Colors.black87)),
            SizedBox(width: 6.w),
            Padding(padding: EdgeInsets.only(bottom: 2.h), child: Text('$y', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400))),
          ]),
        );
      case CalendarThemeId.boldGrid:
        return GestureDetector(onTap: _showMonthYearPicker, child: Text('$y-${m.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace')));
      case CalendarThemeId.initialBadge:
        return GestureDetector(onTap: _showMonthYearPicker, child: Text('$y.${m.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.black87)));
      case CalendarThemeId.underline:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_monthEn3[m - 1].toUpperCase(), style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Colors.black87)),
            SizedBox(width: 6.w),
            // ⭐ "2026 년도가 잘 안 보인다"는 지적으로 아주 살짝만 진하게(shade400→shade500).
            Text('$y', style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade500, letterSpacing: 1)),
          ]),
        );
      case CalendarThemeId.eventChip:
        return GestureDetector(onTap: _showMonthYearPicker, child: Text('$y. $m', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.black87)));
      case CalendarThemeId.editorial:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_monthEnFull[m - 1], style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700, fontFamily: 'serif', color: Colors.black87)),
            SizedBox(width: 8.w),
            // ⭐ "2026 등 텍스트를 아주 약간만 더 진하게" - shade500 → shade600.
            Padding(padding: EdgeInsets.only(bottom: 3.h), child: Text('$y', style: TextStyle(fontSize: 12.sp, fontFamily: 'serif', color: Colors.grey.shade600))),
          ]),
        );
      case CalendarThemeId.mainWhite:
      case CalendarThemeId.mainDark:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(isKorean ? '$y년 $m월' : DateFormat.yMMMM('en').format(_focusedDay), style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            SizedBox(width: 4.w),
            Icon(Icons.arrow_drop_down, size: 24.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
        );
    }
  }

  // ⭐ 헤더 우측 "전체근무표"/"오늘" 버튼 - 규칙적 근무자만 전체근무표 노출
  // (기존 게이트 schedule.isRegular 그대로 유지). 버튼 모양은 테마마다
  // 완전히 다르지만(텍스트만/아이콘 버튼/알약형/텍스트+밑줄 등) onTap은
  // 항상 _openAllShiftsView/_jumpToToday로 동일.
  Widget _buildThemedHeaderButtons(CalendarThemeId theme, ShiftSchedule schedule) {
    final showAllShifts = schedule.isRegular;
    switch (theme) {
      case CalendarThemeId.minimal:
        return Row(children: [
          if (showAllShifts) ...[_thinTextButton(context.l10n.shiftFullSchedule, _openAllShiftsView), SizedBox(width: 12.w)],
          _thinTextButton('Today', _jumpToToday),
        ]);
      case CalendarThemeId.materialCard:
        return Row(children: [
          if (showAllShifts) ...[_roundIconButton(Icons.grid_view_rounded, _openAllShiftsView), SizedBox(width: 8.w)],
          _roundIconButton(Icons.today_rounded, _jumpToToday),
        ]);
      case CalendarThemeId.boldGrid:
        return Row(children: [
          if (showAllShifts) ...[_gridHeaderBtn(context.l10n.shiftFullSchedule, _openAllShiftsView), SizedBox(width: 8.w)],
          _gridHeaderBtn('TODAY', _jumpToToday),
        ]);
      case CalendarThemeId.initialBadge:
        return Row(children: [
          if (showAllShifts) ...[_pillButton(context.l10n.shiftFullSchedule, Icons.table_chart_outlined, _openAllShiftsView), SizedBox(width: 6.w)],
          _pillButton(context.l10n.commonToday, Icons.adjust, _jumpToToday),
        ]);
      case CalendarThemeId.underline:
        return Row(children: [
          GestureDetector(onTap: _jumpToToday, child: Text('TODAY', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 0.5))),
          if (showAllShifts) ...[
            SizedBox(width: 12.w),
            GestureDetector(onTap: _openAllShiftsView, child: Text(context.l10n.shiftFullSchedule, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: Colors.black54))),
          ],
        ]);
      case CalendarThemeId.eventChip:
        return Row(children: [
          if (showAllShifts) ...[_pillButton(context.l10n.shiftFullSchedule, Icons.table_chart_outlined, _openAllShiftsView), SizedBox(width: 6.w)],
          _pillButton(context.l10n.commonToday, Icons.adjust, _jumpToToday),
        ]);
      case CalendarThemeId.editorial:
        return Row(children: [
          if (showAllShifts) ...[
            GestureDetector(onTap: _openAllShiftsView, child: Text(context.l10n.shiftFullSchedule, style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, decoration: TextDecoration.underline))),
            SizedBox(width: 10.w),
          ],
          GestureDetector(onTap: _jumpToToday, child: Text(context.l10n.commonToday, style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, decoration: TextDecoration.underline))),
        ]);
      case CalendarThemeId.mainWhite:
      case CalendarThemeId.mainDark:
        return Row(children: [
          if (showAllShifts) ...[_mainHeaderButtonReal(context.l10n.shiftFullSchedule, _openAllShiftsView), SizedBox(width: 8.w)],
          _mainHeaderButtonReal('today', _jumpToToday),
        ]);
    }
  }

  Widget _thinTextButton(String label, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Text(label, style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)));
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30.w,
        height: 30.w,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3)]),
        child: Icon(icon, size: 16.sp, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _gridHeaderBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(3.r)),
        child: Text(label, style: TextStyle(fontSize: 9.5.sp, color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _pillButton(String label, IconData icon, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
        decoration: BoxDecoration(color: primary.withOpacity(0.08), borderRadius: BorderRadius.circular(20.r)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11.sp, color: primary),
          SizedBox(width: 3.w),
          Text(label, style: TextStyle(fontSize: 10.sp, color: primary, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ⭐ 기존 메인 헤더 버튼(전체근무표/today)이 build() 안에 인라인으로 있던 걸
  // 그대로 함수로 옮김 - 스타일 1px도 안 바뀜(primaryContainer 배경 + primary
  // 30% 테두리 알약형).
  Widget _mainHeaderButtonReal(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 0.8),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.sp, color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ⭐ 요일 헤더 한 칸 - table_calendar의 dowBuilder로 완전히 테마별 위젯을
  // 그림(일/월/... vs Sun/Mon/... vs S/M/... 등 표기 자체가 테마마다 다름).
  Widget _buildThemedDow(CalendarThemeId theme, DateTime day) {
    final i = day.weekday % 7; // 일=0 ... 토=6 (Dart weekday: 월=1..일=7)
    switch (theme) {
      case CalendarThemeId.minimal:
        // ⭐ "맨 위 세로줄들이 삐져나와 보인다"는 지적의 원인 - lab에는 요일행
        // 바로 밑에 구분선 하나가 있었는데(Container height:1) 실제 달력탭에
        // 옮길 때 빠뜨렸음. 그 구분선이 없으니 그리드의 세로선들이 위쪽에서
        // 아무 경계 없이 시작하는 것처럼 보였던 것 - 요일 칸 하나하나 밑에
        // 옅은 선을 그어서 합치면 그 구분선이 그대로 재현됨.
        return Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          alignment: Alignment.center,
          child: Text(_weekdayEn3[i], style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.w600, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500)),
        );
      case CalendarThemeId.materialCard:
        return Center(child: Text(weekdayLabel(context, i), style: TextStyle(fontSize: 11.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade700)));
      case CalendarThemeId.boldGrid:
        return Container(color: const Color(0xFF37474F), alignment: Alignment.center, child: Text(_weekdayEn3[i], style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.redAccent.shade100 : Colors.white70)));
      case CalendarThemeId.initialBadge:
        return Center(child: Text(weekdayLabel(context, i), style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500)));
      case CalendarThemeId.underline:
        return Center(child: Text(_weekdayEn1[i], style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade400)));
      case CalendarThemeId.eventChip:
        return Center(child: Text(_weekdayEn3[i], style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500)));
      case CalendarThemeId.editorial:
        return Container(
          color: i == 0 ? Colors.red.shade50 : (i == 6 ? Colors.blue.shade50 : Colors.grey.shade100),
          alignment: Alignment.center,
          child: Text(_weekdayEn3[i], style: TextStyle(fontSize: 9.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade600)),
        );
      case CalendarThemeId.mainWhite:
      case CalendarThemeId.mainDark:
        return Center(child: Text(weekdayLabel(context, i), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)));
    }
  }

  // ⭐ 6번째 줄을 재활용 안 하는 7개 테마용 - 달력 그리드 아래에 별도로 붙는
  // OT/주별근무시간 푸터. 각 테마 실험판의 원래 디자인 그대로, 데이터만 실제
  // 값(_monthlyOtSummary)으로 교체. 메인 화이트/다크는 이 함수 자체를 안 씀
  // (6번째 줄 카드에 이미 다 있음).
  Widget _buildThemedFooter(CalendarThemeId theme, ShiftSchedule schedule) {
    final summary = _monthlyOtSummary(schedule);
    final otText = formatOvertimeMinutes(context, summary.totalMinutes);
    switch (theme) {
      case CalendarThemeId.minimal:
      case CalendarThemeId.initialBadge:
      case CalendarThemeId.eventChip:
        return _themeOtBar(summary, otText);
      case CalendarThemeId.materialCard:
        return _theme2OtCardReal(summary, otText);
      case CalendarThemeId.boldGrid:
        return _theme4FooterReal(summary, otText);
      case CalendarThemeId.underline:
        return _theme8FooterReal(summary, otText);
      case CalendarThemeId.editorial:
        return _theme10FooterReal(summary, otText);
      case CalendarThemeId.mainWhite:
      case CalendarThemeId.mainDark:
        return const SizedBox.shrink();
    }
  }

  // ⭐ 1/5/9번이 공유하던 lab의 _theme1OtBar() 그대로.
  Widget _themeOtBar(({int totalMinutes, DateTimeRange period}) summary, String otText) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 6.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8.r)),
      child: Row(
        children: [
          Icon(Icons.access_time, size: 13.sp, color: primary.withOpacity(0.6)),
          SizedBox(width: 5.w),
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            child: Text('${context.l10n.shiftThisMonthOt} $otText', style: TextStyle(fontSize: 11.sp, color: Colors.black87)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text('${context.l10n.shiftWeeklyWorkHours} ›', style: TextStyle(fontSize: 11.sp, color: primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _theme2OtCardReal(({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 8.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      // ⭐ "이번 달 OT랑 주별 근무시간이 스크린샷에선 서로 다른 색상이었는데
      // 지금은 똑같다" - lab 원본(_theme2OtCard)은 인디고/틸로 서로 다른
      // MaterialColor를 썼는데 실제 탭으로 옮길 때 공용 primary 색 하나로
      // 합쳐버렸었음 - 원래 색 조합으로 복원.
      child: Row(
        children: [
          _otChipReal(context.l10n.shiftThisMonthOt, otText, () => _showMonthlyOvertimeSheet(summary.period), Colors.indigo),
          SizedBox(width: 8.w),
          _otChipReal(context.l10n.shiftWeeklyWorkHours, context.l10n.commonView, _showWeeklyWorkHoursSheet, Colors.teal),
        ],
      ),
    );
  }

  Widget _otChipReal(String label, String value, VoidCallback onTap, MaterialColor color) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8.r)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 9.sp, color: color.shade400, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 12.sp, color: color.shade700, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _theme4FooterReal(({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Container(
      color: const Color(0xFFECEFF1),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            child: Text('${context.l10n.shiftThisMonthOt} $otText', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: const Color(0xFF263238))),
          ),
          SizedBox(width: 14.w),
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text('${context.l10n.shiftWeeklyWorkHours} ▸', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00695C))),
          ),
        ],
      ),
    );
  }

  Widget _theme8FooterReal(({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 10.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            // ⭐ "OT 3시간 30분도 아주 약간만 더 진하게" - black54→black87.
            // ⭐ "OT만 쓰지 말고 다른 테마들처럼 이번 달 OT로 통일" 요청 반영.
            child: Text('${context.l10n.shiftThisMonthOt} $otText', style: TextStyle(fontSize: 11.sp, color: Colors.black87)),
          ),
          const Spacer(),
          // ⭐ "오늘 표시 밑줄은 그대로 두되, 주별 근무시간의 밑줄은 없애자 -
          // 띄어쓰기 있는 문구에 밑줄이 붙으니 이상해 보인다" - 진하기(bold+
          // black87)는 유지하고 밑줄만 제거.
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text(context.l10n.shiftWeeklyWorkHours, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _theme10FooterReal(({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 6.h, 18.w, 10.h),
      child: Row(
        children: [
          // ⭐ "이번 달 OT, 주별 근무시간 텍스트도 아주 약간만 더 진하게".
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            child: Row(children: [
              Text(context.l10n.shiftThisMonthOt, style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade600, fontFamily: 'serif')),
              SizedBox(width: 4.w),
              Text(otText, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.brown.shade600, fontFamily: 'serif')),
            ]),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text('${context.l10n.shiftWeeklyWorkHours} →', style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade500, fontFamily: 'serif')),
          ),
        ],
      ),
    );
  }

  // ⭐ 8/10번 전용 범례 - 색상만으로 근무를 구분하는 테마라 필수. 실제 등록된
  // 근무명(schedule.shiftTypes, 3개~12개 아무 개수)과 실제 배정된 색을 써서
  // 4열 고정 그리드로 그림(lab의 _theme8Legend/_theme10Legend와 동일 레이아웃 -
  // 개수가 몇 개든 정렬이 항상 맞고 줄 수만 자연스럽게 늘어남).
  Widget _buildThemedLegend(CalendarThemeId theme, ShiftSchedule schedule) {
    final colorMap = _shiftColorMap(schedule);
    final shifts = schedule.shiftTypes;
    final useTriangle = theme == CalendarThemeId.editorial;
    const cols = 4;
    final rows = shifts.isEmpty ? 1 : (shifts.length / cols).ceil();
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(
        border: Border.all(color: useTriangle ? Colors.grey.shade200 : Colors.grey.shade300, width: 0.7),
        borderRadius: useTriangle ? null : BorderRadius.circular(4.r),
      ),
      child: ClipRect(
        child: Column(
          children: List.generate(rows, (r) => Expanded(
            child: Row(
              children: List.generate(cols, (c) {
                final i = r * cols + c;
                if (i >= shifts.length) return const Expanded(child: SizedBox());
                final name = shifts[i];
                final color = colorMap[name] ?? Colors.grey;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
                    child: Row(
                      children: [
                        useTriangle
                            ? ClipPath(clipper: _CalendarTriangleClipper(), child: Container(width: 16.w, height: 16.w, color: color))
                            : Container(width: 16.w, height: 5.h, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.r))),
                        SizedBox(width: useTriangle ? 4.w : 3.w),
                        // ⭐ "범례 글자를 조금 더 키워도 될 듯" - 7.sp → 7.6.sp.
                        Expanded(child: Text(name, style: TextStyle(fontSize: 7.6.sp, color: Colors.black87, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          )),
        ),
      ),
    );
  }

  // ⭐ 테마별 셀 디스패치 - calendar_theme_lab_screen.dart에서 만들어둔 7개
  // 실험 테마(1/2/4/5/8/9/10)를 실제 데이터(schedule/memoProvider)에 물려서
  // 살아있는 달력에 반영함. "코드를 가져다 써, 새로 만들지 마라"는 원칙대로
  // 각 테마의 배지 모양/배치/색 처리 로직은 실험판을 그대로 옮겨왔고, 탭/길게
  // 누르기 등 상호작용은 손도 안 댐(TableCalendar의 onDaySelected/
  // onDayLongPressed가 이 셀들을 감싸는 GestureDetector 없이도 그대로 처리함 -
  // _buildDateCell도 원래 그런 구조였음). 메인·화이트/다크는 이미 완성돼있던
  // _buildDateCell을 그대로 씀(아래에서 분기).
  // ⭐ 2026-08-20 버그 수정 - "심플 라인 테마에서 달력을 좌우로 스와이프하면 특정
  // 셀들이 위아래로 틀어진다"는 신고로 발견. TableCalendar의 PageView는 부드러운
  // 스와이프를 위해 좌우 인접 달(page)도 미리 빌드해두는데, 이때 각 빌더 콜백은
  // "그 페이지가 실제로 나타내는 달"을 focusedDay 파라미터로 정확히 넘겨줌(페이지마다
  // 다름) - 그런데 여기서 이 파라미터를 안 받고 버렸었고, _theme1Cell만 대신 위젯의
  // _focusedDay 상태(스와이프 도중엔 아직 안 바뀐, "커밋된" 달만 가리킴)를 썼음.
  // 그 결과 아직 포커스되지 않은(미리 빌드 중인) 인접 페이지의 셀들이 "엉뚱한 달"
  // 기준으로 첫 줄 여부(_isFirstRow)를 판정해서, 스와이프 도중 위쪽 여백이 있다/없다가
  // 뒤바뀌는 셀이 생겼던 것 - 스와이프가 끝나 상태가 갱신되면 다시 맞아 보여서 순간적인
  // "틀어짐"으로만 보였음. 이제 각 빌더 콜백의 focusedDay를 그대로 전달받아 씀.
  Widget _buildThemedCell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule, DateTime focusedDay, {bool isSelected = false}) {
    final theme = ref.watch(calendarThemeProvider);
    if (theme == CalendarThemeId.mainWhite || theme == CalendarThemeId.mainDark) {
      return _buildDateCell(day, isToday, isOutside, schedule, isSelected: isSelected);
    }
    final cell = switch (theme) {
      CalendarThemeId.minimal => _theme1Cell(day, isToday, isOutside, schedule, focusedDay),
      CalendarThemeId.materialCard => _theme2Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.boldGrid => _theme4Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.initialBadge => _theme5Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.underline => _theme8Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.eventChip => _theme9Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.editorial => _theme10Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.mainWhite || CalendarThemeId.mainDark => throw StateError('unreachable'),
    };
    // ⭐ 7개 실험 테마 셀 함수들은 원래 다중 선택(길게 눌러 여러 날짜 선택) 기능이
    // 없던 시절에 만들어져서 선택 표시가 없음 - 각 셀 디자인은 그대로 두고 선택
    // 상태만 얇은 강조 테두리로 공통 오버레이함 (달력탭의 나머지 다중선택 로직은
    // 그대로 - 여기는 "선택됨"을 시각적으로만 보여주는 부분).
    if (!isSelected) return cell;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 2),
        color: Theme.of(context).colorScheme.secondary.withOpacity(0.12),
      ),
      child: cell,
    );
  }

  // ⭐ 아래 7개 함수 공용으로 쓰는, 셀 하나 그리는 데 필요한 값들을 한 번에 계산.
  // calendar_theme_lab_screen.dart의 목업(_mockShiftFor/_mockMemos 등) 대신
  // 실제 schedule.getShiftForDate/memoProvider를 씀 - 그 외 계산 방식(공휴일,
  // 일요일, 자동 대비 텍스트색 등)은 완전히 동일한 공식을 그대로 씀.
  ({String shiftText, bool hasShift, Color shiftColor, Color shiftTextColor, bool red, String? holidayName, List<String> memos})
      _themedCellData(DateTime day, ShiftSchedule schedule) {
    final shiftText = schedule.getShiftForDate(day);
    final hasShift = shiftText.isNotEmpty && shiftText != '미설정';
    final shiftColor = hasShift ? _getShiftBackgroundColor(shiftText, schedule) : Colors.transparent;
    final shiftTextColor = hasShift ? _getShiftTextColor(shiftText, schedule) : Colors.transparent;
    final holidayName = _getHolidayName(day, context);
    final red = day.weekday == DateTime.sunday || holidayName != null;
    final dateStr = day.toIso8601String().split('T')[0];
    final memos = ref.watch(memoProvider)[dateStr]?.map((m) => m.memoText).toList() ?? const <String>[];
    return (
      shiftText: shiftText, hasShift: hasShift, shiftColor: shiftColor, shiftTextColor: shiftTextColor,
      red: red, holidayName: holidayName, memos: memos,
    );
  }

  // ⭐ "메모/빨간날 글자가 셀 밖으로 넘치면 가위로 자른 듯 반쪽 글자가 보인다"는
  // 지적 - TextOverflow.clip/ellipsis는 픽셀 경계에서 그냥 잘라버려서 마지막
  // 글자가 반쪽만 그려질 수 있음(생략 부호 "..."도 원치 않는다고 함: "..." 없이
  // 그냥 보이는 데까지만"). 실제 폭을 TextPainter로 재서, 완전히 다 들어가는
  // 글자까지만 문자열 자체를 잘라내고 그걸 그림 - 이미 딱 맞게 잘린 문자열이라
  // 반쪽 글자가 원천적으로 나올 수 없음. 모든 테마의 메모/공휴일명 렌더링이
  // 공용으로 씀.
  Widget _fitText(String text, TextStyle style, {TextAlign textAlign = TextAlign.center}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var display = text;
        if (maxWidth.isFinite && maxWidth > 0 && text.isNotEmpty) {
          final full = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
          if (full.width > maxWidth) {
            int lo = 0, hi = text.length;
            while (lo < hi) {
              final mid = (lo + hi + 1) ~/ 2;
              final p = TextPainter(text: TextSpan(text: text.substring(0, mid), style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
              if (p.width <= maxWidth) {
                lo = mid;
              } else {
                hi = mid - 1;
              }
            }
            display = text.substring(0, lo);
          }
        }
        return Text(display, style: style, maxLines: 1, textAlign: textAlign, softWrap: false);
      },
    );
  }

  // ⭐ 1번 · 미니멀 라인 (calendar_theme_lab_screen.dart _theme1Cell 이식)
  // ⭐ focusedDay는 위젯 상태(_focusedDay)가 아니라 이 셀을 그리는 TableCalendar
  // 빌더 콜백이 실제로 받은 값을 그대로 받음 - _buildThemedCell의 주석 참고
  // (스와이프 중 미리 빌드되는 인접 페이지에서 첫 줄 판정이 엉뚱한 달 기준으로
  // 되던 버그 수정).
  Widget _theme1Cell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule, DateTime focusedDay) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    final numColor = isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : (d.red ? Colors.red.shade400 : colorScheme.onSurface);
    // ⭐ "그리드가 이미지보다 진하다"는 지적으로 왼쪽 선을 더 연하게.
    // ⭐ "맨 윗줄 근무명 영역이랑 요일행 밑 구분선 사이에 미세한 여백이 있다"는
    // 지적 - lab 원본도 첫 줄만 위쪽 패딩을 0으로 없앴었는데(다른 행끼리는
    // 위/아래 패딩이 서로 겹쳐서 자연스럽지만, 첫 줄만 위에 겹칠 "이전 행의
    // 아래쪽 패딩"이 없어서 그 틈이 붕 떠 보임) 그 조건을 이식할 때 빠뜨렸음 -
    // 첫 줄만 위쪽 패딩 0으로 복원.
    final isFirstRow = _isFirstRow(day, focusedDay);
    return ClipRect(
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade200))),
        padding: EdgeInsets.only(top: isFirstRow ? 0 : 2.h, bottom: 2.h),
        child: Column(
          children: [
            if (d.hasShift)
              Container(
                width: double.infinity,
                height: 11.h,
                margin: EdgeInsets.only(top: isFirstRow ? 0 : 1.h),
                color: d.shiftColor.withOpacity(0.85),
                alignment: Alignment.center,
                // ⭐ 영어 현지화: 예전엔 4글자로 강제로 자르고 남는 글자는 그냥
                // 버렸음(근무명 글자수 제한이 4였을 때는 어차피 딱 맞아서 티가
                // 안 났음) - 이제 근무명이 최대 kMaxShiftNameLength(10)글자까지
                // 가능해져서, 안 잘리는 부분까지 버리지 않고 이미 있던
                // overflow:ellipsis(말줄임표)가 자연스럽게 나머지를 처리하게 둠.
                child: Text(d.shiftText,
                    style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: d.shiftTextColor),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              )
            else
              SizedBox(height: 12.h),
            SizedBox(height: 1.5.h),
            Container(
              width: 18.w,
              height: 18.w,
              alignment: Alignment.center,
              decoration: isToday ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.indigo.shade400, width: 1.4)) : null,
              child: Text('${day.day}', style: TextStyle(fontSize: 11.sp, fontWeight: isToday ? FontWeight.bold : FontWeight.w500, color: numColor)),
            ),
            if (d.holidayName != null)
              _fitText(d.holidayName!, TextStyle(fontSize: 6.5.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold, height: 1.1)),
            SizedBox(height: 3.8.h),
            ...d.memos.take(3).toList().asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.h, left: 1.w, right: 1.w),
              child: _fitText(e.value, TextStyle(fontSize: 7.sp, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            )),
          ],
        ),
      ),
    );
  }

  // ⭐ 2번 · 머티리얼 카드형
  Widget _theme2Cell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Padding(
        padding: EdgeInsets.all(2.w),
        child: Container(
          decoration: BoxDecoration(
            color: isOutside ? colorScheme.surfaceVariant.withOpacity(0.3) : colorScheme.surface,
            borderRadius: BorderRadius.circular(6.r),
            border: isToday ? Border.all(color: Colors.indigo.shade400, width: 1.4) : null,
            boxShadow: isOutside ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1))],
          ),
          child: Column(
            children: [
              if (d.hasShift)
                Container(
                  width: double.infinity,
                  height: 12.h,
                  margin: EdgeInsets.fromLTRB(4.w, 1.h, 4.w, 0),
                  decoration: BoxDecoration(color: d.shiftColor, borderRadius: BorderRadius.circular(3.r)),
                  alignment: Alignment.center,
                  // ⭐ 영어 현지화: 위 셀과 동일한 이유로 강제 4글자 컷 제거,
                  // 기존 overflow:ellipsis에 맡김.
                  child: Text(d.shiftText,
                      style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: d.shiftTextColor),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )
              else
                SizedBox(height: 13.h),
              SizedBox(height: 1.h),
              Text('${day.day}', style: TextStyle(
                fontSize: 12.sp, fontWeight: isToday ? FontWeight.bold : FontWeight.w700,
                color: isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : (d.red ? Colors.red.shade400 : colorScheme.onSurface),
              )),
              if (d.holidayName != null)
                _fitText(d.holidayName!, TextStyle(fontSize: 6.sp, color: Colors.red.shade600, fontWeight: FontWeight.bold, height: 1.0)),
              SizedBox(height: 1.8.h),
              ...d.memos.take(3).toList().asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.h),
                child: _fitText(e.value, TextStyle(fontSize: 7.5.sp, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.0)),
              )),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 4번 · 굵은 격자형
  Widget _theme4Cell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Container(
        // ⭐ shade300→shade400으로 한 번 진하게 했는데 "아직도 더 진해야 할듯"
        // 이라는 재지적 - 두께는 그대로, 색만 한 단계 더(shade400→shade600).
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade600, width: 0.6),
          color: isOutside ? colorScheme.surfaceVariant.withOpacity(0.3) : (isToday ? const Color(0xFFFFF9C4) : colorScheme.surface),
        ),
        padding: EdgeInsets.all(2.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('${day.day}', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : (d.red ? Colors.red.shade600 : colorScheme.onSurface))),
                if (d.holidayName != null)
                  Expanded(child: _fitText(d.holidayName!, TextStyle(fontSize: 5.5.sp, color: Colors.red.shade600, fontWeight: FontWeight.bold))),
              ],
            ),
            if (d.hasShift)
              Container(
                margin: EdgeInsets.symmetric(vertical: 1.h),
                padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
                width: double.infinity,
                decoration: BoxDecoration(color: d.shiftColor),
                child: Text(d.shiftText, style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: d.shiftTextColor), maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.center),
              ),
            SizedBox(height: 1.h),
            ...d.memos.take(3).map((m) => _fitText('· $m', TextStyle(fontSize: 8.5.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant), textAlign: TextAlign.start)),
          ],
        ),
      ),
    );
  }

  // ⭐ 5번 · 이니셜 뱃지형
  Widget _theme5Cell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    final numColor = isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : (d.red ? Colors.red.shade400 : colorScheme.onSurface);
    // ⭐ "메모가 없으면 홀쭉해 보인다"는 지적의 진짜 원인은 셀 자체가 아니라
    // rowHeight를 75.h로 감으로 고정했던 것 - lab은 6줄을 Expanded로 화면
    // 남는 공간만큼 나눠 쓰는데 그 실제 값과 75.h가 안 맞아서 셀이 필요
    // 이상으로 길었던 것. 이제 build()에서 LayoutBuilder로 lab과 똑같은
    // 방식(남는 높이 ÷ 6)으로 rowHeight를 계산하므로, 이 셀 자체는 lab
    // 원본(calendar_theme_lab_screen.dart의 _theme5Cell)과 100% 동일한
    // 구조로 되돌림 - Center/shrink-wrap 같은 임시방편 제거.
    // width:double.infinity만 예외로 유지 - lab은 Row+Expanded가 가로를
    // 강제로 꽉 채워줬지만(Expanded는 항상 자식에게 꽉 찬 너비를 줌),
    // table_calendar는 셀에게 "이 너비 이하로 알아서" 식의 느슨한 제약만
    // 주기 때문에 그 역할을 여기서 명시로 대신해줘야 함(안 그러면 "대체공휴일"
    // 처럼 내용이 넓은 날만 셀이 옆으로 늘어나 보임).
    return Container(
      width: double.infinity,
      margin: EdgeInsets.all(1.5.w),
      padding: EdgeInsets.symmetric(vertical: 1.h),
      // ⭐ "스크린샷에서는 테두리가 거의 없다시피 세련됐는데 지금은 너무 진하다"는
      // 지적 - outlineVariant*0.4는 이 앱 라이트 테마에서 여전히 눈에 띄는
      // 회색이었음. 거의 안 보일 만큼 연한 고정 회색으로 교체.
      decoration: BoxDecoration(
        border: isToday ? Border.all(color: Colors.indigo.shade400, width: 1.4) : Border.all(color: Colors.grey.shade200, width: 0.5),
        borderRadius: BorderRadius.circular(4.r),
      ),
      // ⭐ "스크린샷에서는 근무명·숫자가 셀 맨 위에 붙어있었는데 지금은 중간에
      // 있고, 메모/빨간날이 있으면 오히려 위로 밀린다"는 지적 - 지난 라운드에
      // "메모 없으면 홀쭉해 보인다"를 고치려고 세로 중앙 정렬(mainAxisAlignment
      // .center)을 넣었었는데, rowHeight 계산 자체를 고친 지금은 그 정렬이
      // 필요 없어졌고 오히려 부작용(내용이 메모 유무에 따라 밀렸다 당겨졌다)만
      // 남았음. lab 원본처럼 기본(맨 위부터 쌓기)으로 되돌림 - 근무명+숫자가
      // 항상 셀 맨 위에 고정되고, 메모는 그 아래로 순서대로 쌓임.
      child: ClipRect(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 1.h),
              child: Column(
                children: [
                  if (d.hasShift)
                    Container(
                      width: 14.w, height: 14.w, alignment: Alignment.center,
                      decoration: BoxDecoration(color: d.shiftColor, shape: BoxShape.circle),
                      child: Text(d.shiftText[0], style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: d.shiftTextColor)),
                    )
                  else
                    SizedBox(height: 14.w),
                  SizedBox(height: 1.h),
                  Text('${day.day}', style: TextStyle(fontSize: 11.5.sp, fontWeight: isToday ? FontWeight.bold : FontWeight.w600, color: numColor)),
                ],
              ),
            ),
            if (d.holidayName != null)
              _fitText(d.holidayName!, TextStyle(fontSize: 6.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold, height: 1.0)),
            if (d.memos.isNotEmpty) SizedBox(height: 1.2.h),
            ...d.memos.take(3).toList().asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(top: e.key == 0 ? 0 : 2.h),
              child: _fitText(e.value, TextStyle(fontSize: 7.sp, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.0)),
            )),
          ],
        ),
      ),
    );
  }

  // ⭐ 8번 · 언더라인 미니멀형 (색상만으로 구분 - 범례는 이 화면에선 생략,
  // 사용자 본인 근무명이라 알아보기 쉬움 + row6는 OT카드가 이미 차지 중이라
  // 자리도 없음. 위젯 큰 사이즈엔 범례를 넣기로 함(후속 작업, 네이티브 쪽)).
  Widget _theme8Cell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Column(
        children: [
          SizedBox(height: 3.h),
          Text('${day.day}', style: TextStyle(
            fontSize: 12.sp, fontWeight: isToday ? FontWeight.bold : FontWeight.w400,
            color: isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : (d.red ? Colors.red.shade400 : colorScheme.onSurface),
            decoration: isToday ? TextDecoration.underline : null, decorationThickness: 2,
          )),
          // ⭐ "근무명 뱃지를 세로로 아주 조금만 더 얇게" - 3.6.h → 3.0.h.
          if (d.hasShift)
            Container(margin: EdgeInsets.symmetric(vertical: 2.h), width: 22.w, height: 3.0.h,
                decoration: BoxDecoration(color: d.shiftColor, borderRadius: BorderRadius.circular(2.r)))
          else
            SizedBox(height: 7.0.h),
          if (d.holidayName != null)
            _fitText(d.holidayName!, TextStyle(fontSize: 6.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold)),
          // ⭐ "메모가 너무 연하고 작다 - 키우고 진하게" - 7.sp→7.8.sp, onSurfaceVariant(연함)→grey.shade700.
          ...d.memos.take(3).map((m) => _fitText(m, TextStyle(fontSize: 7.8.sp, color: Colors.grey.shade700, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ⭐ 9번 · 이벤트 칩형
  Widget _theme9Cell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 1.5.w, vertical: 1.2.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 15.w, height: 15.w, alignment: Alignment.center,
              margin: EdgeInsets.only(bottom: 1.2.h),
              decoration: isToday ? BoxDecoration(color: d.red ? Colors.red.shade400 : Colors.indigo.shade400, shape: BoxShape.circle) : null,
              child: Text('${day.day}', style: TextStyle(
                fontSize: 9.5.sp, fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: isToday ? Colors.white : (isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : (d.red ? Colors.red.shade400 : colorScheme.onSurface)),
              )),
            ),
            if (d.hasShift) _themeChip(d.shiftText, d.shiftColor, d.shiftTextColor),
            if (d.holidayName != null)
              Padding(padding: EdgeInsets.only(top: 0.8.h), child: _themeChip(d.holidayName!, Colors.red.shade50, Colors.red.shade400)),
            ...d.memos.take(3).map((m) => Padding(padding: EdgeInsets.only(top: 0.8.h), child: _themeChip(m, colorScheme.surfaceVariant, colorScheme.onSurface))),
          ],
        ),
      ),
    );
  }

  Widget _themeChip(String text, Color bg, Color fg) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 0.6.h),
      padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.1.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2.5.r)),
      child: _fitText(text, TextStyle(fontSize: 7.5.sp, color: fg, fontWeight: FontWeight.w600, height: 1.1)),
    );
  }

  // ⭐ 10번 · 매거진 에디토리얼형 (범례는 8번과 같은 이유로 이 화면에선 생략)
  Widget _theme10Cell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    // ⭐ "스크린샷보다 셀 테두리가 너무 진하다"는 지적으로 다른 테마들과 같은
    // 톤(grey.shade200)으로 낮춤. 메모 색도 "약간 더 진하게" - onSurfaceVariant
    // 대신 눈에 잘 띄는 고정 회색(grey.shade700)으로 교체.
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200, width: 0.5)),
      child: Stack(
        children: [
          if (d.hasShift)
            Positioned(
              top: 0, left: 0,
              child: ClipPath(clipper: _CalendarTriangleClipper(), child: Container(width: 16.w, height: 16.w, color: d.shiftColor)),
            ),
          Padding(
            padding: EdgeInsets.only(top: 3.h, right: 2.w),
            child: Align(
              alignment: Alignment.topRight,
              child: Text('${day.day}', style: TextStyle(
                fontSize: 12.sp, fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : (d.red ? Colors.red.shade400 : colorScheme.onSurface),
                decoration: isToday ? TextDecoration.underline : null,
              )),
            ),
          ),
          // ⭐ "메모 크기를 조금 더 키우고 진하게 - 광복절까지 여유가 꽤 있다"는
          // 지적으로 6.8.sp→7.3.sp. 공휴일명 Positioned에 left도 명시해서 폭을
          // 고정함(_fitText가 실제 셀 너비를 알아야 안전하게 잘라낼 수 있음 -
          // right만 있으면 폭이 무한대라 잘라낼 기준이 없었음).
          if (d.holidayName != null)
            Positioned(
              top: 18.h, left: 2.w, right: 2.w,
              child: _fitText(d.holidayName!, TextStyle(fontSize: 7.5.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
            ),
          Positioned(
            left: 2.w, right: 2.w, bottom: 2.h,
            child: Column(
              children: d.memos.take(3).toList().asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.2.h),
                child: _fitText(e.value, TextStyle(fontSize: 7.3.sp, color: Colors.grey.shade800), textAlign: TextAlign.right),
              )).toList(),
            ),
          ),
        ],
      ),
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

    final isHoliday = _getHolidayName(day, context) != null;  // ⭐ 공휴일 체크

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
                    if (_getHolidayName(day, context) != null)
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
                              _getHolidayName(day, context)!,
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
                                  // ⭐ 다크모드 오늘 날짜 배경: 더 밝게
                                  color: (isSunday || isHoliday)
                                      ? (isDarkMode ? Colors.amber.shade300 : Colors.lime.shade300)  // 다크모드: 밝은 amber
                                      : (isDarkMode ? Color(0xFFB4BFFF) : Theme.of(context).colorScheme.primary),  // 다크모드: 더 밝은 인디고
                                  borderRadius: BorderRadius.circular(4.r),
                                )
                              : null,
                          child: Text(
                            '${day.day}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              // ⭐ 다크모드 오늘 날짜 텍스트: 명확한 대비
                              color: shouldHighlightToday
                                  ? (isSunday || isHoliday)
                                      ? (isDarkMode ? Colors.red.shade900 : Colors.red)  // 다크모드: 진한 빨강
                                      : (isDarkMode ? Colors.white : Theme.of(context).colorScheme.onPrimary)  // 다크모드: 순백
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
    // ⭐ 메모 3개가 다 찼을 때 맨 아래 여백이 많이 남아서 비율로 살짝 줄임.
    // 키보드가 뜬 상태에서의 높이 조정은 아래 builder 안에서 별도로 계산함
    // (그때만 화면-키보드 높이 기준으로 더 줄여서, 메모 입력창이 키보드 위에 보이게 함).
    final basePopupHeight = screenHeight * 0.66;  // ⭐ 화면의 66% (기존 72%에서 축소)

    final dateStr = day.toIso8601String().split('T')[0];

    // ⭐ 팝업 열기 전에 알람 데이터 새로고침 (dismiss/snooze/timeout 후 최신 데이터 반영)
    ref.invalidate(alarmNotifierProvider);

    // ⭐ 팝업 열기 전에 메모 로드
    ref.read(memoProvider.notifier).loadMemosForDate(dateStr);

    // ⭐ 팝업 열기 전에 OT 로드 (혹시 최신 상태가 아닐 수 있으니 재확인)
    ref.read(overtimeProvider.notifier).loadForRange(day, day);

    // ⭐ TextEditingController를 밖에서 생성 (키보드 문제 해결)
    final memoController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            final isKeyboardVisible = keyboardHeight > 50;  // 키보드 감지 임계값

            // ⭐ CRITICAL FIX: 실시간 측정(RenderBox+setState) 방식은 리빌드가
            // 반복되면서 잔상/겹침 아티팩트가 생겨서 정적 계산으로 되돌림.
            // 팝업 하단(메모 입력 줄보다 아래 - 메모 목록 + 여백)은 키보드에 가려도
            // 상관없는 영역이라, 그 비율만큼은 밀 필요가 없음. 화면 크기에 비례한
            // 값이라 기기가 달라져도 비율은 항상 같음.
            final reservedBottom = basePopupHeight * 0.32;
            final paddingBottom = isKeyboardVisible
                ? (keyboardHeight - reservedBottom).clamp(0.0, keyboardHeight)
                : 0.0;

            // ignore: deprecated_member_use
            return WillPopScope(
              onWillPop: () async {
                // ⭐ 키보드가 떠 있을 때만 포커스 해제 + 딜레이(닫히는 애니메이션과
                // 겹치는 시각적 튐 방지). 키보드가 없는 대부분의 경우(그냥 보고 뒤로가기)
                // 까지 무조건 150ms를 기다리게 해서 팝업이 매번 느리게 닫히는 것처럼
                // 느껴졌음 - 그럴 필요가 없을 땐 바로 닫히게 함.
                if (isKeyboardVisible) {
                  FocusScope.of(context).unfocus();
                  await Future.delayed(Duration(milliseconds: 150));
                }
                return true;
              },
              child: Padding(
                padding: EdgeInsets.only(bottom: paddingBottom),
                child: Container(
                  height: basePopupHeight,
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ⭐ 날짜 + OT(추가근무) 컨트롤. OT 쪽이 버튼 두 줄이라 날짜 텍스트보다
                      // 키가 커서, start 정렬이면 날짜 텍스트 아래로 빈 공간이 남아 "근무 :"
                      // 줄과 멀어 보임 - center로 바꿔서 그 여백을 흡수시킴.
                      // (근무 변경으로 "기존→현재" 뱃지까지 늘어나면 OT 넣을 폭이 기기에
                      // 따라 빠듯할 수 있어서 - 예: 3시간30분처럼 글자 길 때 - 다시 날짜 줄로
                      // 되돌림. 이 줄은 항상 폭이 일정해서(뱃지 안 늘어남) 더 안전함.)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '${DateFormat.MMMd(Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en').format(day)} (${_getWeekday(day, context)})',
                            style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                          ),
                          Spacer(),
                          _buildOvertimeToggle(dateStr),
                        ],
                      ),
                      SizedBox(height: 12.h),

                      // ⭐ 근무 정보
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(context.l10n.calendarShiftLabel, style: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
                          SizedBox(width: 8.w),
                          if (isModified) ...[
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(context.l10n.commonPrevious, style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
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
                                Text(context.l10n.commonCurrent, style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
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
                      Text(context.l10n.calendarFixedAlarmLabel, style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
                      SizedBox(height: 8.h),
                      Consumer(
                        builder: (context, ref, child) {
                          final alarmsAsync = ref.watch(alarmNotifierProvider);

                          return alarmsAsync.when(
                            loading: () => SizedBox(height: 20.h, width: 20.w, child: CircularProgressIndicator(strokeWidth: 2)),
                            error: (_, __) => Text(context.l10n.statusErrorOccurred, style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.error)),
                            data: (allAlarms) {
                              final dayStr = day.toIso8601String().split('T')[0];
                              final fixedAlarms = allAlarms
                                  .where((a) => a.type == 'fixed' && a.date != null && a.date!.toIso8601String().startsWith(dayStr))
                                  .toList();

                              // ⭐ 1단계: 알람이 있으면 우선 표시 (최우선)
                              if (fixedAlarms.isNotEmpty) {
                                // ⭐ 근무당 알람이 kMaxAlarmTemplatesPerShift(5)개까지 늘어나면서
                                // Expanded로 균등폭 배치하던 예전 방식은 카드가 너무 좁아지거나
                                // (5개) 넘치면 레이아웃이 깨짐(그 이상) - 고정폭 카드 + 가로 스크롤로
                                // 바꿔서 몇 개든 항상 같은 크기로 보이게 함. 시간순 정렬도 추가.
                                final sortedAlarms = [...fixedAlarms]..sort((a, b) => a.time.compareTo(b.time));
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: sortedAlarms.map((alarm) {
                                      final typeInfo = _getAlarmTypeInfo(alarm.alarmTypeId);
                                      return GestureDetector(
                                        onTap: () => _showAlarmTypeSelectionPopup(alarm, setState),
                                        child: Container(
                                          width: 78.w,
                                          margin: EdgeInsets.only(right: alarm != sortedAlarms.last ? 8.w : 0),
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
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                );
                              }

                              // ⭐ 2단계: 알람이 없으면 템플릿 조회
                              final currentShift = schedule.getShiftForDate(day);
                              return FutureBuilder<bool>(
                                future: _checkHasTemplate(currentShift),
                                builder: (context, snapshot) {
                                  // 3단계: 템플릿이 없거나 로딩 중이면 (없음)
                                  if (!snapshot.hasData || snapshot.data == false) {
                                    return Text('(${context.l10n.commonNone})', style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant));
                                  }

                                  // 4단계: 템플릿은 있는데 알람이 없는 경우 → 10일 체크 (DST 안전)
                                  final now = DateTime.now();
                                  final daysDiff = julianDayNumber(day.year, day.month, day.day) -
                                      julianDayNumber(now.year, now.month, now.day);

                                  // 5단계: 10일 이후면 안내 문구
                                  if (daysDiff >= kAlarmRefreshWindowDays) {
                                    return Text(
                                      context.l10n.calendarAutoGeneratedWithinDays(kAlarmRefreshWindowDays),
                                      style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.tertiary, fontStyle: FontStyle.italic),
                                    );
                                  }

                                  // 6단계: 10일 이내인데 알람이 없으면 (없음) - 버그 상황
                                  return Text('(${context.l10n.commonNone})', style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant));
                                },
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
                              Text(context.l10n.calendarMemoColonLabel, style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
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
                                          context.l10n.statusMemoLimit(3),
                                          style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      )
                                    : TextField(
                                        controller: memoController,
                                        maxLines: 1,
                                        scrollPhysics: BouncingScrollPhysics(),
                                        decoration: InputDecoration(
                                          hintText: context.l10n.calendarMemoEnter,
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
                                        final text = memoController.text.trim();
                                        if (text.isEmpty) return;

                                        // ⭐ 원래 동작: 팝업은 그대로 열어둔 채 메모만 추가해서
                                        // 바로 아래 목록에 생기는 걸 보여줌. (예전엔 팝업을
                                        // 통째로 닫고 그 결과값으로 메모를 저장했었는데, 그러면
                                        // 저장할 때마다 팝업이 닫혀버려서 사용성이 나빠짐)
                                        FocusScope.of(context).unfocus();
                                        memoController.clear();
                                        ref.read(memoProvider.notifier).createMemo(dateStr, text);
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.secondary,
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                                  minimumSize: Size(0, 0),
                                ),
                                child: Text(context.l10n.commonSave, style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSecondary)),
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
    ).then((_) {
      // ⭐ 메모 저장은 이제 입력창 "저장" 버튼에서 팝업을 안 닫고 바로 처리하므로,
      // 여기서는 팝업이 실제로 닫힌 뒤 컨트롤러만 정리하면 됨.
      memoController.dispose();
    });
  }

  String _getWeekday(DateTime date, BuildContext context) {
    return weekdayLabel(context, weekdayIndexOf(date));
  }

  // ⭐ 알람 타입 정보 반환
  Map<String, String> _getAlarmTypeInfo(int typeId) {
    switch (typeId) {
      case 1:
        return {'emoji': '🔔', 'label': context.l10n.alarmSoundVibration};
      case 2:
        return {'emoji': '📳', 'label': context.l10n.alarmVibration};
      case 3:
        return {'emoji': '🔇', 'label': context.l10n.alarmSilent};
      default:
        return {'emoji': '🔔', 'label': context.l10n.alarmSoundVibration};
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
            context.l10n.calendarSelectAlarmType,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,  // ⭐ 명시적 width 지정
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.calendarAlarmAt(alarm.time),
                  style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 16.h),
                Row(
                  mainAxisSize: MainAxisSize.max,  // ⭐ 명시적 설정
                  children: [
                    _buildAlarmTypeOption(
                      typeId: 1,
                      icon: Icons.volume_up_rounded,
                      label: context.l10n.alarmSoundVibration,
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
                      label: context.l10n.alarmVibration,
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
                      label: context.l10n.alarmSilent,
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
              child: Text(context.l10n.commonDelete, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14.sp)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonCancel),
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
            context.l10n.calendarDeleteAlarmTitle,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          content: Text(
            context.l10n.calendarDeleteAlarmConfirm(alarm.time),
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonCancel),
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
              child: Text(context.l10n.commonDelete, style: TextStyle(color: Theme.of(context).colorScheme.onError)),
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
            content: Text('❌ ${context.l10n.calendarDeleteAlarmFailed}: $e'),
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
          content: Text(context.l10n.alarmDeletedToast),
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
  // ⭐ CRITICAL FIX: activeShiftTypes(패턴에 실제로 쓰이는 근무만)로 제한하지 않고
  // shiftTypes(온보딩에서 만든 모든 근무 카드)를 그대로 씀 - 패턴엔 없는 근무(예: 오전/
  // 오후)도 날짜별 근무 변경(꾹 눌러서 변경)에서 선택 가능해야 함.
  // ⭐ 불규칙 근무인 경우 "없음" 옵션 추가
  final baseShifts = schedule.shiftTypes;
  final displayShifts = schedule.isRegular
    ? baseShifts
    : [...baseShifts, '없음'];

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
              context.l10n.calendarBulkChangeShiftTitle(_selectedDates.length),
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
                        shiftType == '없음' ? context.l10n.commonNone : shiftType,
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

    // ⭐ "없음"을 "미설정"으로 변환
    final actualShiftType = shiftType == '없음' ? '미설정' : shiftType;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      // ⭐ Provider의 bulkAssignShift 사용
      await ref.read(scheduleProvider.notifier).bulkAssignShift(
        _selectedDates.toList(),
        actualShiftType,
      );

      // ⭐ 각 날짜의 고정 알람 재생성 (미설정은 스킵)
      if (actualShiftType != '미설정') {
        for (var date in _selectedDates) {
          await ref.read(alarmNotifierProvider.notifier).regenerateFixedAlarms(
            date,
            actualShiftType,
          );
        }
      }

      Navigator.pop(context);
      _exitMultiSelectMode();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ ${context.l10n.statusShiftAssigned}')),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${context.l10n.statusShiftAssignFailed}: $e'),
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
            content: Text('❌ ${context.l10n.statusShiftChangeFailed}: $e'),
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
            title: Text(context.l10n.calendarMemoDetailTitle, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
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
                          hintText: context.l10n.calendarMemoContent,
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
                  child: Text(context.l10n.commonCancel, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (editController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.statusEnterMemoContent)),
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
                  child: Text(context.l10n.commonSave, style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
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
                  child: Text(context.l10n.commonDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      isEditing = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary),
                  child: Text(context.l10n.commonEdit, style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
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

  // ⭐ 특정 근무 타입의 템플릿 존재 여부 확인
  Future<bool> _checkHasTemplate(String shiftType) async {
    if (shiftType == '미설정' || shiftType.isEmpty) {
      return false;
    }

    try {
      final db = await DatabaseService.instance.database;
      final templates = await db.query(
        'shift_alarm_templates',
        where: 'shift_type = ?',
        whereArgs: [shiftType],
      );
      return templates.isNotEmpty;
    } catch (e) {
      print('⚠️ 템플릿 조회 실패: $e');
      return false;
    }
  }
}
// ⭐ 10번 테마(에디토리얼형)의 모서리 삼각 배지용 클리퍼 -
// calendar_theme_lab_screen.dart의 _CornerTriangleClipper와 동일한 도형
// (그 클래스는 private이라 그대로 import해서 못 씀, 그래서 이 파일에도 하나 둠).
class _CalendarTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
