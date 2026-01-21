import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../models/shift_schedule.dart';
import 'all_teams_setup_dialog.dart';

/// 전체 근무표 - 모든 조의 근무를 한눈에 보는 화면
class AllShiftsView extends ConsumerStatefulWidget {
  const AllShiftsView({super.key});

  @override
  ConsumerState<AllShiftsView> createState() => _AllShiftsViewState();
}

class _AllShiftsViewState extends ConsumerState<AllShiftsView> {
  late PageController _pageController;
  late DateTime _currentMonth;
  bool _isLoading = true;
  bool _isConfigured = false; // ⭐ 전체 교대조 근무표 설정 여부

  // ⭐ PageView용 초기 인덱스 (과거 100년 ~ 미래 100년)
  static const int _initialPage = 1200; // 100년 * 12개월

  // ⭐ 저장된 데이터
  List<String> _teams = ['A', 'B', 'C', 'D'];

  // ⭐ 각 조의 오늘 인덱스 (1~8)
  Map<String, int> _teamOffsets = {
    'A': 1,
    'B': 3,
    'C': 5,
    'D': 7,
  };

  // ⭐ CRITICAL FIX: 기준 날짜 (패턴 밀림 방지)
  DateTime? _referenceDate;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
    _pageController = PageController(initialPage: _initialPage);
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

      // 저장된 인덱스 가져오기
      if (_isConfigured) {
        final indicesJson = prefs.getString('all_teams_indices');
        if (indicesJson != null) {
          final Map<String, dynamic> decoded = jsonDecode(indicesJson);
          _teamOffsets = decoded.map((key, value) =>
            MapEntry(key, int.parse(value.toString()))
          );
        }

        // ⭐ CRITICAL FIX: 기준 날짜 로드
        final referenceDateStr = prefs.getString('all_teams_reference_date');
        if (referenceDateStr != null) {
          try {
            _referenceDate = DateTime.parse(referenceDateStr);
          } catch (e) {
            print('⚠️ 기준 날짜 파싱 실패: $e');
            _referenceDate = DateTime.now(); // 폴백: 오늘
          }
        } else {
          print('⚠️ 기준 날짜 없음 - 오늘로 설정 (이전 버전 호환)');
          _referenceDate = DateTime.now();
        }

        print('✅ 전체 근무표 데이터 로드 완료:');
        print('  - 조 목록: $_teams');
        print('  - 인덱스: $_teamOffsets');
        print('  - 기준 날짜: ${_referenceDate?.toIso8601String()}');
      } else {
        print('⚠️ 전체 교대조 근무표가 설정되지 않았습니다.');
      }
    } catch (e) {
      print('⚠️ 데이터 로드 실패: $e');
      _isConfigured = false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ⭐ 전체 교대조 근무표 작성 다이얼로그 표시
  Future<void> _showAllTeamsSetupDialog() async {
    final schedule = ref.read(scheduleProvider).value;

    // 규칙적 근무자만 사용 가능
    if (schedule == null || !schedule.isRegular || schedule.pattern == null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('전체 교대조 근무표 작성'),
          content: Text('이 기능은 규칙적 근무 패턴이 설정된 경우에만 사용할 수 있습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;

    // 다이얼로그 표시
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AllTeamsSetupDialog(
        pattern: schedule.pattern!,
        onComplete: () {
          // ⭐ 완료 후 데이터 새로고침
          _loadTeamData();
        },
      ),
    );
  }

  // 해당 날짜에 해당 조의 근무 타입 계산
  String _getShiftForTeam(String team, DateTime date, List<String> pattern) {
    if (pattern.isEmpty) return '';

    // ⭐ CRITICAL FIX: 기준 날짜 사용 (설정 시점 날짜)
    if (_referenceDate == null) {
      print('⚠️ 기준 날짜 없음 - 빈 문자열 반환');
      return '';
    }

    final referenceDate = DateTime(_referenceDate!.year, _referenceDate!.month, _referenceDate!.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    // 기준 날짜부터 대상 날짜까지의 일수 차이
    final daysDiff = targetDate.difference(referenceDate).inDays;

    // 이 조의 기준 날짜 인덱스 (1~8)
    final todayIndex = _teamOffsets[team] ?? 1;

    // 대상 날짜의 인덱스 계산: (기준 인덱스 - 1 + 날짜차이) % 패턴길이
    final patternIndex = ((todayIndex - 1 + daysDiff) % pattern.length + pattern.length) % pattern.length;

    return pattern[patternIndex];
  }

  // 근무 타입별 배경색 (calendar_tab과 동일한 로직)
  Color _getShiftColor(String shift, ShiftSchedule? schedule, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (shift.isEmpty) return colorScheme.surfaceVariant;

    final colorValue = schedule?.shiftColors?[shift];

    if (colorValue != null) {
      return Color(colorValue);
    }

    return colorScheme.surfaceVariant;
  }

  // 근무 타입별 텍스트 색상 (calendar_tab과 동일한 로직)
  Color _getShiftTextColor(String shift, ShiftSchedule? schedule, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (shift.isEmpty) return colorScheme.onSurfaceVariant;

    final colorValue = schedule?.shiftColors?[shift];

    if (colorValue != null) {
      final bgColor = Color(colorValue);
      return ShiftSchedule.getTextColor(bgColor);
    }

    return colorScheme.onSurfaceVariant;
  }

  // 해당 날짜의 요일 문자
  String _getWeekdayChar(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ schedule 가져오기
    final scheduleAsync = ref.watch(scheduleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('전체 근무표'),
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
                          '전체 교대조 근무표가\n설정되지 않았습니다',
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
                          onPressed: () => _showAllTeamsSetupDialog(),
                          icon: Icon(Icons.add_circle_outline, size: 22.sp),
                          label: Text('전체 교대조 근무표 만들기', style: TextStyle(fontSize: 16.sp)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('돌아가기', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15.sp)),
                        ),
                      ],
                    ),
                  ),
                )
              : scheduleAsync.when(
                  loading: () => Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('에러 발생: $error')),
                  data: (schedule) => SafeArea(
                    child: Column(
                      children: [
                        // ⭐ 년월 표시 (좌우 화살표 포함)
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          color: colorScheme.surface,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left),
                                onPressed: () {
                                  _pageController.previousPage(
                                    duration: Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                              ),
                              Text(
                                '${_currentMonth.year}년 ${_currentMonth.month}월',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.chevron_right),
                                onPressed: () {
                                  _pageController.nextPage(
                                    duration: Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: colorScheme.outline),
                        // ⭐ PageView로 여러 달 표시
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
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

                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                child: _buildShiftTable(year, month, lastDay, schedule),
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

  Widget _buildShiftTable(int year, int month, int lastDay, ShiftSchedule? schedule) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Table(
        border: TableBorder.all(
          color: colorScheme.outline,
          width: 0.5,
        ),
          columnWidths: {
            0: FixedColumnWidth(22.w), // 조 이름 열 너비 (더 축소)
            // 나머지 열들은 균등 분배 (최대 11개)
            for (int i = 1; i <= 11; i++) i: FlexColumnWidth(1),
          },
          children: [
            // ⭐ 첫 번째 헤더 행: 1 | 2 | ... | 11 (11개)
            _buildDateHeaderRow(year, month, 1, 11, maxColumns: 11),

            // ⭐ A~D조 1~11일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 1, 11, schedule, maxColumns: 11),

            // ⭐ 두 번째 헤더 행: 12 | 13 | ... | 22 (11개)
            _buildDateHeaderRow(year, month, 12, 22, maxColumns: 11),

            // ⭐ A~D조 12~22일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 12, 22, schedule, maxColumns: 11),

            // ⭐ 세 번째 헤더 행: 23 | 24 | ... | lastDay (실제 마지막 날까지)
            _buildDateHeaderRow(year, month, 23, lastDay, maxColumns: 11),

            // ⭐ A~D조 23~lastDay일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 23, lastDay, schedule, maxColumns: 11),
          ],
        ),
    );
  }

  // 날짜 헤더 행 생성
  TableRow _buildDateHeaderRow(
    int year,
    int month,
    int startDay,
    int endDay, {
    required int maxColumns,
  }) {
    // 현재 줄의 날짜 개수
    final dayCount = endDay - startDay + 1;
    final today = DateTime.now();
    final colorScheme = Theme.of(context).colorScheme;

    return TableRow(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
      ),
      children: [
        // 좌측 빈 셀
        Container(
          height: 36.h, // 헤더 행 높이 (줄임)
          alignment: Alignment.center,
        ),
        // 날짜 셀들
        for (int day = startDay; day <= endDay; day++)
          Builder(
            builder: (context) {
              // ⭐ 오늘이면서 현재 보고 있는 달과 같을 때만 강조
              final isToday = year == today.year &&
                             month == today.month &&
                             day == today.day &&
                             _currentMonth.year == today.year &&
                             _currentMonth.month == today.month;
              return Container(
                height: 36.h, // 헤더 행 높이 (줄임)
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: colorScheme.primary,  // 진한 인디고 배경
                      )
                    : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 10.sp, // 날짜 숫자
                        fontWeight: FontWeight.bold,
                        color: isToday ? colorScheme.onPrimary : colorScheme.onSurface,  // 흰색 글씨
                      ),
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      _getWeekdayChar(DateTime(year, month, day > (DateTime(year, month + 1, 0).day) ? DateTime(year, month + 1, 0).day : day)),
                      style: TextStyle(
                        fontSize: 8.sp, // 요일
                        color: isToday ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,  // 흰색 글씨
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        // 빈 셀 채우기 (maxColumns 맞추기 위해)
        for (int i = 0; i < maxColumns - dayCount; i++)
          Container(
            height: 36.h,
          ),
      ],
    );
  }

  // 조별 근무 행 생성
  TableRow _buildTeamRow(
    String team,
    int year,
    int month,
    int startDay,
    int endDay,
    ShiftSchedule? schedule, {
    required int maxColumns,
  }) {
    // 현재 줄의 날짜 개수
    final dayCount = endDay - startDay + 1;
    final actualLastDay = DateTime(year, month + 1, 0).day;
    final colorScheme = Theme.of(context).colorScheme;

    return TableRow(
      children: [
        // 조 이름 셀
        Container(
          height: 34.h, // 근무 행 높이 (줄임)
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
          ),
          child: Text(
            team,
            style: TextStyle(
              fontSize: 9.sp, // 조 이름 (줄임)
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
        // 각 날짜별 근무 셀
        for (int day = startDay; day <= endDay; day++)
          _buildShiftCell(team, DateTime(year, month, day > actualLastDay ? actualLastDay : day), schedule),
        // 빈 셀 채우기 (maxColumns 맞추기 위해)
        for (int i = 0; i < maxColumns - dayCount; i++)
          Container(
            height: 34.h,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
            ),
          ),
      ],
    );
  }

  // 근무 셀 생성
  Widget _buildShiftCell(String team, DateTime date, ShiftSchedule? schedule) {
    // ⭐ schedule의 pattern 사용 (근무명 수정이 반영됨)
    final pattern = schedule?.pattern ?? [];
    final shift = _getShiftForTeam(team, date, pattern);
    // 근무명이 4자까지 허용되지만 전체 근무표에서는 앞 2자만 표시
    final displayText = shift.length > 2 ? shift.substring(0, 2) : shift;

    return Container(
      height: 34.h, // 근무 행 높이 (줄임)
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _getShiftColor(shift, schedule, context),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 10.sp, // 근무명 텍스트
          fontWeight: FontWeight.w600,
          color: _getShiftTextColor(shift, schedule, context),
        ),
      ),
    );
  }
}
