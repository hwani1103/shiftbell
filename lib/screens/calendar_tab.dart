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
import '../widgets/app_second_button.dart';
import '../widgets/day_offset_chip.dart';
import '../constants/alarm_day_offset.dart';
import '../widgets/onboarding_info_popups.dart';
import '../providers/friend_provider.dart';
import 'friend_list_screen.dart';
import '../utils/friend_open_util.dart';
import '../utils/blocking_progress.dart';
import '../utils/lunar_calendar_util.dart';

// ⭐ 공휴일 판정 로직은 utils/holiday_util.dart로 이동함 (friend_calendar_view.dart도
// 똑같은 공휴일 표시가 필요해져서 공용화 - 두 파일 이름만 다르게 감싸서 기존 호출부
// (_getHolidayName(...))는 하나도 안 건드림).
// ⭐ 영어 현지화: 영어 로케일에서는 한국 고유 공휴일을 표시하지 않기로 결정됨
// (holiday_util.dart의 isKorean 파라미터 참고) - 호출부에서 현재 로케일을 넘겨줌.
String? _getHolidayName(DateTime date, BuildContext context) =>
    getHolidayName(date,
        isKorean: Localizations.localeOf(context).languageCode == 'ko');

// ⭐ 2026-09-22 음력 표기 - 매주 수요일 자리에만 보여주되, 그 날이 빨간날(일요일/공휴일)이면
// 겹치지 않게 화→목→월→금→일→토 순서로 옆으로 밀어 빨간날이 아닌 첫 날을 찾음(사용자
// 결정: 화수목 다 빨간날이면 월/금, 월~금 다 빨간날이면 일/토, 그마저 다 빨간날이면 그
// 주는 표기 안 함). 일요일은 이 앱 규칙상 공휴일 여부와 무관하게 항상 빨간날 취급이라
// (_getHolidayName와 별개로 weekday==sunday만으로 red 판정, _themedCellData 참고)
// 사실상 이 일/토 단계는 항상 토요일로 수렴함 - 그래도 로직은 대칭으로 둠.
// 이 함수는 순수하게 "그 주(일~토)에서 음력을 표기할 날짜가 며칠인지"만 계산 - 실제
// 그 날이 오늘 그리는 셀(day)과 같은지는 호출부에서 비교.
DateTime? _lunarLabelDateForWeek(DateTime anyDayInWeek, BuildContext context) {
  final normalized =
      DateTime(anyDayInWeek.year, anyDayInWeek.month, anyDayInWeek.day);
  final daysSinceSunday = normalized.weekday % 7; // Dart: 월=1..일=7 → 일=0
  final sunday = normalized.subtract(Duration(days: daysSinceSunday));
  bool isRed(DateTime d) =>
      d.weekday == DateTime.sunday || _getHolidayName(d, context) != null;

  final wed = sunday.add(const Duration(days: 3));
  if (!isRed(wed)) return wed;
  final tue = sunday.add(const Duration(days: 2));
  if (!isRed(tue)) return tue;
  final thu = sunday.add(const Duration(days: 4));
  if (!isRed(thu)) return thu;
  final mon = sunday.add(const Duration(days: 1));
  if (!isRed(mon)) return mon;
  final fri = sunday.add(const Duration(days: 5));
  if (!isRed(fri)) return fri;
  if (!isRed(sunday)) return sunday;
  final sat = sunday.add(const Duration(days: 6));
  if (!isRed(sat)) return sat;
  return null; // 일주일 내내 빨간날이면 이번 주는 음력 표기 없음
}

// ⭐ 테마별 헤더/요일행 표기에 쓰는 공용 상수 - calendar_theme_lab_screen.dart의
// 동명 상수(그 파일 안에서만 쓰이는 private const)와 값은 같지만 별도 파일이라
// 충돌 없음.
// ⭐ 영어 현지화: 예전엔 여기 _weekdayKr(일/월/화...) 배열이 따로 있었지만,
// 로케일에 따라 바뀌어야 하는 요일 표시는 utils/weekday_util.dart의
// weekdayLabel(context, i)로 통일됨(사용부 참고) - 이 배열은 삭제. 아래
// _weekdayEn3/_weekdayEn1은 "그 테마 디자인 자체가 항상 영어 약자로 보이는"
// 의도적 스타일이라 로케일과 무관하게 그대로 둠.
const List<String> _weekdayEn3 = [
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat'
];
const List<String> _weekdayEn1 = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const List<String> _monthEn3 = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

// ⭐ 다이어리 테마(CalendarThemeId.diary) 전용 포인트 컬러 - 헤더 점 장식/오늘
// 표시/빨간날 텍스트 등 이 테마 안 여러 곳에서 공유해서 씀(_themeDiaryCell,
// _buildThemedHeaderTitle 등). 근무색 자체는 kDiaryPalette(calendar_theme.dart)를
// 따로 쓰고, 이 색은 "테마 톤"(따뜻한 앰버)만 담당.
const Color _diaryAccent = Color(0xFFCB8A4E);

// ⭐ 2026-09-22 음력 표기(메인 달력, 매주 수요일 자리에 "(4.14)" 형태) 글자 크기 -
// 조정하고 싶으면 이 숫자만 바꾸면 됨(모든 테마 공통, .sp 적용 전 기준값).
// 색상은 조정 대상 아님(상세팝업의 "(없음)" 텍스트와 같은 colorScheme.onSurfaceVariant
// 고정 - _lunarCellTextStyle 참고). 표기 위치·표시 요일 결정 로직은 _lunarLabelDateForWeek 참고.
const double kLunarCellFontSize = 7.0;

// ⭐ 2026-09-22 소프트카드 테마(CalendarThemeId.materialCard, _theme2Cell)의 "이번 달"
// 셀 배경색 - "다른 날들이 하얀색이라 칙칙해 보인다"는 지적으로 중립 회색(옛 값
// 0xFFF1F2F6)에서 밝은 파스텔톤으로 교체. 조정하고 싶으면 이 색만 바꾸면 됨 - 반투명도
// (border/boxShadow)·outside(다른 달) 셀 스타일·그 위에 얹히는 근무명 배지 등은 그대로.
const Color kMaterialCardCurrentMonthCellColor = Color(0xFFF3F7F9);

// ⭐ 2026-09-01 - "빨간날(일요일/공휴일)이 오늘이면 원형 배지 안에서 숫자색이
// 흰색으로 바뀌어 버려서 '빨간날'이라는 신호가 사라진다"는 지적 - 메인·화이트/
// 다크가 이미 쓰던 해법(오늘 표시 원 배경만 빨간날 전용으로 바꾸고, 글자는
// 계속 빨간색 유지)을 그대로 따라함. _diaryAccent(진한 앰버)는 빨간 글씨와
// 색상환에서 너무 가깝고 명도도 비슷해 대비가 나빠서(둘 다 중간 톤의
// 붉은기 도는 색) 원 배경 그대로 두고 글자만 빨간색으로 바꾸면 잘 안
// 읽히므로, 오늘+빨간날 전용으로 훨씬 밝은 크림/골드 톤을 따로 둠(테마
// 톤은 유지하되 빨간 글씨와 대비가 확실히 나는 밝기로) - 평소(오늘 아닌)
// 빨간날 색이나 다른 날의 오늘 표시(_diaryAccent)는 전혀 안 건드림.
const Color _diaryTodayRedBg = Color(0xFFFCE2B0);

// StatefulWidget → ConsumerStatefulWidget으로 변경
class CalendarTab extends ConsumerStatefulWidget {
  // ⭐ 변경
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState(); // ⭐ 변경
}

class _CalendarTabState extends ConsumerState<CalendarTab> {
  // ⭐ 변경
  static const platform = kAlarmChannel; // ⭐ 추가

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
    return effectiveShiftColors(
        schedule.shiftTypes, theme, schedule.customShiftColors);
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

  // ⭐ 2026-09-05 - "불규칙 온보딩으로 맨 처음 메인 달력에 왔을 때" 1회 근무
  // 배정 방법 안내 팝업(사용자 요청) - build()가 여러 번 도는 동안 중복으로
  // 안 뜨게 막는 인메모리 가드. 실제 "평생 1회" 여부는
  // onboarding_info_popups.dart의 SharedPreferences 플래그가 담당함(이건 그
  // 비동기 저장이 끝나기 전에 같은 프레임에서 build가 다시 돌아 두 번 뜨는
  // 것만 막는 보조 장치).
  bool _shiftAssignTutorialChecked = false;

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

    final calendarStart =
        firstDayOfMonth.subtract(Duration(days: daysFromSunday));
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
    final daysFromSunday =
        firstDayOfMonth.weekday == 7 ? 0 : firstDayOfMonth.weekday;
    final calendarStart =
        firstDayOfMonth.subtract(Duration(days: daysFromSunday));
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
    final firstDay =
        DateTime(month.year, month.month, 1).subtract(Duration(days: 7));
    final lastDay =
        DateTime(month.year, month.month + 1, 0).add(Duration(days: 7));
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
                  Text(context.l10n.calendarSelectDate,
                      style: TextStyle(
                          fontSize: 20.sp, fontWeight: FontWeight.bold)),
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
                            style: TextStyle(
                                fontSize: 18.sp, fontWeight: FontWeight.bold),
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceVariant,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  isKorean
                                      ? '$month월'
                                      : monthFormat.format(
                                          DateTime(selectedYear, month)),
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.normal,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
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
    // ⭐ 2026-09-01 버그 수정 - 메인테마·다크가 흰 배경으로 깨졌던 원인이 바로
    // 아래 Scaffold들의 `backgroundColor: Colors.white` 하드코딩이었음. 2026-08-24에
    // "파스텔 배경에서 달력 탭만 제외"하려고 추가된 값인데, 그 의도(파스텔 대신
    // 흰색)만 담고 "메인·다크일 땐 흰색이 아니라 진한 남색이어야 한다"는 조건을
    // 놓쳤음. main.dart가 CalendarTab 전체를 `Theme(data: isDark ?
    // AppTheme.darkTheme : AppTheme.lightTheme)`로 감싸서 다크일 때 scaffoldBackgroundColor가
    // 0xFF1A1F2E가 되도록 이미 설계돼 있었는데, 이 화면이 그 값을 무시하고 흰색을
    // 직접 못박아버려서 이번 달 OT/주별근무시간 카드(별도 Container로 자기 배경을
    // 직접 그림 - 그래서 유일하게 안 깨져 보였음)를 제외한 모든 배경이 흰색으로
    // 보였던 것. calendarThemeProvider를 여기서 먼저 읽어(schedule 유무와 무관하게
    // 항상 값이 있음) 로딩/에러/스케줄없음 상태까지 포함한 모든 Scaffold가
    // 다크일 땐 0xFF1A1F2E(=AppTheme.darkTheme.scaffoldBackgroundColor와 동일한 값 -
    // app_theme.dart 참고, 두 값이 다시 어긋나지 않게 항상 이 상수를 그대로 씀),
    // 아니면 흰색을 쓰게 통일함.
    final isDarkTheme = ref.watch(calendarThemeProvider).isDark;
    final scaffoldBg = isDarkTheme ? const Color(0xFF1A1F2E) : Colors.white;

    return scheduleAsync.when(
      // ⭐ 로딩/에러/스케줄없음 상태도 달력 탭 배경 예외(위 build() 안쪽 Scaffold
      // 주석 참고)를 똑같이 적용 - 안 그러면 데이터 로드 전 짧은 순간 파스텔
      // 배경이 깜빡였다가 흰색/다크와 안 맞는 색으로 바뀌는 게 보일 수 있음.
      loading: () => Scaffold(
        backgroundColor: scaffoldBg,
        body: const SizedBox.shrink(), // ⭐ 로딩 인디케이터 제거
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: scaffoldBg,
        body:
            Center(child: Text('${context.l10n.statusErrorOccurred}: $error')),
      ),
      data: (schedule) {
        if (schedule == null) {
          return Scaffold(
            backgroundColor: scaffoldBg,
            body: Center(child: Text(context.l10n.statusNoSchedule)),
          );
        }

        if (!_shiftAssignTutorialChecked) {
          _shiftAssignTutorialChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted)
              maybeShowShiftAssignTutorial(context,
                  isRegular: schedule.isRegular);
          });
        }

        final theme = ref.watch(calendarThemeProvider);
        final reclaimsSixthRow = _themeReclaimsSixthRow(theme);
        // ⭐ 2026-09-05 - 6번째 줄 마지막 3칸(목/금/토)에 일정공유/전체 조 근무표/
        // 오늘 버튼(다이어리 + 범례 없는 나머지 5개 테마, _themeReclaimsSixthRowButtons
        // 참고). 목(일정공유)은 친구 유무와 무관하게 항상 표시(_openFriendShare 참고).
        final reclaimsSixthRowButtons = _themeReclaimsSixthRowButtons(theme);

        return Scaffold(
          // ⭐ 2026-08-24 - 앱 전역 배경을 파스텔톤(app_colors.dart의
          // kAppBackgroundPastel)으로 바꾸면서, 달력 탭은 그 대상에서 명시적으로
          // 제외함(9개 달력 테마 각자의 고유 배색을 그대로 유지하기 위해). 이
          // Scaffold가 배경색을 직접 고정해두지 않으면 AppTheme.lightTheme의
          // scaffoldBackgroundColor를 그대로 물려받아 파스텔톤이 되어버림 -
          // 예전부터 달력 탭이 실제로 보여주던 흰색을 여기서 명시적으로 고정.
          // ⭐ 2026-09-01 - 위 isDarkTheme 계산 참고, 메인·다크에선 흰색 대신
          // 0xFF1A1F2E를 씀(파일 상단 build() 진입부의 버그 수정 주석 참고).
          backgroundColor: scaffoldBg,
          body: SafeArea(
            // ⭐⭐ 2026-08-24 - 애드몹 배너 자리 확보 방식을 재설계함. 예전엔 여기서
            // "메인 테마가 고정 rowHeight(83.h)라 자연스럽게 남기는 여백"을 재서
            // 그 크기만큼 다른 테마도 똑같이 비워두는 식이었는데(SizedBox(adSpaceHeight)),
            // 이건 화면 "높이" 기준으로 계산한 여백이고, 실제 광고(AdMob 적응형 배너)
            // 높이는 화면 "폭" 기준으로 SDK가 계산함 - 서로 다른 기준의 값이라 기기마다
            // 우연히만 맞아떨어졌고, 안 맞으면 광고 위/아래에 뜬금없는 흰 여백이 생겼음.
            //
            // 이제는 이 위젯이 광고 높이를 아예 몰라도 됨 - main.dart에서 이미
            // BottomNavigationBar 바로 위에 실제 광고 높이(AdService.bannerHeight)만큼을
            // Column으로 미리 떼어내고, 그 "위"에 남는 공간만 Expanded로 이 탭에 줌
            // (banner_ad_slot.dart 참고). 그래서 이 위젯이 할 일은 "받은 높이를
            // 남김없이 다 쓰는" 것뿐 - 그러면 광고 자리를 뺀 나머지를 정확히 채우게
            // 되고, 여백이 생길 수가 없음(산수상 남는 공간 자체가 없으므로).
            // _themeRowHeight()가 이제 모든 테마(메인 포함)에서 "남는 높이를 6등분"하는
            // 동일한 방식을 쓰도록 통일한 게 이 전제의 나머지 절반 - 예전엔 메인
            // 테마만 83.h 고정값을 써서 그 아래 자기 몫의 남는 공간을 안 채우고 그냥
            // 비워뒀었음(project_ot_calendar_card 메모리 참고 - OT카드는 "행 전체 높이"를
            // 쓰는 게 조건이라 rowH 변수를 그대로 쓰는 이 구조는 그 조건을 그대로 만족함).
            child: Builder(
              builder: (context) {
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
                                height: 48.h,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8.w, vertical: 4.h),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _isMultiSelectMode
                                          ? Row(
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.close,
                                                      size: 20.sp),
                                                  onPressed:
                                                      _exitMultiSelectMode,
                                                  padding: EdgeInsets.zero,
                                                  constraints: BoxConstraints(),
                                                ),
                                                SizedBox(width: 8.w),
                                                Text(
                                                  context.l10n
                                                      .calendarNSelected(
                                                          _selectedDates
                                                              .length),
                                                  style: TextStyle(
                                                      fontSize: 16.sp,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ],
                                            )
                                          : _buildThemedHeaderTitle(theme),
                                      if (!_isMultiSelectMode)
                                        _buildThemedHeaderButtons(
                                            theme, schedule),
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
                                final rowH = _themeRowHeight(
                                    theme, constraints.maxHeight);
                                return Stack(
                                  children: [
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 6.w),
                                      child: TableCalendar(
                                        firstDay: DateTime(
                                            DateTime.now().year - 3, 1, 1),
                                        lastDay: DateTime(
                                            DateTime.now().year + 3, 12, 31),
                                        focusedDay: _focusedDay,
                                        selectedDayPredicate: (day) {
                                          if (_isMultiSelectMode) {
                                            return _selectedDates
                                                .any((d) => isSameDay(d, day));
                                          }
                                          return isSameDay(_selectedDay, day);
                                        },
                                        locale: Localizations.localeOf(context)
                                                    .languageCode ==
                                                'ko'
                                            ? 'ko_KR'
                                            : 'en_US',

                                        headerVisible: false,
                                        sixWeekMonthsEnforced:
                                            true, // ⭐ 항상 6줄 고정
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
                                          tableBorder: (theme ==
                                                      CalendarThemeId
                                                          .mainWhite ||
                                                  theme ==
                                                      CalendarThemeId.mainDark)
                                              ? TableBorder.all(
                                                  color: Theme.of(context)
                                                              .brightness ==
                                                          Brightness.dark
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(
                                                              0.4) // 다크모드: 더 밝게
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(
                                                              0.15), // 화이트모드: 더 진하게
                                                  width: 1.0,
                                                )
                                              : const TableBorder(),

                                          defaultTextStyle: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface),
                                          weekendTextStyle: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface),
                                          outsideTextStyle: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant),

                                          todayDecoration: BoxDecoration(
                                            color: Colors
                                                .transparent, // ⭐ 배경 제거, 날짜 숫자만 표시
                                          ),
                                          todayTextStyle: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface),

                                          selectedDecoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondary
                                                .withOpacity(_isMultiSelectMode
                                                    ? 0.3
                                                    : 1.0),
                                            shape: BoxShape.circle,
                                          ),
                                          selectedTextStyle: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSecondary),
                                        ),

                                        calendarBuilders: CalendarBuilders(
                                          // ⭐ "그리드/요일 표기까지 테마마다 다 다르게 만들어놓고 실제로는
                                          // 그 틀 안에서만 그린다"는 지적 - 요일 헤더 표기(일/월/... vs
                                          // Sun/Mon/... vs S/M/...)도 테마별로 다르므로 daysOfWeekStyle(같은
                                          // 로케일 문구에 스타일만 입히는 것) 대신 dowBuilder로 완전히
                                          // 테마마다 다른 위젯을 그림.
                                          dowBuilder: (context, day) =>
                                              _buildThemedDow(theme, day),
                                          // ⭐ 여기 4개 콜백만 _buildDateCell → _buildThemedCell로 교체함 -
                                          // 선택된 테마에 따라 셀 디자인을 바꿔주는 유일한 진입점.
                                          // onDaySelected/onDayLongPressed 등 나머지 로직은 전혀 안 건드림.
                                          defaultBuilder:
                                              (context, day, focusedDay) {
                                            // ⭐ 6번째 줄 화~토는 빈 Container (범례/OT 카드가 그 자리를
                                            // 대신 차지하는 테마에서만 - 아래 reclaimsSixthRow 참고)
                                            if (_isRowSixReclaimed(
                                                day, focusedDay,
                                                reclaimsSixthRow:
                                                    reclaimsSixthRow,
                                                reclaimsSixthRowButtons:
                                                    reclaimsSixthRowButtons,
                                                includeAllShiftsCol:
                                                    schedule.isRegular)) {
                                              return Container();
                                            }
                                            return _buildThemedCell(day, false,
                                                false, schedule, focusedDay);
                                          },
                                          outsideBuilder:
                                              (context, day, focusedDay) {
                                            if (_isRowSixReclaimed(
                                                day, focusedDay,
                                                reclaimsSixthRow:
                                                    reclaimsSixthRow,
                                                reclaimsSixthRowButtons:
                                                    reclaimsSixthRowButtons,
                                                includeAllShiftsCol:
                                                    schedule.isRegular)) {
                                              return Container();
                                            }
                                            return _buildThemedCell(day, false,
                                                true, schedule, focusedDay);
                                          },
                                          todayBuilder:
                                              (context, day, focusedDay) {
                                            if (_isRowSixReclaimed(
                                                day, focusedDay,
                                                reclaimsSixthRow:
                                                    reclaimsSixthRow,
                                                reclaimsSixthRowButtons:
                                                    reclaimsSixthRowButtons,
                                                includeAllShiftsCol:
                                                    schedule.isRegular)) {
                                              return Container();
                                            }
                                            // ⭐ 위 _buildThemedCell 주석과 동일한 이유로, "오늘이 지금 이
                                            // 페이지 기준 바깥달 날짜인가"도 상태(_focusedDay)가 아니라 이
                                            // 콜백이 실제로 받은 focusedDay(그 페이지가 나타내는 달) 기준으로.
                                            final isOutsideMonth =
                                                day.month != focusedDay.month ||
                                                    day.year != focusedDay.year;
                                            return _buildThemedCell(
                                                day,
                                                true,
                                                isOutsideMonth,
                                                schedule,
                                                focusedDay);
                                          },
                                          selectedBuilder:
                                              (context, day, focusedDay) {
                                            if (_isRowSixReclaimed(
                                                day, focusedDay,
                                                reclaimsSixthRow:
                                                    reclaimsSixthRow,
                                                reclaimsSixthRowButtons:
                                                    reclaimsSixthRowButtons,
                                                includeAllShiftsCol:
                                                    schedule.isRegular)) {
                                              return Container();
                                            }
                                            return _buildThemedCell(
                                                day,
                                                isSameDay(day, DateTime.now()),
                                                false,
                                                schedule,
                                                focusedDay,
                                                isSelected: true);
                                          },
                                        ),

                                        onDaySelected:
                                            (selectedDay, focusedDay) {
                                          // ⭐ 이전/다음 달 날짜는 탭 무시
                                          if (selectedDay.month !=
                                                  _focusedDay.month ||
                                              selectedDay.year !=
                                                  _focusedDay.year) {
                                            return;
                                          }

                                          // ⭐ 6번째 줄 빈 칸은 탭 무시 (범례/OT 카드가 있는 테마만)
                                          if (_isRowSixReclaimed(
                                              selectedDay, focusedDay,
                                              reclaimsSixthRow:
                                                  reclaimsSixthRow,
                                              reclaimsSixthRowButtons:
                                                  reclaimsSixthRowButtons,
                                              includeAllShiftsCol:
                                                  schedule.isRegular)) {
                                            return;
                                          }

                                          setState(() {
                                            _focusedDay = focusedDay;
                                          });

                                          if (_isMultiSelectMode) {
                                            _toggleDateSelection(selectedDay);
                                          } else {
                                            _showDayDetailPopup(
                                                selectedDay, schedule);
                                          }
                                        },

                                        onDayLongPressed:
                                            (selectedDay, focusedDay) {
                                          // ⭐ 이전/다음 달 날짜는 길게 누르기 무시
                                          if (selectedDay.month !=
                                                  _focusedDay.month ||
                                              selectedDay.year !=
                                                  _focusedDay.year) {
                                            return;
                                          }

                                          // ⭐ 6번째 줄 빈 칸은 길게 누르기 무시 (범례/OT 카드가 있는 테마만)
                                          if (_isRowSixReclaimed(
                                              selectedDay, focusedDay,
                                              reclaimsSixthRow:
                                                  reclaimsSixthRow,
                                              reclaimsSixthRowButtons:
                                                  reclaimsSixthRowButtons,
                                              includeAllShiftsCol:
                                                  schedule.isRegular)) {
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
                                    // ⭐ 2026-09-05 - 언더라인/매거진(범례 필수 2개 테마)은 화~토 5칸을
                                    // 범례가 다 쓰고 있어 6번째 줄에 일정공유 버튼을 넣을 자리가 없음 -
                                    // 이 두 테마는 대신 헤더(_buildThemedHeaderButtonsCore)의 전체조
                                    // 근무표 왼쪽에 일정공유 버튼을 넣음. 일/월 칸은 그대로 빈 채로
                                    // 제스처를 아래 TableCalendar로 전달(다른 재활용 테마와 동일).
                                    if (reclaimsSixthRow)
                                      Positioned(
                                        top: 28.h + rowH * 5, // 요일 헤더 + 5줄
                                        left: 6.w,
                                        right: 6.w,
                                        height: rowH,
                                        child: Row(
                                          children: [
                                            // 일요일 + 월요일 칸 (다음 달 날짜 표시 - 제스처를 아래 TableCalendar로 전달)
                                            const Expanded(
                                              flex: 2,
                                              child: IgnorePointer(
                                                  child: SizedBox()),
                                            ),
                                            // 화~토 칸 - 테마에 따라 월별 OT 카드 또는 범례
                                            // ⭐ 2026-09-11 - 범례(언더라인/매거진)도 다른 테마의 버튼
                                            // 3칸과 같은 영역이니 스와이프로 월 이동되게 함
                                            // (_wrapWithMonthSwipe 참고). 메인 화이트/다크의
                                            // _buildMonthlyOvertimeCard()는 이미 자체적으로 같은
                                            // 래핑을 하고 있어 또 감쌀 필요 없음.
                                            Expanded(
                                              flex: 5,
                                              child: (theme ==
                                                          CalendarThemeId
                                                              .mainWhite ||
                                                      theme ==
                                                          CalendarThemeId
                                                              .mainDark)
                                                  ? _buildMonthlyOvertimeCard()
                                                  : _wrapWithMonthSwipe(
                                                      _buildThemedLegend(
                                                          theme, schedule)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // ⭐ 2026-09-05 - 6번째 줄 마지막 3칸(목/금/토)에 일정공유/전체 조
                                    // 근무표/오늘 버튼 고정 배치(_themeReclaimsSixthRowButtons 참고 -
                                    // 다이어리 + 범례 없는 나머지 5개 테마). 위 reclaimsSixthRow
                                    // 블록과 같은 세로 위치(top)를 쓰지만 서로 겹치는 테마가 없어
                                    // 동시에 그려질 일은 없음. 목(일정공유)은 친구 유무와 무관하게
                                    // 항상 그림 - 친구가 없으면 눌렀을 때 FriendListScreen의
                                    // "친구 추가" 빈 상태로 감(에러 아님).
                                    if (reclaimsSixthRowButtons)
                                      Positioned(
                                        top: 28.h + rowH * 5,
                                        left: 6.w,
                                        right: 6.w,
                                        height: rowH,
                                        // ⭐ 2026-09-11(사용자 요청) - 이 버튼 3칸(목/금/토) 위에서도
                                        // 좌우 스와이프로 월 이동이 되게 바깥을 _wrapWithMonthSwipe로
                                        // 감쌈. 안쪽 각 버튼의 onTap은 그대로 살아있음(제스처 아레나가
                                        // 탭/드래그를 알아서 중재 - _wrapWithMonthSwipe 주석 참고).
                                        child: _wrapWithMonthSwipe(Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            // 일~수 칸 (다음 달 날짜 표시 - 제스처를 아래 TableCalendar로 전달)
                                            const Expanded(
                                              flex: 4,
                                              child: IgnorePointer(
                                                  child: SizedBox()),
                                            ),
                                            // ⭐ 2026-09-13 - 버튼 순서를 전체근무표/일정공유/오늘로
                                            // 바꿈(사용자 지적/제안) - 불규칙 근무자는 전체근무표가
                                            // 안 보이는데, 예전 순서(일정공유/전체근무표/오늘)에서는
                                            // 그 빈 자리가 두 버튼 "사이"(목-금-토 중 금)에 끼어서,
                                            // 이미 항상 비어있는 왼쪽 4칸(일~수)과 안 이어지고 뜬금없이
                                            // 그 자리만 달력 그리드가 비쳐 보였음. 조건부로 사라지는
                                            // 버튼(전체근무표)을 이 3칸 중 맨 왼쪽(목)에 두면, 사라졌을
                                            // 때 왼쪽 4칸의 빈 공간과 자연스럽게 하나로 이어져서 더 이상
                                            // 튀어 보이지 않음.
                                            // 목 - 전체근무표, 규칙적 근무자만. ⭐ "전체 조 근무표"가
                                            // 한 줄엔 안 들어가 잘려 보여서, 자리가 좁은 이 칩에서만
                                            // 한국어 로케일 한정으로 "전체 조\n근무표" 두 줄로 직접
                                            // 끊음(공용 l10n 문자열 자체는 안 건드림 - 다른 테마
                                            // 버튼/AppBar 제목 등은 그대로 한 줄 문구).
                                            Expanded(
                                              child: schedule.isRegular
                                                  ? _rowSixButton(
                                                      theme,
                                                      icon: Icons
                                                          .grid_view_rounded,
                                                      label: Localizations
                                                                      .localeOf(
                                                                          context)
                                                                  .languageCode ==
                                                              'ko'
                                                          ? '전체 조\n근무표'
                                                          : context.l10n
                                                              .shiftFullSchedule,
                                                      onTap: _openAllShiftsView,
                                                    )
                                                  : const IgnorePointer(
                                                      child: SizedBox()),
                                            ),
                                            // 금 - 일정공유, 항상
                                            Expanded(
                                              child: _rowSixButton(
                                                theme,
                                                icon: Icons.people_alt_outlined,
                                                label: context
                                                    .l10n.friendShareTitle,
                                                onTap: _openFriendShare,
                                              ),
                                            ),
                                            // 토 - 오늘, 항상
                                            Expanded(
                                              child: _rowSixButton(
                                                theme,
                                                icon: Icons.today_rounded,
                                                label: context.l10n.commonToday,
                                                onTap: _jumpToToday,
                                              ),
                                            ),
                                          ],
                                        )),
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
                                        child: Container(
                                            color: Colors.grey.shade200),
                                      ),
                                    // ⭐ 2026-09-13 - 다크 그리드(굵은 격자형)만의 추가 지적 - 토(오늘
                                    // 버튼) 칸은 위 _isSixthRowButtonCell 규칙상 항상 reclaim되어
                                    // row6에 실제 셀이 안 그려지므로, 5번째 줄 토요일 칸 밑 가로
                                    // 테두리가 (이웃 칸들처럼 위아래 두 셀 테두리가 겹쳐 두꺼워지는
                                    // 것과 달리) row5 자신의 테두리 한 겹만 남아 얇아 보임 - 같은
                                    // 굵기(0.6)의 선을 하나 더 겹쳐 그어서 다른 칸들과 두께를 맞춤.
                                    // 목(전체근무표) 칸은 불규칙+근무 미배정일 때 이제 reclaim되지
                                    // 않아(위 case 4 수정) 실제 셀이 그대로 그려지므로 자동으로
                                    // 두꺼워짐 - 여기서 따로 안 그려도 됨.
                                    if (theme == CalendarThemeId.boldGrid)
                                      Positioned(
                                        top: 28.h + rowH * 5 - 0.6,
                                        left: 6.w,
                                        right: 6.w,
                                        height: 0.6,
                                        child: Row(
                                          children: [
                                            const Expanded(
                                                flex: 4,
                                                child: SizedBox.shrink()),
                                            const Expanded(
                                                child: SizedBox
                                                    .shrink()), // 목 - 자동으로 두꺼워짐
                                            const Expanded(
                                                child: SizedBox.shrink()), // 금
                                            Expanded(
                                                child: Container(
                                                    color: Colors
                                                        .grey.shade600)), // 토
                                          ],
                                        ),
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
                          // ⭐ 2026-08-24 - 예전엔 여기서 "메인 테마를 흉내낸 여백"을 명시적으로
                          // 넣었었는데(위 Builder 진입부 주석 참고), 이제 모든 테마가 남는
                          // 높이를 100% 채우도록 통일했으므로 더 채울 여백 자체가 없어져서 삭제함.
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
                                Text(context.l10n.shiftChange,
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                Text(context.l10n.calendarTapToAddMoreDates,
                                    style: TextStyle(fontSize: 10.sp)),
                              ],
                            ),
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceVariant,
                            foregroundColor:
                                Theme.of(context).colorScheme.onSurface,
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
  // 🔧 메인·화이트/메인·다크 전용(6번째 줄을 이 카드가 차지 - _themeReclaimsSixthRow
  // 참고). 라벨/값 글자 크기는 아래 두 Text 블록(위 절반 "이번 달 OT", 아래
  // 절반 "주별 근무시간")의 fontSize 각각 따로. 색은 항상 colorScheme.*만
  // 참조하므로 다크에서 자동으로 다크 배색을 받음(이 함수는 2026-09-01 배경
  // 버그와 무관 - 애초부터 하드코딩 색이 없었음).
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
        // ⭐ 2026-09-05 - "(해당 날짜 탭하여 입력)" 안내문구 삭제 요청. OT가 0이어도
        // 그냥 0으로 포맷해서 보여줌(안내문 없이) - 다이어리 쪽 6번째 줄 버튼처럼
        // 이 카드도 값 있음/없음 구분 없이 항상 실제 값을 보여주는 게 더 일관됨.

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
                // ⭐ 2026-09-05 - 세로 분할 50/50 → 30/30/40 재구성(요청: "이번 달
                // OT랑 주별 근무시간이 60을 30/30으로 나눠 쓰고, 남는 40에 친구/전체
                // 조 근무표/오늘 버튼을 다이어리와 같은 순서로"). 위 두 줄(OT/주별)은
                // flex 3씩, 아래 버튼 줄이 flex 4.
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showMonthlyOvertimeSheet(period),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(left: 10.w),
                      // ⭐ 가운데 정렬 → 왼쪽 정렬 요청
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
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
                            // ⭐ "(해당 날짜 탭하여 입력)" 안내문 삭제 - 0이어도 그냥 값 표시
                            Text(
                              formatOvertimeMinutes(context, totalMinutes),
                              style: TextStyle(
                                fontSize: hasOvertime ? 13.sp : 11.sp,
                                fontWeight: hasOvertime
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: hasOvertime
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
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
                Container(
                    height: 1, color: colorScheme.outline.withOpacity(0.3)),
                // ⭐ 아래 절반: 주별 근무시간 (색을 살짝 다르게 줘서 구분감을 한 번 더 줌)
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showWeeklyWorkHoursSheet,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(left: 10.w),
                      alignment: Alignment.centerLeft,
                      color: isDark
                          ? colorScheme.surfaceVariant.withOpacity(0.25)
                          : colorScheme.surface.withOpacity(0.5),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
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
                            Icon(Icons.chevron_right,
                                size: 14.sp,
                                color: colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                    height: 1, color: colorScheme.outline.withOpacity(0.3)),
                // ⭐ 2026-09-05 - 남는 40%에 일정공유/전체 조 근무표/오늘 진입 버튼
                // (다이어리 6번째 줄 버튼과 같은 좌→우 순서: 화/수는 비우고
                // 목=일정공유, 금=전체 조 근무표, 토=오늘 - 고정). 목(일정공유)은
                // 친구 유무와 무관하게 항상 표시. 다이어리보다 세로 자리가 훨씬
                // 좁아서(이 카드 전체 높이의 40%뿐) 라벨 없이 아이콘만 두되,
                // colorScheme.primaryContainer/onPrimaryContainer를 그대로 써서
                // 라이트/다크 양쪽에서 자동으로 대비되는 색을 얻음(이 카드가 이미
                // 따르던 "색은 colorScheme만 참조" 원칙을 그대로 이어감 - 다이어리처럼
                // 이 테마 전용 하드코딩 색을 새로 만들 필요 없음).
                Expanded(
                  flex: 4,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(flex: 2, child: SizedBox.shrink()),
                      // ⭐ 2026-09-13 - 위 reclaimsSixthRowButtons 블록과 동일한 이유로
                      // 순서를 전체근무표/일정공유/오늘로 바꿈 - 불규칙 근무자는
                      // 전체근무표가 사라지는데, 예전 순서에선 그 자리가 일정공유와
                      // 오늘 "사이"에 끼어서 일정공유 버튼이 오늘 버튼과 안 붙고
                      // 중간에 붕 떠 보였음. 조건부 버튼을 맨 앞(왼쪽 spacer 바로
                      // 옆)에 두면 사라졌을 때 왼쪽 spacer와 자연스럽게 이어짐.
                      Expanded(
                        child: (schedule?.isRegular ?? false)
                            ? _mainThemeRowSixButton(
                                colorScheme: colorScheme,
                                icon: Icons.grid_view_rounded,
                                onTap: _openAllShiftsView,
                              )
                            : const SizedBox.shrink(),
                      ),
                      Expanded(
                        child: _mainThemeRowSixButton(
                          colorScheme: colorScheme,
                          icon: Icons.people_alt_outlined,
                          onTap: _openFriendShare,
                        ),
                      ),
                      Expanded(
                        child: _mainThemeRowSixButton(
                          colorScheme: colorScheme,
                          icon: Icons.today_rounded,
                          onTap: _jumpToToday,
                        ),
                      ),
                    ],
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
    final newMonth =
        DateTime(_focusedDay.year, _focusedDay.month + direction, 1);
    setState(() {
      _focusedDay = newMonth;
    });
    _loadMemosForMonth(newMonth);
  }

  // ⭐ 2026-09-11(사용자 요청) - 6번째 줄을 재활용하는 영역(일정공유/전체근무표/
  // 오늘 버튼, 범주 범례) 위에서도 달력 그리드와 똑같이 좌우 스와이프로 월
  // 이동이 되게 함. _buildMonthlyOvertimeCard()가 이미 이 방식(바깥
  // GestureDetector가 onHorizontalDragEnd로 스와이프를 잡고, 안쪽 각 버튼의
  // GestureDetector가 탭을 그대로 잡음 - Flutter 제스처 아레나가 "손가락이
  // touch slop을 넘게 움직이면 드래그가, 그대로 떼면 탭이 이긴다"로 알아서
  // 중재해줘서 버튼 탭 기능은 전혀 안 깨짐)로 이미 검증돼 있어서, 그 로직만
  // 재사용 가능한 래퍼로 뽑음(같은 속도 임계값 300 유지 - 다른 데서 손대지
  // 말 것, 여러 군데서 값이 어긋나면 체감 스와이프 민감도가 달라짐).
  Widget _wrapWithMonthSwipe(Widget child) {
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
      child: child,
    );
  }

  // ⭐ 이번 달 OT 상세 목록 시트 (기준 기간은 달력 월 기준일 수도, 급여일 기준일
  // 수도 있음 - work_hours_settings_provider의 periodForMonth()가 결정)
  void _showMonthlyOvertimeSheet(DateTimeRange period) {
    // ⭐ 영어 현지화: '$month월' 조립 대신 로케일 인식 월 이름(예: "8월" / "August")
    final monthLabel = DateFormat.MMMM(
            Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en')
        .format(_focusedDay);

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
            final periodLabel = workSettings.periodLabel(_focusedDay,
                isKorean: Localizations.localeOf(context).languageCode == 'ko');
            final colorScheme = Theme.of(context).colorScheme;
            final totalWorkMinutes = schedule == null
                ? 0
                : computeTotalWorkMinutes(
                    schedule: schedule,
                    start: period.start,
                    end: period.end,
                    otByDate: otByDate,
                  );

            return SafeArea(
              top: false,
              child: DraggableScrollableSheet(
                initialChildSize: 0.55,
                minChildSize: 0.3,
                maxChildSize: 0.85,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
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
                          context.l10n.calendarOtTotal(
                              formatOvertimeMinutes(context, totalMinutes)),
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          context.l10n.calendarMonthlyWorkTotal(monthLabel,
                              formatOvertimeMinutes(context, totalWorkMinutes)),
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // ⭐ 근무카드에 근무시간이 하나도 설정 안 돼 있으면 위 합산은
                        // 사실상 OT만 반영된 값 - 오해 없게 안내 문구를 추가함
                        if (schedule != null &&
                            !schedule.hasAnyWorkDuration) ...[
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
                                    style: TextStyle(
                                        fontSize: 14.sp,
                                        color: colorScheme.onSurfaceVariant),
                                  ),
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  itemCount: entries.length,
                                  separatorBuilder: (_, __) =>
                                      SizedBox(height: 8.h),
                                  itemBuilder: (context, index) {
                                    final entry = entries[index];
                                    final date = entry.date;
                                    final weekdayStr =
                                        _getWeekday(date, context);

                                    // ⭐ 근무변경으로 늘어난 시간이 있으면 "휴무 → 주간 (12시간)"
                                    // 부제목 추가, 수동 OT까지 있으면 옆에 "OT 3시간"도 같이 표기
                                    // (우측 총합은 항상 entry.totalMinutes = 이 둘의 합)
                                    final hasManual = entry.hasImplied &&
                                        entry.manualMinutes > 0;
                                    final shiftChangeLabel = entry.hasImplied
                                        ? '${entry.fromShift} → ${entry.toShift} (${formatOvertimeMinutes(context, entry.impliedMinutes)})${hasManual ? ',' : ''}'
                                        : null;
                                    final manualLabel = hasManual
                                        ? '+ OT ${formatOvertimeMinutes(context, entry.manualMinutes)}'
                                        : null;

                                    return Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 14.w, vertical: 12.h),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceVariant
                                            .withOpacity(0.4),
                                        borderRadius:
                                            BorderRadius.circular(10.r),
                                        border: Border.all(
                                            color: colorScheme.outline
                                                .withOpacity(0.3)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                '${DateFormat.MMMd(Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en').format(date)} ($weekdayStr)',
                                                style: TextStyle(
                                                    fontSize: 14.sp,
                                                    color:
                                                        colorScheme.onSurface),
                                              ),
                                              Spacer(),
                                              Text(
                                                formatOvertimeMinutes(context,
                                                    entry.totalMinutes),
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
                                                  style: TextStyle(
                                                      fontSize: 12.sp,
                                                      color: colorScheme
                                                          .onSurfaceVariant),
                                                ),
                                                if (manualLabel != null) ...[
                                                  SizedBox(width: 10.w),
                                                  Text(
                                                    manualLabel,
                                                    style: TextStyle(
                                                      fontSize: 12.sp,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: colorScheme
                                                          .onSurfaceVariant,
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
              ),
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
    final monthLabel = DateFormat.MMMM(
            Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en')
        .format(_focusedDay);
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
                  padding:
                      EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
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
                        style: TextStyle(
                            fontSize: 12.sp,
                            color: colorScheme.onSurfaceVariant),
                      ),
                      SizedBox(height: 16.h),

                      Expanded(
                        child: schedule == null
                            ? Center(
                                child: Text(
                                  context.l10n.calendarSetScheduleFirst,
                                  style: TextStyle(
                                      fontSize: 14.sp,
                                      color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            // ⭐ 근무카드에 근무시간이 하나도 설정 안 돼 있으면 누적할
                            // 근거가 없으므로 (전부 0시간) 리스트 대신 설정 안내만 보여줌
                            : !schedule.hasAnyWorkDuration
                                ? Center(
                                    child: Text(
                                      context.l10n
                                          .calendarSpecifyWorkHoursInSettings,
                                      style: TextStyle(
                                          fontSize: 14.sp,
                                          color: colorScheme.onSurfaceVariant),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : ListView.separated(
                                    controller: scrollController,
                                    itemCount: summaries.length,
                                    separatorBuilder: (_, __) =>
                                        SizedBox(height: 8.h),
                                    itemBuilder: (context, index) {
                                      final s = summaries[index];

                                      // ⭐ "주간 2일, 야간 3일, ..." 형태로 근무명별 일수 나열
                                      // (일수가 많은 순 → 이름 가나다순으로 안정적인 정렬)
                                      final countEntries =
                                          s.shiftDayCounts.entries.toList()
                                            ..sort((a, b) {
                                              final byCount =
                                                  b.value.compareTo(a.value);
                                              return byCount != 0
                                                  ? byCount
                                                  : a.key.compareTo(b.key);
                                            });
                                      final countsStr = countEntries
                                          .map((e) => context.l10n
                                              .calendarShiftDayCount(
                                                  e.key, e.value))
                                          .join(', ');
                                      final otSuffix = s.otMinutes > 0
                                          ? ', OT ${formatOvertimeMinutes(context, s.otMinutes)}'
                                          : '';

                                      return Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 14.w, vertical: 12.h),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceVariant
                                              .withOpacity(0.4),
                                          borderRadius:
                                              BorderRadius.circular(10.r),
                                          border: Border.all(
                                              color: colorScheme.outline
                                                  .withOpacity(0.3)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  '${s.start.month}/${s.start.day} ~ ${s.end.month}/${s.end.day}',
                                                  style: TextStyle(
                                                    fontSize: 14.sp,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                ),
                                                Spacer(),
                                                Text(
                                                  formatOvertimeMinutes(
                                                      context, s.totalMinutes),
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
                                                style: TextStyle(
                                                    fontSize: 12.sp,
                                                    color: colorScheme
                                                        .onSurfaceVariant),
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
              hasOvertime
                  ? formatOvertimeMinutes(context, minutes)
                  : context.l10n.commonNone,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
                color: hasOvertime
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
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
          color: enabled
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceVariant.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color:
              enabled ? colorScheme.onSecondaryContainer : colorScheme.outline,
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

  // ┌──────────────────────────────────────────────────────────────────┐
  // │ ⭐ 2026-09-01 - "달력 테마 9종을 VS Code + 핫 리로드로 직접 손보고    │
  // │ 싶다"는 요청으로 추가한 지도(찾아가기용) 주석. 테마 하나당 손댈 만한  │
  // │ 코드가 여러 함수에 흩어져 있어서(헤더/요일/셀/푸터가 전부 별도       │
  // │ 함수), 아래 표로 "이 테마 → 이 함수들" 을 한 번에 찾을 수 있게 함.   │
  // │ 함수 안에서는 switch(theme)의 case 하나가 그 테마 담당 - 그 케이스   │
  // │ 안에서 fontSize/color/padding/margin/Positioned 값만 바꾸면 됨.     │
  // │ (테마 목록 자체는 lib/models/calendar_theme.dart의 CalendarThemeId, │
  // │ 근무색 팔레트/로테이션도 그 파일 - 레이아웃과는 무관, 색상표만 있음) │
  // │                                                                    │
  // │ 【메인 · 화이트 / 메인 · 다크】 (CalendarThemeId.mainWhite/mainDark) │
  // │  - 헤더 타이틀      : _buildThemedHeaderTitle() 의 mainWhite/       │
  // │                       mainDark case (둘이 같은 case 블록 공유)      │
  // │  - 요일(월화수..)   : _buildThemedDow() 의 mainWhite/mainDark case  │
  // │  - 달력 격자선      : build() 안 tableBorder (mainWhite/mainDark만  │
  // │                       table_calendar 기본 격자를 켬 - 나머지 7개는 │
  // │                       각자 셀 안에서 직접 테두리를 그림)            │
  // │  - 날짜 셀(1~5줄)   : _buildDateCell() ⭐ 유일하게 다른 함수 이름    │
  // │                       (7개 실험 테마는 _theme*Cell, 이건 원래부터   │
  // │                       있던 이름 그대로 씀) - 근무명/날짜숫자/공휴일/ │
  // │                       메모가 전부 이 안에 있음                      │
  // │  - 6번째 줄(OT카드) : _buildMonthlyOvertimeCard() - "이번 달 OT" /  │
  // │                       "주별 근무시간" 위아래 2단 카드               │
  // │  - 배경/다크 배색   : main.dart의 Theme(data: isDark ? darkTheme :  │
  // │                       lightTheme) 래퍼 + 이 파일 build() 의         │
  // │                       scaffoldBg(2026-09-01 버그 수정 참고) - 다크  │
  // │                       배색 값 자체는 theme/app_theme.dart           │
  // │                       darkTheme(ColorScheme)에서 바꿈, 여기서 직접  │
  // │                       색을 하드코딩하지 않음(colorScheme.* 참조뿐)  │
  // │  - 별도 푸터/범례 없음(6번째 줄이 이미 그 역할)                     │
  // │                                                                    │
  // │ 【1번 · 미니멀 라인】 (CalendarThemeId.minimal)                     │
  // │  - 헤더/요일/푸터   : 각 함수의 minimal case                        │
  // │  - 날짜 셀          : _theme1Cell()                                 │
  // │                                                                    │
  // │ 【2번 · 머티리얼 카드형】 (CalendarThemeId.materialCard)             │
  // │  - 헤더/요일/푸터   : 각 함수의 materialCard case                    │
  // │  - 날짜 셀          : _theme2Cell()                                 │
  // │  - 페이지 전체 배경 : _themeBodyBackground() (이 테마만 옅은 회색)   │
  // │                                                                    │
  // │ 【4번 · 굵은 격자형】 (CalendarThemeId.boldGrid)                     │
  // │  - 헤더/요일/푸터   : 각 함수의 boldGrid case                        │
  // │  - 날짜 셀          : _theme4Cell()                                 │
  // │  - 헤더 배경        : _themeHeaderBackground() (이 테마만 어두운     │
  // │                       배경 - 흰 헤더 글씨가 안 보이던 버그 수정 흔적)│
  // │                                                                    │
  // │ 【5번 · 이니셜 뱃지형】 (CalendarThemeId.initialBadge)               │
  // │  - 헤더/요일/푸터   : 각 함수의 initialBadge case                    │
  // │  - 날짜 셀          : _theme5Cell()                                 │
  // │                                                                    │
  // │ 【8번 · 언더라인 미니멀형】 (CalendarThemeId.underline)              │
  // │  - 헤더/요일/푸터   : 각 함수의 underline case                       │
  // │  - 날짜 셀          : _theme8Cell()                                 │
  // │  - 범례(6번째 줄)   : _buildThemedLegend() 의 underline case         │
  // │                       (색상만으로 근무를 구분해서 범례 필수)         │
  // │                                                                    │
  // │ 【9번 · 이벤트 칩형】 (CalendarThemeId.eventChip)                    │
  // │  - 헤더/요일/푸터   : 각 함수의 eventChip case                       │
  // │  - 날짜 셀          : _theme9Cell() (+ 근무명/공휴일/메모가 전부     │
  // │                       공용 알약(pill) 위젯 _themeChip()을 재사용)    │
  // │                                                                    │
  // │ 【10번 · 매거진 에디토리얼형】 (CalendarThemeId.editorial)           │
  // │  - 헤더/요일/푸터   : 각 함수의 editorial case                       │
  // │  - 날짜 셀          : _theme10Cell() (날짜/공휴일/메모를 전부 셀     │
  // │                       우측 정렬 Positioned로 배치하는 게 이 테마만   │
  // │                       가진 특징)                                    │
  // │  - 범례(6번째 줄)   : _buildThemedLegend() 의 editorial case         │
  // │                                                                    │
  // │ 【다이어리】 (CalendarThemeId.diary, 2026-09-01 신설)                │
  // │  - 헤더/요일/푸터   : 각 함수의 diary case (헤더엔 제목만, 전체근무표/  │
  // │                       오늘/친구 버튼은 6번째 줄로 - 2026-09-05 실험,   │
  // │                       _themeReclaimsSixthRowButtons/                │
  // │                       _diaryRowSixButton() 참고. 푸터는              │
  // │                       _themeDiaryFooter())                          │
  // │  - 날짜 셀          : _themeDiaryCell() - 상단을 날짜|근무명 절반씩   │
  // │                       나눈 박스(근무명 쪽만 배지처럼 색 채움) +       │
  // │                       공휴일이 있으면 그 아래도 테두리로 한 번 더     │
  // │                       구획, 메모 3개는 테두리 없이 자유롭게          │
  // │  - 전용 팔레트      : kDiaryPalette(calendar_theme.dart) - 채도 낮춘  │
  // │                       차분한 톤                                     │
  // │                                                                    │
  // │ 【1/2/4/5/9번(=6번째 줄을 안 쓰는 5개) 공용 OT 푸터】                │
  // │  - 실제 그리는 함수 : _themeOtBar()(1/5/9 공유) /                    │
  // │                       _theme2OtCardReal()+_otChipReal()(2번) /       │
  // │                       _theme4FooterReal()(4번) - 어느 테마가 어느    │
  // │                       함수를 쓰는지는 _buildThemedFooter()의 switch  │
  // │                       참고. 8/10번은 위 범례가 이 자리를 대신 씀     │
  // │                                                                    │
  // │ 【메인 2개 제외 9개 테마(1/2/4/5/8/9/10 + A/B) 공용 유틸 - 손대면    │
  // │ 9개 전부 영향】                                                     │
  // │  - _themedCellData()  : 근무색/근무글씨색/일요일·공휴일 여부/메모    │
  // │                         목록을 한 번에 계산 - 셀 함수들이 이 결과    │
  // │                         (d.shiftText/d.red/d.holidayName/d.memos 등)│
  // │                         를 그대로 받아 그리기만 함                  │
  // │  - _fitText()         : 메모/공휴일 글자가 셀 폭을 넘기면 "..."     │
  // │                         없이 딱 들어가는 데까지만 잘라서 그림 -      │
  // │                         모든 테마의 메모/공휴일 텍스트가 이걸 씀     │
  // │  - _isFirstRow()      : 1번(미니멀) 전용, 달력 첫 줄만 위쪽 패딩을   │
  // │                         0으로 빼는 예외 처리                        │
  // │                                                                    │
  // │ 아래 각 함수 안에서, "근무명 크기/요일 크기/날짜 숫자 크기·위치/     │
  // │ 빨간날(일요일·공휴일) 글씨크기·위치/메모 시작위치·간격·공휴일과의    │
  // │ 간격" 같은 구체적인 지점은 코드에 🔧 표시로 바로 옆에 달아둠 -       │
  // │ Ctrl+F로 "🔧"를 검색하면 테마 상관없이 조절 가능한 지점만 쭉 훑어볼  │
  // │ 수 있음.                                                            │
  // └──────────────────────────────────────────────────────────────────┘

  // ⭐ 6번째 줄(화~토 5칸)을 OT카드/범례로 재활용하는 테마 - 메인 화이트/다크는
  // OT+주별근무시간 카드, 8/10번은 범례(색상만으로 근무를 구분하는 테마라
  // 범례가 필수). 나머지 7개 테마는 재활용하지 않고 6번째 줄도 평범하게 다음
  // 달 스필오버 날짜를 그대로 보여줌(대신 OT/주별근무시간은 아래 별도 푸터로).
  bool _themeReclaimsSixthRow(CalendarThemeId t) =>
      t == CalendarThemeId.mainWhite ||
      t == CalendarThemeId.mainDark ||
      t == CalendarThemeId.underline ||
      t == CalendarThemeId.editorial;

  // ⭐ 2026-09-05 - "전체근무표를 자주 보는데 진입 버튼이 위에 있어 번거롭다"는
  // 피드백으로 만든 두 번째 재활용 방식. 위 _themeReclaimsSixthRow와 완전히
  // 별개(서로 겹치는 테마 없음) - 6번째 줄 5칸을 통째로 카드 하나로 쓰는 게
  // 아니라, 항상 다음 달 스필오버로 비어있던 마지막 3칸(목/금/토)만 헤더에
  // 있던 일정공유(친구)/전체근무표/오늘 버튼으로 대체함(목/금/토는 고정 -
  // 다른 배치로 바꾸지 말 것). 범례가 필수라 이 자리를 못 쓰는 언더라인/
  // 매거진(_themeReclaimsSixthRow 참고, 이 두 테마는 대신 헤더에 일정공유
  // 버튼을 추가함)만 제외하고 나머지 전부(다이어리/미니멀/머티리얼카드/
  // 굵은격자/이니셜뱃지/이벤트칩) 적용함.
  bool _themeReclaimsSixthRowButtons(CalendarThemeId t) =>
      t == CalendarThemeId.diary ||
      t == CalendarThemeId.minimal ||
      t == CalendarThemeId.materialCard ||
      t == CalendarThemeId.boldGrid ||
      t == CalendarThemeId.initialBadge ||
      t == CalendarThemeId.eventChip;

  // ⭐ 위 두 "6번째 줄 재활용" 방식(_themeReclaimsSixthRow의 5칸 카드/범례,
  // _themeReclaimsSixthRowButtons의 목/금/토 3칸 버튼)은 테마별로 서로 배타적이지만,
  // day builder/탭 핸들러 여러 곳에서 "이 칸을 실제 날짜 대신 다른 걸로 대체해야
  // 하는가"를 매번 두 조건 다 확인해야 해서 이 헬퍼로 한 번에 판정함.
  bool _isRowSixReclaimed(
    DateTime day,
    DateTime focusedDay, {
    required bool reclaimsSixthRow,
    required bool reclaimsSixthRowButtons,
    required bool includeAllShiftsCol,
  }) {
    if (reclaimsSixthRow && _isSixthRowEmptyCell(day, focusedDay)) return true;
    if (reclaimsSixthRowButtons &&
        _isSixthRowButtonCell(day, focusedDay,
            includeAllShiftsCol: includeAllShiftsCol)) {
      return true;
    }
    return false;
  }

  // ⭐ 6번째 줄의 목(4)/금(5)/토(6) 3칸 여부 - _isSixthRowEmptyCell(화~토 5칸,
  // OT카드/범례용)과는 대상 칸도 용도도 다른 별도 헬퍼. 토(오늘 버튼)는 항상,
  // 금(일정공유)은 친구 유무와 무관하게 항상, 목(전체근무표)은 규칙적
  // 근무자일 때만 - 나머지 조건은 호출부(build())가 인자로 넘겨줌.
  // ⭐ 2026-09-13 버그 수정 - build()의 실제 버튼 배치(목/금/토 Row, 2026-09-13
  // 순서 변경 주석 참고)는 "조건부로 사라지는 버튼(전체근무표)을 목으로,
  // 항상 있는 일정공유를 금으로" 바꿨는데, 이 셀 판정 함수는 그때 같이 안
  // 고쳐져서 여전히 옛 순서(목=항상/금=조건부)로 남아있었음 - 그 결과
  // 불규칙+근무 미배정 상태(전체근무표 버튼이 조건부로 사라짐)에서 실제로는
  // 금 칸이 "true"가 아니라 예전 규칙(금=조건부)에 걸려 reclaim 안 되고, 목
  // 칸은 예전 규칙(목=항상) 그대로 reclaim 됨 - 즉 화면에 그려지는 버튼
  // 위치(목=빈칸/금=일정공유)와 실제 날짜 셀이 비워지는 위치(목=비워짐/
  // 금=안 비워짐)가 서로 어긋나서, 금 칸에 실제 달력 셀(스필오버 날짜 +
  // 테마별 배경/테두리)이 일정공유 버튼 밑에 그대로 남아 버튼 여백 틈으로
  // 비쳐 보였음(심플 라인 테마의 "수요일 우측 세로선 소실 + 목요일 우측
  // 세로선 뜬금없이 등장", 다이어리/다크그리드/컬러뱃지/이벤트캘린더 테마의
  // "6번째 줄 금요일에 뜬금없는 달력 셀" 전부 이 어긋남 하나가 원인). 목/금
  // 판정을 실제 버튼 배치와 같은 조건으로 맞춤.
  bool _isSixthRowButtonCell(
    DateTime day,
    DateTime focusedMonth, {
    required bool includeAllShiftsCol,
  }) {
    if (!_isSixthRow(day, focusedMonth)) return false;
    switch (day.weekday) {
      case 6: // 토 - 오늘 버튼, 항상
        return true;
      case 5: // 금 - 일정공유, 친구 유무와 무관하게 항상
        return true;
      case 4: // 목 - 전체근무표, 규칙적 근무자만
        return includeAllShiftsCol;
      default:
        return false;
    }
  }

  // ⭐ "왜 5번만 이렇게 고생하냐, 다른 테마처럼 그리드에 맞게 미리 고정된
  // 적절한 크기로 만들어야지, lab에서 테스트한 디자인 그대로 100% 똑같이
  // 적용하라"는 지적 - 근본 원인은 75.h라는 값을 감으로 고정해서 쓴 것.
  // lab(calendar_theme_lab_screen.dart)의 7개 실험 테마는 전부 6줄을
  // Expanded로 감싸서 "화면에서 남는 공간을 6등분"하는 방식이라, 실제로
  // 받는 한 줄 높이가 기기/헤더/푸터 구성에 따라 자동으로 달라짐 - 그런데
  // 실제 달력탭에서는 table_calendar가 rowHeight를 픽셀 고정값으로 미리
  // 알아야 해서 75.h라는 값 하나를 임의로 못박아 썼던 게 문제였음(테마마다
  // 헤더/푸터 실제 높이가 달라서 딱 맞을 수가 없음). 그래서 이제 감으로
  // 고정하는 대신, build()에서 "헤더/푸터를 제외하고 실제로 남는 높이"를
  // 직접 재서 6등분함 - lab의 Expanded와 정확히 같은 계산을 그대로 재현하는
  // 것이라 헤더/푸터가 몇 픽셀이든 항상 6줄이 딱 맞게 꽉 채워짐(더 이상
  // "남는 빈 공간"이 생기지 않음).
  //
  // ⭐ 2026-08-24 - 메인 화이트/다크의 고정 83.h 예외를 없애고 이 통일된 방식에
  // 합류시킴. 예전엔 "이미 실기기에서 검증 끝난 값이니 건드리지 않는다"는
  // 이유로 일부러 안 건드렸었는데, 그 결과 메인 테마의 Expanded가 실제로 받는
  // 높이보다 항상 조금(또는 화면에 따라 꽤) 적게만 그려서 그 아래가 빈
  // 여백으로 남았음 - 이게 애드몹 배너 자리 위에 기기마다 크기가 다른 뜬금없는
  // 흰 여백을 만드는 원인이었음(calendar_tab.dart의 build() 진입부 주석 참고).
  // 이제 모든 테마가 "받은 높이를 남김없이 6등분"하는 같은 규칙을 쓰므로,
  // 메인 테마도 다른 테마와 마찬가지로 광고 자리 바로 위까지 여백 없이
  // 정확히 채워짐 - 그리고 이 값이 작아지든 커지든 사용자가 껐다 켜지 않아도
  // 항상 실측값 기준이라 어떤 기기에서도 딱 맞음.
  // (6번째 줄 OT 카드는 이 rowH 값을 그대로 재사용해 "행 전체 높이"를 쓰므로
  // project_ot_calendar_card 메모리의 "48.h로 도로 줄이지 말 것" 조건은 그대로
  // 유지됨 - 절대 픽셀값이 아니라 rowH 대비 비율 조건이라 영향 없음.)
  double _themeRowHeight(CalendarThemeId t, double availableHeight) {
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
  // ⭐ 2026-09-01 - "그래도 전체적으로 어둡다/애매하다"는 재지적으로 옅은
  // 회색조 배경 자체를 없애고 흰색(=null, 다른 8개 테마와 동일)으로 되돌림 -
  // 카드 구분은 각 셀의 그림자(boxShadow)와 둥근 모서리만으로 충분하다고
  // 판단. 옅은 회색을 다시 쓰고 싶으면 아래 return을 다시 Color(0xFFF5F6FB)로.
  Color? _themeBodyBackground(BuildContext context, CalendarThemeId t) {
    return null;
  }

  // ⭐ "일정공유"(친구) 버튼도 위 전체근무표/오늘과 같은 원칙 - 자리는 테마마다
  // 다르지만(6번째 줄 목요일 칸 대부분, 언더라인/매거진만 헤더) 실제 동작은
  // 항상 동일: 친구가 1명뿐이면 그 친구 달력으로 바로, 2명 이상이면 목록
  // 화면으로. 친구가 하나도 없어도 항상 노출(누르면 FriendListScreen의
  // "친구 추가" 빈 상태로 감 - 에러 아님).
  void _openFriendShare() {
    final friends = ref.read(friendProvider);
    if (friends.length == 1) {
      openFriendCalendar(context, ref, friends.first);
    } else {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const FriendListScreen()));
    }
  }

  // ⭐ "전체근무표"/"오늘" 버튼은 테마마다 디자인(위치/모양)만 다르고 실제
  // 동작은 항상 동일 - 진짜 이동 로직을 한 곳에 모아 모든 테마 헤더가 공유함.
  void _openAllShiftsView() {
    // ⭐ 2026-09-05 - 버그 수정. 지금 보고 있던 달(_focusedDay)을 넘겨줘야
    // 전체근무표도 그 달로 열림(예전엔 항상 오늘이 속한 달로만 열렸음).
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => AllShiftsView(initialMonth: _focusedDay)),
    );
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
  ({int totalMinutes, DateTimeRange period}) _monthlyOtSummary(
      ShiftSchedule schedule) {
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
  // 🔧 각 case 안의 Text style fontSize/color가 그 테마 헤더 타이틀 크기·색.
  // 헤더 칸 자체의 세로 높이/여백은 이 함수가 아니라 build() 안 헤더
  // SizedBox(height: 48.h)와 그 바깥 Padding(vertical: 4.h)이 결정함(모든
  // 테마 공용 - 테마마다 따로 못 바꿈, 바꾸면 9개 전부 영향).
  Widget _buildThemedHeaderTitle(CalendarThemeId theme) {
    final y = _focusedDay.year;
    final m = _focusedDay.month;
    // ⭐ 영어 현지화: '$m월'/'$y년 $m월' 같은 Korean-particle 조립은 로케일에
    // 따라 표기가 달라져야 함 - materialCard/mainWhite/mainDark에서 사용.
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final shortMonthLabel =
        DateFormat.MMM(isKorean ? 'ko' : 'en').format(_focusedDay);
    switch (theme) {
      case CalendarThemeId.minimal:
        return GestureDetector(
            onTap: _showMonthYearPicker,
            child: Text('${_monthEn3[m - 1]} $y',
                style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)));
      case CalendarThemeId.materialCard:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(shortMonthLabel,
                    style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w300,
                        color: Colors.black87)),
                SizedBox(width: 6.w),
                Padding(
                    padding: EdgeInsets.only(bottom: 2.h),
                    child: Text('$y',
                        style: TextStyle(
                            fontSize: 13.sp, color: Colors.grey.shade400))),
              ]),
        );
      case CalendarThemeId.boldGrid:
        return GestureDetector(
            onTap: _showMonthYearPicker,
            child: Text('$y-${m.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'monospace')));
      case CalendarThemeId.initialBadge:
        return GestureDetector(
            onTap: _showMonthYearPicker,
            child: Text('$y.${m.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)));
      case CalendarThemeId.underline:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_monthEn3[m - 1].toUpperCase(),
                style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Colors.black87)),
            SizedBox(width: 6.w),
            // ⭐ "2026 년도가 잘 안 보인다"는 지적으로 아주 살짝만 진하게(shade400→shade500).
            Text('$y',
                style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey.shade500,
                    letterSpacing: 1)),
          ]),
        );
      case CalendarThemeId.eventChip:
        return GestureDetector(
            onTap: _showMonthYearPicker,
            child: Text('$y. $m',
                style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)));
      case CalendarThemeId.editorial:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ⭐ 2026-09-05 - "September"처럼 다 풀어 쓰면 공간이 부족해서 3글자
                // 약어("Sep")로 - _monthEn3(minimal/underline과 공유).
                Text(_monthEn3[m - 1],
                    style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'serif',
                        color: Colors.black87)),
                SizedBox(width: 8.w),
                // ⭐ "2026 등 텍스트를 아주 약간만 더 진하게" - shade500 → shade600.
                Padding(
                    padding: EdgeInsets.only(bottom: 3.h),
                    child: Text('$y',
                        style: TextStyle(
                            fontSize: 12.sp,
                            fontFamily: 'serif',
                            color: Colors.grey.shade600))),
              ]),
        );
      case CalendarThemeId.mainWhite:
      case CalendarThemeId.mainDark:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
                isKorean
                    ? '$y년 $m월'
                    : DateFormat.yMMMM('en').format(_focusedDay),
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            SizedBox(width: 4.w),
            Icon(Icons.arrow_drop_down,
                size: 24.sp,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
        );
      // ⭐ 2026-09-01 신설 - 다이어리(원래 유럽/애플풍 "노르딕"으로 만들었다가,
      // "다이어리의 살짝 귀여운 느낌을 얹어서 하나로 합쳐달라"는 요청으로
      // 재설계). 절제된 유럽풍 타이포(w500, 살짝 벌어진 자간)는 유지하되,
      // 작은 원형 점 장식 하나로 "다이어리 첫 페이지" 느낌을 살짝 얹음 -
      // 점 색은 이 테마의 포인트 컬러(_diaryAccent, 아래 셀 함수와 공유).
      // 🔧 헤더 타이틀 크기: fontSize: 18.sp / 점 장식 크기: width/height: 7.w.
      case CalendarThemeId.diary:
        return GestureDetector(
          onTap: _showMonthYearPicker,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 7.w,
                height: 7.w,
                margin: EdgeInsets.only(right: 7.w),
                decoration:
                    BoxDecoration(color: _diaryAccent, shape: BoxShape.circle)),
            Text(
              isKorean ? '$y년 $m월' : DateFormat.yMMMM('en').format(_focusedDay),
              style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: const Color(0xFF4A4038)),
            ),
          ]),
        );
    }
  }

  // ⭐ 2026-09-05 - 예전엔 여기서 "친구가 있으면 헤더 버튼 끝에 아이콘 하나
  // 자동으로 덧붙이기"를 했었는데, 이제 모든 테마가 일정공유(친구) 전용
  // 자리를 각자 확실히 갖고 있음(대부분 6번째 줄 목요일 칸 -
  // _themeReclaimsSixthRowButtons/_isSixthRowButtonCell 참고, 범례 필수인
  // 언더라인/매거진만 예외로 아래 core의 헤더에 직접 넣음) - 그래서 이 자동
  // 덧붙이기는 중복이라 없앰. 이 함수는 이제 core를 그대로 전달하는 얇은
  // wrapper - 호출부(build())를 안 건드리려고 이름만 남겨둠.
  Widget _buildThemedHeaderButtons(
      CalendarThemeId theme, ShiftSchedule schedule) {
    return _buildThemedHeaderButtonsCore(theme, schedule);
  }

  // ⭐ 헤더 우측 "전체근무표"/"오늘" 버튼 - 규칙적 근무자만 전체근무표 노출
  // (기존 게이트 schedule.isRegular 그대로 유지). 버튼 모양은 테마마다
  // 완전히 다르지만(텍스트만/아이콘 버튼/알약형/텍스트+밑줄 등) onTap은
  // 항상 _openAllShiftsView/_jumpToToday로 동일.
  // ⭐ 2026-09-05 - 전체근무표/오늘(+일정공유) 버튼을 헤더에서 완전히 빼고
  // 6번째 줄 마지막 3칸(목/금/토)으로 내리는 리팩토링을 다이어리 외 나머지
  // 테마로 확장함(_isSixthRowButtonCell/_themeReclaimsSixthRowButtons 참고,
  // build()의 Positioned 블록에서 실제로 그려짐) - 헤더엔 제목만 남음. 범례가
  // 필수라 6번째 줄에 자리가 없는 언더라인/매거진만 예외로, 기존 헤더 버튼을
  // 유지한 채 일정공유 버튼만 그 헤더 안에 추가로 얹음(아래 case 참고).
  Widget _buildThemedHeaderButtonsCore(
      CalendarThemeId theme, ShiftSchedule schedule) {
    final showAllShifts = schedule.isRegular;
    switch (theme) {
      case CalendarThemeId.minimal:
      case CalendarThemeId.materialCard:
      case CalendarThemeId.boldGrid:
      case CalendarThemeId.initialBadge:
      case CalendarThemeId.eventChip:
      case CalendarThemeId.mainWhite:
      case CalendarThemeId.mainDark:
      case CalendarThemeId.diary:
        return const SizedBox.shrink();
      // ⭐ 2026-09-05 - 언더라인/매거진(범례 필수 2개 테마)은 6번째 줄이 범례로
      // 꽉 차서 일정공유 버튼을 거기 못 넣음 - 대신 이 헤더의 전체근무표 버튼
      // 왼쪽에 일정공유 버튼을 추가함(친구 유무와 무관하게 항상 노출 -
      // _openFriendShare 참고).
      case CalendarThemeId.underline:
        return Row(children: [
          GestureDetector(
              onTap: _jumpToToday,
              child: Text('TODAY',
                  style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                      letterSpacing: 0.5))),
          SizedBox(width: 12.w),
          GestureDetector(
              onTap: _openFriendShare,
              child: Text(context.l10n.friendShareTitle,
                  style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                      letterSpacing: 0.5))),
          if (showAllShifts) ...[
            SizedBox(width: 12.w),
            GestureDetector(
                onTap: _openAllShiftsView,
                child: Text(context.l10n.shiftFullSchedule,
                    style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54))),
          ],
        ]);
      case CalendarThemeId.editorial:
        return Row(children: [
          GestureDetector(
              onTap: _openFriendShare,
              child: Text(context.l10n.friendShareTitle,
                  style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.brown.shade400,
                      decoration: TextDecoration.underline))),
          SizedBox(width: 10.w),
          if (showAllShifts) ...[
            GestureDetector(
                onTap: _openAllShiftsView,
                child: Text(context.l10n.shiftFullSchedule,
                    style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.brown.shade400,
                        decoration: TextDecoration.underline))),
            SizedBox(width: 10.w),
          ],
          GestureDetector(
              onTap: _jumpToToday,
              child: Text(context.l10n.commonToday,
                  style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.brown.shade400,
                      decoration: TextDecoration.underline))),
        ]);
    }
  }

  // ⭐ 다이어리 테마 전용 - 6번째 줄 목/금/토(일정공유/전체근무표/오늘) 버튼
  // 공용 스타일. 따뜻한 웜톤, 이 칸 전체를 채우는 카드형(아이콘 위/라벨
  // 아래) - "버튼 영역을 균일한 크기로" 요청대로 셋 다 같은 위젯을 재사용해서
  // 자동으로 크기가 맞음. 이 테마 전용이라 다른 테마에서 재사용 안 함(다른
  // 테마는 _themedRowSixButton 참고).
  // ⭐ 2026-09-05 후속2 - "전체 조 근무표"가 "전체 조 근..."처럼 잘려 보인다는
  // 지적 - 한 줄 제한을 풀고 2줄까지 허용함(가운데 정렬 + 줄바꿈). 아이콘도
  // "조금씩 더 크게" 요청으로 15→17.sp.
  Widget _diaryRowSixButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Padding(
      padding: EdgeInsets.all(3.w),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0DE),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: _diaryAccent.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17.sp, color: const Color(0xFFB5651D)),
              SizedBox(height: 2.h),
              Text(
                label,
                style: TextStyle(
                    fontSize: 8.5.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB5651D)),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 2026-09-05 - 메인 화이트/다크 전용 6번째 줄 버튼(일정공유/전체 조
  // 근무표/오늘). 다이어리(_diaryRowSixButton)와 같은 자리·같은 순서를 쓰지만, 이 두 테마는
  // 이미 있는 이번 달 OT 카드(_buildMonthlyOvertimeCard) 안 남는 40% 영역에
  // 얹는 거라 다이어리보다 세로 공간이 훨씬 좁음 - 라벨 없이 아이콘만 두고,
  // 다이어리처럼 이 테마 전용 웜톤을 새로 만드는 대신 colorScheme.primaryContainer/
  // onPrimaryContainer를 그대로 씀(라이트/다크 양쪽에서 자동으로 대비되는 색을
  // 얻음 - 이 카드가 이미 따르던 "색은 colorScheme만 참조" 원칙 그대로).
  Widget _mainThemeRowSixButton({
    required ColorScheme colorScheme,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.all(3.w),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8.r),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child:
                Icon(icon, size: 16.sp, color: colorScheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }

  // ⭐ 2026-09-05 - 6번째 줄 목/금/토 버튼 dispatch. 다이어리는 자기 전용 함수
  // (_diaryRowSixButton, 웜톤)를 그대로 쓰고, 나머지 5개 테마는 아래
  // _themedRowSixButton으로. 호출부(build())가 테마 분기를 직접 안 해도 되게
  // 여기서 한 번에 처리함.
  Widget _rowSixButton(CalendarThemeId theme,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    if (theme == CalendarThemeId.diary)
      return _diaryRowSixButton(icon: icon, label: label, onTap: onTap);
    return _themedRowSixButton(theme, icon: icon, label: label, onTap: onTap);
  }

  // ⭐ 미니멀/머티리얼카드/굵은격자/이니셜뱃지/이벤트칩 5개 테마의 6번째 줄
  // 버튼 - 아이콘은 기존 헤더 버튼과 동일한 걸 그대로 쓰고(호출부에서 넘겨줌),
  // 자리가 넉넉해서(다이어리와 같은 칸 크기) 다이어리처럼 라벨도 아이콘 아래에
  // 같이 넣음. 각 case의 배경/테두리/글자색은 그 테마가 기존에 헤더에서 쓰던
  // 톤을 그대로 옮김(각각 옛 _thinTextButton/_roundIconButton/_gridHeaderBtn/
  // _pillButton 자리를 대신함 - 그 함수들은 헤더 호출부가 없어져 지움).
  Widget _themedRowSixButton(CalendarThemeId theme,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    late final Color bg;
    late final Color fg;
    late final BoxBorder? border;
    late final double radius;
    switch (theme) {
      // ⭐ 2026-09-05 후속 - "스와이프 중 이 버튼들 위로 내용이 지나가 보인다"는
      // 재신고 - RepaintBoundary로도 안 고쳐진 3개(미니멀/이니셜뱃지/이벤트칩)의
      // 진짜 원인은 배경이 완전 투명(minimal)이거나 8%대 알파(initialBadge/
      // eventChip)라 스와이프로 지나가는 내용이 그 옅은/없는 배경을 통해
      // 그대로 비쳐 보였던 것(합성 순서 문제가 아니라 그냥 눈에 보임) -
      // materialCard(흰 불투명)/boldGrid(네이비 불투명)는 이미 완전 불투명이라
      // 문제가 없었음. 이 두 개도 완전 불투명 배경으로 다시 그림.
      case CalendarThemeId.minimal:
        bg = Colors.white; // 완전 불투명(예전 transparent에서 변경)
        fg = Colors.grey.shade700;
        border = Border.all(color: Colors.grey.shade300, width: 1);
        radius = 6.r;
        break;
      case CalendarThemeId.materialCard:
        bg = Colors.white;
        fg = Theme.of(context).colorScheme.primary;
        border = null;
        radius = 10.r;
        break;
      case CalendarThemeId.boldGrid:
        bg = const Color(0xFF263238);
        fg = Colors.white;
        border = Border.all(color: Colors.white38);
        radius = 4.r;
        break;
      // ⭐ 2026-09-05 후속2 - "둘이 똑같이 primaryContainer 써서 무성의하다"는
      // 지적 - 이 앱은 ColorScheme.fromSeed가 아니라 손으로 값을 채운
      // ColorScheme(app_theme.dart)라, secondaryContainer/tertiaryContainer는
      // 우리가 고른 색과 무관한 Flutter 기본값이라 못 씀(의미 없는 색이 나옴).
      // 대신 각 테마가 이미 자기 셀 안에서 쓰던 고유 색을 그대로 버튼에도
      // 이어감 - 이니셜뱃지는 "오늘" 표시에 이미 인디고를 쓰고 있고(원형 뱃지
      // 모티프), 이벤트칩은 인디고를 이니셜뱃지가 이미 쓰므로 겹치지 않게
      // 틸(teal)로 새로 지정(칩/알약 모티프에 어울리는 차분한 톤).
      case CalendarThemeId.initialBadge:
        bg = Colors.indigo.shade50;
        fg = Colors.indigo.shade700;
        border = null;
        radius = 16.r; // 원형 뱃지 모티프 - 다른 테마보다 더 둥글게
        break;
      case CalendarThemeId.eventChip:
        bg = Colors.teal.shade50;
        fg = Colors.teal.shade700;
        border =
            Border.all(color: Colors.teal.shade200, width: 0.8); // 칩 특유의 얇은 테두리
        radius = 8.r; // 칩(pill) 모티프 - 완만하게만 둥글게
        break;
      default:
        // 이 함수를 쓰지 않는 테마 - 방어적 fallback(호출될 일 없음).
        bg = Colors.transparent;
        fg = Colors.black87;
        border = null;
        radius = 0;
    }
    return Padding(
      padding: EdgeInsets.all(3.w),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
            border: border,
            boxShadow: theme == CalendarThemeId.materialCard
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06), blurRadius: 3)
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16.sp, color: fg),
              SizedBox(height: 2.h),
              Text(label,
                  style: TextStyle(
                      fontSize: 8.5.sp, fontWeight: FontWeight.w600, color: fg),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 요일 헤더 한 칸 - table_calendar의 dowBuilder로 완전히 테마별 위젯을
  // 그림(일/월/... vs Sun/Mon/... vs S/M/... 등 표기 자체가 테마마다 다름).
  // 🔧 요일 글자 크기 = 각 case의 Text style fontSize. 요일 칸 자체의 세로
  // 위치는 이 함수가 아니라 build()의 daysOfWeekHeight(28.h)가 칸 높이를
  // 정하고, 그 안에서 Center/alignment로 가운데 고정 - 위아래로 옮기려면
  // Center 대신 Align(alignment: Alignment(0, y))로 바꾸거나 Padding을 추가.
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
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          alignment: Alignment.center,
          // ⭐ 2026-09-01 - "요일(Mon/Tue) 글자색이 너무 연한 회색"이라는 지적으로
          // grey.shade500 → grey.shade700로 한 단계 더 진하게(materialCard 테마의
          // 요일 색과 동일한 톤).
          child: Text(_weekdayEn3[i],
              style: TextStyle(
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w600,
                  color: i == 0 ? Colors.red.shade400 : Colors.grey.shade700)),
        );
      case CalendarThemeId.materialCard:
        return Center(
            child: Text(weekdayLabel(context, i),
                style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.bold,
                    color:
                        i == 0 ? Colors.red.shade400 : Colors.grey.shade700)));
      case CalendarThemeId.boldGrid:
        return Container(
            color: const Color(0xFF37474F),
            alignment: Alignment.center,
            child: Text(_weekdayEn3[i],
                style: TextStyle(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    color:
                        i == 0 ? Colors.redAccent.shade100 : Colors.white70)));
      case CalendarThemeId.initialBadge:
        return Center(
            child: Text(weekdayLabel(context, i),
                style: TextStyle(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.bold,
                    color:
                        i == 0 ? Colors.red.shade400 : Colors.grey.shade500)));
      case CalendarThemeId.underline:
        return Center(
            child: Text(_weekdayEn1[i],
                style: TextStyle(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    color:
                        i == 0 ? Colors.red.shade400 : Colors.grey.shade400)));
      case CalendarThemeId.eventChip:
        return Center(
            child: Text(_weekdayEn3[i],
                style: TextStyle(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    color:
                        i == 0 ? Colors.red.shade400 : Colors.grey.shade500)));
      case CalendarThemeId.editorial:
        return Container(
          color: i == 0
              ? Colors.red.shade50
              : (i == 6 ? Colors.blue.shade50 : Colors.grey.shade100),
          alignment: Alignment.center,
          child: Text(_weekdayEn3[i],
              style: TextStyle(
                  fontSize: 9.5.sp,
                  fontWeight: FontWeight.bold,
                  color: i == 0 ? Colors.red.shade400 : Colors.grey.shade600)),
        );
      case CalendarThemeId.mainWhite:
      case CalendarThemeId.mainDark:
        return Center(
            child: Text(weekdayLabel(context, i),
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)));
      // ⭐ 2026-09-01 신설 - 다이어리: 따뜻한 갈색 톤, 로케일 요일명 그대로
      // (Sun/Mon 약자 대신 실제 요일명 - 딱딱한 캘린더 느낌보다 다이어리에
      // 가깝게).
      case CalendarThemeId.diary:
        return Center(
            child: Text(weekdayLabel(context, i),
                style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: i == 0
                        ? const Color(0xFFD9534F)
                        : const Color(0xFF8A6F5C))));
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
      case CalendarThemeId.diary:
        return _themeDiaryFooter(summary, otText);
    }
  }

  // ⭐ 2026-09-01 신설 - 다이어리: 따뜻한 아이보리 카드 + 얇은 크림색 테두리.
  // 🔧 "이번 달 OT" 글자 크기: fontSize: 11.sp / "주별 근무시간" 글자 크기: 아래
  // GestureDetector 안 Text의 fontSize: 11.sp(각각 따로 조절 가능).
  Widget _themeDiaryFooter(
      ({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 8.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E2),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFF0DFC8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _showMonthlyOvertimeSheet(summary.period),
              child: Text('${context.l10n.shiftThisMonthOt} $otText',
                  style: TextStyle(
                      fontSize: 11.sp,
                      color: const Color(0xFFB5651D),
                      fontWeight: FontWeight.w700)),
            ),
          ),
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text('${context.l10n.shiftWeeklyWorkHours} ›',
                style: TextStyle(
                    fontSize: 11.sp,
                    color: const Color(0xFF8A6F5C),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ⭐ 1/5/9번이 공유하던 lab의 _theme1OtBar() 그대로.
  Widget _themeOtBar(
      ({int totalMinutes, DateTimeRange period}) summary, String otText) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 6.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
          color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8.r)),
      child: Row(
        children: [
          Icon(Icons.access_time, size: 13.sp, color: primary.withOpacity(0.6)),
          SizedBox(width: 5.w),
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            child: Text('${context.l10n.shiftThisMonthOt} $otText',
                style: TextStyle(fontSize: 11.sp, color: Colors.black87)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text('${context.l10n.shiftWeeklyWorkHours} ›',
                style: TextStyle(
                    fontSize: 11.sp,
                    color: primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _theme2OtCardReal(
      ({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 8.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      // ⭐ "이번 달 OT랑 주별 근무시간이 스크린샷에선 서로 다른 색상이었는데
      // 지금은 똑같다" - lab 원본(_theme2OtCard)은 인디고/틸로 서로 다른
      // MaterialColor를 썼는데 실제 탭으로 옮길 때 공용 primary 색 하나로
      // 합쳐버렸었음 - 원래 색 조합으로 복원.
      child: Row(
        children: [
          _otChipReal(context.l10n.shiftThisMonthOt, otText,
              () => _showMonthlyOvertimeSheet(summary.period), Colors.indigo),
          SizedBox(width: 8.w),
          _otChipReal(context.l10n.shiftWeeklyWorkHours,
              context.l10n.commonView, _showWeeklyWorkHoursSheet, Colors.teal),
        ],
      ),
    );
  }

  Widget _otChipReal(
      String label, String value, VoidCallback onTap, MaterialColor color) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          decoration: BoxDecoration(
              color: color.shade50, borderRadius: BorderRadius.circular(8.r)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9.sp,
                      color: color.shade400,
                      fontWeight: FontWeight.w600)),
              Text(value,
                  style: TextStyle(
                      fontSize: 12.sp,
                      color: color.shade700,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _theme4FooterReal(
      ({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Container(
      color: const Color(0xFFECEFF1),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            child: Text('${context.l10n.shiftThisMonthOt} $otText',
                style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF263238))),
          ),
          SizedBox(width: 14.w),
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text('${context.l10n.shiftWeeklyWorkHours} ▸',
                style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF00695C))),
          ),
        ],
      ),
    );
  }

  Widget _theme8FooterReal(
      ({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 10.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            // ⭐ "OT 3시간 30분도 아주 약간만 더 진하게" - black54→black87.
            // ⭐ "OT만 쓰지 말고 다른 테마들처럼 이번 달 OT로 통일" 요청 반영.
            child: Text('${context.l10n.shiftThisMonthOt} $otText',
                style: TextStyle(fontSize: 11.sp, color: Colors.black87)),
          ),
          const Spacer(),
          // ⭐ "오늘 표시 밑줄은 그대로 두되, 주별 근무시간의 밑줄은 없애자 -
          // 띄어쓰기 있는 문구에 밑줄이 붙으니 이상해 보인다" - 진하기(bold+
          // black87)는 유지하고 밑줄만 제거.
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text(context.l10n.shiftWeeklyWorkHours,
                style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _theme10FooterReal(
      ({int totalMinutes, DateTimeRange period}) summary, String otText) {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 6.h, 18.w, 10.h),
      child: Row(
        children: [
          // ⭐ "이번 달 OT, 주별 근무시간 텍스트도 아주 약간만 더 진하게".
          GestureDetector(
            onTap: () => _showMonthlyOvertimeSheet(summary.period),
            child: Row(children: [
              Text(context.l10n.shiftThisMonthOt,
                  style: TextStyle(
                      fontSize: 10.sp,
                      color: Colors.grey.shade600,
                      fontFamily: 'serif')),
              SizedBox(width: 4.w),
              Text(otText,
                  style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown.shade600,
                      fontFamily: 'serif')),
            ]),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showWeeklyWorkHoursSheet,
            child: Text('${context.l10n.shiftWeeklyWorkHours} →',
                style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.brown.shade500,
                    fontFamily: 'serif')),
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
        border: Border.all(
            color: useTriangle ? Colors.grey.shade200 : Colors.grey.shade300,
            width: 0.7),
        borderRadius: useTriangle ? null : BorderRadius.circular(4.r),
      ),
      child: ClipRect(
        child: Column(
          children: List.generate(
              rows,
              (r) => Expanded(
                    child: Row(
                      children: List.generate(cols, (c) {
                        final i = r * cols + c;
                        if (i >= shifts.length)
                          return const Expanded(child: SizedBox());
                        final name = shifts[i];
                        final color = colorMap[name] ?? Colors.grey;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 2.w, vertical: 1.h),
                            child: Row(
                              children: [
                                useTriangle
                                    ? ClipPath(
                                        clipper: _CalendarTriangleClipper(),
                                        child: Container(
                                            width: 16.w,
                                            height: 16.w,
                                            color: color))
                                    : Container(
                                        width: 16.w,
                                        height: 5.h,
                                        decoration: BoxDecoration(
                                            color: color,
                                            borderRadius:
                                                BorderRadius.circular(2.r))),
                                SizedBox(width: useTriangle ? 4.w : 3.w),
                                // ⭐ "범례 글자를 조금 더 키워도 될 듯" - 7.sp → 7.6.sp.
                                Expanded(
                                    child: Text(name,
                                        style: TextStyle(
                                            fontSize: 7.6.sp,
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
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
  Widget _buildThemedCell(DateTime day, bool isToday, bool isOutside,
      ShiftSchedule schedule, DateTime focusedDay,
      {bool isSelected = false}) {
    final theme = ref.watch(calendarThemeProvider);
    if (theme == CalendarThemeId.mainWhite ||
        theme == CalendarThemeId.mainDark) {
      return _buildDateCell(day, isToday, isOutside, schedule,
          isSelected: isSelected);
    }
    final cell = switch (theme) {
      CalendarThemeId.minimal =>
        _theme1Cell(day, isToday, isOutside, schedule, focusedDay),
      CalendarThemeId.materialCard =>
        _theme2Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.boldGrid =>
        _theme4Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.initialBadge =>
        _theme5Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.underline =>
        _theme8Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.eventChip =>
        _theme9Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.editorial =>
        _theme10Cell(day, isToday, isOutside, schedule),
      CalendarThemeId.diary =>
        _themeDiaryCell(day, isToday, isOutside, schedule),
      CalendarThemeId.mainWhite ||
      CalendarThemeId.mainDark =>
        throw StateError('unreachable'),
    };
    // ⭐ 7개 실험 테마 셀 함수들은 원래 다중 선택(길게 눌러 여러 날짜 선택) 기능이
    // 없던 시절에 만들어져서 선택 표시가 없음 - 각 셀 디자인은 그대로 두고 선택
    // 상태만 얇은 강조 테두리로 공통 오버레이함 (달력탭의 나머지 다중선택 로직은
    // 그대로 - 여기는 "선택됨"을 시각적으로만 보여주는 부분).
    if (!isSelected) return cell;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.secondary, width: 2),
        color: Theme.of(context).colorScheme.secondary.withOpacity(0.12),
      ),
      child: cell,
    );
  }

  // ⭐ 아래 7개 함수 공용으로 쓰는, 셀 하나 그리는 데 필요한 값들을 한 번에 계산.
  // calendar_theme_lab_screen.dart의 목업(_mockShiftFor/_mockMemos 등) 대신
  // 실제 schedule.getShiftForDate/memoProvider를 씀 - 그 외 계산 방식(공휴일,
  // 일요일, 자동 대비 텍스트색 등)은 완전히 동일한 공식을 그대로 씀.
  ({
    String shiftText,
    bool hasShift,
    Color shiftColor,
    Color shiftTextColor,
    bool red,
    String? holidayName,
    String? lunarText,
    List<String> memos
  }) _themedCellData(DateTime day, ShiftSchedule schedule) {
    final shiftText = schedule.getShiftForDate(day);
    final hasShift = shiftText.isNotEmpty && shiftText != '미설정';
    final shiftColor = hasShift
        ? _getShiftBackgroundColor(shiftText, schedule)
        : Colors.transparent;
    final shiftTextColor =
        hasShift ? _getShiftTextColor(shiftText, schedule) : Colors.transparent;
    final holidayName = _getHolidayName(day, context);
    final red = day.weekday == DateTime.sunday || holidayName != null;
    // ⭐ 2026-09-22 음력 표기 - 빨간날 자리와 겹치면 안 되므로 holidayName이 없을 때만,
    // 그리고 이 날이 그 주의 "음력 표기 날"로 뽑힌 날일 때만 채움(_lunarLabelDateForWeek).
    // ⚠️ 2026-09-22 버그 수정 - 상세팝업(음력 X)은 한국어 로케일 조건이 있었는데 여기(메인
    // 달력 셀)는 빠뜨려서 영어 로케일에도 "(4.14)"가 그대로 보이던 문제. 공휴일 표시와
    // 동일한 기준(languageCode == 'ko')으로 맞춤.
    String? lunarText;
    if (holidayName == null &&
        Localizations.localeOf(context).languageCode == 'ko') {
      final labelDay = _lunarLabelDateForWeek(day, context);
      if (labelDay != null && isSameDay(labelDay, day)) {
        final lunar = solarToLunar(day);
        if (lunar != null) lunarText = formatLunarDateCompact(lunar);
      }
    }
    final dateStr = day.toIso8601String().split('T')[0];
    final memos =
        ref.watch(memoProvider)[dateStr]?.map((m) => m.memoText).toList() ??
            const <String>[];
    return (
      shiftText: shiftText,
      hasShift: hasShift,
      shiftColor: shiftColor,
      shiftTextColor: shiftTextColor,
      red: red,
      holidayName: holidayName,
      lunarText: lunarText,
      memos: memos,
    );
  }

  // ⭐ 음력 표기(메인 달력) 공통 스타일 - 모든 테마가 동일하게 씀(사용자 요청: "폰트
  // 디자인은 모든 테마가 동일"). 크기는 kLunarCellFontSize 하나로 조정, 색은 상세팝업의
  // "(없음)" 텍스트와 같은 onSurfaceVariant 고정.
  TextStyle _lunarCellTextStyle() => TextStyle(
        fontSize: kLunarCellFontSize.sp,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        height: 1.1,
      );

  // 실제 Text가 그려질 한 줄 높이(기본 글꼴·글자 크기 배율 반영).
  double _lineHeightOf(TextStyle style) {
    final tp = TextPainter(
        text: TextSpan(
            text: '가9', style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1)
      ..layout();
    return tp.height;
  }

  // ⭐ 2026-09-23 - "음력/빨간날이 있는 날과 없는 날의 메모 줄이 안 맞는다"는 지적.
  // 빨간날 이름·음력 줄을 있을 때만 그리면 그 줄 높이만큼 아래 메모가 날마다 위아래로
  // 틀어짐 - 이제 이 줄은 내용이 없어도 항상 같은 높이(빨간날/음력 중 큰 쪽)를 차지해서,
  // 같은 주의 셀들이 "날짜 · 근무 · 빨간날/음력 · 메모" 줄을 똑같이 나눠 씀.
  Widget _redDaySlot(String? holidayName, String? lunarText,
      TextStyle holidayStyle,
      {TextAlign textAlign = TextAlign.center, double extraHeight = 0}) {
    final lunarStyle = _lunarCellTextStyle();
    final holidayH = _lineHeightOf(holidayStyle);
    final lunarH = _lineHeightOf(lunarStyle);
    final height = (holidayH > lunarH ? holidayH : lunarH) + extraHeight;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: holidayName != null
          ? _fitText(holidayName, holidayStyle, textAlign: textAlign)
          : (lunarText != null
              ? _fitText(lunarText, lunarStyle, textAlign: textAlign)
              : null),
    );
  }

  // ⭐ "메모/빨간날 글자가 셀 밖으로 넘치면 가위로 자른 듯 반쪽 글자가 보인다"는
  // 지적 - TextOverflow.clip/ellipsis는 픽셀 경계에서 그냥 잘라버려서 마지막
  // 글자가 반쪽만 그려질 수 있음(생략 부호 "..."도 원치 않는다고 함: "..." 없이
  // 그냥 보이는 데까지만"). 실제 폭을 TextPainter로 재서, 완전히 다 들어가는
  // 글자까지만 문자열 자체를 잘라내고 그걸 그림 - 이미 딱 맞게 잘린 문자열이라
  // 반쪽 글자가 원천적으로 나올 수 없음. 모든 테마의 메모/공휴일명 렌더링이
  // 공용으로 씀.
  Widget _fitText(String text, TextStyle style,
      {TextAlign textAlign = TextAlign.center}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var display = text;
        if (maxWidth.isFinite && maxWidth > 0 && text.isNotEmpty) {
          final full = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: TextDirection.ltr,
              maxLines: 1)
            ..layout();
          if (full.width > maxWidth) {
            int lo = 0, hi = text.length;
            while (lo < hi) {
              final mid = (lo + hi + 1) ~/ 2;
              final p = TextPainter(
                  text: TextSpan(text: text.substring(0, mid), style: style),
                  textDirection: TextDirection.ltr,
                  maxLines: 1)
                ..layout();
              if (p.width <= maxWidth) {
                lo = mid;
              } else {
                hi = mid - 1;
              }
            }
            display = text.substring(0, lo);
          }
        }
        return Text(display,
            style: style, maxLines: 1, textAlign: textAlign, softWrap: false);
      },
    );
  }

  // ⭐ 1번 · 미니멀 라인 (calendar_theme_lab_screen.dart _theme1Cell 이식)
  // ⭐ focusedDay는 위젯 상태(_focusedDay)가 아니라 이 셀을 그리는 TableCalendar
  // 빌더 콜백이 실제로 받은 값을 그대로 받음 - _buildThemedCell의 주석 참고
  // (스와이프 중 미리 빌드되는 인접 페이지에서 첫 줄 판정이 엉뚱한 달 기준으로
  // 되던 버그 수정).
  Widget _theme1Cell(DateTime day, bool isToday, bool isOutside,
      ShiftSchedule schedule, DateTime focusedDay) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    final numColor = isOutside
        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
        : (d.red ? Colors.red.shade400 : colorScheme.onSurface);
    // ⭐ "그리드가 이미지보다 진하다"는 지적으로 왼쪽 선을 더 연하게.
    // ⭐ "맨 윗줄 근무명 영역이랑 요일행 밑 구분선 사이에 미세한 여백이 있다"는
    // 지적 - lab 원본도 첫 줄만 위쪽 패딩을 0으로 없앴었는데(다른 행끼리는
    // 위/아래 패딩이 서로 겹쳐서 자연스럽지만, 첫 줄만 위에 겹칠 "이전 행의
    // 아래쪽 패딩"이 없어서 그 틈이 붕 떠 보임) 그 조건을 이식할 때 빠뜨렸음 -
    // 첫 줄만 위쪽 패딩 0으로 복원.
    final isFirstRow = _isFirstRow(day, focusedDay);
    // ⭐ 2026-09-01 버그 수정 - "근무가 하나도 할당 안 된 날(불규칙 스케줄
    // 초기 상태)에는 평범한 날 셀들이 우측으로 쏠리고, 빨간날 셀도 약간
    // 흐트러져 보인다"는 지적의 원인 - table_calendar는 각 날짜 셀을 내부
    // Stack(alignment: Alignment.bottomCenter, 기본 fit: StackFit.loose)에
    // 넣는데, loose라서 Stack이 자기 자식(=이 함수가 반환하는 위젯)에게 "이
    // 크기 이하로 알아서" 식의 느슨한 제약만 줌. 아래 Column은
    // crossAxisAlignment 기본값(center)이라 폭을 스스로 안 채우고 "가장 넓은
    // 자식" 만큼만 차지하는데, 근무명 배지(width: double.infinity)가 있을 땐
    // 그게 제일 넓어서 우연히 셀 폭을 꽉 채웠던 것뿐 - 배지가 없는 날은 남은
    // 자식들(날짜 숫자 18.w 박스, 빨간날/메모 텍스트)이 다 훨씬 좁아서 Column
    // 전체가 좁게 쪼그라들고, 그 좁아진 박스가 Stack의 bottomCenter 정렬로
    // 셀 안에서 가운데 정렬되면서 "왼쪽 테두리선(left border)이 실제 칸
    // 경계보다 안쪽(오른쪽)으로 밀려 보이는" 현상이 생김(빨간날은 글자가
    // 있어서 덜 좁아지니 덜 흐트러져 보였을 뿐, 원인은 동일). _theme5Cell이
    // 이미 겪었던 것과 똑같은 문제라 거기 쓴 것과 동일한 해법 - 이 Container에
    // width: double.infinity를 줘서 배지 유무와 무관하게 항상 셀 전체 폭을
    // 강제로 차지하게 함(파일 상단 지도 주석 옆 "7개 실험 테마 공용 유틸"
    // 참고 - 같은 클래스의 버그가 소프트카드(_theme2Cell)에도 있어서 같이
    // 고침).
    return ClipRect(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Colors.grey.shade200))),
        padding: EdgeInsets.only(top: isFirstRow ? 0 : 2.h, bottom: 2.h),
        child: Column(
          children: [
            // 🔧 근무명 배지 - 크기: height: 11.h(배지 높이) / fontSize: 7.5.sp(글자
            // 크기). 근무명이 없는 날은 이 자리를 SizedBox(height: 12.h)로 대신
            // 비워서 있는 날/없는 날 높이를 맞춤 - 배지 높이(11.h)만 바꾸면 이
            // SizedBox 높이(12.h)도 같이 맞춰줘야 줄이 안 튐.
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
                    style: TextStyle(
                        fontSize: 8.5.sp,
                        fontWeight: FontWeight.bold,
                        color: d.shiftTextColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              )
            else
              // 배지(11.h) + 위 margin(첫 줄은 0)과 같은 높이.
              SizedBox(height: isFirstRow ? 11.h : 12.h),
            // 🔧 근무명 배지 ↔ 날짜 숫자 사이 간격.
            SizedBox(height: 0.3.h),
            // 🔧 날짜 숫자 - 크기: fontSize: 11.sp / 위치: 18x18 정사각 박스 안에서
            // alignment: Alignment.center로 항상 가운데(위아래로 옮기려면 이
            // Container의 padding이나 width/height 자체를 조절).
            Container(
              width: 18.w,
              height: 18.w,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.indigo.shade400, width: 1.4))
                  : null,
              child: Text('${day.day}',
                  style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                      color: numColor)),
            ),
            // 🔧 빨간날(일요일/공휴일) 이름 - 크기: fontSize: 6.5.sp, 색:
            // Colors.red.shade400. 위치는 Column 순서상 "날짜 숫자 바로 아래"로
            // 고정(별도 좌표 없음) - 더 아래로 내리려면 위에 SizedBox를 하나
            // 추가하거나, 날짜 숫자보다 위로 올리려면 이 if 블록 자체를 날짜
            // Container보다 앞으로 옮기면 됨.
            _redDaySlot(
                d.holidayName,
                d.lunarText,
                TextStyle(
                    fontSize: 7.7.sp,
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.bold,
                    height: 1.1)),
            // 🔧 메모 시작 위치(날짜/빨간날 ↔ 첫 메모 사이 간격) - 이 SizedBox
            // 높이가 곧 "메모가 위에서 얼마나 아래서 시작하는가"임. 빨간날이 없는
            // 날은 날짜 숫자 바로 아래가 이 간격이 되고, 빨간날이 있는 날은
            // 빨간날 아래가 이 간격이 됨(둘이 공유하는 하나의 SizedBox).
            SizedBox(height: 3.8.h),
            // 🔧 메모 목록 - 최대 3개(take(3)), 글자 크기: fontSize: 7.sp. 메모끼리
            // 세로 간격은 Padding의 top: (첫 줄만 0, 나머지는 1.h) - 메모끼리
            // 더 붙이려면 이 1.h를 줄이고, 더 띄우려면 키우면 됨.
            ...d.memos.take(3).toList().asMap().entries.map((e) => Padding(
                  padding: EdgeInsets.only(
                      top: e.key == 0 ? 0 : 0.7.h, left: 1.w, right: 1.w),
                  child: _fitText(
                      e.value,
                      TextStyle(
                          fontSize: 7.sp,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                )),
          ],
        ),
      ),
    );
  }

  // ⭐ 2번 · 머티리얼 카드형
  Widget _theme2Cell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Padding(
        padding: EdgeInsets.all(2.w),
        // ⭐ 2026-09-01 버그 수정 - "근무가 할당 안 된 날은 카드 배경이 1일이면
        // 좁은 세로줄, 10일이면 좀 더 넓은 세로줄처럼 내용 크기만큼만 그려진다.
        // 근무가 있으면 100% 폭이 유지된다"는 지적의 원인 - _theme1Cell의 같은
        // 날짜 위 버그 수정 주석 참고(동일한 근본 원인: table_calendar가 이
        // 셀에게 loose 제약만 주는데, 이 Column도 crossAxisAlignment 기본값
        // (center)이라 "가장 넓은 자식"만큼만 폭을 차지함 - 근무 배지(width:
        // double.infinity)가 있을 때만 우연히 셀 폭을 꽉 채웠던 것). 카드
        // 배경(color/border/boxShadow)이 이 Container의 decoration에 있으므로,
        // 배지 유무와 무관하게 이 Container가 항상 셀 전체 폭을 차지하도록
        // width: double.infinity를 추가.
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            // ⭐ 2026-09-05 - "뿌옇게(투명도)는 이미 낮춰놨는데도 색 자체가
            // 진하다"는 지적. 이전 값(colorScheme.surface.withOpacity(0.01))은
            // kAppSurface(0xFFEEF1FC, 차가운 라벤더톤)를 1% 알파로 흰 배경 위에
            // 얹는 방식이었는데, 수학적으로는 흰색과 거의 구분 안 가야 정상이지만
            // 실기기에서는 그 미세한 파란기가 오히려 "탁하다"는 인상을 준 것으로
            // 보임(알파 블렌딩 미세값보다, 색상 자체가 채도 있는 톤이라 그런 것 -
            // 요청대로 알파를 더 낮추는 대신 아예 채도 없는 연회색 고정값(#F1F2F6)으로
            // 교체. outside(다른 달) 셀 스타일은 그대로 둠.
            // ⭐ 2026-09-22 - "다른 날들이 하얀색이라 F1F2F6이 칙칙해 보인다"는 재지적으로
            // kMaterialCardCurrentMonthCellColor(밝은 파스텔 블루)로 다시 교체(불투명 고정색
            // 방식 자체는 유지 - 그 위에 근무명 배지 등이 그대로 렌더링됨).
            color: isOutside
                ? colorScheme.surfaceVariant.withOpacity(0.15)
                : kMaterialCardCurrentMonthCellColor,
            borderRadius: BorderRadius.circular(6.r),
            border: isToday
                ? Border.all(color: Colors.indigo.shade400, width: 1.4)
                : null,
            boxShadow: isOutside
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 2,
                        offset: const Offset(0, 1))
                  ],
          ),
          child: Column(
            children: [
              // 🔧 근무명 배지 - 크기: height: 12.h / fontSize: 7.5.sp. 없는 날은
              // SizedBox(height: 13.h)로 자리를 대신 비움(높이를 바꾸면 이 값도 맞출 것).
              if (d.hasShift)
                Container(
                  width: double.infinity,
                  height: 12.h,
                  margin: EdgeInsets.fromLTRB(4.w, 1.h, 4.w, 0),
                  decoration: BoxDecoration(
                      color: d.shiftColor,
                      borderRadius: BorderRadius.circular(3.r)),
                  alignment: Alignment.center,
                  // ⭐ 영어 현지화: 위 셀과 동일한 이유로 강제 4글자 컷 제거,
                  // 기존 overflow:ellipsis에 맡김.
                  child: Text(d.shiftText,
                      style: TextStyle(
                          fontSize: 8.5.sp,
                          fontWeight: FontWeight.bold,
                          color: d.shiftTextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                )
              else
                SizedBox(height: 13.h),
              // 🔧 근무명 배지 ↔ 날짜 숫자 간격.
              SizedBox(height: 1.h),
              // 🔧 날짜 숫자 - 크기: fontSize: 12.sp. 이 테마는 날짜 숫자를 Container로
              // 감싸지 않고 Column 안에 직접 두므로, 위아래 위치는 앞뒤 SizedBox
              // 높이로만 조절 가능(별도 정렬 박스 없음).
              Text('${day.day}',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w700,
                    color: isOutside
                        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
                        : (d.red ? Colors.red.shade400 : colorScheme.onSurface),
                  )),
              // 🔧 빨간날 이름 - 크기: fontSize: 6.sp, 색: red.shade600. 위치는
              // 날짜 숫자 바로 아래 고정(Column 순서).
              _redDaySlot(
                  d.holidayName,
                  d.lunarText,
                  TextStyle(
                      fontSize: 7.sp,
                      color: Colors.red.shade600,
                      fontWeight: FontWeight.bold,
                      height: 1.0)),
              // 🔧 메모 시작 위치(날짜/빨간날 ↔ 첫 메모 간격) = 이 SizedBox 높이.
              SizedBox(height: 3.5.h),
              // 🔧 메모 목록 - 최대 3개, fontSize: 7.5.sp. 메모끼리 간격은 Padding
              // top(첫 줄 0, 나머지 1.h).
              ...d.memos.take(3).toList().asMap().entries.map((e) => Padding(
                    padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.5.h),
                    child: _fitText(
                        e.value,
                        TextStyle(
                            fontSize: 8.sp,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            height: 1.0)),
                  )),
              // 🔧 이 Spacer가 있어서 이 테마는 메모가 적어도 아래로 안 쏠리고
              // 카드 위쪽에 붙어 보임 - 없애면 세로 중앙 정렬처럼 바뀜.
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 4번 · 굵은 격자형
  Widget _theme4Cell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Container(
        // ⭐ shade300→shade400으로 한 번 진하게 했는데 "아직도 더 진해야 할듯"
        // 이라는 재지적 - 두께는 그대로, 색만 한 단계 더(shade400→shade600).
        // ⭐ 2026-09-01 - "이번 달 셀들이 다 진하게 보인다"는 지적 - 이번 달
        // 평범한 날(오늘 아님)의 배경이 colorScheme.surface(=kAppSurface,
        // app_colors.dart의 옅은 라벤더톤 0xFFEEF1FC)였는데, 이 테마는 굵은
        // grey.shade600 격자선 + 어두운 헤더(_themeHeaderBackground 참고)와
        // 같이 있다 보니 그 살짝 tinted된 흰색이 유독 탁하게 보였음 - 순수
        // 흰색으로 교체(원래부터 이 값이었음, 이번에 처음 바뀌는 것 - "원래
        // 이랬나"의 답은 "네, kAppSurface를 계속 이렇게 썼었음").
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade600, width: 0.6),
          // ⭐ 2026-09-23 - 오늘을 셀 전체 노란 배경(0xFFFFF9C4)으로 칠하던 것을
          // "별로"라는 지적으로 날짜 숫자만 헤더와 같은 네이비 사각 배지로 감싸는
          // 방식으로 바꿈(아래 Row 참고) - 셀 배경은 다른 날과 같은 흰색.
          color: isOutside
              ? colorScheme.surfaceVariant.withOpacity(0.3)
              : Colors.white,
        ),
        padding: EdgeInsets.all(2.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔧 이 테마는 날짜 숫자와 빨간날 이름이 같은 줄(Row)에 나란히 있는
            // 게 특징 - 날짜 숫자 크기: fontSize: 10.sp(맨 위, 왼쪽 정렬).
            // 빨간날 이름 크기: fontSize: 5.5.sp, 날짜 숫자 오른쪽에 이어서 표시
            // (Expanded라 남는 폭을 다 씀 - 위치를 아래 줄로 내리려면 이 Row
            // 밖으로 꺼내 별도 줄로 빼야 함).
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 🔧 날짜 숫자 박스 - 오늘이든 아니든 같은 크기(높이 15.w)라 오늘만
                // 줄이 두꺼워지지 않음. 오늘이면 헤더색(0xFF263238) 사각 배지 +
                // 흰 숫자, 빨간날이면 네이비 위에서도 잘 읽히는 연한 빨강(red.shade200).
                Container(
                  height: 15.w,
                  constraints: BoxConstraints(minWidth: 15.w),
                  padding: EdgeInsets.symmetric(horizontal: 1.5.w),
                  margin: EdgeInsets.only(right: 1.5.w),
                  alignment: Alignment.center,
                  decoration: isToday && !isOutside
                      ? BoxDecoration(
                          color: const Color(0xFF263238),
                          borderRadius: BorderRadius.circular(2.r))
                      : null,
                  child: Text('${day.day}',
                      style: TextStyle(
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold,
                          color: isOutside
                              ? colorScheme.onSurfaceVariant.withOpacity(0.5)
                              : isToday
                                  ? (d.red
                                      ? Colors.red.shade200
                                      : Colors.white)
                                  : (d.red
                                      ? Colors.red.shade600
                                      : colorScheme.onSurface))),
                ),
                if (d.holidayName != null)
                  Expanded(
                      child: _fitText(
                          d.holidayName!,
                          TextStyle(
                              fontSize: 7.5.sp,
                              color: Colors.red.shade600,
                              fontWeight: FontWeight.bold)))
                else if (d.lunarText != null)
                  Expanded(child: _fitText(d.lunarText!, _lunarCellTextStyle())),
              ],
            ),
            // 🔧 근무명 배지(날짜 줄 바로 아래) - 크기: fontSize: 7.5.sp, 위아래
            // 여백은 margin vertical: 1.h. ⭐ 2026-09-23 - 예전엔 근무 없는 날 이
            // 자리를 아예 안 그려서 그날만 메모가 위로 올라붙었음 - 이제 보이지만
            // 않을 뿐 같은 높이를 차지함(Visibility maintainSize).
            Visibility(
              visible: d.hasShift,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Container(
                margin: EdgeInsets.symmetric(vertical: 0.2.h),
                padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.2.h),
                width: double.infinity,
                decoration: BoxDecoration(color: d.shiftColor),
                child: Text(d.shiftText,
                    style: TextStyle(
                        fontSize: 8.5.sp,
                        fontWeight: FontWeight.bold,
                        color: d.shiftTextColor),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center),
              ),
            ),
            // 🔧 메모 시작 위치(근무명 배지 ↔ 첫 메모 간격) = 이 SizedBox 높이.
            SizedBox(height: 4.0.h),
            // 🔧 메모 목록 - 최대 3개, fontSize: 8.5.sp, 왼쪽 정렬("· "로 시작하는
            // 불릿 스타일). _fitText가 줄바꿈 없이 한 줄로만 그리므로 메모끼리
            // 간격은 Text 자체의 줄간격(fontSize와 line-height)에 좌우됨 - 다른
            // 테마들처럼 별도 Padding top이 없어서, 메모 간격만 더 벌리려면
            // 이 map을 Padding(top: ...)으로 감싸야 함.
            ...d.memos.take(3).map((m) => _fitText(
                '· $m',
                TextStyle(
                    fontSize: 8.5.sp,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.start)),
          ],
        ),
      ),
    );
  }

  // ⭐ 5번 · 이니셜 뱃지형
  Widget _theme5Cell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    final numColor = isOutside
        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
        : (d.red ? Colors.red.shade400 : colorScheme.onSurface);
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
        border: isToday
            ? Border.all(color: Colors.indigo.shade400, width: 1.4)
            : Border.all(color: Colors.grey.shade200, width: 0.5),
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
                  // 🔧 근무명 "이니셜" 원형 뱃지(이 테마만 전체 이름이 아니라
                  // d.shiftText[0] 한 글자만 씀) - 크기: width/height: 14.w(원
                  // 지름) / fontSize: 7.5.sp(이니셜 글자). 없는 날은 SizedBox
                  // (height: 14.w)로 자리를 대신 비움.
                  if (d.hasShift)
                    Container(
                      width: 14.w,
                      height: 14.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: d.shiftColor, shape: BoxShape.circle),
                      child: Text(d.shiftText[0],
                          style: TextStyle(
                              fontSize: 8.5.sp,
                              fontWeight: FontWeight.bold,
                              color: d.shiftTextColor)),
                    )
                  else
                    SizedBox(height: 14.w),
                  // 🔧 뱃지 ↔ 날짜 숫자 간격.
                  SizedBox(height: 0.5.h),
                  // 🔧 날짜 숫자 - 크기: fontSize: 11.5.sp.
                  Text('${day.day}',
                      style: TextStyle(
                          fontSize: 10.5.sp,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.w600,
                          color: numColor)),
                ],
              ),
            ),
            // 🔧 빨간날 이름 - 크기: fontSize: 6.sp, 날짜 숫자 바로 아래 고정.
            _redDaySlot(
                d.holidayName,
                d.lunarText,
                TextStyle(
                    fontSize: 7.5.sp,
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.bold,
                    height: 1.0)),
            // 🔧 메모 시작 위치 - 메모가 있을 때만 이 간격(1.2.h)이 붙음(메모가
            // 없으면 이 SizedBox 자체가 안 생김 - if로 감싸져 있음).
            if (d.memos.isNotEmpty) SizedBox(height: 1.2.h),
            // 🔧 메모 목록 - 최대 3개, fontSize: 7.sp. 메모끼리 간격은 Padding
            // top(첫 줄 0, 나머지 2.h - 다른 테마보다 넓은 편).
            ...d.memos.take(3).toList().asMap().entries.map((e) => Padding(
                  padding: EdgeInsets.only(top: e.key == 0 ? 2 : 2.5.h),
                  child: _fitText(
                      e.value,
                      TextStyle(
                          fontSize: 7.5.sp,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.0)),
                )),
          ],
        ),
      ),
    );
  }

  // ⭐ 8번 · 언더라인 미니멀형 (색상만으로 구분 - 범례는 이 화면에선 생략,
  // 사용자 본인 근무명이라 알아보기 쉬움 + row6는 OT카드가 이미 차지 중이라
  // 자리도 없음. 위젯 큰 사이즈엔 범례를 넣기로 함(후속 작업, 네이티브 쪽)).
  Widget _theme8Cell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    // 🔧 이 테마는 근무명 "글자"를 셀 안에 안 그림(색깔 막대만) - 근무 구분은
    // 6번째 줄 범례(_buildThemedLegend의 underline case)가 대신함. 근무명
    // 텍스트를 셀 안에도 넣고 싶으면 아래 막대 Container 안에 Text를 추가하면 됨.
    return ClipRect(
      child: Column(
        children: [
          // 🔧 날짜 숫자 위쪽 여백(맨 위 시작 위치) = 이 SizedBox.
          SizedBox(height: 3.h),
          // 🔧 날짜 숫자 - 크기: fontSize: 12.sp. 오늘이면 밑줄(underline)로 표시.
          Text('${day.day}',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w400,
                color: isOutside
                    ? colorScheme.onSurfaceVariant.withOpacity(0.5)
                    : (d.red ? Colors.red.shade400 : colorScheme.onSurface),
                decoration: isToday ? TextDecoration.underline : null,
                decorationThickness: 2,
              )),
          // 🔧 근무 색깔 막대(글자 없음) - 크기: width: 22.w, height: 3.0.h("근무명
          // 뱃지를 세로로 아주 조금만 더 얇게" 요청으로 3.6.h→3.0.h로 줄어든
          // 이력 있음). 위아래 여백: margin vertical: 2.h. 없는 날은 SizedBox
          // (height: 7.0.h)로 자리를 대신 비움.
          if (d.hasShift)
            Container(
                margin: EdgeInsets.symmetric(vertical: 2.h),
                width: 22.w,
                height: 3.0.h,
                decoration: BoxDecoration(
                    color: d.shiftColor,
                    borderRadius: BorderRadius.circular(2.r)))
          else
            SizedBox(height: 7.0.h),
          // 🔧 빨간날 이름 - 크기: fontSize: 6.sp, 막대 바로 아래 고정. 별도
          // 시작 간격 SizedBox가 없어서 막대 margin(2.h)이 곧 이 간격임.
          _redDaySlot(
              d.holidayName,
              d.lunarText,
              TextStyle(
                  fontSize: 6.sp,
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.bold)),
          // 🔧 메모 목록 - 최대 3개, fontSize: 7.8.sp("너무 연하고 작다"는
          // 지적으로 7.sp→7.8.sp, 색도 onSurfaceVariant→grey.shade700로 진하게
          // 바꾼 이력). 메모끼리 간격을 조절하는 별도 Padding이 없음 - 필요하면
          // 이 map을 Padding(top: ...)으로 감싸서 추가.
          ...d.memos.take(3).map((m) => _fitText(
              m,
              TextStyle(
                  fontSize: 7.8.sp,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ⭐ 9번 · 이벤트 칩형
  // ⭐ 2026-09-01 - "나머지 3개(4/9/10번)도 같은 버그 있는지 훑어봐" 요청으로
  // 점검 - 4번(굵은 격자형)과 10번(매거진 에디토리얼)은 구조상 이 버그가 없음:
  // 4번은 맨 위 Row가 (내용과 무관하게) Flutter Row의 기본값(mainAxisSize.max)
  // 때문에 항상 셀 전체 폭을 스스로 차지하고, 10번은 유일한 비-Positioned
  // 자식(날짜 숫자를 감싼 Align)이 Align의 기본 동작(부모가 유한한 폭을 주면
  // 그 폭을 꽉 채움) 때문에 항상 전체 폭을 차지함 - 결과적으로 근무/공휴일/
  // 메모가 하나도 없어도 항상 셀 전체 폭이 유지됨. 이 9번(이벤트 칩형)만 진짜
  // 버그가 있었음 - 근무/공휴일/메모가 "전부 다 없는 날"(불규칙 스케줄에서
  // 근무를 아예 안 배정한 상태)에는 셀 안에 15x15 날짜 숫자 원 하나만 남는데,
  // 그건 폭을 강제하지 않는 고정 크기 박스라 나머지 테마들과 같은 이유
  // (table_calendar의 loose 제약 + Column 기본 crossAxisAlignment.center)로
  // 셀 전체가 좁게 쪼그라들어 날짜 숫자 위치가 틀어짐. 아래 Container에
  // width: double.infinity를 추가해 배지/칩 유무와 무관하게 항상 셀 전체 폭을
  // 차지하도록 함(_theme1Cell/_theme2Cell 버그 수정과 동일한 처방).
  Widget _theme9Cell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 1.5.w, vertical: 1.2.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔧 날짜 숫자 - 크기: fontSize: 9.5.sp. 오늘이면 15x15 원형 배지
            // (width/height: 15.w) 안에 흰 글씨로. 날짜 숫자 ↔ 근무명 칩 간격은
            // 이 Container의 margin bottom: 1.2.h.
            Container(
              width: 15.w,
              height: 15.w,
              alignment: Alignment.center,
              margin: EdgeInsets.only(bottom: 1.2.h),
              decoration: isToday
                  ? BoxDecoration(
                      color:
                          d.red ? Colors.red.shade400 : Colors.indigo.shade400,
                      shape: BoxShape.circle)
                  : null,
              child: Text('${day.day}',
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    color: isToday
                        ? Colors.white
                        : (isOutside
                            ? colorScheme.onSurfaceVariant.withOpacity(0.5)
                            : (d.red
                                ? Colors.red.shade400
                                : colorScheme.onSurface)),
                  )),
            ),
            // 🔧 이 테마는 근무명/빨간날/메모가 전부 같은 "칩(pill)" 모양
            // (_themeChip 공용 위젯, 아래 정의)을 색만 바꿔서 재사용 - 글자
            // 크기(7.5.sp)와 칩 모양(패딩/둥근 모서리)이 셋 다 동일함. 순서가
            // 곧 화면 순서(근무명 → 빨간날 → 메모)이고, 칩끼리 간격은 각 칩의
            // margin bottom(0.6.h, _themeChip 안) + 다음 칩 앞의 Padding top(0.8.h).
            // ⭐ 2026-09-23 - 근무 칩·빨간날/음력 줄은 내용이 없어도 같은 높이를
            // 차지함("음력이 있는 수요일에 메모를 적으면 옆 날들과 줄이 안 맞는다"
            // 지적 - 예전엔 없는 줄을 아예 안 그려서 메모가 날마다 위아래로 틀어졌음).
            Visibility(
              visible: d.hasShift,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: _themeChip(d.shiftText, d.shiftColor, d.shiftTextColor),
            ),
            // 🔧 빨간날도 칩 형태(배경 red.shade50 / 글자 red.shade400) - 글자
            // 크기는 _themeChip 공용값(7.5.sp)이라 근무명/메모와 따로 못 바꿈
            // (따로 바꾸려면 _themeChip에 fontSize 파라미터를 추가해야 함).
            // ⭐ 음력은 칩(색 배경) 없이 공용 스타일 그대로 - "폰트 디자인은 모든
            // 테마가 동일"해야 해서 이 테마만의 칩 배경을 입히지 않음. 칩과 같은
            // 높이의 자리 안에서 세로 가운데.
            Padding(
              padding: EdgeInsets.only(top: 0.8.h),
              child: SizedBox(
                width: double.infinity,
                height: _themeChipHeight(),
                child: d.holidayName != null
                    ? _themeChip(
                        d.holidayName!, Colors.red.shade50, Colors.red.shade400)
                    : (d.lunarText != null
                        ? Padding(
                            padding: EdgeInsets.only(bottom: 0.6.h),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: _fitText(
                                    d.lunarText!, _lunarCellTextStyle())),
                          )
                        : null),
              ),
            ),
            // 🔧 메모 목록 - 최대 3개, 칩 사이 간격 = Padding top: 0.8.h.
            ...d.memos.take(3).map((m) => Padding(
                padding: EdgeInsets.only(top: 0.8.h),
                child: _themeChip(
                    m, colorScheme.surfaceVariant, colorScheme.onSurface))),
          ],
        ),
      ),
    );
  }

  // 🔧 근무명/빨간날/메모가 공유하는 칩 위젯 - 글자 크기: fontSize: 7.5.sp(전체
  // 공통), 칩 자체 크기: padding horizontal 3.w/vertical 1.1.h, 모서리: 2.5.r,
  // 칩 아래 간격: margin bottom 0.6.h.
  TextStyle _themeChipTextStyle(Color fg) => TextStyle(
      fontSize: 7.sp, color: fg, fontWeight: FontWeight.w600, height: 1.1);

  // 칩 하나가 차지하는 전체 높이(글자 줄 + 위아래 padding + 아래 margin).
  double _themeChipHeight() {
    final textH = _lineHeightOf(_themeChipTextStyle(Colors.black));
    final lunarH = _lineHeightOf(_lunarCellTextStyle());
    return (textH > lunarH ? textH : lunarH) + 2 * 1.1.h + 0.6.h;
  }

  Widget _themeChip(String text, Color bg, Color fg) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 0.6.h),
      padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.1.h),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2.5.r)),
      child: _fitText(text, _themeChipTextStyle(fg)),
    );
  }

  // ⭐ 10번 · 매거진 에디토리얼형 (범례는 8번과 같은 이유로 이 화면에선 생략)
  Widget _theme10Cell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    // ⭐ "스크린샷보다 셀 테두리가 너무 진하다"는 지적으로 다른 테마들과 같은
    // 톤(grey.shade200)으로 낮춤. 메모 색도 "약간 더 진하게" - onSurfaceVariant
    // 대신 눈에 잘 띄는 고정 회색(grey.shade700)으로 교체.
    // 🔧 이 테마는 다른 8개와 달리 Column으로 위에서부터 쌓지 않고 Stack +
    // Positioned로 "절대 좌표"에 각 요소를 따로 박아둠 - 그래서 위치를 옮길
    // 땐 Padding/SizedBox가 아니라 각 Positioned의 top/left/right/bottom 숫자를
    // 직접 바꿔야 함.
    return Container(
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200, width: 0.5)),
      child: Stack(
        children: [
          // 🔧 근무 색 - 글자 없이 좌상단 삼각형 하나로만 표시. 크기: width/
          // height: 16.w. 근무명 텍스트를 넣고 싶으면 이 삼각형 대신 다른
          // 테마들처럼 Container+Text 배지로 바꿔야 함(지금 구조는 색만 표현).
          if (d.hasShift)
            Positioned(
              top: 0,
              left: 0,
              child: ClipPath(
                  clipper: _CalendarTriangleClipper(),
                  child: Container(
                      width: 16.w, height: 16.w, color: d.shiftColor)),
            ),
          // 🔧 날짜 숫자 - 크기: fontSize: 12.sp, 위치: 우측 상단 고정
          // (Align.topRight), 셀 위쪽 여백: padding top: 3.h.
          Padding(
            padding: EdgeInsets.only(top: 3.h, right: 2.w),
            child: Align(
              alignment: Alignment.topRight,
              child: Text('${day.day}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    color: isOutside
                        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
                        : (d.red ? Colors.red.shade400 : colorScheme.onSurface),
                    decoration: isToday ? TextDecoration.underline : null,
                  )),
            ),
          ),
          // ⭐ "메모 크기를 조금 더 키우고 진하게 - 광복절까지 여유가 꽤 있다"는
          // 지적으로 6.8.sp→7.3.sp. 공휴일명 Positioned에 left도 명시해서 폭을
          // 고정함(_fitText가 실제 셀 너비를 알아야 안전하게 잘라낼 수 있음 -
          // right만 있으면 폭이 무한대라 잘라낼 기준이 없었음).
          // 🔧 빨간날 이름 - 크기: fontSize: 7.5.sp, 위치: 셀 상단에서 top: 18.h
          // 고정 좌표(날짜 숫자를 따라가는 게 아니라 절대값 - 날짜 폰트 크기를
          // 바꿔도 이 값은 자동으로 안 따라옴, 겹치면 이 숫자를 직접 조절할 것).
          if (d.holidayName != null)
            Positioned(
              top: 18.h,
              left: 2.w,
              right: 2.w,
              child: _fitText(
                  d.holidayName!,
                  TextStyle(
                      fontSize: 7.5.sp,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right),
            )
          else if (d.lunarText != null)
            Positioned(
              top: 18.h,
              left: 2.w,
              right: 2.w,
              child: _fitText(d.lunarText!, _lunarCellTextStyle(),
                  textAlign: TextAlign.right),
            ),
          // 🔧 메모 목록 - 이 테마만 "아래에서부터" 시작함(다른 8개는 위에서부터
          // 쌓지만, 이건 Positioned에 top 없이 bottom: 2.h만 줘서 셀 바닥에서
          // 2.h 띄운 자리에 붙이고 메모가 늘어나면 위쪽으로 자람). 최대 3개,
          // fontSize: 7.3.sp, 메모끼리 간격은 Padding top(첫 줄 0, 나머지 1.2.h).
          Positioned(
            left: 2.w,
            right: 2.w,
            bottom: 2.h,
            child: Column(
              children: d.memos
                  .take(3)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => Padding(
                        padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.2.h),
                        child: _fitText(
                            e.value,
                            TextStyle(
                                fontSize: 7.3.sp, color: Colors.grey.shade800),
                            textAlign: TextAlign.right),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 2026-09-01 재설계 - 원래 "노르딕"(악센트 바 하나로만 색 표현)과
  // "다이어리"(아이보리 카드+알약 배지) 두 개를 따로 만들었다가, "다이어리는
  // 특별한 게 없다, 노르딕 구조를 이렇게 바꿔서 다이어리 톤을 살짝 얹어 하나로
  // 합쳐달라"는 요청으로 재설계. 구조 자체가 완전히 바뀜:
  //  1) 셀 상단을 "날짜 | 근무명" 절반씩(세로 구분선)으로 나눈 박스 하나로
  //     묶고, 그 박스 전체를 테두리로 감쌈(위/좌/우/아래 + 가운데 세로선).
  //  2) 근무명 쪽 절반만 근무색으로 꽉 채움(뱃지처럼) - 날짜 쪽은 항상 흰
  //     배경. 예전 "얇은 악센트 바"보다 근무 색이 훨씬 잘 보이게 됨.
  //  3) 빨간날(공휴일)이 있으면 그 박스 바로 아래에 흰 배경+빨간 글씨 줄을
  //     하나 더 붙이고, 그 줄에도 아래쪽 테두리를 그어서 "박스"를 한 칸 더
  //     늘림(테두리 안=핵심 정보, 테두리 밖=메모라는 시각적 구분).
  //  4) 메모 3개는 테두리 없이 자유롭게.
  // "약간 귀여운 느낌"은 스칸디나비안 팔레트(kDiaryPalette, 채도는 낮게 유지)
  // 위에 따뜻한 톤의 둥근 모서리(전체 셀 6.r)/오늘 표시(원형 배지, 각지지
  // 않은 채움 스타일)/다이어리풍 헤더 점 장식/로케일 요일명으로만 살짝
  // 얹음 - 팔레트 자체를 쨍하게 바꾸진 않음(다른 9개와 차별화되는 지점이라
  // 유지, 시인성도 채도 낮은 톤이 더 안정적으로 나옴).
  // 🔧 조절 지점:
  //  - 셀 전체 테두리 색/두께/둥근 정도: 함수 맨 위 local const borderColor,
  //    Border.all(width: 0.8), borderRadius circular(6.r) - 세 군데(상단 박스
  //    아래 테두리/세로 구분선/공휴일 줄 아래 테두리) 전부 이 borderColor를
  //    같이 씀, 하나만 바꾸면 나머지도 다 같이 바뀜.
  //  - 상단 박스 높이: 내용(패딩 vertical 3.h + 폰트 크기)에 맞춰 자동 - 늘리려면
  //    이 패딩(날짜 쪽/근무명 쪽 Container 둘 다 vertical: 3.h)을 키울 것
  //  - 날짜 숫자 크기: fontSize: 11.sp / 오늘 표시: 16x16 원형 채움(_diaryAccent,
  //    파일 상단 근처 top-level const) 안의 숫자는 fontSize: 9.5.sp
  //  - 근무명 텍스트 크기: fontSize: 6.8.sp(절반 폭 안에 들어가야 해서 다른
  //    테마보다 작게 잡음 - 셀이 큰 기기라면 키워도 됨)
  //  - 빨간날 텍스트 크기: fontSize: 6.8.sp, 색: 0xFFC0392B(차분한 벽돌색)
  //  - 메모 크기/간격: fontSize: 6.5.sp("– "로 시작하는 다이어리풍 대시 불릿),
  //    Padding top(첫 줄 0, 나머지 0.7.h)
  Widget _themeDiaryCell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule) {
    final d = _themedCellData(day, schedule);
    final colorScheme = Theme.of(context).colorScheme;
    const borderColor = Color(0xFFE4D9C9); // 따뜻한 크림 라인(무채색 회색 대신)
    final dateColor = isOutside
        ? colorScheme.onSurfaceVariant.withOpacity(0.4)
        : (d.red ? const Color(0xFFC0392B) : const Color(0xFF4A4038));
    final holidayStyle = TextStyle(
        fontSize: 8.sp,
        color: const Color(0xFFC0392B),
        fontWeight: FontWeight.w700);
    final holidayLineH = _lineHeightOf(holidayStyle);
    final lunarLineH = _lineHeightOf(_lunarCellTextStyle());
    // 빨간날 줄 아래 테두리(0.8)까지 포함한 높이.
    final redDayLineHeight =
        (holidayLineH > lunarLineH ? holidayLineH : lunarLineH) + 0.8;
    return ClipRect(
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.all(1.w),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: borderColor, width: 0.8),
          borderRadius: BorderRadius.circular(6.r),
        ),
        // ⭐ 2026-09-13 버그 수정 - "모든 달력 셀의 우측상단 모서리가 살짝
        // 잘려 보인다"는 지적 - Container의 clipBehavior(Clip.antiAlias)만으로는
        // border+borderRadius가 같이 있을 때 자식(특히 이 셀 우측상단에 바로
        // 맞닿는 근무명 배지 Container - 그 자체는 각진 사각형이라 둥근 모서리
        // 부분을 깎아줘야 함)이 둥근 모서리 밖으로 정확히 안 깎여서, 각진
        // 모서리가 테두리선 바로 안쪽에 살짝 삐져나와 보였음(특히 얇은
        // 테두리(0.8)+작은 반지름(6.r) 조합에서 두드러짐). 명시적 ClipRRect로
        // 교체하고, 테두리 두께만큼 안쪽으로 줄인 반지름을 써서 클립 경계가
        // 항상 바깥 테두리선 안쪽에 오게 함(바깥 테두리는 그 위에 그대로
        // 그려지므로 이음매가 안 보임).
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5.2.r),
          child: Column(
            children: [
              // 🔧 상단 박스 - 날짜(왼쪽 절반) | 근무명(오른쪽 절반, 근무색 채움).
              // IntrinsicHeight가 있어야 가운데 세로선(Container)이 Row의 실제
              // 높이만큼 늘어남(Row가 스스로 높이를 정하는 상황이라 필요).
              Container(
                decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: borderColor, width: 0.8))),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          // 🔧 오늘 표시(원형 배지) - 평소엔 _diaryAccent 배경 + 흰 글씨.
                          // 빨간날이 오늘이면 배경만 _diaryTodayRedBg로 바꾸고 글자는
                          // 계속 빨간색(dateColor의 빨간 값과 동일) - "빨간날" 신호를
                          // 잃지 않기 위함(위 _diaryTodayRedBg 선언부 주석 참고).
                          child: isToday
                              ? Container(
                                  width: 16.w,
                                  height: 16.w,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: d.red
                                          ? _diaryTodayRedBg
                                          : _diaryAccent,
                                      shape: BoxShape.circle),
                                  child: Text('${day.day}',
                                      style: TextStyle(
                                          fontSize: 9.5.sp,
                                          fontWeight: FontWeight.bold,
                                          color: d.red
                                              ? const Color(0xFFC0392B)
                                              : Colors.white)),
                                )
                              : Text('${day.day}',
                                  style: TextStyle(
                                      fontSize: 11.5.sp,
                                      fontWeight: FontWeight.w600,
                                      color: dateColor)),
                        ),
                      ),
                      const VerticalDivider(
                          width: 0.8, thickness: 0.8, color: borderColor),
                      Expanded(
                        child: Container(
                          color: d.hasShift
                              ? d.shiftColor.withOpacity(0.85)
                              : Colors.white,
                          alignment: Alignment.center,
                          padding: EdgeInsets.symmetric(
                              vertical: 3.h, horizontal: 1.w),
                          child: d.hasShift
                              ? Text(d.shiftText,
                                  style: TextStyle(
                                      fontSize: 8.5.sp,
                                      fontWeight: FontWeight.bold,
                                      color: d.shiftTextColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 🔧 빨간날(공휴일) - 있을 때만, 흰 배경 + 빨간 글씨. 이 줄 자체도
              // 아래쪽 테두리를 그어서 위 박스와 한 몸처럼 보이게 함.
              // ⭐ 2026-09-22 사용자 지적 - 공휴일 Container는 "위 박스와 한 몸처럼"
              // 보이려고 일부러 아래 테두리선을 그었지만(위 주석 참고), 음력은 그
              // 의도가 아니라서 테두리 없이 텍스트만.
              // ⭐ 2026-09-23 - 이 줄은 빨간날/음력이 없는 날도 같은 높이를 비워 둠
              // (메모 시작 줄을 같은 주의 셀끼리 맞추려고 - _redDaySlot 주석 참고).
              SizedBox(
                width: double.infinity,
                height: redDayLineHeight,
                child: d.holidayName != null
                    ? Container(
                        decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: borderColor, width: 0.8))),
                        child: _fitText(d.holidayName!, holidayStyle),
                      )
                    : (d.lunarText != null
                        ? _fitText(d.lunarText!, _lunarCellTextStyle())
                        : null),
              ),
              // 🔧 메모 3개 - 테두리 없음, 남는 공간을 채움(Expanded).
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 2.h),
                  child: Column(
                    children: d.memos
                        .take(3)
                        .toList()
                        .asMap()
                        .entries
                        .map((e) => Padding(
                              padding:
                                  EdgeInsets.only(top: e.key == 0 ? 0 : 0.7.h),
                              child: _fitText(
                                  '– ${e.value}',
                                  TextStyle(
                                      fontSize: 7.5.sp,
                                      color: const Color(0xFF1A1A1A),
                                      fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔧 메인·화이트/메인·다크(사용자 실기기 기본 테마) 날짜 셀 - 이 파일에서
  // 가장 먼저 손보게 될 함수. 구조: Column[근무명 배지(위) / Expanded(Stack[
  // 공휴일 이름(맨 위 고정) + 날짜 숫자(중앙) + 메모(맨 아래 고정, 최대 3개)])].
  // 다크 배색은 이 함수 안에서 직접 하드코딩(isDarkMode 분기)하는 부분과
  // colorScheme.*(=main.dart의 Theme(data: isDark? darkTheme:lightTheme) 래퍼가
  // 내려주는 값, 실제 색상표는 theme/app_theme.dart)를 쓰는 부분이 섞여 있음 -
  // "다크에서만 색이 이상하다" 싶으면 이 함수 안의 `isDarkMode ? ... : ...`
  // 삼항연산자들부터 볼 것.
  Widget _buildDateCell(
      DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule,
      {bool isSelected = false}) {
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

    final isHoliday = _getHolidayName(day, context) != null; // ⭐ 공휴일 체크

    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    Color dateColor;
    if (isSunday || isHoliday) {
      // ⭐ 일요일 또는 공휴일
      dateColor = isOutside
          ? (isDarkMode
              ? Colors.red.shade300.withOpacity(0.5)
              : Colors.red.withOpacity(0.3))
          : (isDarkMode ? Colors.red.shade300 : Colors.red);
    } else {
      dateColor = isOutside
          ? colorScheme.onSurfaceVariant.withOpacity(0.5)
          : colorScheme.onSurface;
    }

    return Container(
      decoration: BoxDecoration(
        color: isSelected && _isMultiSelectMode
            ? Theme.of(context).colorScheme.secondary.withOpacity(0.2)
            : Colors.transparent,
      ),
      padding: EdgeInsets.only(
          left: 2.w, right: 2.w, top: 2.h), // ⭐ 모든 날짜 동일한 padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 🔧 근무명 배지 - 크기: height: 18.h(배지 높이) / fontSize: 9.sp(글자
          // 크기, 아래 Text). 근무 없는 날은 SizedBox(height: 18.h)로 자리를
          // 대신 비움 - 배지 높이를 바꾸면 이 SizedBox도 같이 맞출 것.
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
                    ? Border(
                        left: BorderSide(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 3))
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
                final dateStr =
                    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                final memos = ref.watch(memoProvider)[dateStr] ?? [];
                final memoCount = memos.length;
                // ⭐ 2026-09-22 음력 - 공휴일이 없을 때만, 그리고 이 주의 "음력 표기 날"일
                // 때만 계산(_themedCellData가 이미 그 판정을 하므로 재사용 - 두 번 안
                // 만들려고 여기서 한 번만 불러 변수로 둠).
                final lunarText = _getHolidayName(day, context) == null
                    ? _themedCellData(day, schedule).lunarText
                    : null;

                return Stack(
                  children: [
                    // 🔧 빨간날(공휴일) 이름 - 위치: 셀 맨 위 고정(top: 0, 날짜
                    // 숫자와 무관 - Stack 안에서 독립적으로 배치되므로 날짜 폰트
                    // 크기를 바꿔도 안 따라옴). 크기: height: 11.h(이 줄 자체
                    // 높이) / fontSize: 9.sp인데 FittedBox(fit: scaleDown)로
                    // 감싸져 있어서 글자가 길면 이 11.h 줄 안에 맞게 자동으로
                    // 더 작게 줄어듦(9.sp는 "최대" 크기) - 아래로 옮기려면 top
                    // 값을 늘리거나 이 Positioned 앞에 별도 여백을 추가.
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
                                    ? (isDarkMode
                                        ? Colors.red.shade300.withOpacity(0.5)
                                        : Colors.red.withOpacity(0.3))
                                    : (isDarkMode
                                        ? Colors.red.shade300
                                        : Colors.red),
                              ),
                            ),
                          ),
                        ),
                      )
                    // ⭐ 2026-09-22 음력 - 빨간날 자리와 완전히 같은 위치(top:0)에,
                    // 공휴일이 없을 때만 표기. 폰트는 이 테마 전용이 아니라 모든
                    // 테마 공용 스타일(_lunarCellTextStyle).
                    else if (lunarText != null)
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
                              lunarText,
                              style: _lunarCellTextStyle(),
                            ),
                          ),
                        ),
                      ),
                    // 🔧 날짜 숫자 - 크기: fontSize: 16.sp. 위치: 기본은 셀
                    // 정중앙(Align.center)인데, 메모가 3개 꽉 찬 날만 Padding
                    // (bottom: 20.h)으로 그만큼 위로 밀어서 메모 3줄과 안 겹치게
                    // 함(memoCount >= 3 조건) - 이 20.h가 메모 한 줄 높이×3에
                    // 맞춰진 값이라, 메모 폰트/줄간격을 바꾸면 이 숫자도 같이
                    // 맞춰야 함. 오늘 날짜는 배경 pill(패딩 6.w/2.h + 둥근
                    // 모서리 4.r)이 추가로 덧씌워짐. 색 조합(라이트/다크 각각):
                    // 오늘+빨간날 = 라임/amber 배경 + 빨간텍스트
                    // 오늘+일반날 = 인디고배경 + 흰텍스트
                    // 오늘아님+빨간날 = 빨간텍스트만(배경 없음)
                    // 오늘아님+일반날 = 검정텍스트(다크는 onSurface)
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding:
                            EdgeInsets.only(bottom: memoCount >= 3 ? 20.h : 0),
                        child: Container(
                          padding: shouldHighlightToday
                              ? EdgeInsets.symmetric(
                                  horizontal: 6.w, vertical: 2.h)
                              : EdgeInsets.zero,
                          decoration: shouldHighlightToday
                              ? BoxDecoration(
                                  // ⭐ 다크모드 오늘 날짜 배경: 더 밝게
                                  color: (isSunday || isHoliday)
                                      ? (isDarkMode
                                          ? Colors.amber.shade300
                                          : Colors
                                              .lime.shade300) // 다크모드: 밝은 amber
                                      : (isDarkMode
                                          ? Color(0xFFB4BFFF)
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary), // 다크모드: 더 밝은 인디고
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
                                      ? (isDarkMode
                                          ? Colors.red.shade900
                                          : Colors.red) // 다크모드: 진한 빨강
                                      : (isDarkMode
                                          ? Colors.white
                                          : Theme.of(context)
                                              .colorScheme
                                              .onPrimary) // 다크모드: 순백
                                  : dateColor,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 🔧 메모 - 위치: 셀 맨 아래 고정(bottom: 1.5.h, "메모가
                    // 위/아래 중 어디서 시작하는가"의 답 = 아래에서부터, 날짜
                    // 숫자와 무관하게 독립 배치). 최대 3개(take(3)), 글자 크기:
                    // fontSize: 8.sp. 메모끼리 세로 간격 = 각 메모 Container의
                    // margin bottom: 0.5.h. 메모 3개 꽉 찰 때만 위 날짜 숫자가
                    // 20.h 위로 밀리는 로직과 세트(바로 위 Align 블록 참고) -
                    // 메모 폰트/패딩을 키우면 그 20.h도 같이 늘려야 겹침이 없음.
                    if (memos.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 1.5.h, // ⭐ 바닥에서 살짝 띄움
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: memos.take(3).map((memo) {
                            return Container(
                              width: double.infinity,
                              margin: EdgeInsets.only(bottom: 0.5.h),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 2.w, vertical: 0.5.h),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? colorScheme.primary.withOpacity(0.3)
                                    : colorScheme.surfaceVariant,
                                border: Border.all(
                                    color: isDarkMode
                                        ? colorScheme.primary.withOpacity(0.5)
                                        : colorScheme.outline,
                                    width: 0.5),
                                borderRadius: BorderRadius.circular(2.r),
                              ),
                              child: Text(
                                memo.memoText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 8.sp, // ⭐ 7 → 8 (살짝 크게)
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow
                                    .clip, // ⭐ ellipsis → clip (더 많이 표시)
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
    final basePopupHeight = screenHeight * 0.66; // ⭐ 화면의 66% (기존 72%에서 축소)

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
            final isKeyboardVisible = keyboardHeight > 50; // 키보드 감지 임계값

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
                      // ⭐ 2026-09-22 음력 날짜 - 날짜 텍스트 바로 아래 붙여야 해서(사용자
                      // 지적: 예전엔 Row 전체가 crossAxisAlignment.center라 OT 버튼
                      // 묶음이 날짜 텍스트보다 훨씬 키가 커서, 그 아래에 형제로 둔 음력
                      // 줄이 실제로는 날짜보다 OT 버튼 쪽에 더 붙어 보였음) 날짜 텍스트를
                      // Column으로 감싸 그 안에 음력 줄을 넣음. OT 버튼(_buildOvertimeToggle)이
                      // 이 Row에서 가장 키가 큰 요소라 Row 정렬을 center→start로 바꿔도
                      // OT 버튼 자체의 위치는 그대로(가장 큰 자식은 top/center 정렬이
                      // 결과적으로 같음) - 날짜+음력 묶음만 위쪽으로 붙게 됨.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${DateFormat.MMMd(Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en').format(day)} (${_getWeekday(day, context)})',
                                style: TextStyle(
                                    fontSize: 24.sp,
                                    fontWeight: FontWeight.bold),
                              ),
                              // ⭐ 상세팝업의 "(없음)"과 같은 스타일(fontSize: 14.sp,
                              // colorScheme.onSurfaceVariant)로 톤을 맞춤. 공휴일
                              // 표시와 동일하게 한국어 로케일에서만 보임
                              // (holiday_util.dart의 isKorean 분기와 같은 기준).
                              if (Localizations.localeOf(context)
                                          .languageCode ==
                                      'ko' &&
                                  solarToLunar(day) != null)
                                Padding(
                                  padding: EdgeInsets.only(top: 1.h),
                                  child: Text(
                                    formatLunarDateFull(solarToLunar(day)!),
                                    style: TextStyle(
                                        fontSize: 14.sp,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                  ),
                                ),
                            ],
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
                          Text(context.l10n.calendarShiftLabel,
                              style: TextStyle(
                                  fontSize: 16.sp,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(width: 8.w),
                          if (isModified) ...[
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(context.l10n.commonPrevious,
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontWeight: FontWeight.w500)),
                                SizedBox(height: 4.h),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceVariant,
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                        width: 1.5),
                                  ),
                                  child: Text(patternShift,
                                      style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                                ),
                              ],
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                  left: 6.w, right: 6.w, top: 16.h),
                              child: Icon(Icons.arrow_forward,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  size: 18.sp),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(context.l10n.commonCurrent,
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontWeight: FontWeight.w500)),
                                SizedBox(height: 4.h),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: _getShiftBackgroundColor(
                                        currentShift, schedule),
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(
                                        color: _getShiftTextColor(
                                            currentShift, schedule),
                                        width: 2),
                                  ),
                                  child: Text(currentShift,
                                      style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.bold,
                                          color: _getShiftTextColor(
                                              currentShift, schedule))),
                                ),
                              ],
                            ),
                          ] else
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: _getShiftBackgroundColor(
                                    currentShift, schedule),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(
                                    color: _getShiftTextColor(
                                        currentShift, schedule),
                                    width: 2),
                              ),
                              child: Text(currentShift,
                                  style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                      color: _getShiftTextColor(
                                          currentShift, schedule))),
                            ),
                        ],
                      ),

                      SizedBox(height: 16.h),

                      // ⭐ 고정 알람
                      Text(context.l10n.calendarFixedAlarmLabel,
                          style: TextStyle(
                              fontSize: 14.sp,
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 8.h),
                      Consumer(
                        builder: (context, ref, child) {
                          final alarmsAsync = ref.watch(alarmNotifierProvider);

                          return alarmsAsync.when(
                            loading: () => SizedBox(
                                height: 20.h,
                                width: 20.w,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            error: (_, __) => Text(
                                context.l10n.statusErrorOccurred,
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    color:
                                        Theme.of(context).colorScheme.error)),
                            data: (allAlarms) {
                              final dayStr =
                                  day.toIso8601String().split('T')[0];
                              final fixedAlarms = allAlarms
                                  .where((a) =>
                                      a.type == 'fixed' &&
                                      a.date != null &&
                                      a.date!
                                          .toIso8601String()
                                          .startsWith(dayStr))
                                  .toList();

                              // ⭐ 1단계: 알람이 있으면 우선 표시 (최우선)
                              if (fixedAlarms.isNotEmpty) {
                                // ⭐ 근무당 알람이 kMaxAlarmTemplatesPerShift(5)개까지 늘어나면서
                                // Expanded로 균등폭 배치하던 예전 방식은 카드가 너무 좁아지거나
                                // (5개) 넘치면 레이아웃이 깨짐(그 이상) - 고정폭 카드 + 가로 스크롤로
                                // 바꿔서 몇 개든 항상 같은 크기로 보이게 함. 시간순 정렬도 추가.
                                final sortedAlarms = [...fixedAlarms]
                                  ..sort((a, b) => a.time.compareTo(b.time));
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: sortedAlarms.map((alarm) {
                                      final typeInfo =
                                          _getAlarmTypeInfo(alarm.alarmTypeId);
                                      return GestureDetector(
                                        onTap: () =>
                                            _showAlarmTypeSelectionPopup(
                                                alarm, setState),
                                        child: Container(
                                          width: 78.w,
                                          margin: EdgeInsets.only(
                                              right: alarm != sortedAlarms.last
                                                  ? 8.w
                                                  : 0),
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 8.w, vertical: 6.h),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(8.r),
                                            border: Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondary
                                                    .withOpacity(0.3)),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(typeInfo['emoji']!,
                                                      style: TextStyle(
                                                          fontSize: 14.sp)),
                                                  SizedBox(width: 4.w),
                                                  Text(alarm.time,
                                                      style: TextStyle(
                                                          fontSize: 14.sp,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSecondaryContainer)),
                                                ],
                                              ),
                                              SizedBox(height: 4.h),
                                              Text(
                                                typeInfo['label']!,
                                                style: TextStyle(
                                                    fontSize: 10.sp,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSecondaryContainer),
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

                              // ⭐ 2단계: 알람이 없으면 템플릿 조회 (전날/당일/다음날
                              // 기여를 모두 반영 - day_offset 참고. day 자체에 배정된
                              // 근무뿐 아니라, day+1에 배정된 근무의 "전날" 템플릿이나
                              // day-1에 배정된 근무의 "다음날" 템플릿도 이 날짜에 알람을
                              // 만들 수 있음(AlarmRefreshEngine.kt computeDesiredAlarms와
                              // 동일한 판단 기준).
                              return FutureBuilder<bool>(
                                future: _checkHasUpcomingAlarmTemplate(
                                    schedule, day),
                                builder: (context, snapshot) {
                                  // 3단계: 템플릿이 없거나 로딩 중이면 (없음)
                                  if (!snapshot.hasData ||
                                      snapshot.data == false) {
                                    return Text('(${context.l10n.commonNone})',
                                        style: TextStyle(
                                            fontSize: 14.sp,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant));
                                  }

                                  // 4단계: 템플릿은 있는데 알람이 없는 경우 → 10일 체크 (DST 안전)
                                  final now = DateTime.now();
                                  final daysDiff = julianDayNumber(
                                          day.year, day.month, day.day) -
                                      julianDayNumber(
                                          now.year, now.month, now.day);

                                  // 5단계: 10일 이후면 안내 문구
                                  if (daysDiff >= kAlarmRefreshWindowDays) {
                                    return Text(
                                      context.l10n
                                          .calendarAutoGeneratedWithinDays(
                                              kAlarmRefreshWindowDays),
                                      style: TextStyle(
                                          fontSize: 13.sp,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .tertiary),
                                    );
                                  }

                                  // 6단계: 10일 이내인데 알람이 없으면 (없음) - 버그 상황
                                  return Text('(${context.l10n.commonNone})',
                                      style: TextStyle(
                                          fontSize: 14.sp,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant));
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
                          final currentMemos =
                              ref.watch(memoProvider)[dateStr] ?? [];
                          final isFull = currentMemos.length >= 3;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(context.l10n.calendarMemoColonLabel,
                                  style: TextStyle(
                                      fontSize: 14.sp,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      fontWeight: FontWeight.w600)),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: isFull
                                    ? Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 12.w, vertical: 8.h),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceVariant,
                                          borderRadius:
                                              BorderRadius.circular(8.r),
                                          border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline),
                                        ),
                                        child: Text(
                                          context.l10n.statusMemoLimit(3),
                                          style: TextStyle(
                                              fontSize: 14.sp,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant),
                                        ),
                                      )
                                    : TextField(
                                        controller: memoController,
                                        maxLines: 1,
                                        scrollPhysics: BouncingScrollPhysics(),
                                        decoration: InputDecoration(
                                          hintText:
                                              context.l10n.calendarMemoEnter,
                                          hintStyle: TextStyle(
                                              fontSize: 14.sp,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withOpacity(0.6)),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 12.w, vertical: 8.h),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8.r),
                                            borderSide: BorderSide(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8.r),
                                            borderSide: BorderSide(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondary,
                                                width: 2),
                                          ),
                                        ),
                                        style: TextStyle(fontSize: 14.sp),
                                      ),
                              ),
                              SizedBox(width: 6.w),
                              // ⭐ 2026-08-28 - 앱 공용 second button으로 교체(요청: "우리
                              // 앱의 second button 느낌으로") - 저장/확인 계열이라 success
                              // (초록) variant.
                              // ⭐ 2026-08-31 - compact(패딩 10/6, 폰트 12)로 교체했더니 "너무
                              // 작다"는 피드백 - 이 리팩터 전에 실제로 쓰던 크기(패딩 12/10,
                              // 폰트 13)로 되돌림(app_second_button.dart의 padding/fontSize
                              // override 참고). compact 자체의 정의는 그대로라 알람 이력
                              // 화면 등 다른 재사용처는 영향 없음.
                              AppSecondButton(
                                variant: AppSecondButtonVariant.success,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12.w, vertical: 10.h),
                                fontSize: 13.sp,
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
                                        ref
                                            .read(memoProvider.notifier)
                                            .createMemo(dateStr, text);
                                      },
                                child: Text(context.l10n.commonSave),
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
                              final memos =
                                  ref.watch(memoProvider)[dateStr] ?? [];

                              if (memos.isEmpty) {
                                return SizedBox.shrink();
                              }

                              // ⭐ 2026-09-03 - 메모 모아보기(memo_list_view.dart) 재구성
                              // 때 만든 카드 디자인(왼쪽 파란 포인트 바 + 흰 배경 + 그림자)을
                              // 그대로 가져옴(요청) - 우측 빨간 휴지통 버튼은 그대로 유지.
                              return Column(
                                children: memos.map((memo) {
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: 8.h),
                                    child: Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12.r),
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(12.r),
                                        onTap: () {
                                          // 입력칸에 남아 있던 포커스를 먼저 해제해야
                                          // 상세 팝업을 닫았을 때 키보드가 다시 살아나지 않는다.
                                          FocusScope.of(context).unfocus();
                                          _showMemoDetailPopup(day, memo);
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12.r),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .shadow
                                                    .withOpacity(0.04),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            // ⭐ 2026-09-03 버그수정 - crossAxisAlignment.stretch를
                                            // 썼었는데, 이 Row가 SingleChildScrollView(높이 무제한) 안에
                                            // 있어서 "부모 높이만큼 늘리기"가 무한대(infinity) 높이를
                                            // 요구하게 되어 "BoxConstraints forces an infinite height"
                                            // 런타임 예외로 이어짐(달력 셀 팝업이 메모 있는 날만 안 열리고
                                            // 멈추던 원인 - 메모 모아보기 화면의 동일 카드는 minHeight
                                            // 방식이라 이 문제가 없었음). start + 왼쪽 바에 minHeight를
                                            // 줘서 같은 시각 효과를 안전하게 재현.
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 4.w,
                                                constraints: BoxConstraints(
                                                    minHeight: 40.h),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  borderRadius:
                                                      BorderRadius.horizontal(
                                                          left: Radius.circular(
                                                              12.r)),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 12.w,
                                                      vertical: 10.h),
                                                  child: Text(
                                                    memo.memoText,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: 14.sp,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface),
                                                  ),
                                                ),
                                              ),
                                              // ⭐ 삭제 버튼 (바로 삭제) - 기존 그대로 유지
                                              GestureDetector(
                                                onTap: () async {
                                                  await ref
                                                      .read(
                                                          memoProvider.notifier)
                                                      .deleteMemo(
                                                          memo.id!, dateStr);
                                                },
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 10.w,
                                                      vertical: 10.h),
                                                  child: Icon(
                                                    Icons.delete,
                                                    size: 18.sp,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                ), // ⭐ Container 닫기
              ), // ⭐ Padding 닫기
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
    print(
        '🔍 알람 타입 선택 팝업 열림 - alarm.id: ${alarm.id}, alarmTypeId: ${alarm.alarmTypeId}');
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
            width: double.maxFinite, // ⭐ 명시적 width 지정
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ⭐ "{time} 알람" 앞에 근무명 + 전날/당일/다음날 Chip을 추가 -
                // "09:00 알람"만으로는 어느 근무의 알람인지, 언제 배정된 근무 기준인지
                // 알 수 없었음.
                // ⭐ 2026-08-25 - 글자가 너무 작고(14.sp) 연한 색(onSurfaceVariant)이라
                // 잘 안 보인다는 피드백으로 키우고(17.sp) 진한 색(onSurface)으로,
                // Wrap 대신 Row+중앙정렬로 "근무명 - Chip - 시간" 세 요소가 한 줄에
                // 가지런히 보이게 함. Chip은 DayOffsetBadge(dense한 AppShiftChip
                // 재사용)라 내용물 크기만큼만 차지해서 옆 텍스트와 잘 어울림.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (alarm.shiftType != null &&
                        alarm.shiftType!.isNotEmpty) ...[
                      Text(
                        alarm.shiftType!,
                        style: TextStyle(
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      SizedBox(width: 8.w),
                    ],
                    DayOffsetBadge(dayOffset: alarm.dayOffset, large: true),
                    SizedBox(width: 8.w),
                    Text(
                      context.l10n.calendarAlarmAt(alarm.time),
                      style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                Row(
                  mainAxisSize: MainAxisSize.max, // ⭐ 명시적 설정
                  children: [
                    _buildAlarmTypeOption(
                      typeId: 1,
                      icon: Icons.volume_up_rounded,
                      label: context.l10n.alarmSoundVibration,
                      isSelected: alarm.alarmTypeId == 1,
                      onTap: () async {
                        await ref
                            .read(alarmNotifierProvider.notifier)
                            .updateAlarmType(alarm.id!, 1);
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
                        await ref
                            .read(alarmNotifierProvider.notifier)
                            .updateAlarmType(alarm.id!, 2);
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
                        await ref
                            .read(alarmNotifierProvider.notifier)
                            .updateAlarmType(alarm.id!, 3);
                        Navigator.pop(context);
                        parentSetState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ⭐ 삭제/취소를 좌우로 떨어뜨리지 않고 우측에 나란히 배치(왼쪽=삭제,
          // 오른쪽=확인) - 취소는 이 팝업엔 없음(탭하는 순간 이미 저장되는 구조라
          // "취소"보다 "확인"이 더 알맞음, 클래스 주석 참고).
          actions: [
            AppSecondButton(
              variant: AppSecondButtonVariant.danger,
              onPressed: () =>
                  _showDeleteAlarmConfirmation(alarm, parentSetState),
              child: Text(context.l10n.commonDelete),
            ),
            AppSecondButton(
              variant: AppSecondButtonVariant.success,
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonOk),
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
                Navigator.pop(context); // 확인 팝업 닫기
                Navigator.pop(context); // 타입 선택 팝업 닫기
                await _deleteAlarm(alarm);
                parentSetState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(context.l10n.commonDelete,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.onError)),
            ),
          ],
        );
      },
    );
  }

  // ⭐ 알람 삭제 (울리는 중이면 Overlay도 종료)
  Future<void> _deleteAlarm(Alarm alarm) async {
    // ⭐ 2026-09-14 (출시전 감사 #14) - 여기서 먼저 'dismissOverlay'를 보내던 호출 제거. 울리는 중이면 deleteAlarm()이 Native 'stopRingingAlarm'으로 오버레이까지 닫음.
    // 먼저 보내면 오버레이가 울림을 끝낸 뒤라 삭제 이력이 'cancelled_before_ring'으로 잘못 남음.
    try {
      // 2. DB에서 알람 삭제 + Native 알람 취소
      await ref
          .read(alarmNotifierProvider.notifier)
          .deleteAlarm(alarm.id!, alarm.date);

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
            content: Text('${context.l10n.calendarDeleteAlarmFailed}: $e'),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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
    // ⭐ 2026-08-25 버그 수정 - "선택된 옵션의 아이콘이 안 보인다"는 신고: 이 앱
    // 테마(app_theme.dart)는 ColorScheme.light(primary: ...)만 지정하고
    // primaryContainer를 따로 안 줘서, Flutter가 primaryContainer를 primary와
    // 똑같은 색으로 채움(같은 문제를 work_hours_settings_screen.dart의
    // _selectedBg() 주석이 이미 문서화해둠) - 그 결과 이 위젯은 "primary 아이콘
    // 위에 primaryContainer(=같은 primary) 배경"이 되어 아이콘이 배경에
    // 완전히 묻혔음. primaryContainer에 의존하지 않고, 이미 이 파일의
    // 온보딩/설정 알람 타입 버튼(_buildTypeButton)이 쓰는 것과 동일한 "선택 시
    // 진한 단색 배경 + 흰 아이콘/글씨" 조합으로 바꿔 대비를 항상 보장함.
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24.sp,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(height: 4.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
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
    final displayShifts =
        schedule.isRegular ? baseShifts : [...baseShifts, '없음'];

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
                context.l10n
                    .calendarBulkChangeShiftTitle(_selectedDates.length),
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 24.h),

            // ⭐ 버튼들 - 세로 센터 정렬
            Expanded(
              child: Center(
                // ⭐ Center 추가
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
                      // ⭐ 2026-09-15 (전체 코드 점검 Q-02) - 시트를 먼저 닫고 일괄 변경을 시작함.
                      // 예전엔 순서가 반대라 _bulkAssignShift가 첫 await 전에 동기로 띄운 진행
                      // 다이얼로그를 이 pop이 닫아버렸음 → 시트가 작업 내내 열린 채 남고, 그 사이
                      // 다른 근무를 또 누르면 작업 끝의 pop이 한 번 더 불려 메인 화면까지 닫힐 수 있었음.
                      onPressed: () {
                        Navigator.pop(context);
                        _bulkAssignShift(shiftType, schedule);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _getShiftBackgroundColor(shiftType, schedule),
                        foregroundColor:
                            _getShiftTextColor(shiftType, schedule),
                        padding: EdgeInsets.symmetric(
                            horizontal: 4.w, vertical: 8.h),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          shiftType == '없음'
                              ? context.l10n.commonNone
                              : shiftType,
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

  // ⭐ 2026-09-15 (출시 적합성 재검토 AUD-01) - 일괄 변경이 겹쳐 실행되지 않게
  bool _bulkAssignInProgress = false;

  // ⭐ Provider 사용으로 변경
  Future<void> _bulkAssignShift(
      String shiftType, ShiftSchedule schedule) async {
    if (_selectedDates.isEmpty || _bulkAssignInProgress) return;
    _bulkAssignInProgress = true;

    // ⭐ "없음"을 "미설정"으로 변환
    final actualShiftType = shiftType == '없음' ? '미설정' : shiftType;

    // ⭐ 2026-09-15 (AUD-01) - 예전엔 showDialog(barrierDismissible: false) + 끝에서 Navigator.pop(context)였음.
    // 시스템 뒤로가기는 막지 못해서 로딩 중 뒤로가기로 진행창이 먼저 닫히면, 끝의 pop이 다른 route(메인 화면)를
    // 닫아 빈 화면이 될 수 있었음. runWithBlockingProgress는 뒤로가기를 막고 자기가 띄운 진행창만 닫음(성공·예외 모두).
    try {
      final alarmOutcome = await runWithBlockingProgress<AlarmScheduleOutcome?>(
          context, () async {
        // ⭐ Provider의 bulkAssignShift 사용
        await ref.read(scheduleProvider.notifier).bulkAssignShift(
              _selectedDates.toList(),
              actualShiftType,
            );

        // ⭐ 선택된 모든 날짜 ±1일(전날/다음날 알람이 있을 수 있어서)의 고정 알람을
        // 한 번에 재생성. 방금 갱신된 schedule을 다시 읽어서 넘김 - bulkAssignShift가
        // 이미 assignedDates를 저장했으므로 provider 상태가 최신임.
        // ⭐ 2026-09-04 - CRITICAL FIX: "미설정(=근무 일괄 해제)"일 때만 이 호출을
        // 스킵하던 조건을 제거함. regenerateAlarmsAroundDates/computeDesiredFixedAlarmsForDate는
        // '미설정'을 만나면 그 날짜에 알람을 새로 안 만들 뿐, 기존 알람을 지우는
        // 1단계(regenerateFixedAlarmsForDatesTxn의 delete)는 항상 실행됨 - 즉 이
        // 호출을 스킵하면 "일괄 해제"가 정확히 필요로 하는 정리(전날/다음날 알람
        // 포함, 이제 존재하지 않는 근무를 근거로 남아있던 알람 삭제)가 통째로 빠짐.
        // 그 알람들은 다음 네이티브 갱신 트리거(자정/20분전/앱 재실행 등)가 올
        // 때까지 실제 기기에 그대로 armed 상태로 남아있었음 - 단일 날짜 변경 경로
        // (changeShiftWithAlarms)는 이 가드가 없어서 원래도 정상 동작했음.
        final updatedSchedule = ref.read(scheduleProvider).value;
        if (updatedSchedule == null) return null;
        return await ref
            .read(alarmNotifierProvider.notifier)
            .regenerateAlarmsAroundDates(
              _selectedDates,
              updatedSchedule,
            );
      });

      if (mounted) {
        _exitMultiSelectMode();
        // ⭐ 2026-09-14 (출시전 감사 #13) - 알람 일부만 등록 실패하면 성공 문구 대신 몇 개가 빠졌는지 안내
        // (전부 실패는 regenerateAlarmsAroundDates가 예외 → 아래 catch)
        final partial = alarmOutcome != null && alarmOutcome.partiallyFailed;
        ScaffoldMessenger.of(context).showSnackBar(
          partial
              ? SnackBar(
                  content: Text(
                      '⚠️ ${context.l10n.alarmSchedulePartialFailed(alarmOutcome.failed, alarmOutcome.attempted)}'),
                  backgroundColor: Colors.orange,
                )
              : SnackBar(
                  content: Text(context.l10n.statusShiftAssigned)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.statusShiftAssignFailed}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('❌ _bulkAssignShift 실패: $e');
    } finally {
      _bulkAssignInProgress = false;
    }
  }

  Future<void> _changeShift(
      DateTime date, String newShiftType, ShiftSchedule schedule) async {
    try {
      await ref
          .read(scheduleProvider.notifier)
          .changeShiftWithAlarms(date, newShiftType);

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
            content: Text('${context.l10n.statusShiftChangeFailed}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('❌ _changeShift 실패: $e');
    }
  }

  // ⭐ 2026-09-03 - 메모 모아보기(memo_list_view.dart)에서 만든 바텀시트로 교체
  // (요청: "메모 모아보기에서 메모 탭하면 삭제 수정 나오고... 그대로 반영해줘").
  // 옛 AlertDialog와 기능은 동일(보기/수정/삭제)하되, 바텀시트 + SafeArea +
  // AppSecondButton 톤으로 통일하고 상단에 날짜를 같이 보여줌. 편집 컨트롤러
  // dispose를 100ms 지연시키는 것도 그대로 유지(기존 "MEDIUM FIX" 주석 참고 -
  // 팝업이 실제로 닫히는 애니메이션/rebuild와 dispose 타이밍이 겹치면 문제가
  // 있었던 이력이 있어 건드리지 않음).
  void _showMemoDetailPopup(DateTime day, DateMemo memo) {
    final dateStr = day.toIso8601String().split('T')[0];
    final editController = TextEditingController(text: memo.memoText);
    bool isEditing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = Theme.of(sheetContext).colorScheme;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36.w,
                          height: 4.h,
                          margin: EdgeInsets.only(bottom: 16.h),
                          decoration: BoxDecoration(
                            color: colorScheme.outline,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.event_note_rounded,
                              size: 18.sp, color: colorScheme.primary),
                          SizedBox(width: 6.w),
                          Text(
                            '${DateFormat.MMMd(Localizations.localeOf(sheetContext).languageCode == 'ko' ? 'ko' : 'en').format(day)} (${_getWeekday(day, sheetContext)})',
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      if (isEditing)
                        TextField(
                          controller: editController,
                          autofocus: true,
                          maxLines: 5,
                          minLines: 2,
                          decoration: InputDecoration(
                            hintText: sheetContext.l10n.calendarMemoContent,
                            contentPadding: EdgeInsets.all(12.w),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10.r),
                              borderSide:
                                  BorderSide(color: colorScheme.outline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10.r),
                              borderSide: BorderSide(
                                  color: colorScheme.primary, width: 2),
                            ),
                          ),
                          style: TextStyle(fontSize: 14.sp),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(14.w),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Text(
                            memo.memoText,
                            style: TextStyle(
                                fontSize: 14.sp,
                                color: colorScheme.onSurface,
                                height: 1.5),
                          ),
                        ),
                      SizedBox(height: 16.h),
                      Row(
                        children: [
                          if (isEditing) ...[
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.neutral,
                                onPressed: () {
                                  setSheetState(() {
                                    isEditing = false;
                                    editController.text = memo.memoText;
                                  });
                                },
                                child: Text(sheetContext.l10n.commonCancel),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.success,
                                onPressed: () async {
                                  if (editController.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(sheetContext)
                                        .showSnackBar(
                                      SnackBar(
                                          content: Text(sheetContext
                                              .l10n.statusEnterMemoContent)),
                                    );
                                    return;
                                  }
                                  FocusScope.of(sheetContext).unfocus();
                                  await ref
                                      .read(memoProvider.notifier)
                                      .updateMemo(
                                        memo.id!,
                                        dateStr,
                                        editController.text.trim(),
                                      );
                                  if (sheetContext.mounted)
                                    Navigator.of(sheetContext).pop();
                                },
                                child: Text(sheetContext.l10n.commonSave),
                              ),
                            ),
                          ] else ...[
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.danger,
                                onPressed: () async {
                                  await ref
                                      .read(memoProvider.notifier)
                                      .deleteMemo(memo.id!, dateStr);
                                  if (sheetContext.mounted)
                                    Navigator.of(sheetContext).pop();
                                },
                                child: Text(sheetContext.l10n.commonDelete),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.primary,
                                onPressed: () {
                                  setSheetState(() => isEditing = true);
                                },
                                child: Text(sheetContext.l10n.commonEdit),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // ⭐ MEDIUM FIX: 팝업 닫힐 때 메모리 누수 방지 (약간의 지연으로 rebuild 충돌 방지)
      Future.delayed(const Duration(milliseconds: 100), () {
        editController.dispose();
      });
    });
  }

  // ⭐ 2026-08-25 - 이 날짜 [day]에 (전날/당일/다음날 기여를 모두 포함해) 향후
  // 알람이 생성될 수 있는지 확인. 예전엔 day 자체에 배정된 근무의 템플릿만
  // 봤는데(_checkHasTemplate(String shiftType)), day_offset(-1/0/+1) 도입 후
  // "day+1에 배정된 근무의 전날(-1) 알람"이 실제로 day에 울리는 경우를 놓쳐서,
  // 그런 날은 템플릿이 실제로 있는데도 "(없음)"으로 잘못 표시됐음(달력 셀 팝업의
  // "10일 이내가 되면 자동 생성됩니다" 문구가 안 나오던 버그).
  // computeDesiredFixedAlarmsForDate()/AlarmRefreshEngine.kt의 computeDesiredAlarms()와
  // 동일한 기여 판단 기준(당일 offset 0 / D+1의 전날 offset -1 / D-1의 다음날 offset +1)을 씀.
  Future<bool> _checkHasUpcomingAlarmTemplate(
      ShiftSchedule schedule, DateTime day) async {
    final dayBefore = DateTime(day.year, day.month, day.day - 1);
    final dayAfter = DateTime(day.year, day.month, day.day + 1);

    final contributors = <MapEntry<String, int>>[
      MapEntry(schedule.getShiftForDate(day), kAlarmDaySame),
      MapEntry(schedule.getShiftForDate(dayAfter), kAlarmDayBefore),
      MapEntry(schedule.getShiftForDate(dayBefore), kAlarmDayAfter),
    ].where((e) => e.key != kUnsetShiftSentinel && e.key.isNotEmpty).toList();

    if (contributors.isEmpty) return false;

    try {
      final db = await DatabaseService.instance.database;
      for (final contributor in contributors) {
        final templates = await db.query(
          'shift_alarm_templates',
          where: 'shift_type = ? AND day_offset = ?',
          whereArgs: [contributor.key, contributor.value],
        );
        if (templates.isNotEmpty) return true;
      }
      return false;
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
