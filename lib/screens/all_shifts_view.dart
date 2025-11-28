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
  int _pageIndex = 0; // 0: 1~15일, 1: 16~말일

  // ⭐ 샘플 데이터 (나중에 실제 로직으로 교체)
  final List<String> _teams = ['A', 'B', 'C', 'D'];

  // 각 조의 패턴 (주간→야간→휴무→휴무 순환)
  final List<String> _shiftPattern = ['주간', '야간', '휴무', '휴무'];

  // 각 조의 시작 오프셋 (A=0, B=1, C=2, D=3)
  final Map<String, int> _teamOffsets = {
    'A': 0,
    'B': 1,
    'C': 2,
    'D': 3,
  };

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
  }

  // 해당 날짜의 요일 문자
  String _getWeekdayChar(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  // 해당 날짜에 해당 조의 근무 타입 계산
  String _getShiftForTeam(String team, DateTime date) {
    // 기준일 (2025년 1월 1일이 A조 주간 시작이라고 가정)
    final baseDate = DateTime(2025, 1, 1);
    final daysDiff = date.difference(baseDate).inDays;
    final offset = _teamOffsets[team] ?? 0;
    final patternIndex = (daysDiff + offset) % _shiftPattern.length;
    return _shiftPattern[patternIndex];
  }

  // 근무 타입별 배경색
  Color _getShiftColor(String shift) {
    switch (shift) {
      case '주간':
        return Colors.blue.shade100;
      case '야간':
        return Colors.purple.shade100;
      case '휴무':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  // 근무 타입별 텍스트 색상
  Color _getShiftTextColor(String shift) {
    switch (shift) {
      case '주간':
        return Colors.blue.shade800;
      case '야간':
        return Colors.purple.shade800;
      case '휴무':
        return Colors.red.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  // 현재 페이지의 날짜 범위 계산
  List<DateTime> _getDatesForCurrentPage() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final lastDay = DateTime(year, month + 1, 0).day;

    List<DateTime> dates = [];

    if (_pageIndex == 0) {
      // 1~15일
      for (int i = 1; i <= 15; i++) {
        dates.add(DateTime(year, month, i));
      }
    } else {
      // 16~말일
      for (int i = 16; i <= lastDay; i++) {
        dates.add(DateTime(year, month, i));
      }
    }

    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final dates = _getDatesForCurrentPage();
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final maxPages = lastDay > 15 ? 2 : 1;

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
            // ⭐ 년월 + 페이지 네비게이션
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 이전 달
                  IconButton(
                    icon: Icon(Icons.chevron_left, size: 28.sp),
                    onPressed: () {
                      setState(() {
                        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
                        _pageIndex = 0;
                      });
                    },
                  ),
                  // 년월 표시
                  GestureDetector(
                    onTap: () {
                      // TODO: 월 선택 다이얼로그
                    },
                    child: Text(
                      '${_currentMonth.year}.${_currentMonth.month.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 다음 달
                  IconButton(
                    icon: Icon(Icons.chevron_right, size: 28.sp),
                    onPressed: () {
                      setState(() {
                        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
                        _pageIndex = 0;
                      });
                    },
                  ),
                ],
              ),
            ),

            // ⭐ 페이지 인디케이터 (1~15 / 16~말일)
            Container(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPageButton(0, '1~15일'),
                  SizedBox(width: 12.w),
                  if (maxPages > 1) _buildPageButton(1, '16~${lastDay}일'),
                ],
              ),
            ),

            Divider(height: 1, color: Colors.grey.shade300),

            // ⭐ 메인 테이블
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: _buildShiftTable(dates),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageButton(int index, String label) {
    final isSelected = _pageIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _pageIndex = index;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildShiftTable(List<DateTime> dates) {
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
            0: FixedColumnWidth(40.w), // 조 이름 열
            // 나머지는 균등 분배
            for (int i = 1; i <= dates.length; i++)
              i: FlexColumnWidth(1),
          },
          children: [
            // ⭐ 헤더 행 (날짜/요일)
            TableRow(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
              ),
              children: [
                // 좌상단 빈 셀
                _buildHeaderCell(''),
                // 날짜 헤더들
                ...dates.map((date) => _buildDateHeaderCell(date)),
              ],
            ),
            // ⭐ 각 조별 행
            ..._teams.map((team) => _buildTeamRow(team, dates)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      height: 44.h,
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDateHeaderCell(DateTime date) {
    final isWeekend = date.weekday == 6 || date.weekday == 7;
    final isSaturday = date.weekday == 6;
    final isSunday = date.weekday == 7;

    return Container(
      height: 44.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSunday
            ? Colors.red.shade50
            : isSaturday
                ? Colors.blue.shade50
                : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              color: isSunday
                  ? Colors.red
                  : isSaturday
                      ? Colors.blue
                      : Colors.black,
            ),
          ),
          Text(
            _getWeekdayChar(date),
            style: TextStyle(
              fontSize: 10.sp,
              color: isSunday
                  ? Colors.red.shade400
                  : isSaturday
                      ? Colors.blue.shade400
                      : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTeamRow(String team, List<DateTime> dates) {
    return TableRow(
      children: [
        // 조 이름 셀
        Container(
          height: 48.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
          ),
          child: Text(
            '$team조',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ),
        // 각 날짜별 근무
        ...dates.map((date) {
          final shift = _getShiftForTeam(team, date);
          return _buildShiftCell(shift);
        }),
      ],
    );
  }

  Widget _buildShiftCell(String shift) {
    return Container(
      height: 48.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _getShiftColor(shift),
      ),
      child: Text(
        shift,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: _getShiftTextColor(shift),
        ),
      ),
    );
  }
}
