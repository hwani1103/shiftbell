// lib/screens/calendar_theme_lab_screen.dart
//
// ⭐ 테스트 전용 탭 - 메인 달력탭 디자인 후보 10개를 나란히 비교해보기 위한
// 프로토타입 공간. 실제 배포판에서는 설정에서 테마를 고르면 메인 달력탭 자체의
// 디자인이 바뀌는 구조로 갈 예정이고, 이 탭은 그 전 단계에서 여러 방향을
// 한꺼번에 만들어 비교하기 위한 용도임.
//
// ⭐ 모든 테마 공통 규칙 (요구사항 그대로):
// - 2026년 8월로 통일 (오늘 = 진짜 오늘 날짜를 그대로 씀 - 마침 8월 안에 있음)
// - 근무 6종 목업: 주간근무(4글자, "긴 이름 축약" 테스트용) / 주간 / 야간 / 당직 / 오프 / 휴무
// - 메모 1개·2개·3개짜리 날짜를 하나씩 지정, 3개인 날엔 일부러 긴 문장 하나를 섞어서
//   "메모가 셀 밖으로 넘치면 어떻게 처리되는지"까지 매 테마마다 확인함
// - 화이트 모드 전용 (다크모드는 나중에 별도 테마 축으로 처리할 예정이라 여기선 제외)
// - 일요일/공휴일 숫자는 항상 빨간색, 오늘은 항상 시각적으로 구분됨
// - 화면 맨 아래(네비게이션 바 바로 위)는 모든 테마가 "테마 번호 + 코멘트"만 보여주는
//   고정 높이 영역으로 통일 - 나중에 광고 자리로 쓸 계획이라 여기만은 절대 안 건드림
// - 그 위(상태바 바로 아래 ~ 저 고정 영역 바로 위)는 완전 자유 - 월 표시/전체근무표
//   버튼/오늘 버튼(기능은 유지, 디자인은 자유)/달력 그리드/이번 달 OT/주별 근무시간
//   (위치·디자인 자유, 정보 자체는 반드시 노출)까지 테마마다 전부 다르게 설계함
//
// ⭐ 스코프 관련 솔직한 안내 (구현하면서 내린 판단):
// - "전체근무표" 버튼은 실제 화면(AllShiftsView)으로 진짜 이동함 (그 화면은 테마와
//   무관하게 이미 완성돼 있는 별도 화면이라 그대로 재사용 가능함)
// - "오늘" 버튼은 이 프로토타입이 항상 2026년 8월 고정이라(실제 월 이동 없음) 안내
//   스낵바만 띄움 - 실제 채택 시엔 진짜 달력탭의 오늘 이동 로직을 그대로 씀
// - 날짜 셀을 탭하면 "이 테마가 채택되면 여기서 근무 변경/메모/알람 설정 팝업이 뜬다"는
//   걸 보여주는 간단한 미리보기 시트만 뜸 - 실제 팝업(근무 변경, OT 입력 등)은 이미
//   달력탭에 완성되어 있고 전혀 안 건드렸으므로, 여기서 다시 통째로 복제하지 않음
//   (테마 채택 후 실제 연결 시 그대로 재사용하면 됨)

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'all_shifts_view.dart';
import '../l10n/l10n_extensions.dart';
import '../models/calendar_theme.dart';
import '../models/date_overtime.dart';
import '../theme/app_theme.dart';
import '../utils/weekday_util.dart';

// ============================================================
// ⭐ 공용 목업 데이터
// ============================================================

class _MockShift {
  final String name;
  final Color color;
  final int durationMinutes;
  const _MockShift(this.name, this.color, this.durationMinutes);
}

// ⭐ 영어 현지화: 이름은 로케일에 따라 달라져야 해서(context 필요) 색상/시간
// (로케일 무관)만 top-level에 남기고, 이름은 아래 _mockShiftNames(context)에서
// 계산함. '주간근무'(맨 앞) 자리는 원래 "긴 이름 축약" 테스트용이라 다른
// 이름보다 일부러 더 긴 문구를 씀(기존 근무명 키와 겹치지 않는 별도 키).
const _mockShiftColors = <Color>[
  Color(0xFF42A5F5),
  Color(0xFF26C6DA),
  Color(0xFF7E57C2),
  Color(0xFFFF8A65),
  Color(0xFF66BB6A),
  Color(0xFFEF5350),
];
const _mockShiftDurations = <int>[8 * 60, 8 * 60, 12 * 60, 24 * 60, 0, 0];

List<String> _mockShiftNames(BuildContext context) => [
  context.l10n.themeLabMockDayShiftLong,
  context.l10n.shiftDay,
  context.l10n.shiftNight,
  context.l10n.shiftOnCall,
  context.l10n.shiftOff,
  context.l10n.shiftDayOff,
];

int _mockShiftIndexFor(DateTime d) {
  final epoch = DateTime(2026, 1, 1);
  final days = d.difference(epoch).inDays;
  return ((days % 6) + 6) % 6;
}

// ⭐ 6일 주기로 순환하는 목업 패턴 (앞뒤 스필오버 날짜도 동일하게 적용됨)
_MockShift _mockShiftFor(BuildContext context, DateTime d) {
  final i = _mockShiftIndexFor(d);
  return _MockShift(_mockShiftNames(context)[i], _mockShiftColors[i], _mockShiftDurations[i]);
}

// ⭐ "테마 미리보기(설정 탭 캐러셀 카드)에 메모가 보이는데 다 지우자 - 오늘
// 표시랑 빨간날은 그대로 두고" - 미리보기가 실제 사용자 화면과 더 가깝게
// 보이도록 목업 메모를 전부 비움. 공휴일(_mockHolidayKey 등)/오늘(_isToday)
// 표시 로직은 이 맵과 무관해서 그대로 유지됨.
final Map<String, List<String>> _mockMemos = {};

// ⭐ 수동 OT 목업 (8/15는 광복절과 겹치게 해서 "같은 셀에 여러 배지" 케이스도 같이 확인)
final Map<String, int> _mockOtMinutes = {
  '2026-08-15': 150,
  '2026-08-22': 60,
};

const _mockHolidayKey = '2026-08-15';
const _mockHolidayName = '광복절';

// ⭐ 영어 현지화: 공휴일 이름은 한국 고유 공휴일이라 영어 로케일에서는 표시
// 안 하기로 결정됨(getHolidayName의 isKorean 규칙과 동일 - 2번 섹션 참고).
// 이 목업 미리보기도 한국 로케일일 때만 뱃지를 보여주고, 아니면 숨김.
String? _mockHolidayNameFor(BuildContext context, DateTime d) {
  if (!_isHoliday(d)) return null;
  final isKorean = Localizations.localeOf(context).languageCode == 'ko';
  return isKorean ? _mockHolidayName : null;
}

// ⭐ 근무명 12개 + 라이트/다크 팔레트는 models/calendar_theme.dart로 이동함
// (kMainShiftNames/kMainLightPalette/kMainDarkPalette) - calendar_tab.dart
// (실제 메인 달력)도 똑같은 팔레트를 써야 해서 공용 위치로 옮겼고, 여기서는
// 그 공용 상수를 그대로 씀(중복 정의 없이). 영어 현지화: kMainShiftNames가
// mockShiftNames(BuildContext)로 바뀌어서(플레이북 3번 섹션) top-level에서 더
// 이상 쓸 수 없음 - _CalendarThemeLabScreenState의 메서드로 옮김(아래 참고).

// ⭐ 12개 팔레트를 요일처럼 순환시켜 "메인" 테마 목업 달력을 채움 -
// _mockShiftFor(6종 순환)와 같은 방식, 팔레트만 다르게 받음.
_MockShift _mainShiftFor(DateTime d, List<_MockShift> palette) {
  final epoch = DateTime(2026, 1, 1);
  final days = d.difference(epoch).inDays;
  return palette[((days % palette.length) + palette.length) % palette.length];
}

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool _isOutsideAugust(DateTime d) => d.month != 8;
bool _isSunday(DateTime d) => d.weekday == DateTime.sunday;
bool _isHoliday(DateTime d) => _dateKey(d) == _mockHolidayKey;
bool _isRedDay(DateTime d) => _isSunday(d) || _isHoliday(d);

bool _isToday(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

// ⭐ 2026년 8월을 덮는 6주(일~토) x 7 = 42일 그리드 (7/26 ~ 9/5)
List<DateTime> _augustGridDays() {
  final firstOfMonth = DateTime(2026, 8, 1);
  final daysFromSunday = firstOfMonth.weekday % 7; // Dart weekday: 일=7 -> %7=0, 월=1..토=6
  final gridStart = firstOfMonth.subtract(Duration(days: daysFromSunday));
  return List.generate(42, (i) => gridStart.add(Duration(days: i)));
}

// ⭐ 자동 대비 텍스트 색상 (shift_schedule.dart의 isBright/getTextColor와 동일 공식)
Color _autoTextColor(Color bg) {
  final luminance = bg.red * 0.299 + bg.green * 0.587 + bg.blue * 0.114;
  return luminance > 200 ? const Color(0xFF212121) : Colors.white;
}

// ⭐ 주별(월~일) 근무시간 요약 - "주별 근무시간" 표시용
class _WeekSummary {
  final DateTime start;
  final DateTime end;
  final int totalMinutes;
  final Map<String, int> counts;
  const _WeekSummary(this.start, this.end, this.totalMinutes, this.counts);
}

List<_WeekSummary> _mockWeekSummaries() {
  final firstOfMonth = DateTime(2026, 8, 1);
  final lastOfMonth = DateTime(2026, 8, 31);
  final firstMonday = firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));
  final lastSunday = lastOfMonth.add(Duration(days: 7 - lastOfMonth.weekday));

  final weeks = <_WeekSummary>[];
  var start = firstMonday;
  while (!start.isAfter(lastSunday)) {
    final end = start.add(const Duration(days: 6));
    int minutes = 0;
    final counts = <String, int>{};
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      // ⭐ 이 계산은 State 필드 초기화 시점(_weeks)에 실행되어 아직 context가
      // 없으므로, 로케일에 따라 달라지는 근무명 대신 인덱스로만 집계함(counts는
      // 화면에 표시되지 않는 값이라 키가 무엇이든 영향 없음).
      final idx = _mockShiftIndexFor(d);
      final duration = _mockShiftDurations[idx];
      if (duration > 0) {
        minutes += duration;
        counts['shift$idx'] = (counts['shift$idx'] ?? 0) + 1;
      }
      minutes += _mockOtMinutes[_dateKey(d)] ?? 0;
    }
    weeks.add(_WeekSummary(start, end, minutes, counts));
    start = start.add(const Duration(days: 7));
  }
  return weeks;
}

// ⭐ 영어 현지화: 기존 로컬 포맷터 대신 공용 formatOvertimeMinutes(context, minutes)를
// 재사용함(lib/models/date_overtime.dart, 플레이북 2번 섹션) - 중복 정의 제거.

int get _mockMonthlyOtTotal => _mockOtMinutes.values.fold(0, (a, b) => a + b);

// ⭐ 영어 현지화: _weekdayKr(로케일에 따라 바뀌어야 함)는 weekdayLabel(context, i)로
// 대체되어 제거됨(플레이북 2/3번 섹션). _weekdayEn3/_weekdayEn1은 일부 테마가 항상
// 영어 약자로 보이도록 의도한 디자인 선택이라 로케일과 무관하게 그대로 둠.
const _weekdayEn3 = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _weekdayEn1 = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

// ============================================================
// ⭐ 메인 화면 - PageView로 10개 테마를 스와이프 비교
// ============================================================

class CalendarThemeLabScreen extends StatefulWidget {
  // ⭐ 설정 탭의 테마 선택 캐러셀(calendar_theme_picker_screen.dart)이 이 화면을
  // 그대로 재사용해서 미리보기 카드를 만듦 - 코드를 새로 만들지 않고 특정
  // 테마 페이지에 바로 진입만 시키면 되므로 initialPage를 추가함.
  final int initialPage;
  const CalendarThemeLabScreen({super.key, this.initialPage = 0});

  @override
  State<CalendarThemeLabScreen> createState() => _CalendarThemeLabScreenState();
}

class _CalendarThemeLabScreenState extends State<CalendarThemeLabScreen> {
  late final _pageController = PageController(initialPage: widget.initialPage);

  final List<DateTime> _days = _augustGridDays();
  final List<_WeekSummary> _weeks = _mockWeekSummaries();

  // ⭐ 영어 현지화: kMainShiftNames가 mockShiftNames(BuildContext)로 바뀌면서
  // top-level에서 더 이상 계산할 수 없어진 _mockLegendShifts/_mockLegendShiftsDark를
  // State의 메서드로 옮김(플레이북 3번 섹션 지시대로) - build() 이후에만 호출됨.
  List<_MockShift> _legendShifts(BuildContext context) => List.generate(
    12, (i) => _MockShift(mockShiftNames(context)[i], kMainLightPalette[i], 0),
  );
  List<_MockShift> _legendShiftsDark(BuildContext context) => List.generate(
    12, (i) => _MockShift(mockShiftNames(context)[i], kMainDarkPalette[i], 0),
  );

  // ⭐ 테마 이름/설명 문구는 완전히 제거함("진짜 메인 달력에 쓸 정도로" 다듬는
  // 단계라 화면에 그런 라벨이 있으면 안 됨) - 테마는 이제 내부적으로 숫자
  // (0~8, CalendarThemeId)로만 구분됨. 설정 탭의 테마 선택 화면에서 쓰는
  // "1번/2번/.../메인 화이트/메인 다크" 라벨은 lib/models/calendar_theme.dart
  // 하나로 통합해서 정의함(여기서 다시 안 만듦 - 중복 방지).
  static const _themeCount = 9;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ "진짜 메인 달력에 쓸 정도로" 다듬는 단계 - 테마 이름/설명을 보여주던
    // 하단 고정 띠(원래는 나중에 광고 자리로 남겨두려던 곳)를 완전히 제거함.
    // 테마는 이제 내부적으로 숫자(인덱스)로만 구분되고 화면엔 아무 라벨도 안
    // 보임 - PageView가 화면 전체(SafeArea)를 그대로 씀. 그 띠가 없어졌으니
    // bottom SafeArea도 이제 막을 이유가 없어서 true로 되돌림(제스처 네비
    // 바에 캘린더 내용이 가리는 걸 방지).
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: _themeCount,
          itemBuilder: (context, index) => _buildThemeBody(index),
        ),
      ),
    );
  }

  // ⭐ 이 index는 설정 탭 캐러셀(calendar_theme_picker_screen.dart)이
  // kAllCalendarThemeIds(=CalendarThemeId.values)의 순서 그대로 넘겨줌 - 그
  // 목록을 "메인·화이트/다크가 맨 앞"으로 재배치했으니 여기 매핑도 반드시
  // 동일한 순서로 맞춰야 함(안 그러면 캐러셀 카드가 엉뚱한 테마를 보여줌).
  Widget _buildThemeBody(int index) {
    switch (index) {
      case 0: return _themeMainWhite();
      case 1: return _themeMainDark();
      case 2: return _theme1MinimalLine();
      case 3: return _theme2MaterialCard();
      case 4: return _theme4BoldGrid();
      case 5: return _theme5InitialBadge();
      case 6: return _theme8Underline();
      case 7: return _theme9EventChip();
      case 8: return _theme10Editorial();
      default: return const SizedBox.shrink();
    }
  }

  // ⭐ "전체근무표"는 이미 완성된 실제 화면을 그대로 재사용 (테마와 무관한 별도 화면)
  void _openAllShifts() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AllShiftsView()));
  }

  // ⭐ 이 프로토타입은 2026년 8월 고정이라 실제 "오늘로 이동"은 의미가 없어서 안내만 함
  void _tapToday() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.themeLabPreviewFixedMonthNotice),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ⭐ 날짜 탭 → 실제 팝업 대신 "이 테마가 채택되면 여기서 무슨 일이 일어나는지"
  // 보여주는 가벼운 미리보기 시트. 실제 근무변경/메모/OT 팝업은 달력탭에 이미 완성돼
  // 있고 여기서 안 건드렸으므로, 채택 후 실제 연결 시 그대로 재사용하면 됨.
  void _tapDay(DateTime day) {
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final ot = _mockOtMinutes[_dateKey(day)] ?? 0;
    final locale = Localizations.localeOf(context).toString();
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
              Text(
                context.l10n.themeLabPreviewSheetTitle(
                  DateFormat.MMMd(locale).format(day),
                  weekdayLabel(context, day.weekday % 7),
                ),
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10.h),
              Row(children: [
                Container(width: 10.w, height: 10.w, decoration: BoxDecoration(color: shift.color, shape: BoxShape.circle)),
                SizedBox(width: 6.w),
                Text(context.l10n.themeLabPreviewShiftLabel(shift.name), style: TextStyle(fontSize: 14.sp)),
              ]),
              if (ot > 0) ...[
                SizedBox(height: 4.h),
                Text('OT: ${formatOvertimeMinutes(context, ot)}', style: TextStyle(fontSize: 13.sp, color: Colors.indigo)),
              ],
              if (memos.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text(
                  context.l10n.themeLabPreviewMemoCount(memos.length, memos.join(" / ")),
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700),
                ),
              ],
              SizedBox(height: 14.h),
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8.r)),
                child: Text(
                  context.l10n.themeLabPreviewSheetHint,
                  style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade600, height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}

// ============================================================
// ⭐ 테마 1 · 미니멀 라인 (구글 캘린더 참고)
// 요일당 얇은 선만, 근무는 셀 하단 컬러바 + 1글자. 오늘=숫자 원형 테두리.
// ============================================================
extension _Theme1 on _CalendarThemeLabScreenState {
  Widget _theme1MinimalLine() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
          child: Row(
            children: [
              Text('Aug 2026', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w600, color: Colors.black87)),
              const Spacer(),
              _thinTextButton(context.l10n.shiftFullSchedule, _openAllShifts),
              SizedBox(width: 12.w),
              _thinTextButton('Today', _tapToday),
            ],
          ),
        ),
        SizedBox(height: 4.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(
                child: Text(
                  _weekdayEn3[i],
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w600,
                    color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500,
                  ),
                ),
              ),
            )),
          ),
        ),
        Container(margin: EdgeInsets.only(top: 4.h), height: 1, color: Colors.grey.shade200),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(
                  children: List.generate(7, (col) {
                    final day = _days[row * 7 + col];
                    return Expanded(child: _theme1Cell(day, col == 0, isFirstRow: row == 0));
                  }),
                ),
              )),
            ),
          ),
        ),
        _theme1OtBar(),
        SizedBox(height: 6.h),
      ],
    );
  }

  Widget _theme1Cell(DateTime day, bool isSunCol, {bool isFirstRow = false}) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);
    final numColor = outside
        ? Colors.grey.shade300
        : (red ? Colors.red.shade400 : Colors.black87);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade100))),
        // ⭐ 위쪽 패딩은 매 행마다 근무바 위에 여백을 주는 용도인데, 첫 행에서는
        // 이게 바로 위 요일 밑줄과 근무바 사이에 불필요한 틈으로 보임 (다른 행
        // 사이 간격은 이 패딩이 위/아래로 겹쳐서 자연스러운데, 첫 행은 위에 겹칠
        // "이전 행의 아래쪽 패딩"이 없어서 그 틈만 유독 붕 떠 보였음). 그래서
        // 첫 행만 위쪽 패딩을 0으로 없애 밑줄에 딱 붙게 하고, 나머지 행 사이
        // 간격(비율)은 그대로 유지함.
        padding: EdgeInsets.only(top: isFirstRow ? 0 : 2.h, bottom: 2.h),
        // ⭐ 9번과 같은 이유로 ClipRect를 미리 안전망으로 둠 - 이번에 간격을 다시
        // 넓히면서 혹시라도 넘치더라도 에러 배너 없이 조용히 잘리게 함.
        child: ClipRect(
          child: Column(
          children: [
            // ⭐ 근무명을 맨 위로 - 숫자보다 근무가 먼저 눈에 들어와야 시인성이
            // 좋다는 피드백으로 순서 변경 (원래는 숫자→메모→[Spacer]→근무바 순이라
            // 근무 정보가 셀 맨 아래로 밀려서 한눈에 안 들어왔음 + Spacer가 근무바를
            // 셀 바닥까지 밀어붙여서 다음 줄과 거의 안 떨어져 보이던 문제도 같이
            // 해결됨 - 이제 근무바가 셀 "안쪽" 위에 붙어서 여백을 스스로 가짐).
            // ⭐ "이전/다음 달로 넘어가는 며칠에도 근무명이 나왔었는데 지금은
            // 안 나온다"는 피드백 - 실제 메인 달력(_buildDateCell)도 outside
            // 여부와 무관하게 배지를 항상 그대로(흐리지 않게) 보여주므로 동일하게
            // 맞춤 - 날짜 숫자 쪽만 흐려지는 걸로 이미 "다른 달"이 구분됨.
            Container(
              width: double.infinity,
              height: 11.h,
              // ⭐ 공휴일+메모3개 조합(8/15)에서 bottom overflow가 났음(RenderFlex) -
              // "조금씩 줄여서" 요청대로 이 셀의 모든 세로 여백/크기를 전체적으로
              // 소폭씩 다시 낮춤(badge 12h→11h, margin 1.5h→1h 등, 이하 동일 패턴).
              margin: EdgeInsets.only(top: 1.h),
              color: shift.color.withOpacity(0.85),
              alignment: Alignment.center,
              // ⭐ 굳이 1글자로 줄일 이유가 없는 디자인이라는 피드백으로 전체 이름을
              // 그대로 노출 (영어 현지화로 근무명 글자수 제한이 10글자로 늘어나면서
              // 강제 substring 컷은 제거하고 ellipsis로 자연스럽게 잘리게 함).
              child: Text(
                shift.name,
                style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: 1.5.h),
            Container(
              width: 18.w,
              height: 18.w,
              alignment: Alignment.center,
              decoration: today
                  ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.indigo.shade400, width: 1.4))
                  : null,
              child: Text('${day.day}', style: TextStyle(fontSize: 11.sp, fontWeight: today ? FontWeight.bold : FontWeight.w500, color: numColor)),
            ),
            if (_mockHolidayNameFor(context, day) != null)
              Text(_mockHolidayNameFor(context, day)!, style: TextStyle(fontSize: 6.5.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
            // ⭐ "좋아졌는데 아주 조금만 더" 피드백으로 한 번 더 살짝 키움
            // (3.2h→3.8h) - ClipRect 안전망 있으니 부담 없이 조금 더 키움.
            SizedBox(height: 3.8.h),
            // ⭐ 폰트 크기만으로는 잘 안 보인다는 피드백 - 문제는 크기보다 두께/대비였음
            // (기본 굵기 + grey.shade600은 이 작은 크기에서 획이 너무 가늘어 보임).
            // w600 정도로 살짝 굵게 + grey.shade700으로 한 톤 더 진하게 바꿔서 또렷하게 함.
            // ⭐ 메모끼리 간격도 한 번 더 살짝 키움(0.8h→1.h).
            ...memos.take(3).toList().asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.h, left: 1.w, right: 1.w),
              child: Text(e.value, style: TextStyle(fontSize: 7.sp, color: Colors.grey.shade700, fontWeight: FontWeight.w600, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            )),
          ],
          ),
        ),
      ),
    );
  }

  Widget _theme1OtBar() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8.r)),
      child: Row(
        children: [
          Icon(Icons.access_time, size: 13.sp, color: Colors.indigo.shade300),
          SizedBox(width: 5.w),
          Text('${context.l10n.shiftThisMonthOt} ${formatOvertimeMinutes(context, _mockMonthlyOtTotal)}', style: TextStyle(fontSize: 11.sp, color: Colors.black87)),
          const Spacer(),
          GestureDetector(
            onTap: () => _showWeekSummarySheet(context, _weeks),
            child: Text('${context.l10n.shiftWeeklyWorkHours} ›', style: TextStyle(fontSize: 11.sp, color: Colors.indigo.shade400, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _thinTextButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.indigo.shade400, fontWeight: FontWeight.w600)),
    );
  }
}

// ============================================================
// ⭐ 테마 2 · 머티리얼 카드형
// 셀마다 살짝 뜬 카드 + 그림자. 근무는 카드 상단 컬러 탭. 메모는 카드 하단 미니 텍스트.
// ============================================================
extension _Theme2 on _CalendarThemeLabScreenState {
  Widget _theme2MaterialCard() {
    return Container(
      color: const Color(0xFFF7F7FA),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
            child: Row(
              children: [
                // ⭐ 3번(애플 캘린더 스타일) 헤더 타이포를 그대로 옮겨옴 - 3번은
                // 이 디자인만 채택되고 나머지(테두리 없는 숫자, 오늘=꽉 찬 원 등)는
                // 폐기됨. "2026년 8월"(고정폭 볼드)보다 "8월"을 크게·가늘게,
                // "2026"을 작게·연하게 나눠서 훨씬 세련돼 보임.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat.MMMM(Localizations.localeOf(context).toString()).format(DateTime(2026, 8, 1)),
                      style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w300, color: Colors.black87),
                    ),
                    SizedBox(width: 6.w),
                    Padding(
                      padding: EdgeInsets.only(bottom: 2.h),
                      child: Text('2026', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400)),
                    ),
                  ],
                ),
                const Spacer(),
                _roundIconButton(Icons.grid_view_rounded, _openAllShifts),
                SizedBox(width: 8.w),
                _roundIconButton(Icons.today_rounded, _tapToday),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              children: List.generate(7, (i) => Expanded(
                child: Center(
                  child: Text(weekdayLabel(context, i), style: TextStyle(fontSize: 11.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade700)),
                ),
              )),
            ),
          ),
          SizedBox(height: 4.h),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              child: Column(
                children: List.generate(6, (row) => Expanded(
                  child: Row(
                    children: List.generate(7, (col) => Expanded(child: _theme2Cell(_days[row * 7 + col]))),
                  ),
                )),
              ),
            ),
          ),
          _theme2OtCard(),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _theme2Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      child: Padding(
        padding: EdgeInsets.all(2.w),
        child: Container(
          decoration: BoxDecoration(
            color: outside ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(6.r),
            border: today ? Border.all(color: Colors.indigo.shade400, width: 1.4) : null,
            boxShadow: outside ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1))],
          ),
          // ⭐ 전반적 UI 견고성 점검(2026-08-12) 중 발견 - 이 테마는 확정완료
          // 상태라 기존 튜닝값(간격/폰트)은 전혀 안 건드림. 다만 구조 자체는
          // 1/9번이 overflow 났던 것과 동일한 패턴(고정 Column + Spacer, 안전망
          // 없음)이라 순수 예방 차원으로 ClipRect만 추가함 - 지금까지 실기기로
          // 확인된 모양엔 아무 영향 없고, 혹시 모를 극단 케이스에서만 조용히
          // 클립되게 하는 보험. release 빌드는 overflow 경고 배너 자체가 안 떠서
          // (디버그 전용 기능) 이런 안전망이 없으면 문제가 더 티 안 나게 새어
          // 나올 수 있음.
          child: ClipRect(
            child: Column(
            children: [
              // ⭐ 색상만으로 근무를 구분하는 건 시인성이 안 좋다는 판단으로 채택
              // 불가 - 테마1처럼 근무명(최대 4글자)을 배경색 뱃지에 텍스트로 넣는
              // 걸로 바꿈. 원래는 4h짜리 얇은 색점이라 border radius(2.r)가 거의
              // 알약 모양으로 과하게 둥글어 보였는데, 이제 텍스트가 들어갈 만큼
              // 세로로 키워야 해서(4h→12h) 반지름도 그에 맞게 살짝 줄임(2.r→3.r).
              // ⭐ 근무 뱃지를 셀 맨 위에 딱 붙임(margin 제거) - 그만큼 아래로
              // 여백이 생겨서 숫자/광복절도 같이 위로 당겨지고, 메모 3줄이 들어갈
              // 세로 공간을 최대한 확보함. 메모는 세로로는 절대 안 잘리게(넘치면
              // 카드 밖으로 삐져나감) 하는 게 우선이라 광복절 글자를 살짝
              // 줄이고(7sp→6sp), 메모는 줄 간격(height:1.0)을 타이트하게 잡아서
              // 폰트 크기는 유지하면서 세로 폭만 줄임 - 가로 잘림(ellipsis)은 허용.
              // ⭐ 완전히 붙이니 빡빡해 보인다는 피드백으로 살짝만 여백 다시 둠
              // (테마1과 동일 이유) - 다만 이 테마는 메모 3줄이 카드 밖으로
              // 넘치면 안 되는 제약이 더 타이트해서 테마1(1.5h)보다 작게 1h만 줌.
              // ⭐ outside(다른 달) 날짜도 배지를 그대로 보여줌 - 실제 메인 달력과
              // 동일(outside 여부와 무관하게 배지는 항상 표시, 날짜 숫자만 흐림).
              Container(
                width: double.infinity,
                height: 12.h,
                margin: EdgeInsets.fromLTRB(4.w, 1.h, 4.w, 0),
                decoration: BoxDecoration(color: shift.color, borderRadius: BorderRadius.circular(3.r)),
                alignment: Alignment.center,
                child: Text(
                  shift.name,
                  style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: 1.h),
              Text('${day.day}', style: TextStyle(
                fontSize: 12.sp,
                fontWeight: today ? FontWeight.bold : FontWeight.w700,
                color: outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87),
              )),
              if (_mockHolidayNameFor(context, day) != null)
                Text(_mockHolidayNameFor(context, day)!, style: TextStyle(fontSize: 6.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold, height: 1.0), maxLines: 1, overflow: TextOverflow.ellipsis),
              // ⭐ 광복절-메모 간격 한 번 더 소폭 확대 (1.3h→1.8h) - "아주 조금만 더" 피드백.
              SizedBox(height: 1.8.h),
              // ⭐ 메모끼리 너무 붙어 보인다는 피드백(우선순위 1번, 최우선) - 줄
              // 사이에 살짝 여백을 줌. height:1.0(타이트한 줄간격)은 그대로 둬서
              // 세로 초과를 안 만들면서 "줄 사이 간격"만 명시적으로 벌림.
              ...memos.take(3).toList().asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.h),
                child: Text(e.value, style: TextStyle(fontSize: 7.5.sp, color: Colors.grey.shade700, fontWeight: FontWeight.w600, height: 1.0), maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
              const Spacer(),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _theme2OtCard() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          _otChip(context.l10n.shiftThisMonthOt, formatOvertimeMinutes(context, _mockMonthlyOtTotal), Colors.indigo),
          SizedBox(width: 8.w),
          _otChip(context.l10n.shiftWeeklyWorkHours, context.l10n.commonView, Colors.teal, onTap: () => _showWeekSummarySheet(context, _weeks)),
        ],
      ),
    );
  }

  // ⭐ Expanded는 반드시 Row의 "직속" 자식이어야 함 - GestureDetector로 바깥을 감싸면
  // Expanded와 Row 사이에 Listener가 끼어들어서 "Incorrect use of ParentDataWidget" 예외가
  // 매 프레임 발생함(스와이프 중 페이지가 새로 inflate될 때 특히 심각 - ANR까지 유발했던 버그).
  // 그래서 탭 가능 여부와 무관하게 Expanded가 항상 최상단이고, GestureDetector는 그 "안쪽"에 둠.
  Widget _otChip(String label, String value, MaterialColor color, {VoidCallback? onTap}) {
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8.r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.sp, color: color.shade400, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 12.sp, color: color.shade700, fontWeight: FontWeight.bold)),
        ],
      ),
    );
    return Expanded(
      child: onTap == null ? chip : GestureDetector(onTap: onTap, child: chip),
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30.w,
        height: 30.w,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3)]),
        child: Icon(icon, size: 16.sp, color: Colors.indigo.shade400),
      ),
    );
  }
}

// ============================================================
// ⭐ 테마 4 · 굵은 격자형 (스프레드시트 느낌)
// 두꺼운 격자선 + 근무명 전체 텍스트 뱃지. 정보량 최대, 여백 최소.
// ============================================================
extension _Theme4 on _CalendarThemeLabScreenState {
  Widget _theme4BoldGrid() {
    return Column(
      children: [
        Container(
          color: const Color(0xFF263238),
          padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
          child: Row(
            children: [
              Text('2026-08', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace')),
              const Spacer(),
              _gridHeaderBtn(context.l10n.shiftFullSchedule, _openAllShifts),
              SizedBox(width: 8.w),
              _gridHeaderBtn('TODAY', _tapToday),
            ],
          ),
        ),
        Container(
          color: const Color(0xFF37474F),
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(child: Text(_weekdayEn3[i], style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.redAccent.shade100 : Colors.white70))),
            )),
          ),
        ),
        Expanded(
          child: Column(
            children: List.generate(6, (row) => Expanded(
              child: Row(children: List.generate(7, (col) => Expanded(child: _theme4Cell(_days[row * 7 + col])))),
            )),
          ),
        ),
        Container(
          color: const Color(0xFFECEFF1),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          child: Row(
            children: [
              Text('${context.l10n.shiftThisMonthOt} ${formatOvertimeMinutes(context, _mockMonthlyOtTotal)}', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: const Color(0xFF263238))),
              SizedBox(width: 14.w),
              GestureDetector(
                onTap: () => _showWeekSummarySheet(context, _weeks),
                child: Text('${context.l10n.shiftWeeklyWorkHours} ▸', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00695C))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _theme4Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB0BEC5), width: 1),
          color: outside ? const Color(0xFFFAFAFA) : (today ? const Color(0xFFFFF9C4) : Colors.white),
        ),
        padding: EdgeInsets.all(2.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⭐ 숫자 바로 옆에 붙이니 붐벼 보인다는 피드백 - 숫자는 왼쪽 고정,
            // 공휴일명은 Expanded로 남은 폭을 다 갖고 가운데 정렬(중앙 배치).
            // 실기기 테스트 결과: 6글자(실제 최장급 공휴일명 "부처님오신날")까지는
            // 완전히 다 보이고, 그보다 훨씬 긴 경우(10글자 테스트)만 "..."으로
            // 잘림 - 실사용 범위에서는 안전함. Expanded+ellipsis 구조라 아무리
            // 길어져도 숫자 쪽을 침범할 수 없음.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('${day.day}', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: outside ? Colors.grey.shade400 : (red ? Colors.red.shade600 : const Color(0xFF263238)))),
                if (_mockHolidayNameFor(context, day) != null)
                  Expanded(
                    child: Text(_mockHolidayNameFor(context, day)!, style: TextStyle(fontSize: 5.5.sp, color: Colors.red.shade600, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  ),
              ],
            ),
            // ⭐ 1·2번 근무명 뱃지(7.5sp)에 비해 유독 작아 보인다는 피드백으로
            // 6.5sp→7.5sp로 맞춤.
            // ⭐ outside(다른 달) 날짜도 배지를 그대로 보여줌 - 메인 달력과 동일.
            Container(
              margin: EdgeInsets.symmetric(vertical: 1.h),
              padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
              width: double.infinity,
              decoration: BoxDecoration(color: shift.color),
              child: Text(shift.name, style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color)), maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.center),
            ),
            // ⭐ 메모 3개일 때 셀 아래쪽에 빈 여백이 많이 남는다는 피드백 - 메모끼리
            // 간격은 지금 그대로 두고(요청대로), 폰트만 더 키워서 그 여백을 씀
            // (7sp→8.5sp).
            SizedBox(height: 1.h),
            ...memos.take(3).map((m) => Text('· $m', style: TextStyle(fontSize: 8.5.sp, fontWeight: FontWeight.w600, color: const Color(0xFF37474F)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
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
}

// ============================================================
// ⭐ 테마 5 · 이니셜 뱃지형 (전면 재설계)
// 근무는 원형 뱃지(색상+1글자), 숫자와 나란히 배치. 범례 삭제 - 재검토 배경:
// - 맨 위 범례(_legendRow)는 없애고 그 자리를 그리드에 돌려줌 (요청대로)
// - 요일 헤더(10.w)와 그리드(8.w)의 좌우 패딩이 서로 달라서 열이 안 맞았던
//   버그 수정 - 둘 다 8.w로 통일
// - 기존엔 Stack으로 숫자=좌상단/뱃지=우상단에 "따로" 떠 있어서 서로 안
//   묶여 보이고, 메모도 Positioned(bottom)이라 셀이 낮으면 숫자와 겹쳤음.
//   Stack을 버리고 Column으로 자연스럽게 위→아래 흐르게 바꿔서 겹침 자체가
//   구조적으로 불가능하게 함. 숫자+뱃지를 "같은 줄"에 나란히 둬서 한 쌍으로
//   묶여 보이게 하고(대각선으로 떨어져 있던 어색함 해소), 오늘은 그 줄 전체를
//   감싸는 캡슐 배경으로 강조함.
// ============================================================
extension _Theme5 on _CalendarThemeLabScreenState {
  Widget _theme5InitialBadge() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: Row(
            children: [
              // ⭐ 9번과 같은 이유로 color 없이 두면 흰 배경에서 거의 안 보였음 - 명시.
              Text('2026.08', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.black87)),
              const Spacer(),
              _pillButton(context.l10n.shiftFullSchedule, Icons.table_chart_outlined, _openAllShifts),
              SizedBox(width: 6.w),
              _pillButton(context.l10n.commonToday, Icons.adjust, _tapToday),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(child: Text(weekdayLabel(context, i), style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500))),
            )),
          ),
        ),
        SizedBox(height: 2.h),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(children: List.generate(7, (col) => Expanded(child: _theme5Cell(_days[row * 7 + col])))),
              )),
            ),
          ),
        ),
        _theme1OtBar(),
        SizedBox(height: 6.h),
      ],
    );
  }

  Widget _theme5Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);
    final numColor = outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: EdgeInsets.all(1.5.w),
        padding: EdgeInsets.symmetric(vertical: 1.h),
        // ⭐ 오늘 표시 방식 변경 - 뱃지+숫자를 감싸는 캡슐 배경(색칠) 대신, 2번
        // 테마와 동일하게 "셀 테두리에 색상 포인트"만 주는 방식으로 바꿈. 평소엔
        // (테두리가 아예 없으면 셀 경계가 안 보인다는 예전 피드백대로) 연한 회색
        // 테두리, 오늘만 2번과 동일한 인디고 색+두께로 교체.
        decoration: BoxDecoration(
          border: today
              ? Border.all(color: Colors.indigo.shade400, width: 1.4)
              : Border.all(color: Colors.grey.shade200, width: 0.6),
          borderRadius: BorderRadius.circular(4.r),
        ),
        child: Column(
          children: [
            // ⭐ v2 재배치 - 나란히 놓은 v1이 "그냥 예쁘진 않다"는 피드백이라
            // 테마1이 이미 검증받은 "근무(뱃지) 먼저, 숫자 나중" 위계를 그대로
            // 가져와 세로로 쌓음: 뱃지가 작은 아바타처럼 위에 오고, 숫자가 그
            // 아래 중앙에 옴 - 나란히 두는 것보다 한 쌍으로 훨씬 정돈되어 보임.
            // ⭐ 광복절+메모3개 조합에서 맨 아래 메모가 방금 추가한 테두리를
            // 넘어가던 문제 - 위쪽(뱃지·숫자·광복절 사이) 간격들을 줄여서
            // 메모가 들어갈 세로 공간을 확보함 (광복절을 숫자에 더 가깝게).
            Container(
              padding: EdgeInsets.symmetric(vertical: 1.h),
              child: Column(
                children: [
                  // ⭐ outside(다른 달) 날짜도 이니셜 뱃지를 그대로 보여줌 - 메인 달력과 동일.
                  Container(
                    width: 14.w,
                    height: 14.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: shift.color, shape: BoxShape.circle),
                    child: Text(shift.name[0], style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color))),
                  ),
                  SizedBox(height: 1.h),
                  Text('${day.day}', style: TextStyle(fontSize: 11.5.sp, fontWeight: today ? FontWeight.bold : FontWeight.w600, color: numColor)),
                ],
              ),
            ),
            if (_mockHolidayNameFor(context, day) != null)
              Text(_mockHolidayNameFor(context, day)!, style: TextStyle(fontSize: 6.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold, height: 1.0), maxLines: 1, overflow: TextOverflow.ellipsis),
            // ⭐ 광복절-메모 간격(1.2h)은 실기기 확인 완료된 값이라 그대로 유지.
            // 메모끼리 간격만 다시 넓힘(0.5h→2h) - 셀 아래쪽에 여백이 꽤 남는다는
            // 피드백이라, 그 여유를 메모 사이 간격으로 옮겨서 3개가 붙어 보이던
            // 문제를 완화함.
            SizedBox(height: 1.2.h),
            ...memos.take(3).toList().asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(top: e.key == 0 ? 0 : 2.h),
              child: Text(e.value, style: TextStyle(fontSize: 7.sp, color: Colors.grey.shade600, fontWeight: FontWeight.w600, height: 1.0), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            )),
          ],
        ),
      ),
    );
  }

  Widget _pillButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(20.r)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11.sp, color: Colors.indigo.shade400),
          SizedBox(width: 3.w),
          Text(label, style: TextStyle(fontSize: 10.sp, color: Colors.indigo.shade600, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ============================================================
// ⭐ 테마 8 · 언더라인 미니멀형
// 배경·테두리 없이 숫자 아래 밑줄만 근무색. 메모가 가장 잘 보이는 극단형.
// ============================================================
extension _Theme8 on _CalendarThemeLabScreenState {
  Widget _theme8Underline() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 4.h),
          child: Row(
            children: [
              Text('AUGUST', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Colors.black87)),
              SizedBox(width: 6.w),
              Text('2026', style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade400, letterSpacing: 1)),
              const Spacer(),
              GestureDetector(onTap: _tapToday, child: Text('TODAY', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 0.5))),
              SizedBox(width: 12.w),
              GestureDetector(onTap: _openAllShifts, child: Text(context.l10n.shiftFullSchedule, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: Colors.black54))),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(child: Text(_weekdayEn1[i], style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade400))),
            )),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            // ⭐ 근무를 색상만으로 구분하는 테마라 어딘가에 "무슨 색=무슨 근무"
            // 범례가 필연적으로 있어야 함 - 달력탭이 6번째 줄 화~토(항상 다음
            // 달 스필오버라 실질적으로 빈 칸인 영역, _isSixthRowEmptyCell와
            // 동일 조건)를 OT 카드로 재활용하는 것과 똑같은 자리에 범례를 둠.
            // 일~월(2칸)은 실제 날짜(달력 구조상 6번째 줄에서 유일하게 항상
            // 이번 달의 진짜 날짜일 수 있는 칸)라 그대로 두고, 화~토(5칸)만
            // 하나로 합쳐서 범례에 씀 - Positioned로 겹쳐 그리는 대신 그 5칸
            // 자체를 통째로 범례 위젯 하나로 바꿔치기하는 방식이라, 이 테마처럼
            // 고정 rowHeight가 없는(Expanded로 화면 남는 공간을 나눠 쓰는)
            // 구조에서도 픽셀 계산 없이 항상 정확히 한 줄 높이만큼만 씀.
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(children: row == 5
                    ? [
                        Expanded(child: _theme8Cell(_days[35])),
                        Expanded(child: _theme8Cell(_days[36])),
                        Expanded(flex: 5, child: _theme8Legend()),
                      ]
                    : List.generate(7, (col) => Expanded(child: _theme8Cell(_days[row * 7 + col])))),
              )),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 10.h),
          child: Row(
            children: [
              Text('${context.l10n.shiftThisMonthOt} ${formatOvertimeMinutes(context, _mockMonthlyOtTotal)}', style: TextStyle(fontSize: 11.sp, color: Colors.black87)),
              const Spacer(),
              GestureDetector(onTap: () => _showWeekSummarySheet(context, _weeks), child: Text(context.l10n.shiftWeeklyWorkHours, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: Colors.black87))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _theme8Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      // ⭐ 견고성 점검 중 발견 - 이 테마는 애초에 메모 사이 간격조차 없는(꽉 붙는)
      // 가장 타이트한 구조라 광복절+메모3개 조합에서 overflow 위험이 제일 큼.
      // 보류 상태라 값 튜닝은 안 하고, ClipRect만 예방으로 걸어둠.
      child: ClipRect(
        child: Column(
        children: [
          SizedBox(height: 3.h),
          Text('${day.day}', style: TextStyle(
            fontSize: 12.sp,
            fontWeight: today ? FontWeight.bold : FontWeight.w400,
            color: outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87),
            decoration: today ? TextDecoration.underline : null,
            decorationThickness: 2,
          )),
          // ⭐ "너무 작고 얇아서 구분이 안 된다"는 피드백으로 밑줄(14w×2h, 각짐)
          // 대신 살짝 더 키운 둥근 사각형(22w×6h)으로 바꿨는데, "조금 더 얇게"
          // 피드백으로 세로만 70%(6h→4.2h)로 줄임 - 가로(22w)는 그대로 유지.
          // ⭐ outside(다른 달) 날짜도 색상 도형을 그대로 보여줌 - 8번은
          // 범례로 근무를 구분하는 테마라 이름 텍스트 없이 색상 도형만 유지.
          Container(
            margin: EdgeInsets.symmetric(vertical: 2.h),
            width: 22.w,
            height: 4.2.h,
            decoration: BoxDecoration(color: shift.color, borderRadius: BorderRadius.circular(2.r)),
          ),
          if (_mockHolidayNameFor(context, day) != null)
            Text(_mockHolidayNameFor(context, day)!, style: TextStyle(fontSize: 6.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          ...memos.take(3).map((m) => Text(m, style: TextStyle(fontSize: 7.sp, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        ),
      ),
    );
  }

  // ⭐ 근무를 색상만으로 구분하는 테마라 어딘가에 범례가 필연적으로 필요함 -
  // 근무 개수가 3개든 12개든(온보딩 상한: 기본5+커스텀7=최대12, 이름 4글자
  // 제한 - onboarding_screen.dart 확인) 항상 4열 고정 그리드로 깔아서 정렬이
  // 절대 안 어긋나게 함. 줄 수만 ceil(개수/4)로 자연스럽게 늘어남(1~3줄) -
  // 아이템 폭 안에서 [스와치][간격][Expanded 텍스트+ellipsis] 구조라 이름이
  // 길어져도 그 항목 안에서만 잘리고 옆 칸을 절대 침범 못함.
  Widget _theme8Legend() {
    const cols = 4;
    final legendShifts = _legendShifts(context);
    final rows = (legendShifts.length / cols).ceil();
    // ⭐ "뜬금없어 보인다"는 피드백으로 테두리를 둘러서 하나의 독립된 정보
    // 영역임을 명확히 함 - 이 테마는 셀 자체엔 테두리가 없는(배경·테두리 없이
    // 밑줄만 쓰는) 미니멀 컨셉이라, 범례는 옅은 회색 테두리 정도로만 최소한의
    // 구분을 줌(달력 그리드처럼 진하게 두르지 않음).
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 0.7),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: ClipRect(
        child: Column(
          children: List.generate(rows, (r) => Expanded(
            child: Row(
              children: List.generate(cols, (c) {
                final i = r * cols + c;
                if (i >= legendShifts.length) return const Expanded(child: SizedBox());
                final s = legendShifts[i];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
                    child: Row(
                      children: [
                        Container(
                          width: 16.w,
                          height: 5.h,
                          decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2.r)),
                        ),
                        SizedBox(width: 3.w),
                        Expanded(
                          child: Text(s.name, style: TextStyle(fontSize: 7.sp, color: Colors.black87, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
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
}

// ============================================================
// ⭐ 테마 9 · 이벤트 칩형 (구글 캘린더 이벤트칩 참고)
// 근무명을 가로 칩으로. 메모도 같은 톤의 작은 칩으로 쌓음.
// ============================================================
extension _Theme9 on _CalendarThemeLabScreenState {
  Widget _theme9EventChip() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
          child: Row(
            children: [
              // ⭐ color 없이 두면 앰비언트 텍스트 스타일에 묻혀서 흰 배경 위에서
              // 거의 안 보이는 문제가 있었음 - 다른 테마 헤더들과 같은 black87로 명시.
              Text('2026. 8', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.black87)),
              const Spacer(),
              _pillButton(context.l10n.shiftFullSchedule, Icons.table_chart_outlined, _openAllShifts),
              SizedBox(width: 6.w),
              _pillButton(context.l10n.commonToday, Icons.adjust, _tapToday),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(child: Text(_weekdayEn3[i], style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500))),
            )),
          ),
        ),
        Container(margin: EdgeInsets.only(top: 4.h), height: 1, color: Colors.grey.shade200),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(children: List.generate(7, (col) => Expanded(child: _theme9Cell(_days[row * 7 + col])))),
              )),
            ),
          ),
        ),
        _theme1OtBar(),
        SizedBox(height: 6.h),
      ],
    );
  }

  Widget _theme9Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      // ⭐ 예전엔 셀마다 top border를 줘서 행 구분선처럼 보이게 했는데, 세로줄이
      // 없어서(그리드가 아님) 애초에 격자를 흉내 낼 필요가 없었고, 칩이 5개(근무+
      // 공휴일+메모3개)까지 쌓이는 날엔 마지막 메모가 바로 아래 줄을 침범해 보여서
      // 아예 제거함 - 줄이 없으면 셀 높이를 살짝 넘어가도 훨씬 덜 거슬림.
      // ⭐ 그런데 이건 순전히 시각적(paint)인 조치였을 뿐 - Column의 실제 세로
      // 크기는 그대로였어서, 칩 5개(숫자원+근무+공휴일+메모3)가 쌓이는 8/15 셀은
      // border를 지운 뒤에도 여전히 RenderFlex bottom-overflow 에러가 떴음(구분선이
      // 없어서 "안 넘쳐 보였을" 뿐, 프레임워크는 여전히 넘친 걸 감지해서 에러 배너를
      // 띄움). 그래서 border 제거와는 별개로 칩 크기/여백 자체를 줄여야 했음.
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 1.5.w, vertical: 1.2.h),
        // ⭐ 두 번째 시도까지도 계속 overflow가 나서(칩 5개 조합의 정확한 세로
        // 크기를 실기기 없이 픽셀 단위로 맞히는 건 사실상 불가능) - 이번엔 값
        // 다듬기와 별개로 ClipRect를 하드 백스톱으로 추가함. 셀 안에 실제로
        // 안 들어가는 경우엔 (드물게, 광복절+메모3개처럼 극단적일 때만) 맨 아래
        // 내용이 조용히 잘려나갈 뿐 - Flutter의 노란/검정 경고 줄무늬 배너 자체가
        // 다시는 안 뜸. 이후 목업 데이터가 바뀌거나 폰트가 달라져도 안전함.
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 15.w,
                height: 15.w,
                alignment: Alignment.center,
                margin: EdgeInsets.only(bottom: 1.2.h),
                decoration: today ? BoxDecoration(color: red ? Colors.red.shade400 : Colors.indigo.shade400, shape: BoxShape.circle) : null,
                child: Text('${day.day}', style: TextStyle(
                  fontSize: 9.5.sp,
                  fontWeight: today ? FontWeight.bold : FontWeight.w500,
                  color: today ? Colors.white : (outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87)),
                )),
              ),
              // ⭐ overflow는 ClipRect로 이미 안전망이 있으니, 이번엔 반대로 "너무
              // 작아 보인다"는 피드백대로 칩(근무명/공휴일/메모3)을 다시 키움 -
              // 날짜 숫자~근무명 시작 사이 여백(위 margin 1.2h)은 그대로 두고,
              // 근무명부터 셀 바닥까지 영역만 최대한 채우게 _chip() 자체의
              // 패딩/폰트와 칩 사이 간격을 키움. 그래도 안 들어가면 ClipRect가
              // 조용히 잘라주므로 에러 배너 걱정 없이 크게 잡아도 됨.
              // ⭐ outside(다른 달) 날짜도 근무명 칩을 그대로 보여줌 - 메인 달력과 동일.
              _chip(shift.name, shift.color, _autoTextColor(shift.color)),
              if (_mockHolidayNameFor(context, day) != null)
                Padding(
                  padding: EdgeInsets.only(top: 0.8.h),
                  child: _chip(_mockHolidayNameFor(context, day)!, Colors.red.shade50, Colors.red.shade400),
                ),
              ...memos.take(3).map((m) => Padding(
                padding: EdgeInsets.only(top: 0.8.h),
                child: _chip(m, Colors.grey.shade200, Colors.black87),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 0.6.h),
      padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.1.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2.5.r)),
      // ⭐ height 명시 - 기본 line-height는 폰트마다 달라 얼마나 줄여야 할지 예측이
      // 안 됐음. 1.1로 고정해서 칩 5개가 쌓여도 계산 가능한 만큼만 차지하게 함.
      // ⭐ "너무 작다"는 피드백으로 5.8sp→7.5sp, 패딩도 같이 키워서 셀 바닥까지
      // 최대한 채움 - ClipRect가 안전망이라 커져서 못 들어가도 조용히 잘릴 뿐임.
      child: Text(text, style: TextStyle(fontSize: 7.5.sp, color: fg, fontWeight: FontWeight.w600, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

// ============================================================
// ⭐ 테마 10 · 매거진 에디토리얼형
// 요일 헤더에 색 바, 근무는 모서리 삼각 배지. 세리프 숫자로 잡지 느낌.
// ============================================================
extension _Theme10 on _CalendarThemeLabScreenState {
  Widget _theme10Editorial() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 6.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('August', style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700, fontFamily: 'serif', color: Colors.black87)),
              SizedBox(width: 8.w),
              Padding(padding: EdgeInsets.only(bottom: 3.h), child: Text('2026', style: TextStyle(fontSize: 12.sp, fontFamily: 'serif', color: Colors.grey.shade500))),
              const Spacer(),
              GestureDetector(onTap: _openAllShifts, child: Text(context.l10n.shiftFullSchedule, style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, decoration: TextDecoration.underline))),
              SizedBox(width: 10.w),
              GestureDetector(onTap: _tapToday, child: Text(context.l10n.commonToday, style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, decoration: TextDecoration.underline))),
            ],
          ),
        ),
        Row(
          children: List.generate(7, (i) => Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 3.h),
              color: i == 0 ? Colors.red.shade50 : (i == 6 ? Colors.blue.shade50 : Colors.grey.shade100),
              alignment: Alignment.center,
              child: Text(_weekdayEn3[i], style: TextStyle(fontSize: 9.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade600)),
            ),
          )),
        ),
        // ⭐ 8번과 동일한 이유/기법 - 6번째 줄 화~토(5칸, 항상 다음 달 스필오버라
        // 실질적으로 비어있던 자리)를 통째로 범례로 바꿔치기함. Positioned 겹쳐
        // 그리기 대신 그리드 셀 자체를 교체하는 방식이라 고정 rowHeight가 없는
        // 이 구조에서도 픽셀 계산 없이 항상 정확히 한 줄만큼만 씀.
        Expanded(
          child: Column(
            children: List.generate(6, (row) => Expanded(
              child: Row(children: row == 5
                  ? [
                      Expanded(child: _theme10Cell(_days[35])),
                      Expanded(child: _theme10Cell(_days[36])),
                      Expanded(flex: 5, child: _theme10Legend()),
                    ]
                  : List.generate(7, (col) => Expanded(child: _theme10Cell(_days[row * 7 + col])))),
            )),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(18.w, 6.h, 18.w, 10.h),
          child: Row(
            children: [
              Text(context.l10n.shiftThisMonthOt, style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade500, fontFamily: 'serif')),
              SizedBox(width: 4.w),
              Text(formatOvertimeMinutes(context, _mockMonthlyOtTotal), style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.brown.shade600, fontFamily: 'serif')),
              const Spacer(),
              GestureDetector(
                onTap: () => _showWeekSummarySheet(context, _weeks),
                child: Text('${context.l10n.shiftWeeklyWorkHours} →', style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, fontFamily: 'serif')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _theme10Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(context, day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200, width: 0.5)),
        child: Stack(
          children: [
            // ⭐ outside(다른 달) 날짜도 삼각 배지를 그대로 보여줌 - 10번도
            // 8번과 같은 범례 기반 테마라 이름 텍스트 없이 색상 도형만 유지.
            Positioned(
              top: 0,
              left: 0,
              child: ClipPath(
                clipper: _CornerTriangleClipper(),
                child: Container(width: 16.w, height: 16.w, color: shift.color),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 3.h, right: 2.w),
              child: Align(
                alignment: Alignment.topRight,
                child: Text('${day.day}', style: TextStyle(
                  fontSize: 12.sp,
                  fontFamily: 'serif',
                  fontWeight: today ? FontWeight.bold : FontWeight.w500,
                  color: outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87),
                  decoration: today ? TextDecoration.underline : null,
                )),
              ),
            ),
            // ⭐ serif는 큰 글자(날짜 숫자, 헤더)에선 잡지 느낌을 살려주지만
            // 공휴일/메모처럼 작은 글자에서는 획이 가늘어져 오히려 읽기
            // 어려웠음 - 여기만 기본 서체로 되돌림.
            // ⭐ 공휴일명을 메모 묶음에서 분리 - 날짜 숫자 바로 아래(우측 정렬,
            // 같은 자리)에 따로 배치하고 글씨도 눈에 띄게 키움(5.5sp→7.5sp).
            if (_mockHolidayNameFor(context, day) != null)
              Positioned(
                top: 18.h,
                right: 2.w,
                child: Text(_mockHolidayNameFor(context, day)!, style: TextStyle(fontSize: 7.5.sp, color: Colors.red.shade400, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            // ⭐ 메모는 공휴일과 분리된 채로 계속 하단 고정 - 폰트도 한 번 더
            // 키움(6.8sp→7.5sp), 줄 간격도 넓힘(0.8h→1.2h).
            // ⚠️ 이 영역은 Positioned(bottom-anchored)라 Column처럼 넘치면
            // 에러가 나는 구조가 아니라 그냥 위로 계속 자람 - 너무 키우면 날짜
            // 숫자와 겹칠 수 있어서(점검 결과 기록됨) 적당히만 키움.
            Positioned(
              left: 2.w,
              right: 2.w,
              bottom: 2.h,
              child: Column(
                children: [
                  ...memos.take(3).toList().asMap().entries.map((e) => Padding(
                    padding: EdgeInsets.only(top: e.key == 0 ? 0 : 1.2.h),
                    child: Text(e.value, style: TextStyle(fontSize: 7.5.sp, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ 8번과 같은 이유(색상만으로는 근무 구분 불가)의 범례 - "삼각 배지를 셀에
  // 보이는 그 크기 그대로(16w×16w, _CornerTriangleClipper 동일)에 근무명을
  // 붙여서" 요청대로 구현. 마찬가지로 4열 고정 그리드라 3개든 12개든 정렬이
  // 항상 맞고, 줄 수(ceil(개수/4))만 자연스럽게 늘어남.
  Widget _theme10Legend() {
    const cols = 4;
    final legendShifts = _legendShifts(context);
    final rows = (legendShifts.length / cols).ceil();
    // ⭐ "뜬금없어 보인다"는 피드백으로 테두리로 감쌈 - 이 테마는 셀마다 이미
    // 옅은 회색 테두리(grey.shade200)가 있어서 그거랑 톤을 맞춤.
    // ⭐ serif는 큰 제목("August"/날짜 숫자)엔 잡지 느낌을 살려주지만 이렇게
    // 작은 크기(7sp)에서는 획이 가늘어져 읽기 어려움 - 메모/공휴일과 같은
    // 이유로 여기도 serif를 뺌.
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200, width: 0.7)),
      child: ClipRect(
        child: Column(
          children: List.generate(rows, (r) => Expanded(
            child: Row(
              children: List.generate(cols, (c) {
                final i = r * cols + c;
                if (i >= legendShifts.length) return const Expanded(child: SizedBox());
                final s = legendShifts[i];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
                    child: Row(
                      children: [
                        ClipPath(
                          clipper: _CornerTriangleClipper(),
                          child: Container(width: 16.w, height: 16.w, color: s.color),
                        ),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(s.name, style: TextStyle(fontSize: 7.sp, color: Colors.black87, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
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
}

class _CornerTriangleClipper extends CustomClipper<Path> {
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

// ⭐ 여러 테마가 공유하는 "주별 근무시간" 간단 리스트 시트
void _showWeekSummarySheet(BuildContext context, List<_WeekSummary> weeks) {
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
            Text(context.l10n.shiftWeeklyWorkHours, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 10.h),
            ...weeks.map((w) => Padding(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Row(
                children: [
                  Text('${w.start.month}/${w.start.day} ~ ${w.end.month}/${w.end.day}', style: TextStyle(fontSize: 13.sp)),
                  const Spacer(),
                  Text(formatOvertimeMinutes(context, w.totalMinutes), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ],
              ),
            )),
          ],
        ),
      );
    },
  );
}

// ============================================================
// ⭐ 메인 · 화이트 / 메인 · 다크
// 실제 프로덕션 calendar_tab.dart를 table_calendar로 그대로 재현함(구조는
// "바꿀 필요 없음" 요청대로 그대로 - _buildDateCell의 근무 배지→숫자→공휴일/
// 메모 순서, today 강조, 6번째 줄 화~토를 OT/주별근무시간 카드로 재활용하는
// 기법까지 전부 동일). 유일한 차이는 팔레트: 근무명 색상 변경 기능이 삭제되고
// "테마 선택"으로 대체되면서, 이 두 테마 자체가 앞으로 유일한 확정 팔레트가
// 됨(_mainLightPalette/_mainDarkPalette, 위쪽 정의 참고).
//
// firstDay/lastDay를 8월로 고정해서(다른 테마들처럼 "2026년 8월 고정" 원칙
// 유지) table_calendar가 다른 달로 스와이프해서 넘어가는 걸 애초에 막음 -
// 그 달은 이 목업 데이터(_mockMemos 등)에 대응하는 날짜가 없어서 넘어가봐야
// 의미가 없기 때문. Theme(data: AppTheme.lightTheme/darkTheme, ...)로 감싸서
// 기기의 실제 시스템 다크모드 설정과 무관하게 이 페이지만 항상 그 테마로
// 고정되게 함 - 두 미리보기를 나란히 스와이프해서 비교하려면 시스템 설정을
// 안 따라가야 함.
extension _ThemeMain on _CalendarThemeLabScreenState {
  Widget _themeMainWhite() => _buildMainTheme(isDark: false);
  Widget _themeMainDark() => _buildMainTheme(isDark: true);

  Widget _buildMainTheme({required bool isDark}) {
    final themeData = isDark ? AppTheme.darkTheme : AppTheme.lightTheme;
    final palette = isDark ? _legendShiftsDark(context) : _legendShifts(context);
    final colorScheme = themeData.colorScheme;

    return Theme(
      data: themeData,
      child: Container(
        color: colorScheme.surface,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
              child: Row(
                children: [
                  Text(
                    DateFormat.yMMMM(Localizations.localeOf(context).toString()).format(DateTime(2026, 8, 1)),
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  const Spacer(),
                  // ⭐ "원래 버튼 이미지가 있었는데 텍스트만 남았다"는 피드백 -
                  // 진짜 달력탭(_buildCalendarHeader 부분)의 버튼 스타일을
                  // 그대로 재현함: primaryContainer 배경 + 옅은 테두리의 알약형.
                  _mainHeaderButton(context.l10n.shiftFullSchedule, colorScheme, _openAllShifts),
                  SizedBox(width: 8.w),
                  _mainHeaderButton(context.l10n.commonToday, colorScheme, _tapToday),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: TableCalendar(
                      // ⭐ 8월 안에서만 움직이게 고정(다른 테마들과 동일한 "2026년 8월
                      // 고정" 원칙) - firstDay==lastDay 같은 달이라 스와이프해도
                      // 페이지가 하나뿐이라 자연스럽게 다른 달로 못 넘어감.
                      firstDay: DateTime(2026, 8, 1),
                      lastDay: DateTime(2026, 8, 31),
                      focusedDay: DateTime(2026, 8, 15),
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
                          color: isDark ? colorScheme.onSurface.withOpacity(0.4) : colorScheme.onSurface.withOpacity(0.15),
                          width: 1.0,
                        ),
                      ),
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, focusedDay) => _isMainSixthRowReclaimed(day) ? Container() : _mainCell(day, false, false, palette, colorScheme, isDark),
                        outsideBuilder: (context, day, focusedDay) => _isMainSixthRowReclaimed(day) ? Container() : _mainCell(day, false, true, palette, colorScheme, isDark),
                        todayBuilder: (context, day, focusedDay) => _isMainSixthRowReclaimed(day) ? Container() : _mainCell(day, true, false, palette, colorScheme, isDark),
                      ),
                      onDaySelected: (selectedDay, focusedDay) {
                        if (_isMainSixthRowReclaimed(selectedDay)) return;
                        _tapDay(selectedDay);
                      },
                    ),
                  ),
                  // ⭐ 6번째 줄 화~토(항상 다음 달 스필오버라 실질적으로 빈 칸) 재활용 -
                  // 진짜 달력탭의 _buildMonthlyOvertimeCard()와 동일한 기법/구성
                  // (불투명 카드 + 이번 달 OT / 주별 근무시간 반반).
                  // ⭐ "테두리가 기존 그리드선이랑 겹쳐서 두 줄 같다"는 피드백으로
                  // 카드 자체의 테두리(그리고 실수로 들어간 1px 왼쪽 margin)를
                  // 없앰 - 아래 별도의 "6번째 줄 맨 밑 선"이 전체 폭에 한 줄만
                  // 그어주므로 카드는 배경색만 깔면 충분함.
                  Positioned(
                    top: 28.h + 83.h * 5,
                    left: 6.w,
                    right: 6.w,
                    height: 83.h,
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: IgnorePointer(child: SizedBox())),
                        Expanded(
                          flex: 5,
                          child: Container(
                            color: colorScheme.surface,
                            child: Column(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(context.l10n.themeLabOtDetailNotice)),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                                      child: Row(
                                        children: [
                                          Text(context.l10n.shiftThisMonthOt, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
                                          SizedBox(width: 6.w),
                                          Text(formatOvertimeMinutes(context, _mockMonthlyOtTotal), style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Container(height: 1, color: isDark ? colorScheme.onSurface.withOpacity(0.3) : colorScheme.onSurface.withOpacity(0.1)),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _showWeekSummarySheet(context, _weeks),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                                      child: Row(
                                        children: [
                                          Text(context.l10n.shiftWeeklyWorkHours, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
                                          const Spacer(),
                                          Icon(Icons.chevron_right, size: 16.sp, color: colorScheme.onSurfaceVariant),
                                        ],
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
                  ),
                  // ⭐ "6번째 줄 맨 밑 가로선이 없어졌다" 피드백 - table_calendar
                  // 자체 테두리가 이 화면 높이에서 정확히 어디에 그려지는지는
                  // 기기마다 미세하게 다를 수 있어서, 행 경계를 직접 계산해서
                  // 명시적으로 한 줄 그어줌(전체 폭 - 화~토 칸뿐 아니라 일/월
                  // 칸까지 포함) - table_calendar 렌더링에 의존하지 않는 확실한
                  // 방법.
                  Positioned(
                    top: 28.h + 83.h * 6 - 1,
                    left: 6.w,
                    right: 6.w,
                    height: 1,
                    child: Container(color: isDark ? colorScheme.onSurface.withOpacity(0.4) : colorScheme.onSurface.withOpacity(0.15)),
                  ),
                ],
              ),
            ),
            SizedBox(height: 6.h),
          ],
        ),
      ),
    );
  }

  // ⭐ calendar_tab.dart의 전체근무표/today 버튼과 픽셀 단위로 동일한 스타일
  // (primaryContainer 배경 알약 + primary 30% 테두리, 11sp w600 텍스트).
  Widget _mainHeaderButton(String label, ColorScheme colorScheme, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: colorScheme.primary.withOpacity(0.3), width: 0.8),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.sp, color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ⭐ 달력탭의 _isSixthRowEmptyCell과 동일한 조건(6번째 줄 화~토) - 다만
  // table_calendar 콜백엔 "몇 번째 줄인지"가 안 넘어와서, 날짜 자체로 판별함:
  // 8월 그리드의 6번째 줄은 8/30(일)~9/5(토)이므로 화(9/1)~토(9/5)가 대상.
  bool _isMainSixthRowReclaimed(DateTime day) {
    return day.year == 2026 && day.month == 9 && day.day >= 1 && day.day <= 5;
  }

  // ⭐ calendar_tab.dart의 _buildDateCell을 최대한 그대로 재현 - 근무 배지(맨
  // 위) → 숫자(오늘=강조 배경, 공휴일 이름 숫자 위에 겹침) → 메모(최대 3,
  // 하단 고정) 순서. friend_calendar_view.dart에서 이미 한 번 이 구조를
  // Provider 없는 정적 데이터용으로 옮겨본 적이 있어서 그 패턴을 그대로 씀.
  Widget _mainCell(DateTime day, bool isToday, bool isOutside, List<_MockShift> palette, ColorScheme colorScheme, bool isDark) {
    final shift = _mainShiftFor(day, palette);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final isSunday = day.weekday == DateTime.sunday;
    final holiday = _mockHolidayNameFor(context, day);
    final red = isSunday || holiday != null;

    final Color dateColor = red
        ? (isOutside ? Colors.red.withOpacity(0.3) : (isDark ? Colors.red.shade300 : Colors.red))
        : (isOutside ? colorScheme.onSurfaceVariant.withOpacity(0.5) : colorScheme.onSurface);

    return Container(
      padding: EdgeInsets.only(left: 2.w, right: 2.w, top: 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⭐ 실제 calendar_tab.dart의 _buildDateCell은 outside 여부와 무관하게
          // 근무가 있으면 배지를 항상 보여줌(hasShift만 체크, isOutside는 날짜
          // 숫자 색상에만 영향) - "이전/다음 달 며칠에도 근무명이 나왔었다"는
          // 피드백과 정확히 일치하는 그 동작을 그대로 재현함.
          Container(
            height: 18.h,
            decoration: BoxDecoration(color: shift.color, borderRadius: BorderRadius.circular(3.r)),
            alignment: Alignment.center,
            child: Text(
              shift.name, style: TextStyle(fontSize: 9.sp, color: _autoTextColor(shift.color), fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (holiday != null)
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      height: 11.h,
                      padding: EdgeInsets.symmetric(horizontal: 1.w),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(holiday, style: TextStyle(
                          fontSize: 9.sp, fontWeight: FontWeight.w600,
                          color: isOutside ? Colors.red.withOpacity(0.3) : (isDark ? Colors.red.shade300 : Colors.red),
                        )),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: memos.length >= 3 ? 20.h : 0),
                    child: Container(
                      padding: isToday ? EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h) : EdgeInsets.zero,
                      decoration: isToday
                          ? BoxDecoration(
                              color: red ? (isDark ? Colors.amber.shade300 : Colors.lime.shade300) : (isDark ? const Color(0xFFB4BFFF) : colorScheme.primary),
                              borderRadius: BorderRadius.circular(4.r),
                            )
                          : null,
                      child: Text(
                        '${day.day}', textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600, height: 1.0,
                          color: isToday
                              ? (red ? (isDark ? Colors.red.shade900 : Colors.red) : (isDark ? Colors.white : colorScheme.onPrimary))
                              : dateColor,
                        ),
                      ),
                    ),
                  ),
                ),
                if (memos.isNotEmpty)
                  Positioned(
                    left: 0, right: 0, bottom: 1.5.h,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: memos.take(3).map((m) => Container(
                        width: double.infinity,
                        margin: EdgeInsets.only(bottom: 0.5.h),
                        padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
                        decoration: BoxDecoration(
                          color: isDark ? colorScheme.primary.withOpacity(0.3) : colorScheme.surfaceVariant,
                          border: Border.all(color: isDark ? colorScheme.primary.withOpacity(0.5) : colorScheme.outline, width: 0.5),
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                        child: Text(m, textAlign: TextAlign.center, style: TextStyle(
                          fontSize: 8.sp, color: colorScheme.onSurface, fontWeight: FontWeight.w500, height: 1.0,
                        ), maxLines: 1, overflow: TextOverflow.clip),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
