import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 전체 근무표 - 모든 조의 근무를 한눈에 보는 화면
class AllShiftsView extends StatefulWidget {
  const AllShiftsView({super.key});

  @override
  State<AllShiftsView> createState() => _AllShiftsViewState();
}

class _AllShiftsViewState extends State<AllShiftsView> {
  late DateTime _currentMonth;
  bool _isLoading = true;

  // ⭐ 저장된 데이터 또는 기본값
  List<String> _teams = ['A', 'B', 'C', 'D'];

  // ⭐ 8일 주기 패턴: 주간-주간-휴무-휴무-야간-야간-휴무-휴무
  final List<String> _shiftPattern = [
    '주간',
    '주간',
    '휴무',
    '휴무',
    '야간',
    '야간',
    '휴무',
    '휴무',
  ];

  // 각 조의 시작 오프셋
  Map<String, int> _teamOffsets = {
    'A': 0,
    'B': 2,
    'C': 4,
    'D': 6,
  };

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
    _loadTeamData();
  }

  // ⭐ SharedPreferences에서 팀 데이터 로드
  Future<void> _loadTeamData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 저장된 조 이름 가져오기
      final savedTeams = prefs.getStringList('all_teams_names');
      if (savedTeams != null && savedTeams.isNotEmpty) {
        _teams = savedTeams;
      }

      // 저장된 인덱스 가져오기
      final indicesJson = prefs.getString('all_teams_indices');
      if (indicesJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(indicesJson);
        _teamOffsets = decoded.map((key, value) =>
          MapEntry(key, int.parse(value.toString()))
        );
      }

      print('✅ 전체 근무표 데이터 로드 완료:');
      print('  - 조 목록: $_teams');
      print('  - 인덱스: $_teamOffsets');
    } catch (e) {
      print('⚠️ 데이터 로드 실패, 기본값 사용: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 해당 날짜에 해당 조의 근무 타입 계산
  String _getShiftForTeam(String team, DateTime date) {
    // 오늘 날짜 기준
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    // 오늘부터 대상 날짜까지의 일수 차이
    final daysDiff = targetDate.difference(todayDate).inDays;

    // 이 조의 오늘 인덱스 (1~8)
    final todayIndex = _teamOffsets[team] ?? 1;

    // 대상 날짜의 인덱스 계산: (오늘 인덱스 - 1 + 날짜차이) % 패턴길이
    final patternIndex = ((todayIndex - 1 + daysDiff) % _shiftPattern.length + _shiftPattern.length) % _shiftPattern.length;

    return _shiftPattern[patternIndex];
  }

  // 근무 타입별 배경색
  Color _getShiftColor(String shift) {
    if (shift.contains('주간')) {
      return Colors.blue.shade100;
    } else if (shift.contains('야간')) {
      return Colors.purple.shade100;
    } else if (shift.contains('휴무')) {
      return Colors.red.shade100;
    }
    return Colors.grey.shade100;
  }

  // 근무 타입별 텍스트 색상
  Color _getShiftTextColor(String shift) {
    if (shift.contains('주간')) {
      return Colors.blue.shade800;
    } else if (shift.contains('야간')) {
      return Colors.purple.shade800;
    } else if (shift.contains('휴무')) {
      return Colors.red.shade800;
    }
    return Colors.grey.shade800;
  }

  // 해당 날짜의 요일 문자
  String _getWeekdayChar(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final lastDay = DateTime(year, month + 1, 0).day;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('전체 근무표'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(),
            )
          : SafeArea(
              child: Column(
                children: [
                  // ⭐ 년월 표시 (중앙)
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: Text(
                      '$year년 $month월',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade300),
                  // ⭐ 메인 테이블
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      child: _buildShiftTable(year, month, lastDay),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildShiftTable(int year, int month, int lastDay) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: Table(
          border: TableBorder.all(
            color: Colors.grey.shade300,
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
              _buildTeamRow(team, year, month, 1, 11, maxColumns: 11),

            // ⭐ 두 번째 헤더 행: 12 | 13 | ... | 22 (11개)
            _buildDateHeaderRow(year, month, 12, 22, maxColumns: 11),

            // ⭐ A~D조 12~22일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 12, 22, maxColumns: 11),

            // ⭐ 세 번째 헤더 행: 23 | 24 | ... | 31 (9개, 하드코딩)
            _buildDateHeaderRow(year, month, 23, 31, maxColumns: 11),

            // ⭐ A~D조 23~31일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 23, 31, maxColumns: 11),
          ],
        ),
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

    return TableRow(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
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
              final isToday = year == today.year && month == today.month && day == today.day;
              return Container(
                height: 36.h, // 헤더 행 높이 (줄임)
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: Colors.purple.shade50,
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
                        color: isToday ? Colors.purple : Colors.black87,
                      ),
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      _getWeekdayChar(DateTime(year, month, day > (DateTime(year, month + 1, 0).day) ? DateTime(year, month + 1, 0).day : day)),
                      style: TextStyle(
                        fontSize: 8.sp, // 요일
                        color: isToday ? Colors.purple : Colors.grey.shade600,
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
    int endDay, {
    required int maxColumns,
  }) {
    // 현재 줄의 날짜 개수
    final dayCount = endDay - startDay + 1;
    final actualLastDay = DateTime(year, month + 1, 0).day;

    return TableRow(
      children: [
        // 조 이름 셀
        Container(
          height: 34.h, // 근무 행 높이 (줄임)
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
          ),
          child: Text(
            team,
            style: TextStyle(
              fontSize: 9.sp, // 조 이름 (줄임)
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ),
        // 각 날짜별 근무 셀
        for (int day = startDay; day <= endDay; day++)
          _buildShiftCell(team, DateTime(year, month, day > actualLastDay ? actualLastDay : day)),
        // 빈 셀 채우기 (maxColumns 맞추기 위해)
        for (int i = 0; i < maxColumns - dayCount; i++)
          Container(
            height: 34.h,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
            ),
          ),
      ],
    );
  }

  // 근무 셀 생성
  Widget _buildShiftCell(String team, DateTime date) {
    final shift = _getShiftForTeam(team, date);
    // 근무명이 4자까지 허용되지만 전체 근무표에서는 앞 2자만 표시
    final displayText = shift.length > 2 ? shift.substring(0, 2) : shift;

    return Container(
      height: 34.h, // 근무 행 높이 (줄임)
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _getShiftColor(shift),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 10.sp, // 근무명 텍스트
          fontWeight: FontWeight.w600,
          color: _getShiftTextColor(shift),
        ),
      ),
    );
  }
}
