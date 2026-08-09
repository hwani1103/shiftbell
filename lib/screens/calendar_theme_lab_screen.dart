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
import 'all_shifts_view.dart';

// ============================================================
// ⭐ 공용 목업 데이터
// ============================================================

class _MockShift {
  final String name;
  final Color color;
  final int durationMinutes;
  const _MockShift(this.name, this.color, this.durationMinutes);
}

const _mockShifts = <_MockShift>[
  _MockShift('주간근무', Color(0xFF42A5F5), 8 * 60),
  _MockShift('주간', Color(0xFF26C6DA), 8 * 60),
  _MockShift('야간', Color(0xFF7E57C2), 12 * 60),
  _MockShift('당직', Color(0xFFFF8A65), 24 * 60),
  _MockShift('오프', Color(0xFF66BB6A), 0),
  _MockShift('휴무', Color(0xFFEF5350), 0),
];

// ⭐ 6일 주기로 순환하는 목업 패턴 (앞뒤 스필오버 날짜도 동일하게 적용됨)
_MockShift _mockShiftFor(DateTime d) {
  final epoch = DateTime(2026, 1, 1);
  final days = d.difference(epoch).inDays;
  return _mockShifts[((days % 6) + 6) % 6];
}

// ⭐ 메모 1개/2개/3개 테스트용 (3개짜리엔 일부러 긴 문장 하나 섞음)
final Map<String, List<String>> _mockMemos = {
  '2026-08-05': ['병원 예약'],
  '2026-08-12': ['회식 7시', '월급날'],
  '2026-08-20': ['생일 축하', '약속 있음', '택배 도착 예정일 꼭 확인하기'],
};

// ⭐ 수동 OT 목업 (8/15는 광복절과 겹치게 해서 "같은 셀에 여러 배지" 케이스도 같이 확인)
final Map<String, int> _mockOtMinutes = {
  '2026-08-15': 150,
  '2026-08-22': 60,
};

const _mockHolidayKey = '2026-08-15';
const _mockHolidayName = '광복절';

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
      final shift = _mockShiftFor(d);
      if (shift.durationMinutes > 0) {
        minutes += shift.durationMinutes;
        counts[shift.name] = (counts[shift.name] ?? 0) + 1;
      }
      minutes += _mockOtMinutes[_dateKey(d)] ?? 0;
    }
    weeks.add(_WeekSummary(start, end, minutes, counts));
    start = start.add(const Duration(days: 7));
  }
  return weeks;
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) return '0시간';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '$h시간 $m분';
  if (h > 0) return '$h시간';
  return '$m분';
}

int get _mockMonthlyOtTotal => _mockOtMinutes.values.fold(0, (a, b) => a + b);

const _weekdayKr = ['일', '월', '화', '수', '목', '금', '토'];
const _weekdayEn3 = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _weekdayEn1 = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

// ============================================================
// ⭐ 메인 화면 - PageView로 10개 테마를 스와이프 비교
// ============================================================

class CalendarThemeLabScreen extends StatefulWidget {
  const CalendarThemeLabScreen({super.key});

  @override
  State<CalendarThemeLabScreen> createState() => _CalendarThemeLabScreenState();
}

class _CalendarThemeLabScreenState extends State<CalendarThemeLabScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final List<DateTime> _days = _augustGridDays();
  final List<_WeekSummary> _weeks = _mockWeekSummaries();

  static const _themeCount = 10;

  static const _themeTitles = [
    '1번 · 미니멀 라인',
    '2번 · 머티리얼 카드형',
    '3번 · 애플 캘린더 스타일',
    '4번 · 굵은 격자형',
    '5번 · 이니셜 뱃지형',
    '6번 · 컬러 블록 배경형',
    '7번 · 스플릿 셀형',
    '8번 · 언더라인 미니멀형',
    '9번 · 이벤트 칩형',
    '10번 · 매거진 에디토리얼형',
  ];
  static const _themeComments = [
    '요일당 얇은 선만, 근무는 하단 컬러바+1글자. 여백감 우선 (구글 캘린더 참고).',
    '셀마다 살짝 뜬 카드+그림자. 근무는 상단 탭 색상, 메모는 카드 하단 점.',
    '테두리 없이 숫자만. 오늘=꽉 찬 원. 근무는 숫자 아래 작은 컬러 바 (iOS 참고).',
    '표처럼 두꺼운 격자. 근무명 전체 텍스트 뱃지. 정보량 최대·여백 최소.',
    '근무는 우상단 원형 뱃지 1글자만. 숫자는 좌상단. 가장 컴팩트.',
    '셀 배경 전체를 근무색 파스텔로. 대비색 텍스트. 가장 화려함.',
    '셀을 좌/우 분할 - 왼쪽 컬러+1글자, 오른쪽 숫자. 국기 느낌의 대비.',
    '배경·테두리 없이 숫자 아래 밑줄만 근무색. 메모가 제일 잘 보이는 극단형.',
    '근무명을 가로 칩(구글 캘린더 이벤트칩)으로. 메모도 같은 톤 칩으로 쌓음.',
    '요일 헤더에 색 바, 근무는 모서리 삼각 배지. 세리프 숫자로 잡지 느낌.',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _themeCount,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) => _buildThemeBody(index),
              ),
            ),
            _buildBottomStrip(),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeBody(int index) {
    switch (index) {
      case 0: return _theme1MinimalLine();
      case 1: return _theme2MaterialCard();
      case 2: return _theme3AppleStyle();
      case 3: return _theme4BoldGrid();
      case 4: return _theme5InitialBadge();
      case 5: return _theme6ColorBlock();
      case 6: return _theme7SplitCell();
      case 7: return _theme8Underline();
      case 8: return _theme9EventChip();
      case 9: return _theme10Editorial();
      default: return const SizedBox.shrink();
    }
  }

  // ⭐ 모든 테마 공통 고정 영역 - 테마 번호/코멘트 + 페이지 인디케이터.
  // 나중에 광고가 들어갈 자리라 높이를 고정해두고 절대 이 영역 디자인은 안 건드림.
  Widget _buildBottomStrip() {
    return Container(
      height: 68.h,
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _themeTitles[_currentPage],
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                SizedBox(height: 2.h),
                Text(
                  _themeComments[_currentPage],
                  style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade600, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Row(
            children: List.generate(_themeCount, (i) {
              final active = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.symmetric(horizontal: 1.5.w),
                width: active ? 7.w : 4.w,
                height: 4.w,
                decoration: BoxDecoration(
                  color: active ? Colors.indigo.shade600 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ⭐ "전체근무표"는 이미 완성된 실제 화면을 그대로 재사용 (테마와 무관한 별도 화면)
  void _openAllShifts() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AllShiftsView()));
  }

  // ⭐ 이 프로토타입은 2026년 8월 고정이라 실제 "오늘로 이동"은 의미가 없어서 안내만 함
  void _tapToday() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('미리보기는 2026년 8월 고정 표시예요 (실제 채택 시 달력탭의 오늘 이동 로직을 그대로 사용합니다)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ⭐ 날짜 탭 → 실제 팝업 대신 "이 테마가 채택되면 여기서 무슨 일이 일어나는지"
  // 보여주는 가벼운 미리보기 시트. 실제 근무변경/메모/OT 팝업은 달력탭에 이미 완성돼
  // 있고 여기서 안 건드렸으므로, 채택 후 실제 연결 시 그대로 재사용하면 됨.
  void _tapDay(DateTime day) {
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final ot = _mockOtMinutes[_dateKey(day)] ?? 0;
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
                '${day.month}월 ${day.day}일 (${_weekdayKr[day.weekday % 7]}) 미리보기',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10.h),
              Row(children: [
                Container(width: 10.w, height: 10.w, decoration: BoxDecoration(color: shift.color, shape: BoxShape.circle)),
                SizedBox(width: 6.w),
                Text('근무: ${shift.name}', style: TextStyle(fontSize: 14.sp)),
              ]),
              if (ot > 0) ...[
                SizedBox(height: 4.h),
                Text('OT: ${_formatMinutes(ot)}', style: TextStyle(fontSize: 13.sp, color: Colors.indigo)),
              ],
              if (memos.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text('메모 ${memos.length}개: ${memos.join(" / ")}', style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700)),
              ],
              SizedBox(height: 14.h),
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8.r)),
                child: Text(
                  '이 테마가 채택되면 여기서 실제 근무 변경 · 메모 입력 · OT 입력 팝업(지금 달력탭과 동일)이 뜹니다.',
                  style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade600, height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ⭐ 근무명을 텍스트로 안 보여주는 테마(5번 등)에서 쓰는 색상 범례
  Widget _legendRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: _mockShifts.map((s) {
          return Padding(
            padding: EdgeInsets.only(right: 10.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                SizedBox(width: 3.w),
                Text(s.name, style: TextStyle(fontSize: 9.5.sp, color: Colors.grey.shade700)),
              ],
            ),
          );
        }).toList(),
      ),
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
              _thinTextButton('전체근무표', _openAllShifts),
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
                    return Expanded(child: _theme1Cell(day, col == 0));
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

  Widget _theme1Cell(DateTime day, bool isSunCol) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(day);
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
        padding: EdgeInsets.symmetric(vertical: 2.h),
        child: Column(
          children: [
            SizedBox(height: 2.h),
            Container(
              width: 20.w,
              height: 20.w,
              alignment: Alignment.center,
              decoration: today
                  ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.indigo.shade400, width: 1.4))
                  : null,
              child: Text('${day.day}', style: TextStyle(fontSize: 11.5.sp, fontWeight: today ? FontWeight.bold : FontWeight.w500, color: numColor)),
            ),
            SizedBox(height: 1.h),
            ...memos.take(3).map((m) => Padding(
              padding: EdgeInsets.symmetric(horizontal: 1.w),
              child: Text(m, style: TextStyle(fontSize: 6.5.sp, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            )),
            const Spacer(),
            if (!outside)
              Container(
                width: double.infinity,
                height: 12.h,
                margin: EdgeInsets.only(top: 1.h),
                color: shift.color.withOpacity(0.85),
                alignment: Alignment.center,
                child: Text(shift.name[0], style: TextStyle(fontSize: 7.5.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color))),
              )
            else
              SizedBox(height: 12.h),
          ],
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
          Text('이번 달 OT ${_formatMinutes(_mockMonthlyOtTotal)}', style: TextStyle(fontSize: 11.sp, color: Colors.black87)),
          const Spacer(),
          GestureDetector(
            onTap: () => _showWeekSummarySheet(context, _weeks),
            child: Text('주별 근무시간 ›', style: TextStyle(fontSize: 11.sp, color: Colors.indigo.shade400, fontWeight: FontWeight.w600)),
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
                Text('2026년 8월', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.black87)),
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
                  child: Text(_weekdayKr[i], style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade600)),
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
    final shift = _mockShiftFor(day);
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
          child: Column(
            children: [
              if (!outside)
                Container(
                  height: 4.h,
                  margin: EdgeInsets.fromLTRB(4.w, 3.h, 4.w, 0),
                  decoration: BoxDecoration(color: shift.color, borderRadius: BorderRadius.circular(2.r)),
                )
              else
                SizedBox(height: 7.h),
              SizedBox(height: 2.h),
              Text('${day.day}', style: TextStyle(
                fontSize: 11.sp,
                fontWeight: today ? FontWeight.bold : FontWeight.w600,
                color: outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87),
              )),
              ...memos.take(3).map((m) => Text(m, style: TextStyle(fontSize: 6.sp, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const Spacer(),
            ],
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
          _otChip('이번 달 OT', _formatMinutes(_mockMonthlyOtTotal), Colors.indigo),
          SizedBox(width: 8.w),
          _otChip('주별 근무시간', '보기', Colors.teal, onTap: () => _showWeekSummarySheet(context, _weeks)),
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
// ⭐ 테마 3 · 애플 캘린더 스타일
// 테두리 없이 숫자만. 오늘=꽉 찬 원. 근무는 숫자 아래 작은 컬러 바.
// ============================================================
extension _Theme3 on _CalendarThemeLabScreenState {
  Widget _theme3AppleStyle() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 4.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('8월', style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w300, color: Colors.black87)),
              SizedBox(width: 6.w),
              Text('2026', style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade400)),
              const Spacer(),
              GestureDetector(onTap: _tapToday, child: Text('오늘', style: TextStyle(fontSize: 13.sp, color: Colors.red.shade400, fontWeight: FontWeight.w600))),
              SizedBox(width: 14.w),
              GestureDetector(onTap: _openAllShifts, child: Icon(Icons.list_alt_rounded, size: 20.sp, color: Colors.red.shade400)),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(child: Text(_weekdayEn1[i], style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade400))),
            )),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(children: List.generate(7, (col) => Expanded(child: _theme3Cell(_days[row * 7 + col])))),
              )),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 10.h),
          child: Row(
            children: [
              Expanded(child: Text('이번 달 OT  ${_formatMinutes(_mockMonthlyOtTotal)}', style: TextStyle(fontSize: 12.sp, color: Colors.black54))),
              GestureDetector(
                onTap: () => _showWeekSummarySheet(context, _weeks),
                child: Text('주별 근무시간 보기', style: TextStyle(fontSize: 12.sp, color: Colors.red.shade400, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _theme3Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          SizedBox(height: 4.h),
          Container(
            width: 26.w,
            height: 26.w,
            alignment: Alignment.center,
            decoration: today ? BoxDecoration(color: red ? Colors.red.shade400 : Colors.black87, shape: BoxShape.circle) : null,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: today ? FontWeight.bold : FontWeight.w400,
                color: today ? Colors.white : (outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87)),
              ),
            ),
          ),
          if (!outside) ...[
            SizedBox(height: 3.h),
            Container(width: 18.w, height: 3.h, decoration: BoxDecoration(color: shift.color, borderRadius: BorderRadius.circular(1.5.r))),
          ],
          SizedBox(height: 1.h),
          ...memos.take(3).map((m) => Text(m, style: TextStyle(fontSize: 6.sp, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
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
              _gridHeaderBtn('전체표', _openAllShifts),
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
              Text('OT ${_formatMinutes(_mockMonthlyOtTotal)}', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: const Color(0xFF263238))),
              SizedBox(width: 14.w),
              GestureDetector(
                onTap: () => _showWeekSummarySheet(context, _weeks),
                child: Text('주별 근무시간 ▸', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00695C))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _theme4Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(day);
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
            Text('${day.day}', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: outside ? Colors.grey.shade400 : (red ? Colors.red.shade600 : const Color(0xFF263238)))),
            if (!outside)
              Container(
                margin: EdgeInsets.symmetric(vertical: 1.h),
                padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
                width: double.infinity,
                decoration: BoxDecoration(color: shift.color),
                child: Text(shift.name, style: TextStyle(fontSize: 6.5.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color)), maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.center),
              ),
            ...memos.take(3).map((m) => Text('· $m', style: TextStyle(fontSize: 6.sp, color: const Color(0xFF546E7A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
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
// ⭐ 테마 5 · 이니셜 뱃지형
// 근무는 우상단 원형 뱃지 1글자만. 숫자는 좌상단. 가장 컴팩트 - 범례 필요.
// ============================================================
extension _Theme5 on _CalendarThemeLabScreenState {
  Widget _theme5InitialBadge() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
          child: Row(
            children: [
              Text('2026.08', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              const Spacer(),
              _pillButton('전체근무표', Icons.table_chart_outlined, _openAllShifts),
              SizedBox(width: 6.w),
              _pillButton('오늘', Icons.adjust, _tapToday),
            ],
          ),
        ),
        _legendRow(),
        SizedBox(height: 6.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(child: Text(_weekdayKr[i], style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500))),
            )),
          ),
        ),
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
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: EdgeInsets.all(1.5.w),
        decoration: BoxDecoration(
          color: today ? Colors.indigo.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
        ),
        padding: EdgeInsets.all(3.w),
        child: Stack(
          children: [
            Text('${day.day}', style: TextStyle(
              fontSize: 11.sp,
              fontWeight: today ? FontWeight.bold : FontWeight.w500,
              color: outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87),
            )),
            if (!outside)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 13.w,
                  height: 13.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: shift.color, shape: BoxShape.circle),
                  child: Text(shift.name[0], style: TextStyle(fontSize: 7.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color))),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                children: memos.take(3).map((m) => Text(m, style: TextStyle(fontSize: 6.sp, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis)).toList(),
              ),
            ),
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
// ⭐ 테마 6 · 컬러 블록 배경형
// 셀 배경 전체를 근무색 파스텔로. 대비색 텍스트. 가장 화려하고 눈에 띔.
// ============================================================
extension _Theme6 on _CalendarThemeLabScreenState {
  Widget _theme6ColorBlock() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
          child: Row(
            children: [
              Text('8월', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w900, color: Colors.black87)),
              Text(' 2026', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade500)),
              const Spacer(),
              _roundIconButton(Icons.grid_view_rounded, _openAllShifts),
              SizedBox(width: 8.w),
              _roundIconButton(Icons.today_rounded, _tapToday),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: Row(
            children: List.generate(7, (i) => Expanded(
              child: Center(child: Text(_weekdayKr[i], style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : Colors.grey.shade500))),
            )),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(children: List.generate(7, (col) => Expanded(child: _theme6Cell(_days[row * 7 + col])))),
              )),
            ),
          ),
        ),
        _theme2OtCard(),
        SizedBox(height: 8.h),
      ],
    );
  }

  Widget _theme6Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);
    final textColor = outside ? Colors.grey.shade400 : _autoTextColor(shift.color);

    return GestureDetector(
      onTap: () => _tapDay(day),
      child: Container(
        margin: EdgeInsets.all(1.5.w),
        decoration: BoxDecoration(
          color: outside ? Colors.grey.shade100 : shift.color.withOpacity(0.85),
          borderRadius: BorderRadius.circular(7.r),
          border: today ? Border.all(color: red ? Colors.red.shade700 : Colors.black87, width: 1.6) : null,
        ),
        padding: EdgeInsets.all(2.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${day.day}', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: red && !outside ? Colors.red.shade900 : textColor)),
            if (!outside)
              Text(shift.name.length > 2 ? shift.name.substring(0, 2) : shift.name, style: TextStyle(fontSize: 7.sp, color: textColor.withOpacity(0.9)), maxLines: 1, overflow: TextOverflow.clip),
            const Spacer(),
            ...memos.take(3).map((m) => Container(
              margin: EdgeInsets.only(top: 1.h),
              padding: EdgeInsets.symmetric(horizontal: 2.w),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(2.r)),
              child: Text(m, style: TextStyle(fontSize: 6.sp, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
            )),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ⭐ 테마 7 · 스플릿 셀형
// 셀을 좌/우로 분할 - 왼쪽은 컬러+1글자, 오른쪽은 숫자. 국기 느낌의 대비.
// ============================================================
extension _Theme7 on _CalendarThemeLabScreenState {
  Widget _theme7SplitCell() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
          child: Row(
            children: [
              Text('2026년 8월', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              const Spacer(),
              _pillButton('전체근무표', Icons.table_chart_outlined, _openAllShifts),
              SizedBox(width: 6.w),
              _pillButton('오늘', Icons.adjust, _tapToday),
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
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(children: List.generate(7, (col) => Expanded(child: _theme7Cell(_days[row * 7 + col])))),
              )),
            ),
          ),
        ),
        _theme1OtBar(),
        SizedBox(height: 6.h),
      ],
    );
  }

  Widget _theme7Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      child: Container(
        margin: EdgeInsets.all(1.5.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5.r),
          border: today ? Border.all(color: Colors.black87, width: 1.4) : Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 14.w,
                    color: outside ? Colors.grey.shade100 : shift.color,
                    alignment: Alignment.center,
                    child: outside ? null : Text(shift.name[0], style: TextStyle(fontSize: 8.sp, fontWeight: FontWeight.bold, color: _autoTextColor(shift.color))),
                  ),
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      alignment: Alignment.topCenter,
                      padding: EdgeInsets.only(top: 2.h),
                      child: Text('${day.day}', style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: today ? FontWeight.bold : FontWeight.w500,
                        color: outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87),
                      )),
                    ),
                  ),
                ],
              ),
            ),
            if (memos.isNotEmpty)
              Container(
                width: double.infinity,
                color: Colors.grey.shade50,
                padding: EdgeInsets.symmetric(horizontal: 2.w),
                child: Column(
                  children: memos.take(3).map((m) => Text(m, style: TextStyle(fontSize: 6.sp, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis)).toList(),
                ),
              ),
          ],
        ),
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
              GestureDetector(onTap: _openAllShifts, child: Text('전체표', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: Colors.black54))),
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
            child: Column(
              children: List.generate(6, (row) => Expanded(
                child: Row(children: List.generate(7, (col) => Expanded(child: _theme8Cell(_days[row * 7 + col])))),
              )),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 10.h),
          child: Row(
            children: [
              Text('OT ${_formatMinutes(_mockMonthlyOtTotal)}', style: TextStyle(fontSize: 11.sp, color: Colors.black54)),
              const Spacer(),
              GestureDetector(onTap: () => _showWeekSummarySheet(context, _weeks), child: Text('주별 근무시간', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: Colors.black87, decoration: TextDecoration.underline))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _theme8Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
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
          if (!outside)
            Container(margin: EdgeInsets.symmetric(vertical: 2.h), width: 14.w, height: 2.h, color: shift.color)
          else
            SizedBox(height: 6.h),
          ...memos.take(3).map((m) => Text(m, style: TextStyle(fontSize: 7.sp, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
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
              Text('2026. 8', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              const Spacer(),
              _pillButton('전체근무표', Icons.table_chart_outlined, _openAllShifts),
              SizedBox(width: 6.w),
              _pillButton('오늘', Icons.adjust, _tapToday),
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
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
        padding: EdgeInsets.symmetric(horizontal: 1.5.w, vertical: 2.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18.w,
              height: 18.w,
              alignment: Alignment.center,
              margin: EdgeInsets.only(bottom: 2.h),
              decoration: today ? BoxDecoration(color: red ? Colors.red.shade400 : Colors.indigo.shade400, shape: BoxShape.circle) : null,
              child: Text('${day.day}', style: TextStyle(
                fontSize: 10.5.sp,
                fontWeight: today ? FontWeight.bold : FontWeight.w500,
                color: today ? Colors.white : (outside ? Colors.grey.shade300 : (red ? Colors.red.shade400 : Colors.black87)),
              )),
            ),
            if (!outside)
              _chip(shift.name, shift.color, _autoTextColor(shift.color)),
            ...memos.take(3).map((m) => Padding(
              padding: EdgeInsets.only(top: 1.h),
              child: _chip(m, Colors.grey.shade200, Colors.black87),
            )),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 0.5.h),
      padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2.5.r)),
      child: Text(text, style: TextStyle(fontSize: 6.sp, color: fg, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
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
              GestureDetector(onTap: _openAllShifts, child: Text('전체근무표', style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, decoration: TextDecoration.underline))),
              SizedBox(width: 10.w),
              GestureDetector(onTap: _tapToday, child: Text('오늘', style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, decoration: TextDecoration.underline))),
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
        Expanded(
          child: Column(
            children: List.generate(6, (row) => Expanded(
              child: Row(children: List.generate(7, (col) => Expanded(child: _theme10Cell(_days[row * 7 + col])))),
            )),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(18.w, 6.h, 18.w, 10.h),
          child: Row(
            children: [
              Text('이번 달 OT', style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade500, fontFamily: 'serif')),
              SizedBox(width: 4.w),
              Text(_formatMinutes(_mockMonthlyOtTotal), style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.brown.shade600, fontFamily: 'serif')),
              const Spacer(),
              GestureDetector(
                onTap: () => _showWeekSummarySheet(context, _weeks),
                child: Text('주별 근무시간 →', style: TextStyle(fontSize: 11.sp, color: Colors.brown.shade400, fontFamily: 'serif')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _theme10Cell(DateTime day) {
    final outside = _isOutsideAugust(day);
    final shift = _mockShiftFor(day);
    final memos = _mockMemos[_dateKey(day)] ?? [];
    final today = _isToday(day);
    final red = _isRedDay(day);

    return GestureDetector(
      onTap: () => _tapDay(day),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200, width: 0.5)),
        child: Stack(
          children: [
            if (!outside)
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
            Positioned(
              left: 2.w,
              right: 2.w,
              bottom: 2.h,
              child: Column(
                children: memos.take(3).map((m) => Text(m, style: TextStyle(fontSize: 6.sp, color: Colors.grey.shade600, fontFamily: 'serif'), maxLines: 1, overflow: TextOverflow.ellipsis)).toList(),
              ),
            ),
          ],
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
            Text('8월 주별 근무(예정) 시간', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 10.h),
            ...weeks.map((w) => Padding(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Row(
                children: [
                  Text('${w.start.month}/${w.start.day} ~ ${w.end.month}/${w.end.day}', style: TextStyle(fontSize: 13.sp)),
                  const Spacer(),
                  Text(_formatMinutes(w.totalMinutes), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ],
              ),
            )),
          ],
        ),
      );
    },
  );
}
