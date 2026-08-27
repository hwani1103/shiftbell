// lib/screens/schedule_management_tab.dart
//
// ⭐ 2026-08-25 추가, 같은 날 다섯 번째 재작업 - "일정관리" 탭.
//
// 헤더(연/월/일/요일 텍스트 + 근무명 칩, ◀▶ 월 이동)는 이전 라운드에서
// 확정됨("이 부분은 마음에 든다") - 그대로 유지.
//
// ⭐ 다섯 번째 재작업(가장 큰 전환) - "+ 버튼 → 편집모드 → 빈 시간대 탭-탭"
// 방식은 다시 갈아엎음. 이번엔 완전히 다른 인터랙션을 시험함:
//  - 편집모드 토글(연필 아이콘) 자체를 없앰 - 아래 방식은 상시 사용 가능.
//  - 세로 시간축을 화면 "가로 중앙"으로 옮기고, 축을 따라 스크롤 가능(00:00~
//    24:00, 지금까지와 동일). 정각(00,01,...24)은 숫자로, 30분 단위는 눈금
//    (선)만 표시 - 30분도 선택은 가능하지만 라벨은 안 보여줌.
//  - 화면 "정중앙"에 고정된 인디케이터를 하나 둠(스크롤해도 화면상 위치는
//    안 움직임) - 축을 스크롤하면 인디케이터가 가리키는 시각만 바뀜(예: 축이
//    00~06시가 보이게 스크롤돼 있으면 인디케이터는 대략 03시 근처를 가리킴).
//    인디케이터는 30분 단위로만 멈춤(스크롤이 끝나면 가장 가까운 30분으로
//    스냅). 스크롤이 멈추는 순간 = 그 시각이 "선택된 시작 시간" → 확인
//    팝업을 띄움(barrier 탭하면 닫히고 다시 시도 가능).
//  - 인디케이터 디자인: 앱 아이콘(원형으로 잘라냄)에 왼쪽으로 향하는 작은
//    화살표(부리)를 붙여서, 그 부리 끝이 정확히 축의 눈금을 가리키게 함.
//    위치는 일단 축의 우측.
//  - 지금 단계에선 "일정 목록/카드"는 아직 안 만듦 - 시간축 + 인디케이터 +
//    확인 팝업까지만. 실제로 일정을 만들어 저장하는 건 다음 단계.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/calendar_theme.dart';
import '../models/date_schedule.dart';
import '../models/shift_schedule.dart';
import '../providers/calendar_theme_provider.dart';
import '../providers/date_schedule_provider.dart';
import '../providers/schedule_background_provider.dart';
import '../providers/schedule_provider.dart';
import '../services/memo_category_classifier.dart';
import '../theme/app_colors.dart';

// ⭐ 2026-08-27(2차) - "배경색 설정을 만들면 그거 따라서 텍스트/영역 색도
// 전부 유동적으로" 요청으로, 예전엔 흰 배경 전용 고정값이었던
// kScheduleTimeNumberColor를 이 클래스로 대체함. 선택된 배경 하나로부터
// 헤더/날짜스트립/칩/시간텍스트/내용텍스트 색을 전부 계산해서 뽑아냄 -
// 10개 프리셋마다 색을 일일이 하드코딩하지 않고, 밝기(luminance) 기준으로
// 일관되게 파생시키는 방식(그래야 나중에 배경 프리셋이 늘어나도 자동으로
// 대응됨). 예외(요청): 근무명 칩(_ShiftPill)과 그 안의 색깔 점은 이 스킴과
// 무관하게 항상 고정 - 여기서 만든 색은 그 두 곳엔 아예 안 씀.
class _ScheduleColorScheme {
  final Color mainBg; // 일정 타임라인 영역 + 날짜칩/설정칩의 배경(선택한 색 그대로)
  final Color headerBg; // 헤더(연월일)~날짜스트립 영역 배경(mainBg와 톤만 다름)
  final Color headerText; // 헤더 텍스트/아이콘(연월일, ◀▶, 날짜숫자, 톱니바퀴)
  final Color chipBorder; // 날짜칩/설정칩 테두리
  final Color chipShadowDark; // 칩의 살짝 튀어나온 입체감(3·6시 방향) - 그림자쪽
  final Color chipShadowLight; // 칩의 입체감 - 반대쪽 하이라이트
  final Color timeText; // 축 시간 숫자 + 일정의 시작~끝 시간 텍스트(연한 대비)
  final Color contentText; // 일정 내용 텍스트(진한 대비)

  const _ScheduleColorScheme({
    required this.mainBg,
    required this.headerBg,
    required this.headerText,
    required this.chipBorder,
    required this.chipShadowDark,
    required this.chipShadowLight,
    required this.timeText,
    required this.contentText,
  });

  factory _ScheduleColorScheme.of(Color bg) {
    final isDark = bg.computeLuminance() < 0.5;
    final headerBg = isDark
        ? Color.lerp(bg, Colors.white, 0.16)!
        : Color.lerp(bg, Colors.black, 0.045)!;
    final headerText = isDark
        ? Color.lerp(Colors.white, Colors.black, 0.10)!
        : Color.lerp(Colors.black, Colors.white, 0.22)!;
    final chipBorder = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.12);
    final chipShadowDark = isDark
        ? Colors.black.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.18);
    final chipShadowLight = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.7);
    final timeText = isDark
        ? Color.lerp(Colors.white, bg, 0.30)!
        : Color.lerp(Colors.black, bg, 0.40)!;
    final contentText = isDark
        ? Color.lerp(Colors.white, bg, 0.06)!
        : Color.lerp(Colors.black, bg, 0.06)!;
    return _ScheduleColorScheme(
      mainBg: bg,
      headerBg: headerBg,
      headerText: headerText,
      chipBorder: chipBorder,
      chipShadowDark: chipShadowDark,
      chipShadowLight: chipShadowLight,
      timeText: timeText,
      contentText: contentText,
    );
  }
}

// ⭐ 날짜칩/설정칩 공용 데코레이션 - "두 칩은 디자인적으로 100% 동일해야
// 함" 요청이라 아예 함수 하나로 묶어서 두 군데서 부르는 값이 절대 어긋날 수
// 없게 함. 테두리 + 살짝 튀어나온(3·6시 방향 오프셋 그림자) 입체감을 줌.
BoxDecoration _scheduleChipDecoration(_ScheduleColorScheme scheme) {
  return BoxDecoration(
    color: scheme.mainBg,
    borderRadius: BorderRadius.circular(11.r),
    border: Border.all(color: scheme.chipBorder, width: 1),
    boxShadow: [
      BoxShadow(
        color: scheme.chipShadowDark,
        offset: Offset((1.3 * 7 / 8).w, (1.3 * 7 / 8).h),
        blurRadius: (1.5 * 7 / 8).r,
      ),
      BoxShadow(
        color: scheme.chipShadowLight,
        offset: Offset(-(1 * 7 / 8).w, -(1 * 7 / 8).h),
        blurRadius: (1 * 7 / 8).r,
      ),
    ],
  );
}

class ScheduleManagementTab extends ConsumerStatefulWidget {
  final VoidCallback? onSwipeToCalendar;
  const ScheduleManagementTab({super.key, this.onSwipeToCalendar});

  @override
  ConsumerState<ScheduleManagementTab> createState() =>
      _ScheduleManagementTabState();
}

class _ScheduleManagementTabState extends ConsumerState<ScheduleManagementTab> {
  late DateTime _selectedDate;
  final ScrollController _dateStripController = ScrollController();
  // ⭐ 2026-08-27 - 인디케이터를 드래그하는 동안은 이 화면 전체를 덮는
  // onHorizontalDragEnd(달력 탭으로 스와이프)와 제스처 아레나에서 경합해서,
  // 세로 드래그 중 살짝만 가로로 틀어져도 인디케이터 쪽이 취소돼버리는
  // 문제가 있었음(요청: "세로축을 조금만 벗어나도 선택이 해제됨"). 드래그
  // 활성 중엔 이 가로 스와이프 자체를 꺼서 경합을 없앰 - _TimeAxisPicker가
  // onIndicatorDragActiveChanged로 알려줌.
  bool _indicatorDragActive = false;

  static const double _dateChipWidth = 36;
  static const double _dateChipHeight = 34;
  static const double _dateChipGap = 6;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollDateStripToSelected(animate: false));
  }

  @override
  void dispose() {
    _dateStripController.dispose();
    super.dispose();
  }

  void _scrollDateStripToSelected({bool animate = true}) {
    if (!_dateStripController.hasClients) return;
    final index = _selectedDate.day - 1;
    final itemExtent = _dateChipWidth.w + _dateChipGap.w;
    final target = (index * itemExtent - 90.w)
        .clamp(0.0, _dateStripController.position.maxScrollExtent);
    if (animate) {
      _dateStripController.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _dateStripController.jumpTo(target);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      final firstOfNewMonth =
          DateTime(_selectedDate.year, _selectedDate.month + delta, 1);
      final daysInNewMonth =
          DateUtils.getDaysInMonth(firstOfNewMonth.year, firstOfNewMonth.month);
      final clampedDay = _selectedDate.day.clamp(1, daysInNewMonth);
      _selectedDate =
          DateTime(firstOfNewMonth.year, firstOfNewMonth.month, clampedDay);
    });
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollDateStripToSelected(animate: false));
  }

  String _intlLocale(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko' ? 'ko_KR' : 'en_US';

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateUtils.getDaysInMonth(_selectedDate.year, _selectedDate.month);
    final schedule = ref.watch(scheduleProvider).value;
    final themeId = ref.watch(calendarThemeProvider);
    final shiftColors = schedule == null
        ? const <String, Color>{}
        : effectiveShiftColors(
            schedule.shiftTypes, themeId, schedule.customShiftColors);

    final selectedShiftName =
        schedule?.getShiftForDate(_selectedDate) ?? kUnsetShiftSentinel;
    final selectedHasShift = selectedShiftName != kUnsetShiftSentinel &&
        selectedShiftName.isNotEmpty;
    final selectedShiftColor =
        selectedHasShift ? shiftColors[selectedShiftName] : null;

    final locale = _intlLocale(context);
    final dateLabel = DateFormat.yMMMMEEEEd(locale).format(_selectedDate);
    final dateKey = _selectedDate.toIso8601String().split('T')[0];
    // ⭐ 2026-08-27(2차) - "근무 칩/점 빼고는 전부 배경에 따라 유동적으로"
    // 요청으로 헤더/날짜스트립도 이 스킴을 받아서 색을 맞춤(_buildHeader/
    // _buildDateStrip에 scheme로 넘김) - 더 이상 "일단 배경만" 단계가 아님.
    final scheme = _ScheduleColorScheme.of(
        kScheduleBackgroundColors[ref.watch(scheduleBackgroundProvider)]);

    return GestureDetector(
      // ⭐ 인디케이터 드래그 중엔 null로 꺼서 경합 자체를 없앰(위 필드 주석 참고).
      onHorizontalDragEnd: _indicatorDragActive
          ? null
          : (details) {
              if (widget.onSwipeToCalendar != null &&
                  details.primaryVelocity != null) {
                if (details.primaryVelocity! > 500) {
                  widget.onSwipeToCalendar!();
                }
              }
            },
      child: Scaffold(
        backgroundColor: scheme.mainBg,
        body: Column(
          children: [
            _buildHeader(dateLabel, selectedShiftName, selectedHasShift,
                selectedShiftColor, scheme),
            _buildDateStrip(daysInMonth, scheme),
            Container(height: 1, color: kAppChipBorder.withValues(alpha: 0.08)),
            Expanded(
                child: _TimeAxisPicker(
                    key: ValueKey(dateKey),
                    dateKey: dateKey,
                    onIndicatorDragActiveChanged: (active) =>
                        setState(() => _indicatorDragActive = active),
                    hasShiftToday: selectedHasShift)),
          ],
        ),
      ),
    );
  }

  // ⭐ 2026-08-27 - "배경색을 헤더(2026년 8월 27일...)까지 적용, 핸드폰
  // 상태표시줄만 빼고" 요청 - 예전엔 이 Container 전체가 불투명 흰색이라
  // SafeArea의 상단 패딩(상태표시줄 자리)까지 같이 흰색으로 덮여있었음.
  // 이제 상태표시줄 자리만 정확히 그 높이(MediaQuery.padding.top)만큼
  // 흰색으로 남기고(요청대로 이 부분만 예외), 헤더 본문(Row)은
  // scheme.headerBg로 칠함.
  // ⭐ 2026-08-27(2차) - 텍스트/아이콘 색도 scheme.headerText로(요청: "검정색이
  // 아니라 검정색보다 약간 연한 색깔로, 그 영역 배경에 대비되게"). 근무명
  // 칩(_ShiftPill)은 예외라 scheme를 안 받고 그대로 둠.
  Widget _buildHeader(String dateLabel, String shiftName, bool hasShift,
      Color? shiftColor, _ScheduleColorScheme scheme) {
    return Column(
      children: [
        Container(
            height: MediaQuery.of(context).padding.top, color: Colors.white),
        Container(
          color: scheme.headerBg,
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
          child: Row(
            children: [
              _MonthNavButton(
                  icon: Icons.chevron_left,
                  color: scheme.headerText,
                  onTap: () => _shiftMonth(-1)),
              Expanded(
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8.w,
                    runSpacing: 4.h,
                    children: [
                      Text(
                        dateLabel,
                        style: TextStyle(
                            fontSize: 15.5.sp,
                            fontWeight: FontWeight.w700,
                            color: scheme.headerText),
                      ),
                      if (hasShift)
                        _ShiftPill(shiftName: shiftName, color: shiftColor),
                    ],
                  ),
                ),
              ),
              _MonthNavButton(
                  icon: Icons.chevron_right,
                  color: scheme.headerText,
                  onTap: () => _shiftMonth(1)),
            ],
          ),
        ),
      ],
    );
  }

  // ⭐ "그냥 숫자만" - 요일 라벨 없이 날짜 숫자만. 편집모드 토글이 없어져서
  // 다시 전체 폭을 다 씀(트레일링 아이콘 자리 없앰).
  // ⭐ 2026-08-27 - 맨 끝에 날짜 칩과 동일한 크기의 톱니바퀴 칩을 하나 추가함
  // (요청) - 일정관리 전용 설정 화면(지금은 배경색 선택만) 진입점.
  // ⭐ 2026-08-27(2차) - 컨테이너 배경 scheme.headerBg로, 날짜칩/설정칩은
  // 공용 데코레이션(_scheduleChipDecoration)으로 통일(요청: "두 칩은
  // 디자인적으로 100% 동일해야 함") - 배경은 scheme.mainBg(선택된 배경색
  // 그대로), 텍스트/아이콘은 scheme.headerText(선택 안 된 상태 기준).
  Widget _buildDateStrip(int daysInMonth, _ScheduleColorScheme scheme) {
    final chipDecoration = _scheduleChipDecoration(scheme);
    return Container(
      color: scheme.headerBg,
      height: _dateChipHeight.h + 14.h,
      child: ListView.separated(
        controller: _dateStripController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        itemCount: daysInMonth + 1,
        separatorBuilder: (_, __) => SizedBox(width: _dateChipGap.w),
        itemBuilder: (context, index) {
          if (index == daysInMonth) {
            return GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const _ScheduleSettingsScreen())),
              child: Container(
                width: _dateChipWidth.w,
                height: _dateChipHeight.h,
                alignment: Alignment.center,
                decoration: chipDecoration,
                child: Icon(Icons.settings,
                    size: 16.sp, color: scheme.headerText),
              ),
            );
          }
          final date =
              DateTime(_selectedDate.year, _selectedDate.month, index + 1);
          final isSelected = date.day == _selectedDate.day;
          final isToday = DateUtils.isSameDay(date, DateTime.now());

          return GestureDetector(
            onTap: () {
              setState(() => _selectedDate = date);
              _scrollDateStripToSelected();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _dateChipWidth.w,
              height: _dateChipHeight.h,
              alignment: Alignment.center,
              decoration: isSelected
                  ? BoxDecoration(
                      color: kAppMainAccent,
                      borderRadius: BorderRadius.circular(11.r),
                      boxShadow: [
                        BoxShadow(
                            color: kAppMainAccent.withValues(alpha: 0.35),
                            blurRadius: 7,
                            offset: const Offset(0, 3))
                      ],
                    )
                  : chipDecoration.copyWith(
                      border: isToday
                          ? Border.all(
                              color: kAppMainAccent.withValues(alpha: 0.5),
                              width: 1.3)
                          : chipDecoration.border,
                    ),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : scheme.headerText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MonthNavButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(8.w),
          child: Icon(icon, size: 22.sp, color: color.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}

class _ShiftPill extends StatelessWidget {
  final String shiftName;
  final Color? color;
  const _ShiftPill({required this.shiftName, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: kAppChipFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: color?.withValues(alpha: 0.7) ??
                kAppChipBorder.withValues(alpha: 0.18),
            width: 1.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[
            Container(
                width: 7.w,
                height: 7.w,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            SizedBox(width: 5.w),
          ],
          Text(shiftName,
              style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: kAppChipBorder)),
        ],
      ),
    );
  }
}

// ============================================================
// ⭐ 세로 시간축 + 화면 중앙 고정 인디케이터
//
// ⭐ 여섯 번째 재작업(큰 전환, 사용자 아이디어) - "일정을 시작~끝 범위로
// 그리기"를 완전히 버림. 대신:
//  - 일정 하나 = 시작 시각 슬롯(30분 단위)에 놓이는 "아이콘 + 텍스트 한 줄".
//    카드(색칠된 박스) 자체가 없어짐 - 아이콘(둥근 원, 나중에 카테고리
//    아이콘/색상 자동배정 예정, 지금은 그냥 색칠된 원) 옆에 "제목 + 시간"
//    한 줄, 그 아래 "내용" 한 줄, 끝.
//  - 세로축의 각 30분 슬롯은 기본 높이(_baseSlotHeight)를 갖다가, 그 슬롯에서
//    "시작하는" 일정이 있으면 그 개수만큼 늘어남(줄 수 × _rowHeight) - 즉
//    슬롯 높이가 이제 균일하지 않고 일정에 따라 동적으로 계산됨
//    (_recomputeLayout). 그래서 더 이상 "겹침 처리"(z-order/띠) 자체가
//    필요 없음 - 같은 슬롯에서 시작하는 여러 일정은 그냥 그 슬롯 안에
//    세로로 쌓인 여러 줄이 될 뿐.
//  - 핵심 좌표 트릭(이전과 동일한 발상, 슬롯 단위로 일반화): 렌더링에서는
//    항상 "뷰포트 절반 + 슬롯 누적 offset(_slotTops)"을 씀. 그러면 "지금
//    화면 정중앙이 가리키는 슬롯"과 "그 슬롯을 정중앙에 오게 하는 스크롤
//    offset"이 정확히 같은 값(_slotTops[slot])이 되어 보정 없이 그대로
//    scrollOffset을 슬롯 위치로 읽고 쓸 수 있음.
// ============================================================

class _TimeAxisPicker extends ConsumerStatefulWidget {
  // ⭐ "오늘 근무 조건이 아예 없고(=근무 미배정) 만들어둔 일정도 없는" 완전
  // 빈 상태를 판정하기 위해 부모가 이미 계산해둔 값을 그대로 받음 - 아래
  // _computeInitialCenterMinutes의 확장 포인트 참고.
  final bool hasShiftToday;
  // ⭐ 2026-08-27 - date_schedules 영구 저장(DB v20) 연동용. 'YYYY-MM-DD'.
  // 부모가 key: ValueKey(dateKey)로 감싸서 넘기므로, 날짜가 바뀌면 이 위젯
  // 전체가 새로 마운트됨(스크롤 위치·드래그 상태도 자연스럽게 리셋).
  final String dateKey;
  // ⭐ 2026-08-27 - 인디케이터 드래그 시작/종료를 부모에게 알림(가로 스와이프
  // 경합 방지용 - _ScheduleManagementTabState 참고).
  final ValueChanged<bool>? onIndicatorDragActiveChanged;
  const _TimeAxisPicker(
      {super.key,
      required this.hasShiftToday,
      required this.dateKey,
      this.onIndicatorDragActiveChanged});

  @override
  ConsumerState<_TimeAxisPicker> createState() => _TimeAxisPickerState();
}

class _TimeAxisPickerState extends ConsumerState<_TimeAxisPicker> {
  // ⭐⭐ 2026-08-26 - "픽셀 단위로 박아놔도 되냐, 기기별 편차는?" 피드백으로
  // 전체 리팩터. 이 축 내부 기하 값들은 전부 raw(스케일 없음)로 박혀 있었음
  // - 지금 기기(1080×2340, override density 420)에서 눈으로 맞춘 값들이라
  // 다른 화면 크기/밀도에서는 그대로 안 맞음.
  //
  // 방식: 각 상수를 "이 기기에서 지금과 똑같은 결과가 나오는 디자인 좌표"로
  // 바꾸고 ScreenUtil(.h/.w/.r)로 스케일함. 이 기기의 스케일 배율은
  // scaleWidth == scaleHeight == 8/7 (디자인 360×780 : 실제 411.43×891.43 -
  // 두 비율이 정확히 6:13으로 일치하는 우연 덕에 가로/세로 스케일이 같음,
  // 런타임 디버그 프린트로 실측 확인함). 그래서 raw값 V → `(V*7/8)` 을
  // `.h`/`.w`/`.r`에 넣으면 `V*7/8 * 8/7 = V`로 지금 기기에서는 픽셀 단위로
  // 완전히 동일하게 나오고, 다른 기기에서는 그 기기의 실제 스케일 배율로
  // 자동 재계산됨.
  //
  // ⚠️ 지난번 버그(정각/30분 눈금 비대칭)의 원인이 "서로 더해지는 값 중
  // 하나만 스케일하고 하나는 raw로 둬서 어긋남"이었기 때문에, 이 축
  // 좌표계(_slotTops에 누적되는 세로 값들: _baseSlotHeight/_rowHeight/
  // _hourTickBoxHeight/_edgePadding)는 전부 `.h`로, 가로 위치(_axisX 계열)는
  // 전부 `.w`로, 원형/두께처럼 가로세로 구분이 없는 값은 `.r`로 통일함 -
  // 절대 섞지 말 것.
  static const int _slotCount = 48; // 하루 = 30분 슬롯 48개
  static double get _baseSlotHeight => (30 * 7 / 8).h; // 일정이 없을 때 슬롯 높이

  // ⭐ 인디케이터에서 손을 뗀 후 "새 일정" 시트가 뜨기까지의 딜레이 - 요청:
  // "바로 팝업 나오지 말고 약간의 딜레이만 줘보자, 그 딜레이는 내가 조정할
  // 수 있게". 이 숫자만 바꿔가면서(0, 50, 100, 150...) 핫리로드로 감 잡으면 됨.
  static const Duration _createSheetOpenDelay = Duration(milliseconds: 100);
  // ⭐ 인디케이터가 원래(축 중앙) 위치로 리셋되는 딜레이 - 항상
  // _createSheetOpenDelay보다 더 길게 둬서, 팝업이 화면을 덮은 뒤에
  // 리셋되게 함(요청: "손 떼는 순간 바로 중앙으로 스냅되는 게 보기 안
  // 좋다"). 팝업 시트의 슬라이드-업 애니메이션 시간(기본 ~300ms)까지
  // 감안해서 넉넉히 잡음 - 이 숫자도 필요하면 조정 가능.
  static const Duration _indicatorResetDelay = Duration(milliseconds: 400);

  // ⭐ 텍스트를 전반적으로 키우면서(요청) 한 줄 안에 다 들어가도록 같이 키움
  // (44→56 / 30→36→40) - "어차피 긴 글은 안 쓸 것 같다"는 전제라 아이콘도
  // 같이 살짝 키움. 40: 인디케이터를 줄이면서 생긴 여유만큼 한 번 더 키움.
  // ⭐ 2026-08-27 - "일정 스타일 8종" 도입으로 줄 높이가 스타일마다 달라져서
  // (겹침 버그 재발 방지, _ScheduleRow.heightForStyle 참고) 고정
  // "_rowHeight" 상수는 없앰 - 아이콘 지름만 여기 남음.
  static double get _iconDiameter => (40 * 7 / 8).r;

  static double get _edgeMargin => (56 * 7 / 8).h; // 이 안쪽으로 들어오면 가장자리로 간주
  static const Duration _edgeScrollInterval = Duration(milliseconds: 220);
  // ⭐ 숫자/눈금을 축 왼쪽으로 옮기면서(요청) 그만큼 왼쪽 여백이 더 필요해짐
  // (숫자 텍스트 + 눈금이 들어갈 자리) - 26→58로 늘림.
  // 🔧 튜닝 포인트 1: 세로축(선+숫자열) 전체를 좌우로 옮기려면 이 숫자(58)를
  // 줄이면 왼쪽으로, 늘리면 오른쪽으로 감 - _axisX가 이 값 그대로임(아래
  // build()의 `_axisX = _axisLeftMargin;`).
  static double get _axisLeftMargin => (58 * 7 / 8).w;
  // ⭐ 2026-08-27(3차) - "인디케이터를 우측 하단 고정 버튼으로" 요청으로
  // 신설 - 축을 더 이상 안 따라다니니 화면 우측 하단 한 자리에 이 마진만큼
  // 떨어뜨려 고정함. 광고 배너는 이 위젯(Expanded 안 LayoutBuilder)의 바깥
  // (부모 Scaffold의 별도 슬롯)이라 _viewportHeight 자체가 이미 광고 위까지만
  // 이라, bottom 마진만 줘도 자동으로 광고보다 위에 옴.
  static double get _fabRightMargin => (16 * 7 / 8).w;
  static double get _fabBottomMargin => (16 * 7 / 8).h;
  // ⭐ 정각 눈금(숫자+선) 한 칸의 "고정" 높이 - 이 값으로 Positioned에 실제
  // height를 줘서 Row를 정확히 이 높이만큼 강제로 차지하게 만듦. 예전엔
  // Row의 높이를 텍스트 폰트 크기로 눈대중해서 "-9"라는 추정값으로 중앙
  // 정렬했는데, 실제 렌더 높이와 추정치가 안 맞아서 정각 눈금 자체가
  // 눈금선(slotTop)보다 살짝 밀려 그려졌음(=화살표가 정각을 가리킬 때
  // "선보다 약간 위"를 가리키는 것처럼 보인 원인). 30분 눈금처럼 높이를
  // 고정해서 -H/2로 계산하면 텍스트 실제 높이와 무관하게 항상 정확히
  // slotTop이 중앙이 됨.
  static double get _hourTickBoxHeight => (24 * 7 / 8).h;
  // ⭐ "00 위/아래 여백이 너무 많다"는 피드백 - 예전엔 뷰포트 높이의 절반을
  // 위아래 여백으로 둬서(그래야 첫/마지막 슬롯도 정중앙까지 스크롤 가능)
  // 스크롤을 끝까지 하면 화면 절반이 빈 채로 남았음. 이제 고정된 작은
  // 여백만 둠 - 그 대신 아주 처음/끝 슬롯 근처에서는 인디케이터가 화면
  // 정중앙이 아니라 그 여백만큼 치우친 채로 멈출 수 있음(트레이드오프).
  static double get _edgePadding => (48 * 7 / 8).h;
  // ⭐ 세로축 선의 두께 - 원형/선 두께처럼 가로세로 구분 없는 값이라 .r로 통일.
  // ⭐ 2026-08-27 - 정각/30분 눈금(짧은 선) 자체는 삭제함(요청) - 숫자만 남김.
  // 눈금 두께 상수(_hourTickThickness/_halfTickThickness)도 같이 제거.
  static double get _axisLineWidth => (4 * 7 / 8).r;

  final ScrollController _controller = ScrollController();
  double _initialMinutes = 0; // 최초 진입 시 중앙에 놓일 시각(현재 시각)
  bool _jumpedToInitial = false;

  // ⭐ 2026-08-27 - date_schedules 테이블(DB v20)에서 영구 저장으로 전환.
  // build()마다 dateScheduleProvider를 watch해서 최신값으로 갱신함(아래
  // build() 참고) - 여기 초기값은 그 갱신 전까지의 플레이스홀더일 뿐.
  List<DateSchedule> _blocks = const [];

  // ⭐ 인디케이터 드래그 상태 - null이면 평소(축 정중앙 고정) 상태.
  // ⭐ 2026-08-27(2차) - "일정이 있는 슬롯을 지날 때만 드래그가 더 뻑뻑하다"는
  // 사용성 피드백으로 좌표계를 바꿈. 예전엔 이게 실제(가변 높이) _slotTops와
  // 같은 좌표계라 손가락 delta를 그대로 누적했는데, 그러면 슬롯에 일정이
  // 쌓여서 물리적으로 더 큰(=heightForStyle만큼 늘어난) 슬롯은 다음 슬롯
  // 경계를 넘기까지 그만큼 더 드래그해야 했음. 이제 이 값은 "균일 슬롯
  // 좌표계"(슬롯 1개 = 항상 _baseSlotHeight, 일정 유무와 무관)를 씀 -
  // 그래서 어느 슬롯이든 정확히 _baseSlotHeight만큼만 손가락을 움직이면
  // 다음 슬롯으로 넘어감. 화면에 실제로 그리는 위치(_indicatorScreenY)는
  // 여전히 _slotTops(실제 가변 레이아웃)를 따로 참조하므로, "판정"과
  // "렌더링"이 서로 다른 좌표계를 쓰게 분리된 것 - _realYToUniformY가 그
  // 변환을 담당함.
  double? _dragContentY;
  double? _downContentY; // 누른 순간의 균일 좌표 - "정말 움직였는지" 판정 기준점
  bool _hasMovedSinceDown = false; // "탭만 하고 안 움직였으면 취소" 판정용
  Timer? _edgeTimer;

  // ⭐ 아주 작은 손떨림까지 "이동"으로 잡으면 그냥 탭했다 떼는 것도 취소가
  // 안 됨(버그 재발) - 최소 이 정도(균일 좌표 기준)는 움직여야 "진짜
  // 이동"으로 침. Flutter 제스처 인식기의 터치 슬롭에 기대지 않고 직접
  // 판정하는 이유는 위 Listener 관련 주석 참고.
  // ⭐ 2026-08-27(2차) - raw 6이 스케일 없이 박혀 있던 걸 발견해서(비교
  // 대상인 _dragContentY delta는 전부 .h 스케일된 값이라 단위가 안 맞았음)
  // 이 파일 전체가 따르는 (N*7/8) 컨벤션으로 맞춤.
  static double get _moveThreshold => (6 * 7 / 8).h;

  // ⭐ 인디케이터를 누르면 손가락이 바로 그 시각의 숫자를 가려버림 - 그래서
  // 화면에 보이는 활성 인디케이터(+생성 시각)는 실제 드래그 위치보다 항상
  // 2칸(=1시간) 위를 가리키게 함. 손가락은 여전히 "원래" 위치 근처에 있지만
  // 눈에 보이는 마커/숫자는 그 위에 떠 있어서 안 가려짐.
  static const int _activeDisplayOffsetSlots = 2;

  double _viewportHeight = 0;
  double _axisX = 0;

  // ⭐ 매 build마다 다시 계산됨(_recomputeLayout) - 일정이 추가/삭제되면
  // 슬롯 높이가 바뀌므로. 제스처 콜백(build 밖)에서도 참조해야 해서 필드로 캐싱.
  Map<int, List<DateSchedule>> _grouped = {};
  List<double> _slotTops = List<double>.filled(_slotCount + 1, 0);

  @override
  void initState() {
    super.initState();
    // ⭐ _initialMinutes는 이 날짜 데이터가 실제로 로드된 뒤 build()에서
    // 계산함(아래 build()의 isLoaded 참고) - 여기서 미리 계산하면 아직 빈
    // 상태인 _blocks를 보고 "일정 없음"으로 잘못 판단하게 됨.
    // ⭐ 이 위젯은 날짜가 바뀌면 key: ValueKey(dateKey) 덕분에 통째로 새로
    // 마운트되므로(부모 build() 참고), initState에서 한 번만 로드하면 됨.
    // 이미 로드된 날짜면 DateScheduleNotifier.loadForDate가 알아서 스킵함.
    ref.read(dateScheduleProvider.notifier).loadForDate(widget.dateKey);
  }

  // ⭐ 확장 포인트 - "처음 렌더링될 때 축 중앙에 뭘 보여줄지" 결정 지점을
  // 하나로 모아둠. 지금은 "오늘 근무 조건도 없고 만들어둔 일정도 없는"
  // 완전 빈 상태에서만 고정값(09:00)을 쓰고, 그 외엔 원래대로 현재 시각을
  // 씀. 나중에 "근무별 실제 근무시간"을 입력받게 되면, 그 근무의 "근무
  // 후" 시각(예: 주간 09~18시 근무면 18시 근처, 야간 22~08시 근무면 09~12시
  // 사이)을 반환하도록 이 함수 안쪽 분기만 늘리면 됨 - 호출부(initState)는
  // 안 건드려도 됨.
  // ⭐ 2026-08-27 - "다른 탭에서 들어오면 기본 9시, 그 날 일정이 있으면 가장
  // 먼저 시작하는 일정 쪽" 요청으로 전면 교체. hasShiftToday/현재시각 기준
  // 분기는 없앰(값이 흔들리면 "인디케이터가 왜 매번 다른 데를 가리키냐"는
  // 혼란을 줄 수 있어서, 이제 순수하게 "그 날 일정 유무"만 기준으로 함).
  double _computeInitialCenterMinutes() {
    if (_blocks.isNotEmpty) {
      final earliest =
          _blocks.map((b) => b.startMinutes).reduce((a, b) => a < b ? a : b);
      return earliest.toDouble();
    }
    // TODO(근무시간 입력 기능 붙을 때): widget.hasShiftToday를 활용해서 그날의
    // 실제 근무 유형 + 근무별 근무시간 설정을 받아서, 주간/야간 등 유형별로
    // "근무 후" 시각을 반환하도록 분기 추가(지금은 항상 09:00 고정).
    return 9 * 60; // 09:00
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ⭐ 2026-08-27 - AM/PM 표기로 교체(요청) - _scheduleTimeLabel(전역 함수)로
  // 이식. 소요시간 없는 일정("10:00 AM"만 표시)도 이 함수가 처리함.
  String _timeRangeLabel(DateSchedule block) =>
      _scheduleTimeLabel(block.startMinutes, block.durationMinutes);

  // ⭐ "정확히 동일한 시간 범위"의 일정은 중복 생성을 막음 - 그런 경우는
  // 기존 일정에 내용을 같이 적으면 되니까. [exclude]는 수정 시 자기 자신은
  // 비교 대상에서 빼기 위함.
  bool _hasDuplicateRange(int start, int? duration, {DateSchedule? exclude}) {
    return _blocks.any((b) =>
        !identical(b, exclude) &&
        b.startMinutes == start &&
        b.durationMinutes == duration);
  }

  // ⭐ 일정을 시작 슬롯(30분 단위) 기준으로 묶고, 각 슬롯의 실제 렌더 높이와
  // 누적 offset을 계산함 - 이번 재작업의 핵심("시작과 끝이 아니라 시작
  // 시간으로 렌더링"). ⭐ 2026-08-27 - 스타일(1~8)마다 필요한 높이가 달라져서
  // (_ScheduleRow.heightForStyle) 더 이상 "개수 × 고정 줄높이"가 아니라
  // 그 슬롯에 쌓인 일정들의 실제 스타일별 높이를 하나씩 더함 - 그래야 스타일이
  // 서로 다른 일정 두 개가 같은 슬롯에 있어도 안 겹침.
  void _recomputeLayout() {
    final grouped = <int, List<DateSchedule>>{};
    for (final b in _blocks) {
      final slot = (b.startMinutes ~/ 30).clamp(0, _slotCount - 1);
      grouped.putIfAbsent(slot, () => []).add(b);
    }
    final tops = List<double>.filled(_slotCount + 1, 0);
    double cursor = 0;
    for (int i = 0; i < _slotCount; i++) {
      tops[i] = cursor;
      final blocksHere = grouped[i];
      double height;
      if (blocksHere == null || blocksHere.isEmpty) {
        height = _baseSlotHeight;
      } else {
        // ⭐ 2026-08-27 - 스타일이 이제 항상 고정이라 개수만큼 곱하면 됨
        // (예전엔 일정마다 styleIndex가 달라서 하나씩 더했음).
        final sum = blocksHere.length * _ScheduleRow.heightForStyle;
        height = sum > _baseSlotHeight ? sum : _baseSlotHeight;
      }
      cursor += height;
    }
    tops[_slotCount] = cursor;
    _grouped = grouped;
    _slotTops = tops;
  }

  // ⭐ 슬롯 안에 쌓인 일정들을 각자의 실제 스타일별 높이(heightForStyle)만큼
  // 누적된 offset에 배치함 - 스타일이 서로 다른 일정이 같은 슬롯에 섞여도
  // 절대 안 겹치는 이유가 이거임(고정 줄높이 대신 실제 필요 높이를 씀).
  List<Widget> _buildScheduleRowWidgets(
      double rowLeft, _ScheduleColorScheme scheme) {
    final widgets = <Widget>[];
    for (final entry in _grouped.entries) {
      double offset = 0;
      for (final block in entry.value) {
        final h = _ScheduleRow.heightForStyle;
        widgets.add(Positioned(
          top: _edgePadding + _slotTops[entry.key] + offset,
          left: rowLeft,
          right: (16 * 7 / 8).w,
          height: h,
          child: _ScheduleRow(
            block: block,
            timeLabel: _timeRangeLabel(block),
            iconDiameter: _iconDiameter,
            timeTextColor: scheme.timeText,
            contentTextColor: scheme.contentText,
            onTap: () => _openEditSheet(block),
          ),
        ));
        offset += h;
      }
    }
    return widgets;
  }

  // ⭐ 콘텐츠 좌표(y, _slotTops와 같은 기준) → 그 위치가 속한 슬롯 인덱스.
  // 슬롯이 48개뿐이라 이분 탐색 없이 선형 탐색으로 충분함.
  int _slotIndexAtContentY(double y) {
    for (int i = 0; i < _slotCount; i++) {
      if (y < _slotTops[i + 1]) return i;
    }
    return _slotCount - 1;
  }

  Future<void> _openCreateSheet(int startMinutes) async {
    final raw = await showModalBottomSheet<DateSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreateBlockSheet(startMinutes: startMinutes),
    );
    if (!mounted || raw == null) return;
    if (_hasDuplicateRange(raw.startMinutes, raw.durationMinutes)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('이미 같은 시간대의 일정이 있어요 - 그 일정에 내용을 같이 적어주세요')),
      );
      return;
    }
    // ⭐ 2026-08-27 - _colorCursor(세션 한정 카운터) 대신 현재 저장된 개수로
    // 색을 정함 - date_schedules가 영구 저장이라 앱을 껐다 켜도 같은 규칙으로
    // 계속 순환하게.
    final color =
        kScheduleBlockColors[_blocks.length % kScheduleBlockColors.length];
    await ref.read(dateScheduleProvider.notifier).create(
          raw.copyWith(
            date: widget.dateKey,
            color: color,
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
  }

  // ⭐ 기존 일정을 탭하면 - 같은 시트를 "수정 모드"로 열어서 저장/삭제 가능하게
  // 함. 시작 시간은 인디케이터 전용 개념이라 여기선 안 바꿈(제목/내용/
  // 소요시간만 수정 가능) - 시작 시간을 바꾸고 싶으면 삭제 후 다시 만드는
  // 흐름을 일단 씀. 색은 그대로 유지.
  Future<void> _openEditSheet(DateSchedule block) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _CreateBlockSheet(startMinutes: block.startMinutes, existing: block),
    );
    if (!mounted || result == null) return;
    if (result is DateSchedule &&
        _hasDuplicateRange(result.startMinutes, result.durationMinutes,
            exclude: block)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('이미 같은 시간대의 일정이 있어요 - 그 일정에 내용을 같이 적어주세요')),
      );
      return;
    }
    final notifier = ref.read(dateScheduleProvider.notifier);
    if (result == _CreateBlockSheet.deleteSignal) {
      await notifier.delete(block);
    } else if (result is DateSchedule) {
      await notifier.update(result.copyWith(
        id: block.id,
        date: block.date,
        color: block.color,
        createdAt: block.createdAt,
      ));
    }
  }

  // ⭐ 실제(가변 높이) 콘텐츠 좌표 하나를 "균일 슬롯 좌표"(슬롯 1개 =
  // _baseSlotHeight)로 변환함 - 드래그를 시작하는 순간(_onIndicatorDragDown)
  // "지금 화면 정중앙이 실제로 몇 번째 슬롯의 몇 %쯤인지"를 구해서, 그
  // 이후로는 균일 좌표계에서만 델타를 누적하기 위한 최초 1회 변환.
  double _realYToUniformY(double realY) {
    final slot = _slotIndexAtContentY(realY).clamp(0, _slotCount - 1);
    final segStart = _slotTops[slot];
    final segEnd = _slotTops[slot + 1];
    final segLen = segEnd - segStart;
    final frac =
        segLen > 0 ? ((realY - segStart) / segLen).clamp(0.0, 1.0) : 0.0;
    return (slot + frac) * _baseSlotHeight;
  }

  // ⭐ 지금 손가락이 실제로 가리키는(가려버리는) 슬롯 - 표시/생성 둘 다
  // 이걸 그대로 안 쓰고 아래 _displaySlot(2칸 위)을 씀. _dragContentY가 이제
  // 균일 좌표계라 나눗셈 하나로 바로 슬롯이 나옴(선형 탐색이던
  // _slotIndexAtContentY보다 오히려 더 간단해짐).
  int get _rawDragSlot => _dragContentY == null
      ? -1
      : (_dragContentY! / _baseSlotHeight).floor().clamp(0, _slotCount - 1);

  // ⭐ 화면에 보이고, 실제로 생성되는 슬롯 - 손가락에 가려지지 않도록 항상
  // 실제 위치보다 2칸(1시간) 위.
  int get _displaySlot =>
      (_rawDragSlot - _activeDisplayOffsetSlots).clamp(0, _slotCount - 1);

  // ⭐ 2026-08-27(3차) - 인디케이터가 우측 하단 고정 버튼으로 바뀌면서, 이
  // 값은 더 이상 "인디케이터를 화면 어디에 그릴지"가 아니라 순수하게
  // "지금 선택된 슬롯(_displaySlot)이 뷰포트 가장자리에 가까운지"를
  // _checkEdgeScroll에서 판정하는 용도로만 남음 - 드래그 중 축을 자동으로
  // 더 스크롤할지 결정하는 계산이라 여전히 필요함.
  double get _indicatorScreenY {
    if (_dragContentY == null) return _viewportHeight / 2;
    final scrollOffset = _controller.hasClients ? _controller.offset : 0.0;
    return _edgePadding + _slotTops[_displaySlot] - scrollOffset + (3 * 7 / 8).h;
  }

  // ⭐ 콘텐츠 좌표계("scrollOffset과 같은 기준"의 절대 위치)에서, 지금 화면
  // 정중앙에 있는 위치. edgePadding이 뷰포트 절반보다 작아진 뒤로는
  // scrollOffset과 이 값이 더 이상 같지 않아서(예전엔 우연히 같았음) 항상
  // 이 식으로 변환해야 함.
  double _unshiftedCenterPosition() {
    final scrollOffset = _controller.hasClients ? _controller.offset : 0.0;
    return scrollOffset + _viewportHeight / 2 - _edgePadding;
  }

  // ⭐ "탭 하자마자 바로" 활성 모드로 바뀌게 하려고 onVerticalDragStart(=
  // 움직여야 발동) 대신 onVerticalDragDown(=손을 대는 즉시 발동)에서 상태를
  // 채움.
  //
  // ⭐ 2026-08-27 - Listener → GestureDetector로 되돌림. 이유: "일정
  // 아이콘/내용 위에서 드래그를 시작하면 인디케이터가 안 움직인다"는 버그
  // - 원인은 인디케이터의 히트테스트 영역이 아이콘 하나 크기밖에 안 돼서,
  // 그 영역 밖(이미 그려진 일정 위 등)에서 드래그를 시작하면 애초에 이
  // 위젯이 손가락을 붙잡을 기회조차 없었던 것. 그래서 이제 인디케이터를
  // 화면 전체를 덮는 투명 GestureDetector(HitTestBehavior.translucent)로
  // 감싸서 어디를 눌러도 드래그를 시작할 수 있게 함 - translucent라 그
  // 아래 일정 카드의 탭(수정)도 그대로 살아있음(제스처 아레나가 "많이
  // 움직였으면 이 드래그가 이기고, 안 움직이고 뗐으면 카드의 탭이 이긴다"로
  // 알아서 갈라줌 - Flutter의 표준 탭-vs-드래그 판정 방식).
  // ⭐ GestureDetector로 돌아오면서 예전 "왕복 후 제자리 복귀 시 오취소"
  // 버그가 재발할 수 있는 지점(onEnd 대신 onCancel이 불리는 경우)이 다시
  // 생기는데, 그건 onEnd/onCancel을 완전히 같은 함수(_finishIndicatorDrag)로
  // 몰아서 처리해 없앰 - "이동했는지"는 Flutter의 내부 판정이 아니라 우리가
  // 직접 잰 스레숄드(_hasMovedSinceDown)로만 보므로, Flutter가 내부적으로
  // onEnd를 부르든 onCancel을 부르든 결과가 똑같아짐.
  void _onIndicatorDragDown(DragDownDetails details) {
    setState(() {
      // ⭐ 2026-08-27(2차) - 균일 슬롯 좌표계로 변환해서 저장(위
      // _dragContentY 필드 주석 참고) - 이 최초 변환 이후로는 실제 레이아웃
      // (_slotTops)을 전혀 안 쓰고 순수 델타 누적만으로 슬롯을 판정함.
      _dragContentY = _realYToUniformY(_unshiftedCenterPosition());
      _downContentY = _dragContentY;
      _hasMovedSinceDown = false;
    });
    widget.onIndicatorDragActiveChanged?.call(true);
  }

  void _onIndicatorDragUpdate(DragUpdateDetails details) {
    if (_dragContentY == null) return;
    setState(() {
      // ⭐ 균일 좌표계라 최대값도 "슬롯 개수 × 균일 슬롯 높이"(실제 총
      // 콘텐츠 높이 _slotTops[_slotCount]가 아님).
      _dragContentY = (_dragContentY! + details.delta.dy)
          .clamp(0.0, _slotCount * _baseSlotHeight);
      // ⭐ 최소 이동거리(_moveThreshold)를 넘었을 때만 "이동함"으로 판정 -
      // 미세한 손떨림 한 번에 바로 true가 되는 걸 막음(그러면 탭하자마자
      // 뗐을 때도 "이동함"으로 오판정돼서 취소가 아예 안 됨). 한 번
      // true가 되면 그 뒤로 원위치로 돌아와도 계속 true 유지(왕복 취소
      // 버그 재발 방지, 이전 수정 그대로).
      if (!_hasMovedSinceDown &&
          _downContentY != null &&
          (_dragContentY! - _downContentY!).abs() >= _moveThreshold) {
        _hasMovedSinceDown = true;
      }
    });
    _checkEdgeScroll();
  }

  void _onIndicatorDragEnd(DragEndDetails details) => _finishIndicatorDrag();
  void _onIndicatorDragCancel() => _finishIndicatorDrag();

  // ⭐ onEnd/onCancel 공용 종료 처리.
  void _finishIndicatorDrag() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    if (_dragContentY == null) return;
    widget.onIndicatorDragActiveChanged?.call(false);
    final moved = _hasMovedSinceDown;
    final slot = _displaySlot; // 리셋 전에 미리 계산해둠
    _downContentY = null;
    if (!moved) {
      // ⭐ 요청: "움직임 없이 바로 손을 떼면 일정 생성 없이 그냥 원래대로".
      // 뜰 팝업이 없으니 바로 리셋해도 문제없음.
      setState(() => _dragContentY = null);
      return;
    }
    // ⭐ 요청: "손을 떼는 순간 바로 중앙으로 스냅되는 게 보기 안 좋다" - 그
    // 자리에 그대로 있다가, 팝업이 화면을 덮고 난 뒤에야 원위치로 리셋함.
    // 그래야 사용자 눈엔 "그 자리에서 그대로 팝업이 뜸"으로 보이고, 원래
    // 위치로 돌아간 건 팝업을 닫았을 때만 드러남.
    Future.delayed(_createSheetOpenDelay, () {
      if (!mounted) return;
      _openCreateSheet(slot * 30);
    });
    Future.delayed(_indicatorResetDelay, () {
      if (!mounted) return;
      setState(() => _dragContentY = null);
    });
  }

  // ⭐ 인디케이터를 화면 위/아래 가장자리 쪽으로 계속 밀면, 슬롯 단위로
  // "드르륵" 끊어서 계속 진행함 - 인디케이터 자신은 가장자리 근처에 머문 채,
  // 축만 그만큼(슬롯 높이만큼, 슬롯마다 다를 수 있음) 넘어감.
  void _checkEdgeScroll() {
    if (_dragContentY == null || !_controller.hasClients) return;
    final screenY = _indicatorScreenY;

    int direction = 0;
    if (screenY > _viewportHeight - _edgeMargin) direction = 1;
    if (screenY < _edgeMargin) direction = -1;

    if (direction == 0) {
      _edgeTimer?.cancel();
      _edgeTimer = null;
      return;
    }
    _edgeTimer ??= Timer.periodic(
        _edgeScrollInterval, (_) => _advanceEdgeScroll(direction));
  }

  void _advanceEdgeScroll(int direction) {
    if (_dragContentY == null || !_controller.hasClients) {
      _edgeTimer?.cancel();
      _edgeTimer = null;
      return;
    }
    // ⭐ 2026-08-27(2차) - currentSlot 판정은 균일 좌표계로.
    final currentSlot =
        (_dragContentY! / _baseSlotHeight).floor().clamp(0, _slotCount - 1);
    final targetSlot = (currentSlot + direction).clamp(0, _slotCount - 1);
    if (targetSlot == currentSlot) {
      _edgeTimer?.cancel();
      _edgeTimer = null;
      return;
    }
    // ⭐ 실제 스크롤 이동량은 여전히 실제 레이아웃(_slotTops, 가변 높이)을
    // 써야 화면에 보이는 축과 정확히 맞물림 - 균일 좌표계는 "몇 슬롯
    // 지났는지" 판정에만 쓰고, 화면을 실제로 얼마나 스크롤할지는 별개.
    final realDelta = _slotTops[targetSlot] - _slotTops[currentSlot];
    final newOffset = (_controller.offset + realDelta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    setState(() {
      // ⭐ 균일 좌표계에서 정확히 한 슬롯만큼 이동(edge-scroll 타이머 한
      // 틱 = 슬롯 하나, 기존 "슬롯 단위로 드르륵" 의도 그대로).
      _dragContentY = targetSlot * _baseSlotHeight;
      _hasMovedSinceDown = true;
    });
    _controller.jumpTo(newOffset);
  }

  @override
  Widget build(BuildContext context) {
    final providerState = ref.watch(dateScheduleProvider);
    // ⭐ 2026-08-27 - DB 로드는 비동기라, initState 시점엔 이 날짜 데이터가
    // 아직 없음(빈 리스트와 "아직 안 불러옴"을 구분해야 함 - 안 그러면
    // "가장 먼저 시작하는 일정으로 초기 위치" 기능이 로드 전에 빈 리스트로
    // 잘못 판단해서 항상 09:00으로 점프해버림). containsKey로 "실제로 이
    // 날짜를 로드했는지"를 확인하고, 로드된 뒤 딱 한 번만 점프함.
    final isLoaded = providerState.containsKey(widget.dateKey);
    _blocks = providerState[widget.dateKey] ?? const [];
    // ⭐ 2026-08-27(2차) - 축 시간 숫자 + 일정 시간/내용 텍스트 색이 배경색에
    // 따라 유동적으로 바뀌게(요청) - 부모(_ScheduleManagementTabState)와
    // 똑같은 배경값을 그대로 다시 watch해서 계산함(단일 소스, 같은 함수).
    final scheme = _ScheduleColorScheme.of(
        kScheduleBackgroundColors[ref.watch(scheduleBackgroundProvider)]);
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        _axisX = _axisLeftMargin;
        _recomputeLayout();
        final totalContentHeight = _slotTops[_slotCount] + _edgePadding * 2;
        // ⭐ 고정 인디케이터(축 정중앙에 뜬 원)와 안 겹치게 살짝 더 띄움 -
        // 일정을 새로 만들 때 "움직인" 인디케이터와 겹치는 건 상관없음
        // (요청), 가만히 있는 기본 위치와만 안 겹치면 됨. 평소 인디케이터가
        // 작아진 만큼(44→36) 간격도 줄임 - 다만 너무 붙지는 않게(요청) 58→46.
        final rowLeft = _axisX + (26 * 7 / 8).w;

        if (!_jumpedToInitial && isLoaded) {
          _jumpedToInitial = true;
          _initialMinutes = _computeInitialCenterMinutes();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_controller.hasClients) return;
            final slot = (_initialMinutes ~/ 30).clamp(0, _slotCount - 1);
            final target = _slotTops[slot] - _viewportHeight / 2 + _edgePadding;
            _controller.jumpTo(
                target.clamp(0.0, _controller.position.maxScrollExtent));
          });
        }

        return Stack(
          children: [
            // ⭐ 배경 축 - 평소처럼 자유롭게 스크롤됨(순수 탐색용, 그 자체로는
            // 아무 액션도 안 만듦). 인디케이터를 직접 드래그할 때만 배경
            // 스크롤을 잠그고 대신 edge-scroll이 움직여줌.
            SingleChildScrollView(
              controller: _controller,
              physics: _dragContentY == null
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: SizedBox(
                height: totalContentHeight,
                width: double.infinity,
                child: Stack(
                  children: [
                    // ⭐ 축을 관통하는 세로선 - "파워포인트 선 도형처럼 허접하다"는
                    // 피드백으로 전면 재작업. 밋밋한 단색 회색 막대 대신
                    // 메인 색상(kAppMainAccent) 그라데이션 캡슐 + 은은한
                    // 글로우(그림자)를 줘서 입체감을 냄. 위/아래 끝은 여전히
                    // 둥글게 마감.
                    Positioned(
                      left: _axisX - _axisLineWidth / 2,
                      top: _edgePadding,
                      height: _slotTops[_slotCount],
                      width: _axisLineWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          // ⭐ 2026-08-27 - 끝단 알파를 0.25→0.6으로 올림
                          // (요청: "맨 위/아래 00 부분만 세로축이 뿌옇게 보인다") -
                          // 축 양끝이 정확히 00시/24시(=00) 라벨 위치와 겹쳐서,
                          // 그 지점의 짙은 페이드(25%) + 그림자 블러가 합쳐져
                          // 유독 흐릿하게 보였던 것으로 보임. 캡슐 느낌은
                          // 남기되 그 정도로 옅어지진 않게 완화.
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              kAppMainAccent.withValues(alpha: 0.6),
                              kAppMainAccent.withValues(alpha: 0.8),
                              kAppMainAccent.withValues(alpha: 0.6),
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(_axisLineWidth / 2),
                          boxShadow: [
                            // ⭐ 2026-08-27(2차) - "00 라벨이 여전히 뿌옇다"는
                            // 재확인 - 이 glow의 블러가 정확히 축 선의
                            // 위/아래 끝(=00/24시 라벨이 있는 자리)에서
                            // 가장 넓게 번지기 때문으로 보여서, 블러 반경
                            // 자체를 더 줄임(4→2, spread는 아예 0으로) -
                            // 글로우 느낌은 옅게 남기되 라벨과 겹치는 번짐은
                            // 최소화.
                            BoxShadow(
                              color: kAppMainAccent.withValues(alpha: 0.2),
                              blurRadius: (2 * 7 / 8).r,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ⭐ 2026-08-27 - 정각/30분 눈금(짧은 선) 전부 삭제 요청 -
                    // 숫자만 남기고, 그만큼 폰트를 살짝 키우고 축에 더 붙임
                    // (눈금이 없어져서 숫자 오른쪽 끝이 자연히 축에 닿음).
                    // 인디케이터가 각 정각/30분에 자석처럼 붙는 동작 자체는
                    // 그대로 유지됨(_snapToNearestSlot 등 - 눈금은 시각적
                    // 표시일 뿐 스냅 로직과 무관).
                    for (int hour = 0; hour <= 24; hour++)
                      Positioned(
                        top: _edgePadding +
                            _slotTops[(hour * 2).clamp(0, _slotCount)] -
                            _hourTickBoxHeight / 2,
                        left: 0,
                        // ⭐ 2026-08-27 - "너무 붙었다"는 후속 피드백으로 축과의
                        // 간격을 4.w→10.w로 다시 살짝 벌림.
                        // ⭐ 2026-08-27(2차) - "조끔만 더 떨어뜨려줘" 재요청으로
                        // 10→13. 늘어난 만큼 이 Positioned의 width가 줄어서,
                        // Row(mainAxisAlignment.end)가 숫자를 그만큼 더 왼쪽에서
                        // 오른쪽-정렬함(=축에서 더 멀어짐).
                        width: _axisX - (13 * 7 / 8).w,
                        height: _hourTickBoxHeight,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              (hour % 24).toString().padLeft(2, '0'),
                              // ⭐ 2026-08-27 - 일정 시간 텍스트(_ScheduleRow.
                              // _timeTextStyle)와 스타일 통일 요청 - 폰트/굵기는
                              // 그대로(Quicksand w700), 색은 scheme.timeText로
                              // (배경색별 유동).
                              // ⭐ 2026-08-27(2차) - "00이 다른 숫자들보다 왼쪽에
                              // 그려진다"는 재확인 피드백 - Row가 오른쪽 끝을
                              // 기준으로 정렬하는 이상 이론상 텍스트 폭과
                              // 무관하게 오른쪽 끝은 일치해야 하는데, 폰트가
                              // "00"(0이 두 번 겹침)처럼 좌우 bearing이 비대칭인
                              // 숫자 글리프를 자연 폭으로 그리면 미묘하게
                              // 어긋나 보일 수 있음. fontFeatures로 모든 숫자를
                              // 강제로 같은 폭(tabular figures)으로 그리게 하면
                              // 이 클래스의 비대칭 자체가 사라짐 - 폰트가 이
                              // 기능을 지원 안 해도 그냥 무시될 뿐이라 안전함.
                              style: GoogleFonts.quicksand(
                                  fontSize: 19.sp,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  color: scheme.timeText),
                            ),
                          ],
                        ),
                      ),
                    // ⭐ 일정들 - 시작 슬롯 기준으로 아이콘+내용 한 줄씩. 같은
                    // 슬롯에서 시작하는 게 여러 개면 그 슬롯 안에서 세로로 쌓임
                    // (_recomputeLayout이 이미 그만큼 슬롯을 늘려둠). 스타일마다
                    // 필요한 높이가 달라서(_ScheduleRow.heightForStyle) 고정
                    // 간격이 아니라 각 일정의 실제 높이를 누적해서 배치함
                    // (_buildScheduleRowWidgets).
                    ..._buildScheduleRowWidgets(rowLeft, scheme),
                  ],
                ),
              ),
            ),
            // ⭐ 2026-08-27(3차) - "인디케이터를 세로축이 아니라 우측 하단에
            // 고정으로 박아줘" 요청으로 축 옆을 따라다니던 인디케이터를
            // 완전히 걷어내고, 화면 우측 하단에 고정된 원형 버튼(플로팅) 하나로
            // 대체함 - 그만큼 축 옆 공간을 다른 용도(숫자/아이콘열을 더
            // 왼쪽으로 붙이는 등)로 쓸 수 있게 됨. 동작 자체는 요청대로 예전과
            // 완전히 동일: 이 버튼을 누르는 순간(onVerticalDragDown) 지금
            // 보고 있는 축 뷰포트의 정중앙에 가까운 시각으로 선택이 시작되고
            // (_unshiftedCenterPosition → _realYToUniformY), 위/아래로 끌면
            // 그 시각이 바뀌고, 손을 떼면 그 시각으로 일정 생성 시트가 뜸
            // (_onIndicatorDragDown/Update/End/Cancel - 로직은 그대로, 이
            // 버튼이 호출하는 콜백만 바뀜). 다만 이 버튼이 축과 완전히
            // 분리되어 있어서, 예전처럼 "드래그 중 지금 몇 시가 선택됐는지"를
            // 축 위에서 실시간으로 보여주는 시각적 마커는 이제 없음(요청:
            // "그것만 해줘" - 그 외 UX는 사용자가 직접 다듬을 예정).
            // 히트테스트 영역이 이 버튼 하나로 고정돼서, 예전에 있던
            // "일정 카드 위에서도 드래그가 되게 하려고 각 _ScheduleRow에
            // 같은 콜백을 같이 달아주던" 우회도 더 이상 의미가 없어짐 -
            // 다만 그 배선을 걷어내는 건 이번 요청 범위 밖이라 그대로 둠.
            Positioned(
              right: _fabRightMargin,
              bottom: _fabBottomMargin,
              child: GestureDetector(
                onVerticalDragDown: _onIndicatorDragDown,
                onVerticalDragUpdate: _onIndicatorDragUpdate,
                onVerticalDragEnd: _onIndicatorDragEnd,
                onVerticalDragCancel: _onIndicatorDragCancel,
                child: const _AxisIndicator(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ⭐ 2026-08-27(3차) - "인디케이터를 세로축이 아니라 우측 하단에 고정으로
// 박아줘" 요청으로 축을 따라다니던 인디케이터(평소엔 작은 동그라미, 드래그
// 중엔 부리 달린 큰 동그라미)를 완전히 걷어내고, 항상 고정 위치·고정
// 크기(예전 "활성" 크기)로만 뜨는 단순 원형 버튼으로 바꿈. 더 이상 축 옆에
// 붙어서 축 선을 가리킬 필요가 없어져서 부리(beak)도 통째로 삭제함(요청:
// "코드상으로도 삭제" 관례 그대로 따름) - 아래에 있던 idle/active 크기
// 분기, _LeftBeakPainter 전부 제거.
class _AxisIndicator extends StatelessWidget {
  const _AxisIndicator();

  // ⭐ 예전 "활성(탭됨)" 크기 그대로 - 요청: "지금 탭했을 때만큼의 크기로
  // 키운다음에" 고정.
  static double get _iconSize => (50 * 7 / 8).r;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _iconSize,
      height: _iconSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 7,
              offset: const Offset(0, 2))
        ],
      ),
      // ⭐ 2026-08-27(3차) - "인디케이터가 가까이서 보면 자글자글하다"는
      // 피드백 - 원본(assets/icon/app_icon.png)은 1024×1024라 해상도 자체는
      // 충분한데, Flutter Image의 기본 FilterQuality(low, 단순 bilinear)로
      // 이렇게 큰 비율(1024px → ~44dp)을 축소하면 세밀한 선(아이콘 내부
      // 디테일)이 밀리언스 없이 계단져 보임 - FilterQuality.high로 올려서
      // 축소 시 밉맵 품질 보간을 쓰게 함.
      child: const ClipOval(
        child: Image(
            image: AssetImage('assets/icon/app_icon.png'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high),
      ),
    );
  }
}

// ⭐ 일정 한 줄 - "내용"만 있는 구조(제목 없앰, 요청)로, 렌더링 스타일을
// 8종 실험해보기 위해 block.styleIndex(1~8)로 분기함. 어떤 스타일이든
// 공통 규칙 두 가지는 지킴:
//  1) 아이콘은 항상 첫 줄(시간이 나오는 줄) 정중앙에 오도록
//     Transform.translate(0, -iconDiameter/2)로 눈금선에 맞춤 - "아이콘/시간과
//     정확히 동일한 가로선" 요청.
//  2) heightForStyle()이 실제로 그리는 내용과 항상 정확히 맞아야 함 - 같은
//     슬롯에 여러 일정이 쌓일 때 그 값을 그대로 각 줄의 세로 간격으로
//     쓰기 때문에(_TimeAxisPickerState._recomputeLayout 참고), 여기서
//     과소평가하면 다음 일정의 아이콘/줄과 겹침(예전 버그).
class _ScheduleRow extends StatelessWidget {
  final DateSchedule block;
  final String timeLabel;
  final double iconDiameter;
  // ⭐ 2026-08-27(2차) - 배경색 설정에 따라 유동적으로 바뀌는 두 텍스트색
  // (요청: "시간 숫자랑 내용 텍스트는 서로 다른 색상 규칙") - 이 위젯은
  // ref에 접근할 수 없는 StatelessWidget이라, 계산은 부모
  // (_TimeAxisPickerState.build())가 하고 값만 여기로 내려받음.
  final Color timeTextColor;
  final Color contentTextColor;
  final VoidCallback onTap;
  // ⭐ 2026-08-27 - 예전엔 이 카드 위 드래그도 인디케이터에 얹어서 생성모드로
  // 새 나갔는데("이미 생성된 일정을 눌러도 인디케이터가 우측으로 빠지면서
  // 생성모드로 감" 버그 리포트) - 완전히 제거함. 이제 이 카드는 onTap(편집
  // 모드 진입)만 반응하고, 세로 드래그는 아예 안 받아서(GestureDetector에
  // 등록을 안 함) 제스처 아레나에서 자동으로 부모 스크롤뷰가 가져감 - "카드
  // 위에서 드래그하면 그냥 스크롤됨" 요청과도 맞음.
  const _ScheduleRow({
    required this.block,
    required this.timeLabel,
    required this.iconDiameter,
    required this.timeTextColor,
    required this.contentTextColor,
    required this.onTap,
  });

  // ⭐ 2026-08-27 - 렌더링 스타일 3번(밑줄 강조)으로 확정, 나머지 7종은
  // 코드째로 삭제(요청: "팝업에서 선택하는 거 다 삭제, 코드상으로도 삭제").
  // iconDiameter는 axisPicker와 동일한 스케일 getter를 그대로 참조함(같은
  // 파일=라이브러리라 접근 가능).
  // ⭐ 첫 줄~내용 줄 사이 간격을 6.h→2.h로 줄임(요청: "시간이랑 너무 멀리
  // 떨어져있다") - _buildBody()의 SizedBox와 반드시 같이 맞출 것.
  // ⭐ 2026-08-27 - "raw 값 그대로면 기기별 화면 차이를 못 맞춘다"는 지적으로
  // 이 파일의 축 좌표계 전체가 따르는 표준 스케일 보정(N*7/8 → .h/.w/.r,
  // _TimeAxisPickerState 상단 주석 참고)에 맞춤 - safety도 원래 raw(12.0,
  // 스케일 아예 없었음)였던 걸 같이 고침.
  static double get heightForStyle {
    final iconD = _TimeAxisPickerState._iconDiameter;
    final safety = (12 * 7 / 8).h; // 폰트별 줄높이 편차 대비 여유분
    return iconD + (2 * 7 / 8).h + (26 * 7 / 8).h + iconD / 2 + safety;
  }

  String get _categoryAsset => _kScheduleCategoryIcons[
          block.iconIndex.clamp(0, _kScheduleCategoryIcons.length - 1)]
      .$3;

  // ⭐ 2026-08-27 - 아이콘 배경 3단계(요청):
  //  1) 1시간 이내(또는 시간 미정) - 지금처럼 정원
  //  2) 1~2시간 - 원을 아래로 살짝 늘림
  //  3) 2시간 초과 - 스타일 3번의 세로 막대(밑줄)가 끝나는 라인까지 전부.
  // "약간 더 길게 해서 세로 막대기 끝과 맞춰라"는 요청으로 +8.h를 얹었다가,
  // ⭐ 2026-08-27(2차) - "4시간짜리 도형이 살짝 더 커져도 될 것 같다"는 재요청으로
  // +8→+16으로 한 번 더 키움(heightForStyle의 safety 여유분(12*7/8) 안에서
  // 충분히 안전 - _ScheduleRow.heightForStyle 계산 참고).
  double _iconBgHeight(double diameter) {
    final duration = block.durationMinutes;
    if (duration == null || duration <= 60) return diameter;
    final fullSpan =
        diameter + (2 * 7 / 8).h + (26 * 7 / 8).h + (16 * 7 / 8).h;
    if (duration <= 120) {
      return diameter + (fullSpan - diameter) * 0.55;
    }
    return fullSpan;
  }

  // ⭐ 아이콘 자체를 살짝 아래로 눌러서(시각적 위치만, 레이아웃 크기는 그대로)
  // 시간 텍스트와 나란히 보이게 하는 미세조정값.
  // ⭐ 2026-08-27(2차) - "일정 아이콘이 시간보다 살짝 위에서 렌더링된다"는
  // 재확인 피드백 - Row(crossAxisAlignment.center)는 아이콘/텍스트를 각자의
  // "레이아웃 박스" 중심으로 맞추는데, 텍스트 박스는 폰트 자체의 여유
  // 행간(디센더 자리 등)이 아이콘 원의 진짜 중심과 다르게 배분돼서 살짝
  // 어긋나 보임 - 아이콘의 "그려지는 위치"만(레이아웃 폭/높이는 그대로,
  // Stack+Clip.none 트릭이라 가능) 이 값만큼 아래로 밀어서 보정.
  static double get _iconVisualNudgeDown => (2 * 7 / 8).h;

  // ⭐ Stack + 레이아웃 전용 SizedBox(diameter×diameter) 트릭 - 실제 배경(pill)은
  // Positioned(top:0)으로 그 위에 겹쳐 그리고 Clip.none으로 아래로 넘치게 둠.
  // 이렇게 하면 배경이 아무리 길어져도 Row/Column의 "크기 계산"에는 항상
  // diameter만 반영돼서, 시간 라벨·내용 텍스트 위치가 전혀 안 흔들림(요청:
  // "시간이랑 내용은 일단 위치 그대로 지키고").
  Widget _icon(double diameter) {
    final bgHeight = _iconBgHeight(diameter);
    final glyphSize = diameter * 0.52;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(width: diameter, height: diameter),
        Positioned(
          top: _iconVisualNudgeDown,
          left: 0,
          child: Container(
            width: diameter,
            height: bgHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: block.color,
              borderRadius: BorderRadius.circular(diameter / 2),
            ),
            child: SizedBox(
              width: glyphSize,
              height: glyphSize,
              child: SvgPicture.asset(
                _categoryAsset,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ⭐ 2026-08-27 - 내용 텍스트는 "진한 검정색 bold체" 느낌으로(요청) -
  // fontWeight를 w500→w700으로 올림. 폰트는 5번(주아체) 고정.
  // ⭐ 2026-08-27(2차) - color 기본값을 고정 kAppChipBorder 대신
  // contentTextColor(배경색에 따라 유동)로.
  TextStyle _contentStyle({double size = 14, Color? color}) => GoogleFonts.jua(
      fontSize: size.sp, fontWeight: FontWeight.w700, color: color ?? contentTextColor);

  // ⭐ 2026-08-27 - 세로축 시간 숫자와 스타일 통일(요청: "세로축의 숫자랑
  // 일정에 생성되는 숫자랑 크기+색깔+텍스트 스타일을 전부 맞추자"). 폰트=
  // Quicksand w700(축과 동일), 크기는 축(19sp)보다 작고 예전 값(13sp)보다는
  // 큼(16sp).
  // ⭐ 2026-08-27(2차) - 색은 고정 kScheduleTimeNumberColor 대신
  // timeTextColor(배경색에 따라 유동)로. tabularFigures도 축 숫자와
  // 동일하게 적용(같은 스타일 통일 요청 연장선).
  TextStyle get _timeTextStyle => GoogleFonts.quicksand(
      fontSize: 16.sp,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: timeTextColor);

  // ⭐ 2026-08-27 - "아이콘/시간/그 사이 공간을 탭해도 편집모드로" 요청 -
  // HitTestBehavior.opaque로 GestureDetector 자기 영역(Positioned가 준 전체
  // 칸) 안이면 자식이 안 그린 빈 공간이라도 전부 탭을 잡음(기본값
  // deferToChild는 실제로 뭔가 그려진 픽셀 위에서만 반응해서, 아이콘과 내용
  // 사이 여백을 탭하면 안 먹혔던 것).
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _buildBody(),
    );
  }

  // ⭐ 아이콘 + 시간 텍스트 한 줄.
  Widget _iconAndTimeRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _icon(iconDiameter),
        SizedBox(width: (10 * 7 / 8).w),
        Flexible(
          child: Text(
            timeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _timeTextStyle,
          ),
        ),
      ],
    );
  }

  Widget _firstLine() => Transform.translate(
      offset: Offset(0, -iconDiameter / 2), child: _iconAndTimeRow());

  // ⭐ 2026-08-27 - 렌더링 스타일 3번(밑줄/왼쪽 세로 막대 강조)으로 확정,
  // 나머지 7종은 코드째로 삭제(요청).
  // ⭐ 2026-08-27(2차) - "내용 바(세로 막대)를 조금만 더 위로" 재요청 - 이미
  // 6→2로 좁혀둔 SizedBox 간격만으론 더 줄일 여지가 별로 없어서(0에
  // 가까워짐), Transform.translate로 살짝(음수) 겹쳐서 그만큼 더 당김.
  // heightForStyle은 안 건드림 - safety 여유분(12*7/8)이 이 정도 겹침은
  // 충분히 흡수함(_ScheduleRow.heightForStyle 주석 참고).
  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _firstLine(),
        SizedBox(height: (1 * 7 / 8).h),
        Transform.translate(
          offset: Offset(0, -(2 * 7 / 8).h),
          child: Padding(
            padding: EdgeInsets.only(left: iconDiameter + (10 * 7 / 8).w),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: (3 * 7 / 8).w,
                    decoration: BoxDecoration(
                        color: block.color,
                        borderRadius: BorderRadius.circular((2 * 7 / 8).r)),
                  ),
                  SizedBox(width: (8 * 7 / 8).w),
                  Expanded(
                    child: Text(block.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _contentStyle()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ⭐ 일정 생성 시트 - 인디케이터로 시작 시간을 고정한 뒤 여기서 제목/내용/
// 소요시간을 정함.
// ============================================================

// ⭐ 2026-08-27 - 예전엔 여기 화면 로컬 DateSchedule 클래스가 있었는데,
// date_schedules 영구 저장(DB v20)으로 전환하며 lib/models/date_schedule.dart로
// 옮김(그 파일이 kScheduleBlockColors도 같이 들고 있음). 이 화면은 그걸 import해서 씀.

// ⭐ 카테고리 아이콘 10종 - assets/icons/memo_category/README.md의 매핑과
// 동일(memo_category_icon_lab_screen.dart의 kMemoCategoryIcons도 같은
// 목록이지만, 그 파일은 "확인용 임시 화면"이라 나중에 지워질 수 있어서
// 여기 독립적으로 같은 목록을 둠 - 그 파일이 지워져도 이 화면은 안 깨짐).
const List<(String key, String label, String asset)> _kScheduleCategoryIcons = [
  ('work', '업무', 'assets/icons/memo_category/work.svg'),
  ('study', '공부', 'assets/icons/memo_category/study.svg'),
  ('exercise', '운동', 'assets/icons/memo_category/exercise.svg'),
  ('health', '병원·건강관리', 'assets/icons/memo_category/health.svg'),
  ('meal', '식사', 'assets/icons/memo_category/meal.svg'),
  ('social', '약속/사교', 'assets/icons/memo_category/social.svg'),
  ('family', '가족', 'assets/icons/memo_category/family.svg'),
  ('shopping', '쇼핑', 'assets/icons/memo_category/shopping.svg'),
  ('leisure', '여가/휴식', 'assets/icons/memo_category/leisure.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc.svg'),
];

// ⭐ 2026-08-27 - 글씨체 5종(고운돋움/개구쟁이/도현체/나눔펜/주아체) 실험을
// 접고 5번(주아체)으로 확정하면서 이 함수/목록 삭제(요청: "코드상으로도
// 삭제"). 이제 _ScheduleRow._contentStyle()이 GoogleFonts.jua를 직접 씀.

// ⭐ 소요시간 프리셋 - "10분/15분/20분/30분/45분/1시간/2시간/4시간/5시간" 요청.
// 자유 입력 대신 프리셋 칩으로 고른 이유: 어차피 시작 시간도 30분 단위로
// 스냅해서 고르는 화면인데, 종료 시간까지 분 단위로 세밀하게 입력받으면
// 오히려 "축에서 손가락으로 척 찍는" 앞 단계와 결이 안 맞음 - 한 번 더
// 탭하는 것만으로 끝나는 칩이 가장 빠르고, 실제로 교대근무자가 쓸 만한
// 흔한 길이(짧은 휴식~긴 근무 블록)를 그대로 나열한 것도 이 목록의 근거.
const List<int> _kDurationPresets = [10, 15, 20, 30, 45, 60, 120, 240, 300];

// ⭐ 2026-08-27(3차) - "1시간 30분"처럼 한글 단위를 쓰면 나중에 30분 단위
// 조정까지 들어갔을 때("1시간 30분" 같은 조합) 레이아웃을 너무 많이 먹어서
// "h"/"m" 표기로 교체(요청) - 예: "30m", "1h", "1h 30m".
String _durationPresetLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

// ⭐ 2026-08-27 - 12시간제(AM/PM) 변환. 자정=12:00 AM, 정오=12:00 PM.
(String hhmm, String period) _to12Hour(int totalMinutes) {
  final h24 = (totalMinutes ~/ 60) % 24;
  final m = totalMinutes % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  var h12 = h24 % 12;
  if (h12 == 0) h12 = 12;
  return (
    '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
    period,
  );
}

// ⭐ 2026-08-27 - 시간 표시 전면 개편(요청):
//  - "~" 대신 "-"
//  - AM/PM 표기 - 시작/끝이 같은 오전·오후면 끝에 한 번만("10:00 - 11:00 AM"),
//    다르면 각각("10:00 AM - 01:00 PM")
//  - 소요시간이 없으면(요청: "몇 시간 할지는 안 정해도 되게") 시작 시각만
//    ("10:00 AM") - 범위/소요시간 괄호 없음.
String _scheduleTimeLabel(int startMinutes, int? durationMinutes) {
  final (startHHMM, startPeriod) = _to12Hour(startMinutes);
  if (durationMinutes == null) {
    return '$startHHMM $startPeriod';
  }
  final endTotal = (startMinutes + durationMinutes).clamp(0, 24 * 60);
  final (endHHMM, endPeriod) = _to12Hour(endTotal);
  final durationLabel = _durationPresetLabel(durationMinutes);
  // ⭐ 2026-08-27(2차) - "-가 너무 짧다"는 요청으로 하이픈(-) 대신 더 긴
  // 줄표(em dash, —)로 교체.
  if (startPeriod == endPeriod) {
    return '$startHHMM — $endHHMM $endPeriod ( $durationLabel )';
  }
  return '$startHHMM $startPeriod — $endHHMM $endPeriod ( $durationLabel )';
}

class _CreateBlockSheet extends StatefulWidget {
  final int startMinutes;
  // ⭐ null이면 새로 만드는 중, 값이 있으면 그 일정을 수정하는 중(제목/내용/
  // 소요시간만 - 시작 시간은 인디케이터 전용이라 여기선 고정).
  final DateSchedule? existing;
  const _CreateBlockSheet({required this.startMinutes, this.existing});

  // ⭐ Navigator.pop(context, deleteSignal)로 "삭제를 눌렀다"를 알림 - 저장
  // 결과(DateSchedule)와 구분해야 해서 별도 sentinel 값을 씀.
  static const Object deleteSignal = '__delete__';

  @override
  State<_CreateBlockSheet> createState() => _CreateBlockSheetState();
}

class _CreateBlockSheetState extends State<_CreateBlockSheet> {
  late final _contentController =
      TextEditingController(text: widget.existing?.content ?? '');
  // ⭐ 2026-08-27 - null 허용(요청: "몇 시간 할지는 안 정해도 되게") - null이면
  // "시작 시각만" 표시(_scheduleTimeLabel 참고). 새 일정 기본값은 기존과 동일한
  // 30분(UI는 나중에 다듬을 예정, 지금은 토글만 추가).
  late int? _selectedDuration = widget.existing?.durationMinutes ?? 30;
  // ⭐ 2026-08-27 - 스타일/폰트/아이콘 선택 팝업 전부 삭제(요청: "팝업 간소화,
  // 스타일 3번·글씨체 5번으로 확정"). 아이콘은 이제 항상 자동분류만 씀 -
  // _iconManuallySet 같은 "수동 우선" 개념 자체가 없어짐(고를 UI가 없으니까).
  bool _autoClassifying = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // ⭐ 제목이 없어졌으니 이제 "내용"이 유일한 필수 입력.
  bool get _isValid => _contentController.text.trim().isNotEmpty;

  // ⭐ 2026-08-27 - 저장 버튼 핸들러. 아이콘 선택 팝업이 없어졌으므로 항상
  // 내용 텍스트로 자동분류(MemoCategoryClassifier)함 - 분류에 실패(모델 로드
  // 전 등)하면 조용히 기본값(0=업무)으로 저장, 이것 때문에 저장 자체가
  // 막히면 안 됨.
  Future<void> _handleSave() async {
    var iconIndex = 0;
    String? predictedCategory;
    setState(() => _autoClassifying = true);
    try {
      await MemoCategoryClassifier.instance.ensureLoaded();
      final prediction = MemoCategoryClassifier.instance
          .classify(_contentController.text.trim());
      predictedCategory = prediction.categoryKey;
      final matched = _kScheduleCategoryIcons
          .indexWhere((e) => e.$1 == prediction.categoryKey);
      if (matched != -1) iconIndex = matched;
    } catch (e) {
      debugPrint('⚠️ 카테고리 자동분류 실패(기본 아이콘으로 저장): $e');
    } finally {
      if (mounted) setState(() => _autoClassifying = false);
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      DateSchedule(
        date: '', // _openCreateSheet/_openEditSheet가 실제 날짜로 덮어씀
        content: _contentController.text.trim(),
        startMinutes: widget.startMinutes,
        durationMinutes: _selectedDuration,
        styleIndex: 3, // ⭐ 스타일 3번(밑줄 강조)으로 확정(요청) - 더 이상 선택 안 함
        fontIndex: 5, // ⭐ 글씨체 5번(주아체)으로 확정(요청)
        iconIndex: iconIndex,
        predictedCategory: predictedCategory,
        // ⭐ 수동 선택 자체가 없어져서 "정정" 개념이 성립 안 함 - 항상 false.
        isUserCorrected: false,
        createdAt: '', // 위와 동일 - 호출부가 덮어씀
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(minHeight: 420.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                      color: kAppChipBorder.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2.r)),
                ),
              ),
              SizedBox(height: 18.h),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? '일정 수정' : '새 일정',
                      style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w800,
                          color: kAppChipBorder),
                    ),
                  ),
                  if (_isEditing)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(
                          context, _CreateBlockSheet.deleteSignal),
                      icon: const Icon(Icons.delete_outline,
                          color: Color(0xFFD64545), size: 18),
                      label: const Text('삭제',
                          style: TextStyle(color: Color(0xFFD64545))),
                    ),
                ],
              ),
              SizedBox(height: 20.h),
              TextField(
                controller: _contentController,
                autofocus: true,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '내용',
                  filled: true,
                  fillColor: const Color(0xFFF4F6FC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide.none),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                ),
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 22.h),
              Text('시간',
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: kAppChipBorder.withValues(alpha: 0.6))),
              SizedBox(height: 8.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                decoration: BoxDecoration(
                    color: kAppMainAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12.r)),
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 18.sp, color: kAppMainAccent),
                    SizedBox(width: 8.w),
                    Flexible(
                      child: Text(
                        _scheduleTimeLabel(
                            widget.startMinutes, _selectedDuration),
                        style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: kAppMainAccent),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10.h),
              Text('시작 시간 + 얼마나? (선택 안 하면 시작 시각만 표시돼요)',
                  style: TextStyle(
                      fontSize: 11.5.sp,
                      color: kAppChipBorder.withValues(alpha: 0.45))),
              SizedBox(height: 8.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  // ⭐ 2026-08-27 - 소요시간 미정 토글(요청: "시간을 추가하고
                  // 안하고는 사용자 선택으로"). UI는 나중에 다듬을 예정 -
                  // 지금은 프리셋 칩과 같은 모양의 토글 하나만.
                  GestureDetector(
                    onTap: () => setState(() => _selectedDuration = null),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: _selectedDuration == null
                            ? kAppMainAccent
                            : const Color(0xFFF4F6FC),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '시간 미정',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: _selectedDuration == null
                              ? Colors.white
                              : kAppChipBorder.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  for (final preset in _kDurationPresets)
                    GestureDetector(
                      onTap: () => setState(() => _selectedDuration = preset),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: _selectedDuration == preset
                              ? kAppMainAccent
                              : const Color(0xFFF4F6FC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _durationPresetLabel(preset),
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: _selectedDuration == preset
                                ? Colors.white
                                : kAppChipBorder.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 12.h),
              // ⭐ 2026-08-27 - 스타일/글씨체/아이콘 선택 팝업 전부 삭제(요청:
              // "팝업 간소화" - 스타일 3번·글씨체 5번 고정, 아이콘은 항상
              // 내용으로 자동분류). 안내 문구 하나만 남김.
              Text(
                '아이콘은 내용으로 자동 판단해서 붙여요.',
                style: TextStyle(
                    fontSize: 11.5.sp,
                    color: kAppChipBorder.withValues(alpha: 0.45)),
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h)),
                      child: const Text('취소'),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          (_isValid && !_autoClassifying) ? _handleSave : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAppMainAccent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                      child: _autoClassifying
                          ? SizedBox(
                              width: 18.w,
                              height: 18.w,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isEditing ? '저장' : '생성'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ⭐ 2026-08-27 - 일정관리 전용 설정 화면. 날짜 스트립 맨 끝 톱니바퀴에서
// 진입(요청). 지금은 배경색 선택 하나만 - 다른 옵션은 나중에 추가.
// ============================================================

class _ScheduleSettingsScreen extends ConsumerWidget {
  const _ScheduleSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(scheduleBackgroundProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('일정관리 설정'),
        backgroundColor: Colors.white,
        foregroundColor: kAppChipBorder,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('배경화면',
                style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: kAppChipBorder)),
            SizedBox(height: 4.h),
            Text(
              '일정관리 탭의 배경색을 골라주세요(상태표시줄·광고·하단 탭바는 제외).',
              style: TextStyle(
                  fontSize: 12.sp, color: kAppChipBorder.withValues(alpha: 0.55)),
            ),
            SizedBox(height: 18.h),
            Wrap(
              spacing: 14.w,
              runSpacing: 14.h,
              children: [
                for (int i = 0; i < kScheduleBackgroundColors.length; i++)
                  GestureDetector(
                    onTap: () => ref
                        .read(scheduleBackgroundProvider.notifier)
                        .setColorIndex(i),
                    child: Container(
                      width: 52.w,
                      height: 52.w,
                      decoration: BoxDecoration(
                        color: kScheduleBackgroundColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == selectedIndex
                              ? kAppMainAccent
                              : kAppChipBorder.withValues(alpha: 0.15),
                          width: i == selectedIndex ? 3 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: i == selectedIndex
                          ? Icon(Icons.check,
                              color: kScheduleBackgroundColors[i]
                                          .computeLuminance() >
                                      0.5
                                  ? Colors.black87
                                  : Colors.white,
                              size: 20.sp)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
