import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 전체 근무표 - 모든 조의 근무를 한눈에 보는 화면
class AllShiftsView extends StatefulWidget {
  const AllShiftsView({super.key});

  @override
  State<AllShiftsView> createState() => _AllShiftsViewState();
}

class _AllShiftsViewState extends State<AllShiftsView> {
  late DateTime _currentMonth;

  // ⭐ 샘플 데이터 (나중에 실제 로직으로 교체)
  final List<String> _teams = ['A', 'B', 'C', 'D'];

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

  // 각 조의 시작 오프셋 (2일씩 차이)
  final Map<String, int> _teamOffsets = {
    'A': 0,
    'B': 2,
    'C': 4,
    'D': 6,
  };

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
  }

  // 해당 날짜에 해당 조의 근무 타입 계산
  String _getShiftForTeam(String team, DateTime date) {
    // 기준일 (2025년 1월 1일이 A조 주간 첫째날이라고 가정)
    final baseDate = DateTime(2025, 1, 1);
    final daysDiff = date.difference(baseDate).inDays;
    final offset = _teamOffsets[team] ?? 0;
    final patternIndex = (daysDiff + offset) % _shiftPattern.length;
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
      body: SafeArea(
        child: Column(
          children: [
            // ⭐ 년월 표시 (중앙)
            Container(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              color: Colors.white,
              alignment: Alignment.center,
              child: Text(
                '${year.toString().substring(2)}.${month.toString().padLeft(2, '0')}',
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: _buildShiftTable(year, month, lastDay),
                ),
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
            0: FixedColumnWidth(24.w), // 조 이름 열 너비 (축소)
            // 나머지 열들은 균등 분배 (최대 11개: 21~31일)
            for (int i = 1; i <= 11; i++) i: FlexColumnWidth(1),
          },
          children: [
            // ⭐ 첫 번째 헤더 행: 1 | 2 | ... | 10
            _buildDateHeaderRow(year, month, 1, 10),

            // ⭐ A~D조 1~10일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 1, 10),

            // ⭐ 두 번째 헤더 행: 11 | 12 | ... | 20
            _buildDateHeaderRow(year, month, 11, 20),

            // ⭐ A~D조 11~20일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 11, 20),

            // ⭐ 세 번째 헤더 행: 21 | 22 | ... | 말일
            _buildDateHeaderRow(year, month, 21, lastDay),

            // ⭐ A~D조 21~말일 근무
            for (var team in _teams)
              _buildTeamRow(team, year, month, 21, lastDay),
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
    int endDay,
  ) {
    // 현재 줄의 날짜 개수
    final dayCount = endDay - startDay + 1;

    return TableRow(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
      ),
      children: [
        // 좌측 빈 셀
        Container(
          height: 44.h, // 헤더 행 높이
          alignment: Alignment.center,
        ),
        // 날짜 셀들
        for (int day = startDay; day <= endDay; day++)
          Container(
            height: 44.h, // 헤더 행 높이
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 11.sp, // 날짜 숫자 (더 크게)
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _getWeekdayChar(DateTime(year, month, day)),
                  style: TextStyle(
                    fontSize: 9.sp, // 요일 (더 크게)
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        // 빈 셀 채우기 (11개 맞추기 위해)
        for (int i = 0; i < 11 - dayCount; i++)
          Container(
            height: 44.h,
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
  ) {
    // 현재 줄의 날짜 개수
    final dayCount = endDay - startDay + 1;

    return TableRow(
      children: [
        // 조 이름 셀
        Container(
          height: 42.h, // 근무 행 높이
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
          ),
          child: Text(
            team,
            style: TextStyle(
              fontSize: 10.sp, // 조 이름
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ),
        // 각 날짜별 근무 셀
        for (int day = startDay; day <= endDay; day++)
          _buildShiftCell(team, DateTime(year, month, day)),
        // 빈 셀 채우기 (11개 맞추기 위해)
        for (int i = 0; i < 11 - dayCount; i++)
          Container(
            height: 42.h,
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
      height: 42.h, // 근무 행 높이
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _getShiftColor(shift),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 11.sp, // 근무명 텍스트 (더 크게)
          fontWeight: FontWeight.w600,
          color: _getShiftTextColor(shift),
        ),
      ),
    );
  }
}
