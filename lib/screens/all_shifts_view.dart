import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/calendar_theme_provider.dart';
import '../models/shift_schedule.dart';
import '../models/calendar_theme.dart';
import '../l10n/l10n_extensions.dart';
import '../utils/weekday_util.dart';
import 'all_teams_setup_screen.dart';

/// 전체 근무표 - 모든 조의 근무를 한눈에 보는 화면
class AllShiftsView extends ConsumerStatefulWidget {
  // ⭐ 2026-09-05 - 버그 수정. 달력 탭에서 보고 있던 달(예: 8월)과 무관하게
  // 항상 오늘이 속한 달(예: 9월)로 열리던 문제 - 호출부(calendar_tab.dart)가
  // 지금 보고 있던 달을 넘겨주면 그 달로 열림. null(예: 다른 진입 경로)이면
  // 기존처럼 오늘이 속한 달로 열림.
  final DateTime? initialMonth;

  const AllShiftsView({super.key, this.initialMonth});

  @override
  ConsumerState<AllShiftsView> createState() => _AllShiftsViewState();
}

class _AllShiftsViewState extends ConsumerState<AllShiftsView> {
  late PageController _pageController;
  late DateTime _currentMonth;
  bool _isLoading = true;
  bool _isConfigured = false; // ⭐ 전체 교대조 근무표 설정 여부
  String _myTeam = ''; // ⭐ 2026-09-05 - 편집 화면 프리필용("내 조" 자동인식)

  // ⭐ PageView용 초기 인덱스 (과거 100년 ~ 미래 100년)
  static const int _initialPage = 1200; // 100년 * 12개월

  // ⭐ 저장된 데이터
  List<String> _teams = ['A', 'B', 'C', 'D'];

  // ⭐ 각 조의 오프셋 (패턴 시작점, 0~패턴길이-1)
  Map<String, int> _teamOffsets = {
    'A': 0,
    'B': 1,
    'C': 2,
    'D': 3,
  };

  // ⭐ CRITICAL FIX: 절대 기준일 (고정, 저장 불필요)
  static final DateTime _baseDate = DateTime(2024, 1, 1);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = widget.initialMonth == null
        ? now
        : DateTime(widget.initialMonth!.year, widget.initialMonth!.month);
    // ⭐ itemBuilder(아래 build())가 매 페이지를 "오늘이 속한 달"(now) 기준
    // monthsDiff로 계산하므로(now.year, now.month + (index - _initialPage)),
    // _currentMonth로 열리는 페이지 인덱스도 그 기준에 맞춰 역산해야 함 -
    // 안 그러면 PageController는 _initialPage(항상 "오늘" 페이지)에서 시작해서
    // widget.initialMonth를 무시하게 됨.
    final monthsFromNow =
        (_currentMonth.year - now.year) * 12 + (_currentMonth.month - now.month);
    _pageController = PageController(initialPage: _initialPage + monthsFromNow);
    _loadTeamData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ⭐ SharedPreferences에서 팀 데이터 로드
  Future<void> _loadTeamData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 저장된 조 이름 가져오기
      final savedTeams = prefs.getStringList('all_teams_names');
      if (savedTeams != null && savedTeams.isNotEmpty) {
        _teams = savedTeams;
        _isConfigured = true; // ⭐ 설정된 상태
      } else {
        _isConfigured = false; // ⭐ 미설정 상태
      }

      // 저장된 오프셋 가져오기
      if (_isConfigured) {
        final offsetsJson = prefs.getString('all_teams_offsets');
        if (offsetsJson != null) {
          final Map<String, dynamic> decoded = jsonDecode(offsetsJson);
          _teamOffsets = decoded.map((key, value) =>
            MapEntry(key, int.parse(value.toString()))
          );
        }
      }
      // ⭐ 편집 화면 프리필용 - 설정 여부와 무관하게 항상 읽어둠(미설정 상태에서도
      // 값이 남아있을 수 있는 엣지케이스를 굳이 배제할 이유가 없음).
      _myTeam = prefs.getString('all_teams_my_team') ?? '';
    } catch (e) {
      _isConfigured = false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ⭐ 2026-09-05 - 월 이동 버튼 3종 - 위쪽 헤더와 두 블록 사이 보조 내비게이션
  // 바가 공유해서 씀(중복 코드 방지). PageView의 스와이프 제스처는 껐지만
  // (위 physics 주석 참고) 이 프로그램적 페이지 이동은 physics와 무관하게 계속 동작함.
  void _goToPreviousMonth() {
    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _goToNextMonth() {
    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _jumpToCurrentMonth() {
    _pageController.animateToPage(_initialPage, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  // ⭐ 2026-09-05 - 전체 교대조 근무표 설정/편집 화면 열기(신규 작성/편집
  // 공용 - _isConfigured면 기존 값이 프리필된 채로 열림). 예전엔 다이얼로그
  // 하나였는데, 프리필 지원하는 풀스크린으로 교체(all_teams_setup_screen.dart
  // 상단 주석 참고).
  Future<void> _openAllTeamsSetupScreen() async {
    final schedule = ref.read(scheduleProvider).value;

    // 규칙적 근무자만 사용 가능(내 조 오늘 근무를 자동 계산하려면 pattern/
    // todayIndex/startDate가 전부 있어야 함).
    if (schedule == null ||
        !schedule.isRegular ||
        schedule.pattern == null ||
        schedule.todayIndex == null ||
        schedule.startDate == null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.statusFullTeamScheduleTitle),
          content: Text(context.l10n.settingsAllTeamsRegularOnly),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonOk),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;

    // ⭐ 2026-09-05 - 버그 수정. schedule.todayIndex는 "오늘의" 패턴 인덱스가
    // 아니라 schedule.startDate 시점의 패턴 인덱스임(shift_schedule.dart의
    // getShiftForDate/getPatternShiftForDate와 동일한 계산식 참고) - startDate
    // 이후로 하루라도 지났으면 todayIndex를 그대로 쓰면 내 조의 "오늘 근무"가
    // 완전히 틀어짐(그 틀어진 값이 오프셋 계산의 기준이 되어 전체근무표 전체가
    // 어긋나 보이는 원인). startDate 기준 경과일만큼 반드시 보정해야 함.
    final now = DateTime.now();
    final daysSinceStart = julianDayNumber(now.year, now.month, now.day) -
        julianDayNumber(schedule.startDate!.year, schedule.startDate!.month,
            schedule.startDate!.day);
    final patternLen = schedule.pattern!.length;
    final myTodayIndex =
        ((schedule.todayIndex! + daysSinceStart) % patternLen + patternLen) %
            patternLen;

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AllTeamsSetupScreen(
          pattern: schedule.pattern!,
          myTodayIndex: myTodayIndex,
          existingTeamNames: _isConfigured ? _teams : const [],
          existingTeamOffsets: _isConfigured ? _teamOffsets : const {},
          existingMyTeam: _myTeam,
        ),
      ),
    );

    if (completed == true) {
      await _loadTeamData();
    }
  }

  // ⭐ 2026-09-04 - LOW 항목 수정(전체_코드_점검_리포트_2026-09-04.md). 이 화면만
  // schedule.shiftColors(DB에 캐시된 스냅샷)를 직접 읽고 있었는데, calendar_tab.dart는
  // 항상 effectiveShiftColors(테마+customShiftColors)로 라이브 계산함 - 캐시 갱신을
  // 빼먹는 쓰기 경로가 생기면 전체근무표만 색이 다르게 보일 수 있는 구조적 위험이라
  // 동일한 라이브 계산 방식으로 맞춤.
  // ⭐ 2026-09-05 - 실제 (team,date)→근무 계산/색상 조회 로직 자체는
  // _MonthShiftTable로 옮겼음(그 위젯은 Riverpod 없이 순수 데이터만 받음) -
  // 여기 남은 건 이 색상 맵을 한 번 계산해서 넘겨주는 이 함수 하나뿐.
  Map<String, Color> _shiftColorMap(ShiftSchedule? schedule) {
    if (schedule == null) return {};
    final theme = ref.watch(calendarThemeProvider);
    return effectiveShiftColors(schedule.shiftTypes, theme, schedule.customShiftColors);
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ schedule 가져오기
    final scheduleAsync = ref.watch(scheduleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.shiftFullSchedule),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(),
            )
          : !_isConfigured
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.groups_outlined,
                          size: 80.sp,
                          color: colorScheme.outline,
                        ),
                        SizedBox(height: 24.h),
                        Text(
                          context.l10n.allTeamsNotConfigured,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: 32.h),
                        // ⭐ 전체 교대조 근무표 만들기 버튼
                        ElevatedButton.icon(
                          onPressed: () => _openAllTeamsSetupScreen(),
                          icon: Icon(Icons.add_circle_outline, size: 22.sp),
                          label: Text(context.l10n.allTeamsCreateButton, style: TextStyle(fontSize: 16.sp)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(context.l10n.commonGoBack, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15.sp)),
                        ),
                      ],
                    ),
                  ),
                )
              : scheduleAsync.when(
                  loading: () => Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text(context.l10n.statusErrorWithDetail(error.toString()))),
                  data: (schedule) => SafeArea(
                    child: Column(
                      children: [
                        // ⭐ 년월 표시
                        // ⭐ 2026-09-05 후속 - 편집 아이콘과 겹치던 문제 수정. 텍스트를
                        // "화면 전체" 기준으로 가운데 정렬하면 글자가 크거나 로케일에
                        // 따라 길어질 때 옆 버튼 자리를 침범할 수 있었음 - 양쪽에 같은
                        // 폭의 자리를 대칭으로 두는 구조로, 텍스트는 그 "가운데 남는
                        // 공간" 안에서만 가운데 정렬되게 함.
                        // ⭐ 후속2 - "이번 달" 버튼을 두 블록 사이에서 이 줄의 왼쪽으로
                        // 옮김(요청) - 왼쪽엔 이번 달, 오른쪽엔 편집(기존 그대로).
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          color: colorScheme.surface,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 76.w,
                                child: Center(
                                  child: GestureDetector(
                                    onTap: _jumpToCurrentMonth,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(16.r),
                                      ),
                                      child: Text(
                                        context.l10n.allTeamsThisMonthButton,
                                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    DateFormat.yMMMM(Localizations.localeOf(context).toString()).format(_currentMonth),
                                    style: TextStyle(
                                      fontSize: 19.sp,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 76.w,
                                // ⭐ 2026-09-05 후속 - "편집 버튼도 버튼 느낌으로, 이번
                                // 달 버튼이랑 스타일은 비슷하게" 요청 - IconButton
                                // 대신 왼쪽 "이번 달"과 같은 알약(pill) 모양의
                                // Container로 통일(배경색/둥글기/강조색 전부 동일).
                                // ⭐ 후속2 - 아이콘을 24.sp로 키웠다가 "왜 커졌냐"는
                                // 지적으로 이전 크기(20.sp/패딩 8.w)로 되돌림 - "이번
                                // 달" 글자 크기(13.sp)는 이것과 무관하게 그대로 둠(둘은
                                // 서로 다른 요청이었을 뿐 연동되는 값이 아님).
                                child: _isConfigured
                                    ? Center(
                                        child: Tooltip(
                                          message: context.l10n.allTeamsSetupEditTooltip,
                                          child: GestureDetector(
                                            onTap: () => _openAllTeamsSetupScreen(),
                                            child: Container(
                                              padding: EdgeInsets.all(8.w),
                                              decoration: BoxDecoration(
                                                color: colorScheme.surfaceVariant,
                                                borderRadius: BorderRadius.circular(16.r),
                                              ),
                                              child: Icon(Icons.edit_outlined, size: 20.sp, color: colorScheme.primary),
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: colorScheme.outline),
                        // ⭐ PageView로 여러 달 표시
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            // ⭐ 2026-09-05 - 버그 수정. 좌우 스와이프로 월을 넘기던
                            // 제스처가, 각 블록 안의 가로 스크롤(날짜 넘기기)과 같은
                            // 축이라 서로 겹쳐서 손이 자꾸 엉뚱한 쪽으로 반응했음
                            // ("때때로 겹친다"는 신고). 월 이동은 이제 버튼(위/아래
                            // 두 자리)으로만 하게 하고, 스와이프 제스처 자체를 꺼서
                            // 이 화면엔 "가로 드래그"가 블록 내부 날짜 스크롤 하나만
                            // 남게 함 - 애매함 자체가 구조적으로 없어짐. previousPage/
                            // nextPage/animateToPage 같은 프로그램적 페이지 이동은
                            // physics와 무관하게 그대로 동작(버튼은 계속 잘 작동함).
                            physics: const NeverScrollableScrollPhysics(),
                            onPageChanged: (page) {
                              final now = DateTime.now();
                              final monthsDiff = page - _initialPage;
                              setState(() {
                                _currentMonth = DateTime(
                                  now.year,
                                  now.month + monthsDiff,
                                );
                              });
                            },
                            itemBuilder: (context, index) {
                              final now = DateTime.now();
                              final monthsDiff = index - _initialPage;
                              final targetMonth = DateTime(
                                now.year,
                                now.month + monthsDiff,
                              );
                              final year = targetMonth.year;
                              final month = targetMonth.month;
                              final lastDay = DateTime(year, month + 1, 0).day;

                              // ⭐ 2026-09-05 - "팀 로우 타임라인" 안으로 전면 교체.
                              // 1~15일/16~31일 두 블록이 화면을 정확히 반씩 채우고
                              // (Expanded), 각 블록 안에서만 가로 스크롤 + (조가
                              // 많을 때만) 세로 스크롤이 생김 - 페이지 자체를 감싸는
                              // 바깥 스크롤은 더 이상 필요 없음(_MonthShiftTable 참고).
                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                child: _MonthShiftTable(
                                  key: ValueKey('$year-$month'),
                                  year: year,
                                  month: month,
                                  lastDay: lastDay,
                                  teams: _teams,
                                  teamOffsets: _teamOffsets,
                                  baseDate: _baseDate,
                                  pattern: schedule?.pattern ?? const [],
                                  shiftColorMap: _shiftColorMap(schedule),
                                  isViewingCurrentRealMonth: _currentMonth.year == DateTime.now().year &&
                                      _currentMonth.month == DateTime.now().month,
                                  onPrevMonth: _goToPreviousMonth,
                                  onNextMonth: _goToNextMonth,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════
// 🎛 여기 숫자들만 바꾸면 셀 크기/글자 크기/여백이 바로 바뀝니다(핫 리로드로
// 바로 확인 가능). 어떤 값이 뭘 조절하는지는 각 줄 옆 주석 참고.
// ═══════════════════════════════════════════════════════════════════════
/// 하루 열 하나의 폭 - 이 값이 클수록 가로 스크롤 없이 한 화면에 보이는
/// 날짜 수가 줄어드는 대신 셀 하나하나는 넉넉해짐(요청: "가로 스크롤을 좀
/// 더 하는 한이 있더라도 글자/셀은 크게").
const double kAllShiftsDayColumnWidth = 40;

/// 좌/우 고정 팀명 열의 폭.
const double kAllShiftsTeamLabelColumnWidth = 20;

/// 날짜+요일 헤더 행의 높이.
const double kAllShiftsHeaderRowHeight = 40;

/// 팀 하나(근무 한 줄)의 행 높이.
const double kAllShiftsTeamRowHeight = 36;

/// 셀과 셀 사이 흰 여백(테두리처럼 보이는 간격) 두께.
const double kAllShiftsCellGap = 1.3;

/// 셀 모서리 둥글기.
const double kAllShiftsCellRadius = 5;

/// 날짜 숫자("1") 글자 크기.
const double kAllShiftsDateNumberFontSize = 14;

/// 요일("월") 글자 크기.
const double kAllShiftsWeekdayFontSize = 11;

/// 좌/우 고정 열의 팀 이름("A") 글자 크기.
const double kAllShiftsTeamLabelFontSize = 14;

/// 근무명(최대 2글자로 잘라 보여줌, 예: "주간") 글자 크기.
const double kAllShiftsShiftTextFontSize = 13;

/// 두 블록(1~15일 / 16~말일) 사이 세로 간격.
const double kAllShiftsBlockGap = 12;

/// ⭐ 2026-09-05 - "팀 로우 타임라인" 기반 재설계(사용자 확정안, 후속 수정
/// 반영).
///
/// 핵심 구조:
/// 1. **두 블록** - 1~15일 / 16~말일. 각 블록은 독립적으로 가로 스크롤됨.
/// 2. **좌우 양쪽 고정 팀명 열** - 스크롤 위치와 무관하게 항상 어느 한쪽
///    팀명 열이 지금 보이는 날짜들과 가까이 있게 함(사용자가 직접 짚어낸
///    지점 - "가로 스크롤로 맨 끝까지 가면 반대쪽 팀명이 바로 옆에 오게").
/// 3. **세로 스크롤은 이 화면 전체(두 블록 다 합친 것) 기준 하나뿐** - 처음엔
///    "블록마다 절반씩 고정 높이 + 그 안에서만 스크롤"로 만들었는데, 그러면
///    조가 4개뿐이어도 항상 절반 높이를 억지로 차지해서 빈 여백이 크게 남는
///    문제가 있었음(사용자 피드백: "지금 남는 여백이 너무 많다"). 이제는
///    셀 크기를 고정해서 넉넉하게 키우고(위 상수들), 두 블록을 딱 필요한
///    만큼의 높이로만 쌓은 뒤 전체를 SingleChildScrollView 하나로 감쌈 -
///    보통(조 4~5개) 화면 하나에 다 들어가고, 6개 이상이면 그 넘치는 만큼만
///    화면 전체가 아래로 스크롤됨("어거지로 한 화면에 다 담지 말고 그냥
///    넘치는 상태로 스크롤" 요청 그대로).
/// 4. **스크롤바는 안 보이게** - 좌/우 팀명 열 덕분에 "이게 스크롤되는
///    영역이다"는 이미 셀 잘림으로 충분히 드러나서, 얇은 회색 막대(Scrollbar)
///    없이 깔끔하게 둠.
///
/// 좌우 팀명 열은 이제 별도 스크롤 동기화가 필요 없음(2차 수정 이전엔 세로
/// 스크롤이 블록 내부에 있어서 Transform.translate로 위치를 맞춰야 했는데,
/// 이제 블록 자체가 고정 높이라 팀명 열도 그냥 평범한 Column 하나로 끝남).
class _MonthShiftTable extends StatefulWidget {
  final int year;
  final int month;
  final int lastDay;
  final List<String> teams;
  final Map<String, int> teamOffsets;
  final DateTime baseDate;
  final List<String> pattern;
  final Map<String, Color> shiftColorMap;
  final bool isViewingCurrentRealMonth;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _MonthShiftTable({
    super.key,
    required this.year,
    required this.month,
    required this.lastDay,
    required this.teams,
    required this.teamOffsets,
    required this.baseDate,
    required this.pattern,
    required this.shiftColorMap,
    required this.isViewingCurrentRealMonth,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  static const int _block2Start = 16;

  @override
  State<_MonthShiftTable> createState() => _MonthShiftTableState();
}

class _MonthShiftTableState extends State<_MonthShiftTable> {
  // ⭐ 2026-09-05 - "오늘 날짜가 바로 보이게" 요청 - 오늘이 속한 블록의 가로
  // 스크롤을 처음부터 오늘 칸 근처로 맞춰서 시작함(initialScrollOffset). 오늘이
  // 아닌 달을 보고 있거나, 오늘이 그 블록 범위 밖이면 그냥 0(맨 앞)에서
  // 시작 - _initialOffsetFor 참고. 스크롤 컨트롤러를 명시적으로 들고 있어야
  // initialScrollOffset을 줄 수 있어서 StatelessWidget에서 StatefulWidget으로
  // 바꿈(dispose 필요).
  late final ScrollController _block1Controller;
  late final ScrollController _block2Controller;

  @override
  void initState() {
    super.initState();
    final hasBlock2 = widget.lastDay >= _MonthShiftTable._block2Start;
    _block1Controller = ScrollController(
      initialScrollOffset: _initialOffsetFor(1, hasBlock2 ? 15 : widget.lastDay),
    );
    _block2Controller = ScrollController(
      initialScrollOffset: hasBlock2 ? _initialOffsetFor(_MonthShiftTable._block2Start, widget.lastDay) : 0,
    );
  }

  @override
  void dispose() {
    _block1Controller.dispose();
    _block2Controller.dispose();
    super.dispose();
  }

  // ⭐ 오늘이 이 블록(start~end) 범위 안에 있으면, 오늘 칸이 화면에 바로
  // 보이도록 그 칸 조금 앞(lookback칸)부터 시작하는 오프셋을 계산 - 오늘
  // 바로 앞 며칠도 같이 보여서 맥락이 좀 남게 함. 범위를 벗어나면(오늘이
  // 그 블록에 없거나, 지금 보고 있는 달이 오늘이 속한 달이 아니면) 0(맨
  // 앞부터).  단위는 칸 폭의 정수배로만 계산 - _SnapToCellScrollPhysics가
  // 기대하는 "항상 칸 경계"와 어긋나지 않게 함. 실제 스크롤 가능 범위를
  // 넘는 값은 SingleChildScrollView가 첫 레이아웃 때 알아서 clamp함.
  double _initialOffsetFor(int start, int end) {
    if (!widget.isViewingCurrentRealMonth) return 0;
    final today = DateTime.now().day;
    if (today < start || today > end) return 0;
    const lookback = 2;
    final todayIndexInBlock = today - start;
    final targetIndex = (todayIndexInBlock - lookback).clamp(0, todayIndexInBlock);
    return targetIndex * kAllShiftsDayColumnWidth.w;
  }

  // 해당 날짜에 해당 조의 근무 타입 계산 - all_shifts_view.dart의
  // _getShiftForTeam과 동일한 공식(오프셋 + 기준일로부터 경과일 → 패턴 인덱스).
  String _shiftFor(String team, DateTime date) {
    if (widget.pattern.isEmpty) return '';
    final daysFromBase = julianDayNumber(date.year, date.month, date.day) -
        julianDayNumber(widget.baseDate.year, widget.baseDate.month, widget.baseDate.day);
    final offset = widget.teamOffsets[team] ?? 0;
    final patternIndex = ((offset + daysFromBase) % widget.pattern.length + widget.pattern.length) % widget.pattern.length;
    return widget.pattern[patternIndex];
  }

  Color _shiftColor(String shift, ColorScheme colorScheme) {
    if (shift.isEmpty) return colorScheme.surfaceVariant;
    return widget.shiftColorMap[shift] ?? colorScheme.surfaceVariant;
  }

  Color _shiftTextColor(String shift, ColorScheme colorScheme) {
    if (shift.isEmpty) return colorScheme.onSurfaceVariant;
    final color = widget.shiftColorMap[shift];
    if (color != null) return ShiftSchedule.getTextColor(color);
    return colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final hasBlock2 = widget.lastDay >= _MonthShiftTable._block2Start;
    final colorScheme = Theme.of(context).colorScheme;
    // ⭐ 화면 전체(두 블록 다 합친 것) 기준 세로 스크롤 하나 - 클래스
    // docstring 3번 참고. 보통은 다 들어가서 스크롤이 아예 안 생김.
    return SingleChildScrollView(
      child: Column(
        children: [
          _dayBlock(context, colorScheme, start: 1, end: hasBlock2 ? 15 : widget.lastDay, controller: _block1Controller),
          if (hasBlock2) ...[
            SizedBox(height: kAllShiftsBlockGap.h),
            _monthNavRow(context, colorScheme),
            SizedBox(height: kAllShiftsBlockGap.h),
            _dayBlock(context, colorScheme,
                start: _MonthShiftTable._block2Start, end: widget.lastDay, controller: _block2Controller),
          ],
        ],
      ),
    );
  }

  // ⭐ 2026-09-05 - 두 블록(1~15일/16~말일) 사이에 넣는 보조 월 이동 바(위쪽
  // 헤더의 화살표는 삭제됨 - 요청, 월 이동은 이제 이 바 하나로만 함).
  // ⭐ 후속 - "이번 달" 버튼은 맨 위 년월 표시 줄의 왼쪽으로 옮김(요청) - 이
  // 자리엔 화살표 두 개만 남고 가운데는 빈 채로 둠.
  Widget _monthNavRow(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, size: 28.sp),
            color: colorScheme.onSurfaceVariant,
            onPressed: widget.onPrevMonth,
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, size: 28.sp),
            color: colorScheme.onSurfaceVariant,
            onPressed: widget.onNextMonth,
          ),
        ],
      ),
    );
  }

  Widget _dayBlock(BuildContext context, ColorScheme colorScheme,
      {required int start, required int end, required ScrollController controller}) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [BoxShadow(color: colorScheme.shadow.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: EdgeInsets.all(4.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _teamLabelColumn(colorScheme),
          Expanded(
            // ⭐ 2026-09-05 - 요청: "가로 스크롤하다가 어중간하게 잘린 날짜
            // 칸이 보이는 게 부자연스럽다, 완전히 다 보이는 날짜까지만
            // 보이게". 두 가지를 같이 적용해야 함:
            //  1) LayoutBuilder로 이 자리가 실제로 받은 폭을 재서, 정확히
            //     "칸 폭(kAllShiftsDayColumnWidth)의 정수배"만큼만 이 영역이
            //     쓰게 함(floor 계산) - 나머지 자투리 폭은 오른쪽 팀명 열
            //     바로 앞의 여백처럼 그냥 비워둠. 이렇게 하면 스크롤을 맨
            //     끝까지 밀어도 오른쪽 끝에서 칸이 잘릴 일이 아예 없음(뷰포트
            //     폭 자체가 칸 폭의 배수라서).
            //  2) 스크롤이 "칸 폭의 배수" 위치에서만 멈추도록
            //     _SnapToCellScrollPhysics를 적용 - 왼쪽 끝도 항상 칸 경계에서
            //     시작하게 됨. 두 조건이 같이 있어야 "왼쪽도 오른쪽도 항상
            //     완전한 칸만 보인다"가 성립함(폭만 맞추면 왼쪽 시작점이
            //     안 맞을 수 있고, snap만 하면 뷰포트 폭이 안 맞아 오른쪽이
            //     잘릴 수 있음).
            // 드래그 도중엔 손가락을 그대로 따라가며 자연스럽게 움직이고,
            // 손을 뗀 순간(관성 멈출 때)만 가장 가까운 칸 경계로 스냅됨 -
            // 흔한 캐러셀/페이지 넘김 UX와 같은 느낌이라 부자연스럽지 않음.
            child: LayoutBuilder(builder: (context, constraints) {
              final cellW = kAllShiftsDayColumnWidth.w;
              final visibleWidth = (constraints.maxWidth / cellW).floor() * cellW;
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: visibleWidth > 0 ? visibleWidth : constraints.maxWidth,
                  // ⭐ 스크롤바 안 보이게(요청) - ScrollConfiguration으로 이
                  // 서브트리에서만 기본 스크롤바 표시를 꺼서, 다른 화면(설정 등
                  // 기본 스크롤바가 필요할 수 있는 곳)에는 영향 없음.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      physics: _SnapToCellScrollPhysics(itemExtent: cellW),
                      child: Column(
                        children: [
                          Row(children: [for (int d = start; d <= end; d++) _dateHeaderCell(context, d, colorScheme)]),
                          for (final team in widget.teams)
                            Row(children: [for (int d = start; d <= end; d++) _shiftCell(team, d, colorScheme)]),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          _teamLabelColumn(colorScheme),
        ],
      ),
    );
  }

  // ⭐ 2026-09-05 - 버그 수정. 여기 팀 라벨을 Container(height:.., margin:..)로
  // 직접 만들었었는데, Container는 margin을 height 지정과 별개로 "바깥쪽에
  // 추가"하는 방식이라(내부적으로 ConstrainedBox(height) 다음에 Padding(margin)이
  // 한 번 더 감쌈) 실제 차지하는 세로 폭이 height+margin*2가 됨. 반면 오른쪽의
  // 근무 칸(_shiftCell)은 SizedBox(height:..)로 감싼 뒤 그 "안에서" Container가
  // margin을 쓰는 방식이라(SizedBox가 준 고정 높이 안에서 margin이 안쪽으로
  // 파고듦) 실제 차지하는 높이가 정확히 height 그대로임 - 두 계산 방식이 서로
  // 달라서 한 줄 내려갈 때마다 margin*2만큼씩 라벨이 계속 밀려 내려갔던 것
  // (A는 거의 안 어긋나 보이다가 아래로 갈수록 누적되어 크게 어긋남). 여기도
  // 오른쪽과 똑같이 SizedBox로 먼저 높이를 고정한 뒤 그 안에서 margin을 쓰도록
  // 맞춰서 매 줄이 정확히 같은 높이를 차지하게 함.
  Widget _teamLabelColumn(ColorScheme colorScheme) {
    return SizedBox(
      width: kAllShiftsTeamLabelColumnWidth.w,
      child: Column(
        children: [
          SizedBox(height: kAllShiftsHeaderRowHeight.h),
          for (final team in widget.teams)
            SizedBox(
              width: double.infinity,
              height: kAllShiftsTeamRowHeight.h,
              child: Container(
                margin: EdgeInsets.all(kAllShiftsCellGap.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(kAllShiftsCellRadius.r)),
                child: Text(
                  team,
                  style: TextStyle(fontSize: kAllShiftsTeamLabelFontSize.sp, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateHeaderCell(BuildContext context, int day, ColorScheme colorScheme) {
    final actualDay = day > widget.lastDay ? widget.lastDay : day;
    final date = DateTime(widget.year, widget.month, actualDay);
    final isToday =
        widget.isViewingCurrentRealMonth && actualDay == DateTime.now().day && date.month == DateTime.now().month;

    return SizedBox(
      width: kAllShiftsDayColumnWidth.w,
      height: kAllShiftsHeaderRowHeight.h,
      child: Container(
        margin: EdgeInsets.all(kAllShiftsCellGap.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isToday ? colorScheme.primary : colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(kAllShiftsCellRadius.r),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: kAllShiftsDateNumberFontSize.sp,
                fontWeight: FontWeight.bold,
                color: isToday ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 1.h),
            Text(
              weekdayLabel(context, weekdayIndexOf(date), narrow: true),
              style: TextStyle(
                fontSize: kAllShiftsWeekdayFontSize.sp,
                color: isToday ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftCell(String team, int day, ColorScheme colorScheme) {
    final actualDay = day > widget.lastDay ? widget.lastDay : day;
    final shift = _shiftFor(team, DateTime(widget.year, widget.month, actualDay));
    // ⭐ 요청: "주 야 휴가 아니라 주간 야간 휴무, 최대 2글자로(앞 두 글자)".
    final displayText = shift.length > 2 ? shift.substring(0, 2) : shift;

    return SizedBox(
      width: kAllShiftsDayColumnWidth.w,
      height: kAllShiftsTeamRowHeight.h,
      child: Container(
        margin: EdgeInsets.all(kAllShiftsCellGap.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _shiftColor(shift, colorScheme), borderRadius: BorderRadius.circular(kAllShiftsCellRadius.r)),
        child: Text(
          displayText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: kAllShiftsShiftTextFontSize.sp, fontWeight: FontWeight.w600, color: _shiftTextColor(shift, colorScheme)),
        ),
      ),
    );
  }
}

/// ⭐ 2026-09-05 - 가로 스크롤이 항상 "칸 폭(itemExtent)의 정수배" 위치에서만
/// 멈추게 하는 물리 - Flutter 프레임워크 자체의 PageScrollPhysics(스크롤을
/// "페이지" 단위로 스냅시키는 그 물리)와 완전히 같은 방식을 그대로 가져오되,
/// "페이지 1장" 대신 "칸 하나(itemExtent 픽셀)" 단위로 스냅하도록 바꾼 것뿐임.
/// 드래그 중엔 평소처럼 손가락을 그대로 따라가고(부자연스러움 없음), 손을
/// 떼서 관성이 멈추려는 지점만 가장 가까운 칸 경계로 보정됨 - _dayBlock의
/// 뷰포트 폭도 칸 폭의 정수배로 맞춰두므로(위 LayoutBuilder 참고), 이 둘이
/// 같이 있어야 "왼쪽도 오른쪽도 항상 완전한 칸만 보인다"가 성립함.
class _SnapToCellScrollPhysics extends ScrollPhysics {
  final double itemExtent;

  const _SnapToCellScrollPhysics({required this.itemExtent, super.parent});

  @override
  _SnapToCellScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SnapToCellScrollPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));
  }

  double _snapTarget(ScrollMetrics position, Tolerance tolerance, double velocity) {
    double cell = position.pixels / itemExtent;
    if (velocity < -tolerance.velocity) {
      cell -= 0.5;
    } else if (velocity > tolerance.velocity) {
      cell += 0.5;
    }
    return cell.round() * itemExtent;
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // 이미 스크롤 범위 밖(양 끝)이고 안쪽으로 되돌아오는 방향이 아니면
    // 평소 물리(오버스크롤 튕김 등)에 그대로 맡김.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = _snapTarget(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => true;
}
