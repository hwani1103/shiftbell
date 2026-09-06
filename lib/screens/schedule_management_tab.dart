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

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n_extensions.dart';
import '../models/calendar_theme.dart';
import '../models/date_schedule.dart';
import '../models/shift_schedule.dart';
import '../providers/calendar_theme_provider.dart';
import '../providers/date_schedule_provider.dart';
import '../providers/schedule_background_provider.dart';
import '../providers/schedule_provider.dart';
import '../services/memo_category_classifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_second_button.dart';
import '../widgets/app_shift_chip.dart';

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
  const ScheduleManagementTab({super.key});

  @override
  ConsumerState<ScheduleManagementTab> createState() =>
      _ScheduleManagementTabState();
}

class _ScheduleManagementTabState extends ConsumerState<ScheduleManagementTab> {
  late DateTime _selectedDate;
  final ScrollController _dateStripController = ScrollController();

  // ⭐ 2026-09-01 - "스와이프가 너무 조금만 해도 날짜가 넘어간다"는 지적으로
  // 추가. 예전엔 onHorizontalDragEnd의 속도(velocity)만 보고 판정했는데,
  // 세로 시간축을 스크롤하다가 손가락이 살짝 비스듬해지기만 해도 그 순간의
  // 속도가 우연히 임계값을 넘을 수 있었음(짧고 빠른 드래그일수록 취약) -
  // 그래서 "실제로 얼마나 옆으로 움직였는지"(누적 dx)도 같이 요구하도록
  // 바꿈 - 속도 + 거리 둘 다 충족해야만(더 확실하고 의도적인 스와이프만)
  // 날짜가 넘어감.
  double _dayDragDx = 0;

  // ⭐ 2026-09-03(4차) - _TimeAxisPicker 안의 "일정 선택모드"(같은 시간대
  // 여러 일정 중 좌우 드래그로 고르는 중) 동안엔 이 화면 바깥쪽의 날짜
  // 스와이프 제스처를 완전히 꺼야 함 - 안 그러면 두 가로 드래그 인식기가
  // 같은 제스처 아레나에서 경합해서 "드래그가 너무 민감하다/대각선에도
  // 반응한다"는 문제가 생김(선택모드 쪽 드래그가 이 화면 전체를 덮는
  // GestureDetector의 자식이라 항상 같이 경합함). _TimeAxisPicker가
  // onSelectionModeChanged로 이 값을 올려줌.
  bool _childSelectionModeActive = false;

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
    // ⭐ 2026-09-03(12차) - "미래로 갈 땐 날짜 칩이 깜빡이는데 과거로 갈 땐
    // 깔끔하다" 버그 - 월 이동도 스와이프(_shiftDay)와 같은 원인이라 같이
    // 고침(_shiftDay 쪽 주석 참고).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollDateStripToSelected());
  }

  // ⭐ 2026-08-28 - "메인화면 좌우 스와이프하면 다음날/이전날로" 요청 - 예전엔
  // 이 화면 전체를 덮는 GestureDetector가 가로 스와이프를 "달력탭으로 이동"에
  // 썼는데(그마저도 우측 스와이프만 반응하고 좌측은 무반응이었음), 이제 그
  // 기능 자체를 없애고 대신 날짜 이동으로 바꿈 - _shiftMonth와 동일한 패턴
  // (달의 마지막 날 근처에서 델타를 더해도 DateTime이 알아서 다음 달로 넘어감).
  void _shiftDay(int delta) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: delta));
    });
    // ⭐ 2026-09-03(12차) - "9/3에서 미래(9/4...)로 스와이프하면 날짜 칩들이
    // 깜빡이는데, 과거(9/2...)로 갈 땐 깔끔하다" 버그 - 원인은 방향이 아니라
    // _scrollDateStripToSelected()의 목표 스크롤 위치 계산(index*itemExtent
    // -90.w)이 달 초반(1~3일 정도, 마침 오늘 9/3이 여기 걸림)에서는
    // clamp(0.0, ...)에 의해 항상 0으로 고정된다는 것 - 그래서 그 구간
    // 안에서는(9/3↔9/2처럼) 실제로 스크롤이 전혀 안 움직여서 깔끔해 보였고,
    // 그 구간을 벗어나는(9/3→9/4 같은) 방향으로는 매번 실제 스크롤 이동이
    // 필요했음. 그런데 이 실제 스크롤을 여태 animate:false(jumpTo, 무보간)로
    // 처리하고 있었고, 그마저도 setState가 반영된 프레임보다 한 프레임 늦게
    // (addPostFrameCallback) 튀듯이 적용돼서 - 칩 하이라이트는 즉시 바뀌는데
    // 스크롤은 한 프레임 늦게 뚝 끊겨 튀는 두 단계가 눈에 "깜빡임"으로
    // 보였던 것. 날짜 탭(_buildDateStrip의 onTap)은 원래부터 이 함수를
    // animate:true(기본값)로 불러서 항상 부드러웠음 - 스와이프/월이동도
    // 똑같이 부드러운 애니메이션으로 통일해서 실제 스크롤이 필요한 구간에서도
    // 더 이상 뚝 끊겨 보이지 않게 함(최초 진입 시 initState의 jumpTo는
    // 그대로 유지 - 화면 첫 진입에 스크롤 애니메이션이 보이는 건 오히려
    // 어색하므로).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollDateStripToSelected());
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
      // ⭐ 2026-08-28 - 좌우 스와이프 = 다음날/이전날 이동으로 교체(예전엔
      // 달력탭으로 이동, 그마저도 우측 스와이프만 반응했음). 달 이동
      // (calendar_tab.dart)과 동일한 부호 규칙: velocity<0(왼쪽으로 스와이프)
      // → 다음날, velocity>0(오른쪽으로 스와이프) → 이전날.
      // ⭐ 2026-09-01 - "조금만 스와이프해도 넘어간다"는 지적으로 두 가지를
      // 같이 요구하도록 강화: (1) 속도 임계값을 300→600으로 올리고, (2) 드래그
      // 시작부터 끝까지 누적된 가로 이동 거리(_dayDragDx)가 최소 60논리픽셀은
      // 넘어야 함. 이 화면은 세로 시간축을 스크롤하는 게 주된 조작이라, 짧고
      // 빠른 대각선 드래그의 순간 속도만으로는 오작동하기 쉬웠음 - 거리 조건을
      // 더하면 "확실히 옆으로 민" 제스처만 통과함.
      // ⭐ 2026-09-03(4차) - 자식(_TimeAxisPicker)이 선택모드에 들어가 있는
      // 동안엔 이 가로 드래그 인식기 자체를 꺼서(_childSelectionModeActive)
      // 날짜 스와이프와 일정 선택 드래그가 서로 경합하지 않게 함.
      onHorizontalDragStart:
          _childSelectionModeActive ? null : (_) => _dayDragDx = 0,
      onHorizontalDragUpdate: _childSelectionModeActive
          ? null
          : (details) => _dayDragDx += details.delta.dx,
      onHorizontalDragEnd: _childSelectionModeActive
          ? null
          : (details) {
              final velocity = details.primaryVelocity;
              final dx = _dayDragDx;
              _dayDragDx = 0;
              if (velocity == null) return;
              const kMinVelocity = 600.0;
              const kMinDistance = 60.0;
              if (velocity < -kMinVelocity && dx < -kMinDistance) {
                _shiftDay(1);
              } else if (velocity > kMinVelocity && dx > kMinDistance) {
                _shiftDay(-1);
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
                    hasShiftToday: selectedHasShift,
                    onSelectionModeChanged: (active) {
                      if (_childSelectionModeActive != active) {
                        setState(() => _childSelectionModeActive = active);
                      }
                    })),
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
  // ⭐ 2026-09-03(4차) - "일정 선택모드"(_dragSlot != null) 진입/해제를
  // 부모(_ScheduleManagementTabState)에 알려서, 부모의 날짜 스와이프
  // 제스처와 여기 선택 드래그가 서로 경합하지 않게 함.
  final ValueChanged<bool> onSelectionModeChanged;
  const _TimeAxisPicker(
      {super.key,
      required this.hasShiftToday,
      required this.dateKey,
      required this.onSelectionModeChanged});

  @override
  ConsumerState<_TimeAxisPicker> createState() => _TimeAxisPickerState();
}

class _TimeAxisPickerState extends ConsumerState<_TimeAxisPicker>
    with TickerProviderStateMixin {
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

  // ⭐ 텍스트를 전반적으로 키우면서(요청) 한 줄 안에 다 들어가도록 같이 키움
  // (44→56 / 30→36→40) - "어차피 긴 글은 안 쓸 것 같다"는 전제라 아이콘도
  // 같이 살짝 키움. 40: 인디케이터를 줄이면서 생긴 여유만큼 한 번 더 키움.
  // ⭐ 2026-08-27 - "일정 스타일 8종" 도입으로 줄 높이가 스타일마다 달라져서
  // (겹침 버그 재발 방지, _ScheduleRow.heightForStyle 참고) 고정
  // "_rowHeight" 상수는 없앰 - 아이콘 지름만 여기 남음.
  static double get _iconDiameter => (40 * 7 / 8).r;

  // ⭐ 숫자/눈금을 축 왼쪽으로 옮기면서(요청) 그만큼 왼쪽 여백이 더 필요해짐
  // (숫자 텍스트 + 눈금이 들어갈 자리) - 26→58로 늘림.
  // 🔧 튜닝 포인트 1: 세로축(선+숫자열) 전체를 좌우로 옮기려면 이 숫자(58)를
  // 줄이면 왼쪽으로, 늘리면 오른쪽으로 감 - _axisX가 이 값 그대로임(아래
  // build()의 `_axisX = _axisLeftMargin;`).
  static double get _axisLeftMargin => (48 * 7 / 8).w;

  // ⭐ 2026-09-03 - 일정 카드의 실제 가로 위치/폭 - 원래
  // _buildScheduleRowWidgets(rowLeft 매개변수)/build()에만 흩어져 있던 계산을
  // 여기 getter로 모음. "내용 두 줄 필요 여부" 실측(_recomputeLayout에서 씀)이
  // 카드가 실제로 그려질 때와 정확히 같은 폭을 알아야 하기 때문 - build()가
  // 넘겨주는 rowLeft와 반드시 같은 값이어야 함(아래 rowLeft 계산과 동일 공식).
  static double get _rowRightMargin => (16 * 7 / 8).w;
  double get _rowLeft => _axisX + (18 * 7 / 8).w;
  // 내용 텍스트가 실제로 그려지는 폭 = 카드 전체 폭 - (아이콘+간격만큼의
  // 왼쪽 들여쓰기) - (세로 막대 폭 + 막대~텍스트 간격) - _ScheduleRow._buildBody()의
  // Padding/Container 치수와 정확히 같은 값을 써야 함.
  double get _contentTextWidth =>
      _viewportWidth -
      _rowLeft -
      _rowRightMargin -
      (_iconDiameter + (10 * 7 / 8).w) -
      (3 * 7 / 8).w -
      (8 * 7 / 8).w;
  // ⭐ 2026-08-28 - "일정생성 flow 개선" 전면 재작업으로 온-axis 드래그
  // 인디케이터(부리 달린 원, _AxisIndicator/_LeftBeakPainter)를 완전히
  // 폐기함(요청: "기존의 그 인디케이터는 안 쓰게 되는 거니까"). 대신:
  //  - 우측 하단에 "항상 같은 자리에" 떠 있는 원형 버튼(_ScheduleFab)이
  //    비활성/활성 두 상태만 가짐(위치는 안 바뀜) - 이 마진/비율 두 상수가
  //    그 고정 위치를 정함.
  //  - 시간 선택 자체는 축 위에 뜨는 사각형 배지 2개(_selectedSlot,
  //    아래 build()의 "시간 선택 배지" 참고)로 표현하고, 스크롤 추적(방식 1)
  //    또는 축 직접 탭(방식 2)으로만 움직임 - 더 이상 손가락으로 이 버튼
  //    자체를 드래그하지 않음.
  static double get _fabRightMargin => (24 * 7 / 8).w;
  static const double _idleIndicatorVerticalRatio = 0.625;
  // ⭐ 정각 눈금(숫자+선) 한 칸의 "고정" 높이 - 이 값으로 Positioned에 실제
  // height를 줘서 Row를 정확히 이 높이만큼 강제로 차지하게 만듦. 예전엔
  // Row의 높이를 텍스트 폰트 크기로 눈대중해서 "-9"라는 추정값으로 중앙
  // 정렬했는데, 실제 렌더 높이와 추정치가 안 맞아서 정각 눈금 자체가
  // 눈금선(slotTop)보다 살짝 밀려 그려졌음(=화살표가 정각을 가리킬 때
  // "선보다 약간 위"를 가리키는 것처럼 보인 원인). 30분 눈금처럼 높이를
  // 고정해서 -H/2로 계산하면 텍스트 실제 높이와 무관하게 항상 정확히
  // slotTop이 중앙이 됨.
  static double get _hourTickBoxHeight => (24 * 7 / 8).h;
  // ⭐ 2026-08-27(5차) - 축 시간 숫자를 "한 글자 = 고정 폭 칸"으로 그리기
  // 위한 칸 폭(00 정렬 버그 수정, 아래 for(hour...) 루프 참고) - 지금
  // 폰트 크기(17.sp) 기준으로 숫자 하나가 넉넉히 들어갈 정도로 여유 있게
  // 잡음(칸이 좀 넓어도 가운데 정렬이라 다른 숫자와의 정렬엔 영향 없음).
  static double get _hourDigitCellWidth => (13 * 7 / 8).w;
  // ⭐ 2026-08-28 - "일정생성 flow 개선" - 시간 선택 배지(축 숫자를 감싸는
  // 사각형 + 그 우측의 "08:00 AM" 사각형) 크기/간격. 왼쪽 배지는 축 숫자
  // 칸(_hourDigitCellWidth 2개)을 넉넉히 감싸는 정도, 높이는 정각 눈금
  // 칸(_hourTickBoxHeight)보다 살짝 커서 사각형 티가 나게.
  static double get _pickerBadgeHeight => (30 * 7 / 8).h;
  static double get _pickerHourBadgeWidth => (44 * 7 / 8).w;
  static double get _pickerBadgeGap => (6 * 7 / 8).w; // 축 선~배지 사이 간격
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

  // ⭐ 2026-08-28 - "스크롤이 한번씩 버벅인다" 피드백 - 원인은 이 축이
  // SingleChildScrollView의 기본 드래그(관성/fling 포함)를 안 쓰고
  // _onAxisDragUpdate에서 매 포인터 이벤트마다 델타를 그대로 jumpTo하는
  // 방식이라서(_virtualOffset 필드 주석 참고, "화면 끝에서도 인디케이터가
  // 계속 갈 수 있어야" 해서 이렇게 만들었음) - 손을 떼는 순간 스크롤이 즉시
  // 멈춰서, 나머지 앱(날짜스트립 등 일반 ListView)의 자연스러운 관성 스크롤과
  // 비교되어 "뚝 끊긴다"는 인상을 줌. _virtualOffset 트릭 자체는 그대로 두고
  // (여전히 축 끝단 오버슛/calibration에 필요), 손을 뗄 때만 FrictionSimulation
  // 으로 감속 애니메이션을 얹어서 "던지면 관성으로 더 굴러간다"를 흉내냄 -
  // 매 프레임 같은 클램프/스냅 로직(_applyVirtualOffset)을 그대로 타므로
  // 끝단 동작(calibration)은 전혀 안 바뀜.
  late final AnimationController _flingController;

  // ⭐ 2026-08-27 - date_schedules 테이블(DB v20)에서 영구 저장으로 전환.
  // build()마다 dateScheduleProvider를 watch해서 최신값으로 갱신함(아래
  // build() 참고) - 여기 초기값은 그 갱신 전까지의 플레이스홀더일 뿐.
  List<DateSchedule> _blocks = const [];

  // ⭐ 2026-08-28 - "일정생성 flow 개선" - 우측 하단 버튼(_ScheduleFab)이
  // 활성 상태인지. false면 시간 선택 배지도 안 그리고 슬롯 추적도 안 함
  // (_onAxisDragUpdate 참고) - 그냥 평소처럼 자유 탐색용 스크롤만 됨.
  bool _pickerActive = false;
  // ⭐ 활성 상태일 때 선택된 슬롯(30분 단위, 0~47) - null이면 비활성.
  int? _selectedSlot;
  // ⭐ 활성 버튼 둘레에 도는 "여기를 누르라"는 펄스 링 애니메이션 -
  // repeat()로 계속 돔, 비활성화되면 stop().
  late final AnimationController _pulseController;

  // ⭐ 2026-08-28(2차/3차) - "인디케이터 이동은 스크롤 추적(방식 1)만 남기고,
  // 화면이 물리적으로 더 스크롤 안 되는 축 양 끝에서도 인디케이터는 계속
  // 갈 수 있게" 요청으로 도입. 축 스크롤을 SingleChildScrollView의 기본
  // 드래그(ClampingScrollPhysics)에 맡기지 않고, 이 위젯이 직접
  // GestureDetector로 세로 드래그를 받아서 "가상 오프셋"을 계산함:
  //  - _virtualOffset은 드래그 델타를 그대로 뺄셈해서 누적하되,
  //    _virtualOffsetMin/Max(인디케이터가 슬롯 0/마지막 슬롯에 닿는 지점)로
  //    클램프함 - 화면에 실제로 적용하는 스크롤 오프셋은 이 값을 다시
  //    [0, maxScrollExtent]로 클램프한 것(_onAxisDragUpdate의 jumpTo).
  //  - 화면이 이미 끝(0 또는 maxScrollExtent)에 닿아 있어도 _virtualOffset
  //    자체는 (min/max 한도까지는) 계속 움직이므로("화면은 멈춰도 인디케이터는
  //    계속 감"), 인디케이터 위치 계산(_centerContentY)은 항상 이 값을 기준으로 함.
  //  - 반대 방향으로 다시 드래그하면, 화면에 적용되는 클램프된 값이
  //    [0, maxScrollExtent] 범위 안으로 돌아올 때까지는 화면은 안 움직임(=
  //    "calibration 구간") - 다만 3차 수정으로 _virtualOffset 자체에도 상한을
  //    둬서, 이 구간이 "슬롯 0/마지막 슬롯까지 도달하는 데 필요한 만큼"으로
  //    항상 유한함 - 끝에서 몇 번을 더 밀어도 그 이상 늘어나지 않음(예전엔
  //    무한정 쌓여서, 여러 번 밀수록 되돌리기가 점점 힘들어지는 버그였음).
  // 드래그 제스처가 끝나도 리셋하지 않음 - 다음 드래그가 이어서 정확히
  // 같은 지점부터 시작해야 하므로(안 그러면 손을 뗐다 다시 잡을 때 인디케이터가
  // 화면에 보이는 위치에서 갑자기 04시 등으로 튀어버림).
  double? _virtualOffset;

  double _viewportHeight = 0;
  double _viewportWidth = 0;
  double _axisX = 0;
  TextScaler _textScaler = TextScaler.noScaling;

  // ⭐ 매 build마다 다시 계산됨(_recomputeLayout) - 일정이 추가/삭제되면
  // 슬롯 높이가 바뀌므로. 제스처 콜백(build 밖)에서도 참조해야 해서 필드로 캐싱.
  Map<int, List<DateSchedule>> _grouped = {};
  List<double> _slotTops = List<double>.filled(_slotCount + 1, 0);

  // ⭐ 2026-08-31("D번") - 같은 슬롯에 일정이 여러 개일 때 "지금 맨 앞에 보이는
  // 게 몇 번째(그룹 내 인덱스)인가"만 기억함. build()마다 새로 계산되는
  // _grouped와 달리 이건 순수 UI 상태(사용자가 스택을 몇 번 넘겼는지)라
  // 별도 필드로 유지 - _recomputeLayout이 다시 불려도(일정 추가/삭제 등)
  // 리셋 안 됨(같은 슬롯이 계속 존재하는 한).
  final Map<int, int> _stackFrontIndex = {};

  // ⭐ 2026-09-03(3차 재설계, 요청) - "아이콘을 누르고 바로 드래그"가 아니라
  // "아이콘을 탭하면 선택모드로 토글 진입 → 그 다음엔 화면 아무 데서나
  // 좌우로 드래그하면 선택 대상이 바뀜"으로 바꿈. _dragSlot이 null이 아니면
  // 그 슬롯이 지금 "선택모드"라는 뜻(이름은 그대로 두지만 이제 "드래그 중"이
  // 아니라 "선택모드 활성" 의미로 씀 - 토글 진입 시점엔 아직 손가락이 안
  // 움직였어도 이미 true). 이 상태 동안엔 실제 _stackFrontIndex를 안 바꾸고
  // (카드/스택 순서 그대로), 오직 _dragPreviewIndex만 바뀌어서 "어떤 아이콘이
  // 확대돼 보이는지"만 미리보기함 - 드래그를 손을 떼는 순간(_endIconDrag)
  // 그제서야 _stackFrontIndex에 반영됨(선택모드 자체는 유지 - 다시 드래그해서
  // 또 바꿀 수 있고, 아이콘을 다시 탭해야 완전히 선택모드에서 빠져나감).
  int? _dragSlot;
  int _dragStartIndex = 0;
  int _dragPreviewIndex = 0;
  double _dragStartX = 0;

  // ⭐ front 아이콘을 탭할 때마다 토글 - 꺼져 있으면 이 슬롯을 선택모드로
  // 켜고(현재 front를 미리보기 시작점으로), 이미 이 슬롯이 켜져 있으면
  // 아무것도 안 바꾸고 그대로 끔(취소).
  void _toggleSelectionMode(int slot) {
    setState(() {
      if (_dragSlot == slot) {
        _dragSlot = null;
      } else {
        _dragSlot = slot;
        _dragPreviewIndex = _stackFrontIndex[slot] ?? 0;
        _dragStartIndex = _dragPreviewIndex;
      }
    });
    // ⭐ 2026-09-03(4차) - 선택모드 진입/해제를 부모에 알려서 날짜 스와이프
    // 제스처를 그동안 꺼두게 함(_ScheduleManagementTabState 참고).
    widget.onSelectionModeChanged(_dragSlot != null);
  }

  // ⭐ 선택모드가 켜진 뒤, 화면 아무 데서나 시작되는 가로 드래그를 여기서
  // 받음(_TimeAxisPickerState.build()의 최상위 GestureDetector가 호출) -
  // 이 드래그가 시작되는 지점은 토글할 때 누른 위치와 무관하므로 시작
  // 기준(x좌표/시작 인덱스)을 여기서 다시 잡음.
  void _handleSelectionDragStart(DragStartDetails details) {
    if (_dragSlot == null) return;
    _dragStartX = details.globalPosition.dx;
    _dragStartIndex = _dragPreviewIndex;
  }

  // ⭐ 가로 이동량을 "한 칸"(아이콘 지름 정도) 단위로 끊어서, 그 칸 수만큼
  // 시작 인덱스에서 이동. 실제 stack 순서/카드는 안 바꾸고 _dragPreviewIndex만
  // 갱신(요청: "드래그 중에는 실제 stack 순서와 카드 내용을 변경하지
  // 않는다").
  // ⭐ 2026-09-03(10차) - "계속 드래그하면 계속 바뀐다(쭈르르륵), 좌우로만
  // 움직이게 고쳐" 요청 - 예전엔 모듈로(순환)라서 손을 안 떼고 한 방향으로
  // 계속 밀면 ①→②→③→①→②→③...으로 끝없이 계속 바뀌었음. 이제 순환을
  // 없애고 [0, groupLength-1] 범위로 그냥 clamp - 끝(맨 앞/맨 뒤)에 도달하면
  // 더 밀어도 거기서 멈추고 더 이상 안 바뀜.
  // ⭐ 2026-09-03(10차 긴급수정) - "우측 드래그로 바꾼 뒤 다시 선택모드에
  // 들어가면 방향이 반대로 느껴진다" 버그 - 방금 위 clamp를 "절대 리스트
  // 인덱스"(_dragStartIndex + rawSteps) 기준으로 걸었던 게 원인. 렌더링
  // 쪽(_buildScheduleRowWidgets)의 캐스케이드 위치는 항상 "지금 front로부터의
  // depth"((i - frontIndex) % length)로 정해지는데, 절대 인덱스로 clamp하면
  // front가 바뀔 때마다(예: 2로 바뀜) 그 인덱스가 이미 최댓값 근처라서 우측
  // 드래그로는 더 못 가고 좌측으로만 가야 하는 등 방향이 뒤집혀 보였음.
  // depth(0=front, 커질수록 캐스케이드 더 먼 아이콘)를 직접 clamp하고, 그
  // depth를 렌더링과 동일한 공식으로 절대 인덱스로 변환하도록 고침 - 이제
  // front가 뭐든 상관없이 "오른쪽으로 밀수록 캐스케이드 순서대로(가까운 것
  // →먼 것) 선택"이 항상 똑같이 성립함(끝에 도달하면 clamp로 멈춤,
  // 좌측으로는 더 못 감 - front보다 "얕은" depth가 없으므로).
  void _handleSelectionDragUpdate(DragUpdateDetails details) {
    final slot = _dragSlot;
    if (slot == null) return;
    final groupLength = _grouped[slot]?.length ?? 1;
    if (groupLength <= 1) return;
    final dx = details.globalPosition.dx - _dragStartX;
    // ⭐ 2026-09-03(8차) - "스크롤(드래그)이 너무 빠르게 넘어간다, 조금만
    // 더 느리게" 요청으로 한 칸 이동에 필요한 드래그 거리를 34→60으로 늘림
    // (더 많이 밀어야 다음 아이콘으로 넘어감).
    final stepDistance = (60 * 7 / 8).w;
    final rawSteps = (dx / stepDistance).round();
    final depth = rawSteps.clamp(0, groupLength - 1);
    // ⭐ 2026-09-03(11차) - "못 가는 방향으로 계속 밀면, 반대로 돌릴 때 그만큼
    // 다시 쭉 밀어야 겨우 옮겨진다" 버그 - depth는 clamp했지만 rawSteps(=dx)
    // 자체는 계속 누적돼서, 끝에 막힌 채로 계속 밀면 "빚"(반대 방향으로
    // 되돌려야 할 거리)이 끝없이 쌓였음. _onAxisDragUpdate의 _virtualOffset이
    // min/max로 자체 클램프해서 이 문제를 막은 것과 같은 방식 - depth가
    // clamp돼서 rawSteps와 달라졌으면(=경계에 막힌 상태) _dragStartX 자체를
    // "지금 이 손가락 위치에서 딱 이 depth가 나오는 지점"으로 재설정함.
    // 그러면 다음 프레임부터는 여기서부터 다시 재는 셈이라 빚이 전혀 안
    // 쌓이고, 방향을 반대로 돌리는 즉시(한 칸 거리만 밀어도) 바로 옆 depth로
    // 넘어감.
    if (depth != rawSteps) {
      _dragStartX = details.globalPosition.dx - depth * stepDistance;
    }
    final newIndex = (_dragStartIndex + depth) % groupLength;
    if (newIndex != _dragPreviewIndex) {
      setState(() => _dragPreviewIndex = newIndex);
    }
  }

  // ⭐ 손을 떼는 순간 미리보기 중이던 인덱스를 실제로 확정 - 이때부터
  // _stackFrontIndex가 바뀌어서 AnimatedPositioned(_buildScheduleRowWidgets)가
  // 자연스러운 전환 애니메이션으로 그 카드를 앞으로 옮김. 선택모드 자체도
  // 같이 끔(요청상 명시는 안 됐지만, 확정 후에도 선택모드가 계속 켜져
  // 있으면 "이미 골랐는데 왜 아직도 확대돼 보이지" 하는 혼란을 줄 수 있어서 -
  // 다시 바꾸고 싶으면 새로 탭해서 켜면 됨).
  void _handleSelectionDragEnd(DragEndDetails details) {
    final slot = _dragSlot;
    if (slot == null) return;
    setState(() {
      _stackFrontIndex[slot] = _dragPreviewIndex;
      _dragSlot = null;
    });
    // ⭐ 2026-09-03(10차) - "선택모드가 꺼진 다음(취소하거나 바꿨을 때)에는
    // 드래그모드가 리셋돼야 한다" 버그 수정 - _toggleSelectionMode(취소로
    // 꺼질 때)는 이 콜백을 부르는데, 여기(드래그로 확정돼서 꺼질 때)는
    // 빠져있었음 - 그래서 드래그로 한 번이라도 확정하고 나면 부모
    // (_ScheduleManagementTabState._childSelectionModeActive)가 계속 true로
    // 남아서 날짜 스와이프가 영영 막히는 버그였음. 여기도 동일하게 호출.
    widget.onSelectionModeChanged(false);
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _flingController = AnimationController.unbounded(vsync: this)
      ..addListener(_onFlingTick);
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
    // ⭐ 2026-09-03(4차) - 날짜 스트립 탭/월 이동처럼 스와이프를 거치지 않는
    // 경로로도 날짜가 바뀔 수 있어서(그러면 key: ValueKey(dateKey)가 바뀌어
    // 이 State 자체가 파괴됨), 선택모드가 켜진 채로 이 위젯이 사라지면
    // 부모의 _childSelectionModeActive가 영영 true로 남아 날짜 스와이프가
    // 계속 막히는 버그가 생김 - 파괴되는 순간 명시적으로 꺼줌.
    if (_dragSlot != null) {
      widget.onSelectionModeChanged(false);
    }
    _controller.dispose();
    _pulseController.dispose();
    _flingController.dispose();
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

  // ⭐ 2026-08-31("D번") - 같은 슬롯(같은 30분 자리)에 일정이 여러 개면 더 이상
  // 세로로 쌓아 슬롯을 늘리지 않음 - 맨 앞(front) 일정 하나만 제자리에 전부
  // 보여주고, 나머지는 그 카드 우상단에 작은 원으로 살짝만 겹쳐 보이는
  // "카드 스택"으로 바꿈(탭/스와이프로 순서를 바꿔가며 봄, _buildScheduleRowWidgets
  // 참고). 그래서 슬롯 높이는 이제 "일정이 있냐 없냐"와 "일정이 2개 이상이라
  // 뒷카드가 살짝 삐져나올 여유가 필요하냐"만 좌우함 - 개수를 곱하지 않음.
  // ⭐ 2026-09-03 - 스택 UI 재설계(드래그로 선택)에 맞춰 5→3으로 낮춤(요청) -
  // 뒤 아이콘이 겹쳐 쌓이는 구조라 5개까지 허용하면 너무 빽빽해짐.
  static const int _maxSchedulesPerSlot = 3;
  static double get _stackPeekAllowance => (14 * 7 / 8).h;

  // ⭐ 2026-09-03 - "내용이 길어서 한 줄에 안 들어가면 두 번째 줄까지 쓰자"
  // 요청 - 스택의 맨 앞(front, 실제로 전체 크기로 그려지는) 카드가 실제로
  // 몇 줄을 쓸지 실측해서 그만큼 슬롯 높이를 확보함. 뒤에 숨은(peek) 카드는
  // 항상 작은 원 하나로만 보이므로(내용 텍스트 자체를 안 그림) 줄 수와 무관 -
  // group 전체가 아니라 front 하나만 보면 됨.
  double _frontCardHeight(int slot, List<DateSchedule> group) =>
      _frontCardLayout(slot, group).height;

  // ⭐ 2026-09-03 - height/twoLines를 한 번에 반환 - _buildScheduleRowWidgets가
  // _ScheduleRow에 twoLines를 그대로 넘겨줘야 해서(2줄 전용 여백 좁히기),
  // 같은 실측(needsTwoLines)을 두 번 하지 않도록 묶음.
  ({double height, bool twoLines}) _frontCardLayout(
      int slot, List<DateSchedule> group) {
    final frontIndex = (_stackFrontIndex[slot] ?? 0) % group.length;
    final front = group[frontIndex];
    final twoLines = _ScheduleRow.needsTwoLines(
      front.content,
      _contentTextWidth,
      textScaler: _textScaler,
    );
    return (height: _ScheduleRow.heightForLines(twoLines ? 2 : 1), twoLines: twoLines);
  }

  void _recomputeLayout() {
    final grouped = <int, List<DateSchedule>>{};
    for (final b in _blocks) {
      // ⭐ startMinutes(정확한 시작 시각, 5분 단위로 미세조정될 수 있음)가
      // 아니라 slotMinutes(정각이면 그 정각, 아니면 그 시간대의 30분 자리 -
      // date_schedule.dart의 computeSlotMinutes 참고)로 그룹핑함.
      final slot = (b.slotMinutes ~/ 30).clamp(0, _slotCount - 1);
      grouped.putIfAbsent(slot, () => []).add(b);
    }
    // ⭐ "맨 처음(가장 이른 시각) 일정이 기본으로 맨 앞에 보인다"를 위해 항상
    // 시작 시각 오름차순으로 정렬해둠 - _buildScheduleRowWidgets/스택 순서
    // 전부 이 정렬을 그대로 신뢰함.
    for (final list in grouped.values) {
      list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
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
        height = _frontCardHeight(i, blocksHere);
        if (blocksHere.length > 1) height += _stackPeekAllowance;
        if (height < _baseSlotHeight) height = _baseSlotHeight;
      }
      // ⭐ 2026-09-03(재수정) - 홀수(30분) 슬롯 카드는 _tickDisplayY로 앞뒤
      // 정각의 "정중앙"에 배치되는데(_buildScheduleRowWidgets 참고), 그
      // 정중앙이 진짜 안 겹치면서도 항상 똑같은 자리이려면 "앞 정각 슬롯의
      // 높이"가 뒤에 오는 30분 카드의 유무와 무관하게 항상 일정해야 함 -
      // 안 그러면 "11시가 비어있을 때"와 "11시에 뭐가 있을 때"의 11시30분
      // 카드 위치가 달라짐(첫 시도 - _slotTops[slot]로 clamp만 하는 방식은
      // 겹침은 막았지만 "11시 쪽으로 치우쳐 보인다"는 새 문제를 만듦 -
      // 재확인 피드백으로 발견). 그래서 짝수(정각) 슬롯은 "바로 다음 홀수
      // (30분) 슬롯에 카드가 있으면" 자기 자신은 비어있어도 그 카드 높이만큼
      // 미리 예약해둔다 - 그러면 정중앙 계산이 항상 "정각 슬롯 높이의 절반"
      // 지점이 되어(증명: 앞 정각 높이=h, 뒤 30분 카드 높이=h일 때 두 정각
      // 사이 중점 = 앞 정각 시작+h = 30분 슬롯의 원래 시작점과 정확히 일치)
      // 정각에 카드가 있든 없든 완전히 똑같은 위치가 됨.
      if (i.isEven) {
        final nextOddBlocks = grouped[i + 1];
        if (nextOddBlocks != null && nextOddBlocks.isNotEmpty) {
          // ⭐ 2026-09-03 - 예약량도 그 30분 카드가 실제로 몇 줄을 쓸지(내용
          // 두 줄 필요 여부)에 맞춰야 함 - 아니면 두 줄짜리 카드가 1줄
          // 기준으로만 예약된 자리에 들어가면서 다음 정각과 다시 겹침.
          final reserve = _frontCardHeight(i + 1, nextOddBlocks);
          if (height < reserve) height = reserve;
        }
      }
      cursor += height;
    }
    tops[_slotCount] = cursor;
    _grouped = grouped;
    _slotTops = tops;
  }

  // ⭐ 2026-08-31("D번") - 같은 슬롯의 일정이 1개면 예전과 동일하게 제자리에
  // 그대로 그림. 2개 이상이면 "카드 스택"으로 바꿈: 맨 앞(front) 하나만 전부
  // 보여주고, 나머지는 그 카드 우상단(1시 방향)에 작게(가장 작은 원 크기,
  // 회색으로 살짝 가려짐) 겹쳐 보이게 배치함. 각 항목에 ValueKey(block.id)를
  // 줘서, 앞/뒤가 바뀔 때 같은 위젯 인스턴스가 유지된 채 AnimatedPositioned가
  // 새 위치로 부드럽게 옮겨가게 함(겹치는 카드가 "앞으로 다가오는" 전환).
  // ⭐ 2026-09-03 - "단순 탭으로 순서 바꾸기"를 완전히 없애고 재설계(요청):
  // 이제 스택의 아무 아이콘(front든 back이든)이나 누르자마자(long press
  // 아님) 좌우로 드래그하면 그 이동량만큼 "선택 예정" 아이콘이 스택 안에서
  // 바뀌며 살짝 확대+그림자로 미리보기되고(_dragPreviewIndex), 손을 떼는
  // 순간에만 실제로 확정됨(_endIconDrag가 _stackFrontIndex를 갱신) - 드래그
  // 도중엔 카드 내용/스택 순서 자체는 전혀 안 바뀜. 상세 팝업은 이제 아이콘이
  // 아니라 카드(시간/내용 텍스트) 쪽을 탭해야만 열림 - _ScheduleRow 내부에서
  // 아이콘과 카드의 제스처를 완전히 분리해둠(아이콘=onIconDrag*, 카드=onTap).
  // ⭐ 2026-09-03(4차) - activeOnTop: 지금 선택모드 중인 슬롯의 아이콘들만
  // 따로 담아서 반환 - build()가 스크림 위에 한 번 더 그려서 "선택 중인
  // 아이콘 영역만 스크림에 안 가려짐"을 구현함(요청).
  // ⭐ 2026-09-03(5차) - "중심간 거리/각도를 내가 직접 테스트해볼게" 요청으로
  // 스택 뒤 아이콘 ②③의 위치를 결정하는 세 값을 여기 한곳에 상수로 모음.
  // 아래에서 실제로 어떻게 쓰이는지는 이 상수들 바로 아래 for문 안
  // (cumulativeDx/Dy 계산부) 참고 - 셋 다 "①→②" "②→③" 두 구간에 똑같이
  // 적용되는 "한 칸" 벡터를 만드는 재료임.
  //  - _kStackCenterDistance: 두 아이콘 "중심 사이" 거리(iconDiameter 비율).
  //    ①→②, ②→③ 두 구간 모두 이 값 하나로 고정(요청: "중심간의 거리는
  //    고정인 채로 각도만"). 낮출수록 서로 더 바짝(살짝만) 겹쳐 보임.
  //  - _kStackAngle1Deg: ①→②의 방향(각도). 0=수평 우측, 90=수직 위 방향.
  //  - _kStackAngle2Deg: ②→③의 방향(각도). 값이 1보다 작을수록(수평에
  //    가까울수록) "위보다 옆으로 더 치우친" 느낌이 남.
  // ⭐ 2026-09-03(5차) - "아주 살짝씩만 보이게 더 좁혀" 요청으로 0.40→0.22.
  static const double _kStackCenterDistance = 0.33;
  static const double _kStackAngle1Deg = 35;
  static const double _kStackAngle2Deg = 20;

  // ⭐ 2026-09-03(5차) - "선택모드가 아닌 평소 화면에서만 뒤에 숨은 아이콘을
  // 살짝 줄여보고 싶다" 요청 - 앞 아이콘/선택모드 중 크기(_iconDiameter,
  // _ScheduleRow._kStackSmallRatio)는 그대로 두고, 이 비율 하나만 평소
  // peek 크기에 곱함. 1.0이면 지금과 동일(앞 아이콘과 완전히 같은 크기).
  static const double _kPeekNormalSizeRatio = 0.75;

  ({List<Widget> normal, List<Widget> activeOnTop}) _buildScheduleRowWidgets(
      double rowLeft, _ScheduleColorScheme scheme) {
    final widgets = <Widget>[];
    final activeOnTop = <Widget>[];
    final rightMargin = (16 * 7 / 8).w;
    const animDuration = Duration(milliseconds: 320);
    // ⭐ 2026-09-03 - 드래그로 스택을 선택하고 손을 뗐을 때 "자연스러운 spring
    // animation"으로 전환하라는 요청 - 물리 기반 SpringSimulation 대신(과한
    // 엔지니어링), 살짝 오버슈트했다가 정착하는 easeOutBack 커브로 스프링
    // 느낌만 냄. 이 커브/시간은 스택 재정렬 전환 전체(드래그로 바뀔 때뿐
    // 아니라 일정 추가/삭제로 바뀔 때도)에 공통 적용됨 - 기존보다 durations을
    // 260→320ms로 살짝 늘려서 오버슈트가 눈에 편하게 보이게 함.
    const animCurve = Curves.easeOutBack;

    for (final entry in _grouped.entries) {
      final slot = entry.key;
      final group = entry.value;
      // ⭐ 2026-09-03 - _recomputeLayout()이 예약한 높이와 반드시 같은 계산을
      // 써야 함(front 카드가 두 줄이면 실제로 그만큼 그려야 안 잘림). twoLines도
      // 같이 받아서 아래 _ScheduleRow에 그대로 넘김(여백 좁히기용).
      final frontLayout = _frontCardLayout(slot, group);
      final h = frontLayout.height;
      // ⭐ 2026-09-01 - "30분 슬롯 일정이 실제 30분 위치가 아니라 정각 바로
      // 밑에 붙는다" 재확인 피드백. 원인은 _tickDisplayY() 위 주석(2026-08-31)에
      // 이미 정확히 진단돼 있음 - 그 슬롯 자체에 카드가 있으면 그 슬롯의 렌더
      // 높이가 커져서 "다음 정각" 경계만 아래로 밀리고, "이 30분 슬롯의 시작
      // 경계"(_slotTops[slot])는 그대로라 두 정각 사이에서 위쪽으로 치우쳐
      // 보임. 그때는 이 비대칭을 "시간 선택 배지"(임시 UI)에서만 고치고 실제
      // 카드 배치는 안 건드렸는데, 이번엔 카드 자체도 고침 - 홀수(30분)
      // 슬롯의 카드 top을 _tickDisplayY(앞뒤 정각의 보정된 중간점)로 맞춤.
      // ⭐ 후속6 - 처음엔 이 지점에 "중심 정렬"(top = 중간점 - h/2)했다가
      // 재확인 피드백으로 다시 고침: "카드는 그 지점부터 시작해야 하는데
      // 그 지점에서 끝나버린다"(카드 절반이 위로 삐져나와 앞 정각 슬롯과
      // 겹침) - 중심 정렬이 아니라 그 지점을 top으로 삼는 상단 정렬이 맞음.
      // ⭐ 2026-09-03(재수정) - 위 "알려진 한계"가 실제로 재발했고(11시 비면
      // 12시와 겹침), 1차 수정(중간점을 _slotTops[slot]로 clamp)은 겹침은
      // 없앴지만 "11시가 비어있을 때 카드가 11시 쪽으로 너무 치우쳐 보인다"는
      // 새 문제(재확인 피드백)를 만듦 - "11시에 있든 없든 항상 정중앙"이
      // 목표인데 clamp 방식은 "있을 때만 정중앙, 없을 때는 위쪽 경계"로 둘이
      // 달라짐. 근본 수정은 _recomputeLayout()으로 옮김 - 앞 정각(짝수) 슬롯이
      // 자기 자신은 비어있어도 "바로 다음 30분 슬롯에 카드가 있으면" 그 카드
      // 높이만큼 미리 예약해두게 해서, 정중앙 계산 자체가 정각 슬롯의
      // 유무와 무관하게 항상 똑같은 값이 나오도록 만듦(증명은 그쪽 주석
      // 참고) - 그래서 여기는 다시 순수 _tickDisplayY(중간점)만 쓰면 되고,
      // 이제 그 중간점 자체가 항상 안전함(겹침도 없고 위치도 항상 동일).
      final frontTop = slot.isOdd
          ? _edgePadding + _tickDisplayY(slot)
          : _edgePadding + _slotTops[slot];
      final frontIndex = (_stackFrontIndex[slot] ?? 0) % group.length;
      final isDraggingThisSlot = _dragSlot == slot;

      // ⭐ 2026-09-03 - back(뒤에 숨은) 위젯을 먼저 모으고 front 위젯을 맨
      // 나중에 widgets에 추가함 - Stack은 나중에 추가된 자식이 위에 그려지는데,
      // frontIndex가 반드시 i=0이 아니라서(스택 순서 자유) 예전 코드처럼 i
      // 순서 그대로 추가하면 front가 뒤에 깔릴 수 있었음(잠재적 z-order 버그,
      // 이번에 같이 고침) - front는 항상 맨 위에 그려져야 함.
      // ⭐ 2026-09-03(7차) - "왜 3번째가 2번째보다 위에 있냐, 3번째가 가장
      // 밑으로 가야 한다"는 지적 - 원인은 이 리스트가 원래 그룹의 시간순
      // 인덱스(i) 순서 그대로 추가돼서, cascade(스택 깊이)와 무관하게 쌓였기
      // 때문이었음. depth도 같이 담아뒀다가 루프가 끝난 뒤 depth 내림차순으로
      // 정렬해서 넣음(depth가 클수록=더 뒤/아래쪽으로 치우친 아이콘일수록
      // 먼저 그려지고, depth가 작을수록=front에 가까운 아이콘일수록 나중에
      // 그려져서 위로 옴 - front 바로 아래까지 항상 "가까운 게 위, 먼 게
      // 아래" 순서가 보장됨).
      final backEntries = <(int depth, Widget widget)>[];
      Widget? frontWidget;
      // ⭐ 2026-09-03(6차) - "드래그로 왔다갔다할 때 지금 선택된(=isPreview)
      // 게 커지긴 하는데 다른 아이콘 뒤에 깔릴 수 있다" 버그 수정용 - preview
      // 상태인 위젯은 그게 front든 back이든 이 변수에 따로 담아뒀다가 맨
      // 마지막에 추가해서, 그 슬롯 안에서 무조건 최상단(z-order 가장 위)에
      // 그려지게 함.
      Widget? previewWidget;

      // ⭐ 2026-09-03(3차) - 앞 아이콘의 실제 화면 위치(왼쪽 위 기준) - 뒤에
      // 숨은 원들의 위치를 전부 이 지점 기준 상대 오프셋으로 계산함.
      final frontIconTop = frontTop - _iconDiameter / 2;
      // ⭐ 2026-09-03(5차) - 평소(선택모드 아닐 때)엔 _kPeekNormalSizeRatio로
      // 살짝 줄이고, 선택모드 중엔 앞 아이콘과 동일한 완전 크기로.
      final peekDiameter = isDraggingThisSlot
          ? _iconDiameter * _ScheduleRow._kStackSmallRatio
          : _iconDiameter *
              _ScheduleRow._kStackSmallRatio *
              _kPeekNormalSizeRatio;

      for (var i = 0; i < group.length; i++) {
        final block = group[i];
        final depth = (i - frontIndex + group.length) % group.length;
        final key = ValueKey('sched_${block.id}');
        // ⭐ 2026-09-03(3차) - 선택모드(이 슬롯이 _dragSlot과 같음) 동안엔
        // front도 실제 소요시간 아이콘 대신 peek과 같은 크기/색으로 잠깐
        // 바뀜(_ScheduleRow.iconUniformSmall) - "왔다갔다하는 순간엔 가장
        // 작은 원 크기로, 색상도 표시" 요청.
        final isPreview = isDraggingThisSlot && i == _dragPreviewIndex;

        if (depth == 0) {
          final widget = AnimatedPositioned(
            key: key,
            duration: animDuration,
            curve: animCurve,
            top: frontTop,
            left: rowLeft,
            right: rightMargin,
            height: h,
            child: _ScheduleRow(
              block: block,
              timeLabel: _timeRangeLabel(block),
              iconDiameter: _iconDiameter,
              timeTextColor: scheme.timeText,
              contentTextColor: scheme.contentText,
              // ⭐ 2026-09-03 - 아이콘에서는 더 이상 안 열림(요청) - 카드
              // (시간 텍스트/내용 줄)에서만 열리도록 _ScheduleRow 내부에서
              // 이미 분리해뒀음(아이콘은 onIconTap 전용 - 선택모드 토글).
              // ⭐ 2026-09-03(4차) - 선택모드 중(isDraggingThisSlot)이면 카드
              // 탭 자체를 꺼버림 - 이 위젯 인스턴스는 스크림 위(activeOnTop)에도
              // 그대로 다시 쓰이는데, 거기서도 카드 탭이 막혀야 하므로 원천에서
              // null 처리(요청: "오로지 좌우 드래그로 일정 변경하는 것만").
              onTap: isDraggingThisSlot ? null : () => _openEditSheet(block),
              twoLines: frontLayout.twoLines,
              onIconTap:
                  group.length > 1 ? () => _toggleSelectionMode(slot) : null,
              iconUniformSmall: isDraggingThisSlot,
              iconIsPreview: isPreview,
            ),
          );
          // ⭐ 2026-09-03(6차) - front 자리(depth==0)라도 지금 preview로
          // 미리보기 중이면 previewWidget 쪽으로 - 맨 마지막에 추가되어
          // 최상단이 되게 함(front는 원래도 backWidgets보다 나중에 추가돼서
          // 이미 위였지만, back 아이콘이 preview인 경우와 일관되게 같은
          // 경로로 통일).
          if (isPreview) {
            previewWidget = widget;
          } else {
            frontWidget = widget;
          }
          continue;
        }

        // ⭐ 2026-09-03(3차 재수정) - 위치 공식: "3개일 때 ①은 정위치, ②는
        // ①에서 약간 우상단, ③은 ②에서 다시 약간 우상단인데 위보다는 옆으로
        // 더 치우친 각도 - 단, ①~②, ②~③ 두 구간의 '중심 사이 거리'는 서로
        // 같아야 함". 두 스텝을 서로 다른 각도의 벡터로 따로 정의하되 거리는
        // 완전히 동일한 _kStackCenterDistance 하나만 씀. 최대 3개(스택 인원
        // 제한)라 cascade는 0(2번째) 또는 1(3번째)뿐이라 이 두 벡터만 있으면
        // 충분함.
        // ⭐ 2026-09-03(5차) - "중심간 거리/각도를 내가 직접 조절해볼게" 요청
        // 으로 세 값(_kStackCenterDistance/_kStackAngle1Deg/_kStackAngle2Deg,
        // 이 함수 바로 위 선언부)을 밖으로 빼고 여기는 그 값으로 벡터만
        // 계산하게 정리 - 값 자체는 저 위 상수만 바꾸면 됨(여기 수식은 안
        // 건드려도 됨).
        final cascade = (depth - 1).clamp(0, 1);
        const angle1 = _kStackAngle1Deg * math.pi / 180;
        const angle2 = _kStackAngle2Deg * math.pi / 180;
        final step1Dx = _iconDiameter * _kStackCenterDistance * math.cos(angle1);
        final step1Dy = -_iconDiameter * _kStackCenterDistance * math.sin(angle1); // 위로 음수
        final step2Dx = _iconDiameter * _kStackCenterDistance * math.cos(angle2);
        final step2Dy = -_iconDiameter * _kStackCenterDistance * math.sin(angle2);
        final cumulativeDx = cascade == 0 ? step1Dx : step1Dx + step2Dx;
        final cumulativeDy = cascade == 0 ? step1Dy : step1Dy + step2Dy;
        final backWidget = AnimatedPositioned(
          key: key,
          duration: animDuration,
          curve: animCurve,
          top: frontIconTop + cumulativeDy,
          left: rowLeft + cumulativeDx,
          width: peekDiameter,
          height: peekDiameter,
          child: AnimatedOpacity(
            duration: animDuration,
            // ⭐ 2026-09-03(7차) - "선택모드에서 아이콘 배경이 반투명해 보인다,
            // 아예 불투명으로" 요청 - 평소(선택모드 아닐 때)엔 기존처럼
            // cascade에 따라 살짝 옅어지는 느낌을 유지하되, 선택모드
            // 중(isDraggingThisSlot)에는 무조건 1.0(완전 불투명).
            opacity:
                isDraggingThisSlot ? 1.0 : (0.9 - cascade * 0.15).clamp(0.4, 1.0),
            child: AnimatedScale(
              duration: animDuration,
              curve: animCurve,
              scale: isPreview ? 1.1 : 1.0,
              // ⭐ 2026-09-03(3차) - 뒤에 숨은 원 자체엔 이제 제스처를 안
              // 붙임(요청 - "화면 아무 데서나" 드래그로 바뀌어야 하므로,
              // 이 원 위에서만 반응하던 예전 방식은 제거) - 순수 표시 전용.
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // ⭐ 2026-09-03(3차) - 선택모드일 때는 회색 대신 카테고리
                  // 고유색을 보여줌(요청: "뒤에 숨어있는애들도 아이콘 색상은
                  // 표시해").
                  // ⭐ 2026-09-03(5차) - "선택모드가 아닐 때도 색상 보이게"
                  // 재요청으로 회색 폴백을 아예 없애고 항상 block.color.
                  color: block.color,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: isPreview
                      ? const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 6,
                              offset: Offset(0, 2)),
                        ]
                      : const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 3,
                              offset: Offset(0, 1)),
                        ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(peekDiameter * 0.24),
                  child: SvgPicture.asset(
                    _kScheduleCategoryIcons[block.iconIndex
                            .clamp(0, _kScheduleCategoryIcons.length - 1)]
                        .$3,
                    colorFilter: const ColorFilter.mode(
                        Colors.white, BlendMode.srcIn),
                  ),
                ),
              ),
            ),
          ),
        );
        // ⭐ 2026-09-03(6차) - 이 back 아이콘이 지금 preview 중이면
        // backEntries가 아니라 previewWidget으로 - 맨 마지막에 추가되어
        // 다른 back 아이콘들(그리고 front)보다 항상 위에 그려지게 함
        // (요청: "드래그할 때마다 현재 선택된 게 그 위치에서 가장 위에서,
        // 가장 앞에서 가장 먼저 보이게").
        if (isPreview) {
          previewWidget = backWidget;
        } else {
          backEntries.add((depth, backWidget));
        }
      }

      // ⭐ 2026-09-03(7차) - depth 내림차순(먼 아이콘이 먼저=아래) 정렬 -
      // List.sort는 in-place라 여기서 한 번만 정렬.
      backEntries.sort((a, b) => b.$1.compareTo(a.$1));
      final orderedBackWidgets = [for (final e in backEntries) e.$2];

      widgets.addAll(orderedBackWidgets);
      if (frontWidget != null) widgets.add(frontWidget);
      if (previewWidget != null) widgets.add(previewWidget);
      // ⭐ 2026-09-03(4차) - "선택모드일 때 반투명 검정 배경이 아이콘 선택하는
      // 쪽까지 가리면 안 된다, 그쪽은 잘 보이게"라는 요청 - 이 슬롯이 지금
      // 선택모드 중이면 같은 위젯들을(키가 같아도 서로 다른 부모 아래라
      // 문제없음 - Flutter Key는 같은 형제 목록 안에서만 고유하면 됨) 별도
      // 목록에도 담아뒀다가, build()에서 스크림보다 나중에(=위에) 한 번 더
      // 그려서 스크림 위로 뚫린 것처럼 보이게 함. previewWidget도 여기서 항상
      // 맨 마지막에 추가돼서 activeOnTop 레이어 안에서도 최상단을 유지함.
      if (isDraggingThisSlot) {
        activeOnTop.addAll(orderedBackWidgets);
        if (frontWidget != null) activeOnTop.add(frontWidget);
        if (previewWidget != null) activeOnTop.add(previewWidget);
      }
    }
    return (normal: widgets, activeOnTop: activeOnTop);
  }

  Future<void> _openCreateSheet(int startMinutes) async {
    final raw = await _showFixedBottomSheet<DateSchedule>(
      context,
      builder: (context) => _CreateBlockSheet(startMinutes: startMinutes, dateKey: widget.dateKey),
    );
    if (!mounted || raw == null) return;
    if (_hasDuplicateRange(raw.startMinutes, raw.durationMinutes)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10n.scheduleDuplicateTimeSlot)),
      );
      return;
    }
    // ⭐ 2026-08-31("D번") - 같은 슬롯(같은 물리적 자리)의 카드 스택이 한도
    // 없이 늘어나면 계속 뒤로 숨겨지는 일정이 쌓이기만 하고 찾기 힘들어짐 -
    // 최대 개수로 제한(스펙: "최대 3~5개정도로 제한" → 2026-09-03 드래그
    // 선택 UI 재설계로 3개 확정).
    final countInSlot =
        _blocks.where((b) => b.slotMinutes == raw.slotMinutes).length;
    if (countInSlot >= _maxSchedulesPerSlot) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(context.l10n.scheduleMaxPerSlot(_maxSchedulesPerSlot))),
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
    final result = await _showFixedBottomSheet<Object>(
      context,
      builder: (context) => _CreateBlockSheet(
          startMinutes: block.startMinutes, dateKey: block.date, existing: block),
    );
    if (!mounted || result == null) return;
    if (result is DateSchedule &&
        _hasDuplicateRange(result.startMinutes, result.durationMinutes,
            exclude: block)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10n.scheduleDuplicateTimeSlot)),
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

  // ⭐ 콘텐츠 좌표(y, _slotTops와 같은 기준) → 가장 가까운 슬롯 "경계"
  // 인덱스(=그 슬롯이 시작하는 시각). 슬롯이 48개뿐이라 선형 탐색으로 충분함.
  // 30분 단위 시각 하나하나가 _slotTops의 각 원소와 정확히 대응되므로
  // (_slotTops[i] = i*30분 지점의 화면 y좌표), 스크롤 중심이 어느 시각에
  // 가장 가까운지는 이렇게 구하는 게 맞음. y가 범위 밖(먼 음수/큰 값)이어도
  // 알아서 가장 가까운 끝(0 또는 _slotCount-1)을 돌려줌 - _virtualOffset이
  // 화면 스크롤 한계 너머로 계속 누적될 때도 그대로 안전하게 동작함.
  int _nearestSlotToContentY(double y) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i <= _slotCount; i++) {
      final dist = (y - _slotTops[i]).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best.clamp(0, _slotCount - 1);
  }

  // ⭐ 2026-08-31 - "09시 30분에 일정이 있으면, 인디케이터가 09시와 10시의
  // 정중앙이 아니라 09시 바로아래에 위치한다" 버그 수정.
  // 원인: _slotTops[i]는 "그 시각이 시작되는 y좌표"(경계선)일 뿐이라, 정각
  // 슬롯끼리(예: 09시=_slotTops[18], 10시=_slotTops[20]) 높이가 똑같을 때만
  // 그 사이의 30분 슬롯(_slotTops[19])이 우연히 기하학적 정중앙과 일치함.
  // 그런데 그 30분 슬롯 자체에 일정이 쌓이면 그 슬롯의 렌더 높이가 커져서
  // (_recomputeLayout 참고) 10시 경계가 그만큼 아래로 밀리고, 09시~10시
  // 구간이 더 이상 위아래로 대칭이 아니게 됨 - 그 결과 09시 30분 표시 위치
  // (여전히 09시로부터 "고정 슬롯 높이 하나"만큼만 아래)가 실제 09시~10시
  // 구간의 정중앙보다 위쪽(=09시에 더 가깝게)에 있는 것처럼 보였음.
  // 수정: 30분(홀수) 슬롯의 "표시 위치"만 별도로, 그 앞뒤 정각(짝수) 슬롯
  // 두 개의 정확한 정중앙으로 다시 계산함 - 정각 자체의 위치나 실제 일정
  // 배치(_recomputeLayout/_buildScheduleRowWidgets)는 전혀 안 건드리고,
  // 오직 이 화면의 "시간 선택 배지" 두 개가 그리는 y좌표에만 적용함.
  double _tickDisplayY(int slot) {
    if (slot.isEven) return _slotTops[slot];
    final prevHour = slot - 1;
    final nextHour = (slot + 1).clamp(0, _slotCount);
    return (_slotTops[prevHour] + _slotTops[nextHour]) / 2;
  }

  // ⭐ 콘텐츠 좌표계("scrollOffset과 같은 기준"의 절대 위치)에서, 지금 화면
  // 정중앙에 있는 위치 - _virtualOffset(클램프 안 됨)을 기준으로 계산하므로,
  // 실제 화면 스크롤이 끝에 닿아 멈춰 있어도 이 값 자체는 계속 움직일 수
  // 있음(위 _virtualOffset 필드 주석 참고).
  double _centerContentY() {
    final offset = _virtualOffset ??
        (_controller.hasClients ? _controller.offset : 0.0);
    return offset + _viewportHeight / 2 - _edgePadding;
  }

  // ⭐ 2026-08-28(3차) - "끝에서 여러 번 계속 스크롤하면, 반대로 돌아올 때
  // 그만큼 다시 스크롤해야 움직인다" 재확인 버그 리포트 - 원인은
  // _virtualOffset을 완전히 무한정 누적시켰던 것(2차 구현). 인디케이터가
  // 실제로 갈 수 있는 곳은 어차피 슬롯 0(00:00)~마지막 슬롯(23:30)까지가
  // 전부인데, 그 이후로 계속 드래그해도 _virtualOffset이 한도 없이 계속
  // 쌓여서 "빚"이 무한히 늘어났던 것 - 반대 방향으로 되돌릴 때 그 빚을 다
  // 갚기 전까진 화면도 인디케이터도 안 움직이니, 여러 번 끝까지 밀면 밀수록
  // 되돌리기가 점점 힘들어짐. _virtualOffset 자체를 "중심이 슬롯 0/마지막
  // 슬롯에 정확히 오는 지점"까지만 움직이게 딱 그만큼만 클램프해서, 그
  // 지점에 도달한 뒤로는 같은 방향으로 더 밀어도 전혀 안 쌓이게 함 - 그래서
  // 반대로 돌리는 순간 항상 즉시 반응함(빚이 0 아니면 딱 그 지점에서
  // 시작하는 것과 동일 - "몇 번을 더 밀었든" 결과가 똑같아짐).
  double get _virtualOffsetMin => _edgePadding - _viewportHeight / 2;
  double get _virtualOffsetMax =>
      _slotTops[_slotCount - 1] + _edgePadding - _viewportHeight / 2;

  // ⭐ 2026-08-28(2차) - 축 스크롤 전체를 이 위젯이 직접 처리함(build()에서
  // SingleChildScrollView는 physics: NeverScrollableScrollPhysics로 사용자
  // 드래그를 안 받고, 대신 이 GestureDetector가 받음). 매 프레임:
  //  1) _virtualOffset을 델타만큼 갱신하되, 위 _virtualOffsetMin/Max로 클램프
  //     (3차 - "무한정 쌓이는 빚" 방지, 그 이상은 이 값 자체가 안 움직임).
  //  2) 화면에 실제로 보여줄 오프셋은 그걸 다시 [0, maxScrollExtent]로
  //     클램프한 값 - jumpTo로 적용. 화면 끝에 닿아도 _virtualOffset은
  //     (1)의 한도까지는 계속 움직이므로 "화면은 멈춰도 인디케이터는 계속
  //     간다"가 됨. 반대로 되돌리면 _virtualOffset이 다시 [0, maxScrollExtent]
  //     안으로 들어올 때까지만 화면이 안 움직임 - (1)에서 상한을 뒀으므로
  //     이 구간은 항상 유한(최대 "슬롯 0/마지막 슬롯이 화면 중앙에 오기까지"
  //     거리 하나뿐, 몇 번을 더 밀었든 늘어나지 않음).
  //  3) 활성 상태(_pickerActive)면 그 시점의 중심 슬롯을 다시 계산 -
  //     정수 슬롯이 바뀔 때만 setState해서 불필요한 리빌드를 피함
  //     (build()의 AnimatedPositioned가 "따라 따락" 계단식으로 보간해줌).
  // ⭐ 2026-08-28 - _onAxisDragUpdate/관성 애니메이션(_onAxisDragEnd) 양쪽이
  // 공유하는 핵심 로직만 뽑아냄 - "raw 가상 오프셋 하나를 받아서 클램프하고,
  // 실제 화면 스크롤에 적용하고, 활성 상태면 선택 슬롯을 갱신한다"는 동작
  // 자체는 손가락이 직접 미는 중이든 관성으로 굴러가는 중이든 완전히 동일해야
  // 끝단 오버슛/calibration 동작이 어긋나지 않음.
  // ⭐ 2026-08-31(재확인) - "끝까지 갔다가 그 방향으로 한 번 더 스크롤하면, 그
  // 다음 반대로 돌릴 때 처음 한 번은 꼭 버벅인다" 재확인 버그. 이전 수정(관성이
  // 물리적 끝에서 멈추게 한 것)은 "관성(fling)"이 만드는 빚만 막았을 뿐,
  // **손가락으로 직접 끝까지 드래그한 뒤에도 계속 미는 경우**(fling 없이 그냥
  // 쭉 미는 것)에 생기는 빚은 못 막았음 - _virtualOffsetMin/Max 오버슛은
  // _pickerActive(일정 생성/수정 시간 선택 모드) 여부와 무관하게 항상 적용되고
  // 있었는데, 정작 그 오버슛이 필요한 이유("인디케이터가 슬롯 0/47까지 정확히
  // 갈 수 있어야 함")는 오직 그 모드에서만 의미가 있음 - 평소 자유 스크롤에는
  // 이 오버슛이 아무 이득도 없이 "끝에서 밀수록 반대로 돌릴 때 첫 한 번 버벅이는"
  // 부작용만 남김. 그래서 이제 _pickerActive일 때만 오버슛을 허용하고, 아닐 땐
  // 그냥 [0, maxScrollExtent]로 곧바로 클램프함 - 평소 스크롤은 빚 개념 자체가
  // 없어져서 끝에서 몇 번을 밀든 반대로 돌리는 즉시 반응함.
  void _applyVirtualOffset(double raw) {
    if (!_controller.hasClients) return;
    final maxExtent = _controller.position.maxScrollExtent;
    if (_pickerActive) {
      _virtualOffset = raw.clamp(_virtualOffsetMin, _virtualOffsetMax);
      _controller.jumpTo(_virtualOffset!.clamp(0.0, maxExtent));
      final slot = _nearestSlotToContentY(_centerContentY());
      if (slot != _selectedSlot) {
        setState(() => _selectedSlot = slot);
      }
    } else {
      _virtualOffset = raw.clamp(0.0, maxExtent);
      _controller.jumpTo(_virtualOffset!);
    }
  }

  void _onAxisDragUpdate(DragUpdateDetails details) {
    if (!_controller.hasClients) return;
    _applyVirtualOffset((_virtualOffset ?? _controller.offset) - details.delta.dy);
  }

  // ⭐ 2026-08-31 - "끝까지 스크롤한 뒤 반대로 돌리면 1~2초간 멈춘 것처럼 안
  // 움직인다" 버그 수정. 원인: 관성(fling)이 화면은 이미 물리적 끝(0 또는
  // maxScrollExtent)에 닿았는데도 _virtualOffsetMin/Max까지 계속 "가상으로"
  // 더 나아가며 빚을 쌓았음(_virtualOffset 필드 주석의 "빚" 개념) - 그 빚을
  // 다 갚기 전까진 반대 방향 드래그가 화면에 전혀 반영이 안 돼서 멈춘 것처럼
  // 보였음. 손가락 직접 드래그(_onAxisDragUpdate)는 여전히 끝단을 넘어
  // 인디케이터가 더 갈 수 있어야 하므로(정확한 슬롯 0/47 선택을 위한 의도된
  // 기능) 그대로 두되, 관성 애니메이션만 화면이 물리적 끝에 닿는 순간 즉시
  // 멈추게 함 - 애초에 빚이 안 쌓이므로 반대로 되돌릴 때도 즉시 반응함.
  void _onFlingTick() {
    _applyVirtualOffset(_flingController.value);
    if (!_controller.hasClients) return;
    final atEdge = _controller.offset <= 0.0 ||
        _controller.offset >= _controller.position.maxScrollExtent;
    if (atEdge) {
      _flingController.stop();
    }
  }

  // ⭐ 손가락을 다시 대면(새 드래그 시작) 진행 중이던 관성 애니메이션을 즉시
  // 멈춤 - 일반 스크롤뷰를 손으로 잡으면 관성이 뚝 멎는 것과 같은 동작.
  // 안 멈추면 손가락 위치와 관성 애니메이션이 동시에 offset을 밀어서 뚝뚝
  // 끊기는 것처럼 보임.
  void _onAxisDragStart(DragStartDetails details) {
    _flingController.stop();
  }

  // ⭐ 2026-08-28 - "스크롤이 한번씩 버벅인다" 개선 - 손을 뗄 때의 속도로
  // FrictionSimulation(감속 곡선)을 만들어 _flingController에 흘려보냄.
  // 이 컨트롤러의 리스너(initState)가 매 프레임 _applyVirtualOffset을 그대로
  // 호출하므로, 손가락 드래그든 관성이든 동일한 클램프/스냅 경로를 탐 -
  // 끝단에서 "화면은 멈춰도 인디케이터는 계속 간다"는 기존 동작이 관성
  // 중에도 똑같이 유지됨(단, 2026-08-31부터는 물리적 끝단에 닿으면 관성
  // 자체를 멈춤 - _onFlingTick 참고).
  // ⭐ 2026-08-31 - "너무 미끄럽다(아이스 스케이트 같다), 빡 멈출 수가 없다"
  // 피드백으로 마찰계수를 0.135(Flutter 공식 gallery 예제 - 만족스러운 긴
  // 관성을 보여주려고 일부러 미끄럽게 튜닝된 데모용 상수였음)에서 훨씬 낮은
  // 값으로 낮춤. FrictionSimulation은 계수가 작을수록(0에 가까울수록) 감속이
  // 빨라 관성 이동 거리가 짧아짐 - 총 이동거리는 대략 `속도 / |ln(계수)|`이라
  // 0.045는 0.135 대비 관성 거리가 약 1/3 수준(체감상 "조금 느려지고 훨씬
  // 빨리 멎는" 정도)로 튜닝한 값. 손뗌 속도 임계값(관성 없이 그 자리에 바로
  // 멈추는 기준)도 80→160으로 올려서, 손을 자연스럽게 뗄 때 남는 미세한
  // 속도까지 관성으로 이어지지 않고 "확실히 세게 던졌을 때만" 관성이 붙게 함
  // - "내가 빡 멈출 수 있는" 느낌을 위함.
  void _onAxisDragEnd(DragEndDetails details) {
    if (!_controller.hasClients) return;
    // 부호 규칙은 _onAxisDragUpdate와 동일(콘텐츠 오프셋 = -드래그 방향).
    final velocity = -details.velocity.pixelsPerSecond.dy;
    if (velocity.abs() < 160) return; // 느린/보통 손뗌은 관성 없이 그 자리에 멈춤
    final start = _virtualOffset ?? _controller.offset;
    _flingController.animateWith(FrictionSimulation(0.045, start, velocity));
  }

  // ⭐ 우측 하단 버튼(_ScheduleFab) 탭 - 비활성 상태면 활성화(현재 화면
  // 정중앙에 가장 가까운 시각으로 배지가 즉시 나타남), 이미 활성 상태면
  // 지금 선택된 시각으로 일정 생성 시트를 염. 시트가 닫히면(생성했든
  // 취소했든) 항상 비활성 상태로 되돌림 - "시간 선택 → 시트" 한 사이클이
  // 끝났으니 다음엔 다시 버튼을 눌러 새로 시작하게 함.
  void _activatePicker() {
    setState(() {
      _pickerActive = true;
      _selectedSlot = _nearestSlotToContentY(_centerContentY());
    });
    _pulseController.repeat();
  }

  void _deactivatePicker() {
    _pulseController.stop();
    if (!mounted) return;
    // ⭐ 비활성화되는 순간 _virtualOffset을 실제 화면 오프셋([0, maxScrollExtent])
    // 으로 다시 맞춰둠 - 활성 상태였을 때 끝단 오버슛으로 이 값이 화면 범위
    // 밖에 남아있을 수 있는데(_applyVirtualOffset 참고), 그대로 두면 다음에
    // 스크롤 없이 곧장 다시 활성화할 때(_activatePicker의 _centerContentY())
    // 화면에 실제로 안 보이는 엉뚱한 슬롯을 "지금 중앙"으로 잘못 계산할 수 있음.
    if (_controller.hasClients) {
      _virtualOffset =
          (_virtualOffset ?? _controller.offset).clamp(0.0, _controller.position.maxScrollExtent);
    }
    setState(() {
      _pickerActive = false;
      _selectedSlot = null;
    });
  }

  Future<void> _onFabTap() async {
    if (!_pickerActive) {
      _activatePicker();
      return;
    }
    final slot = _selectedSlot;
    if (slot == null) return;
    await _openCreateSheet(slot * 30);
    _deactivatePicker();
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
        _viewportWidth = constraints.maxWidth;
        _axisX = _axisLeftMargin;
        // ⭐ 2026-09-03 - 두 줄 필요 여부 실측(needsTwoLines)이 쓰는
        // TextPainter는 기본적으로 시스템 "큰 글씨" 접근성 설정을 반영 안 함
        // (실제 Text 위젯은 주변 MediaQuery의 textScaler를 자동으로 받지만,
        // 위젯 트리 밖에서 직접 만든 TextPainter는 안 그럼) - 그대로 두면
        // 큰 글씨 설정을 쓰는 사용자에게 "한 줄로 측정했는데 실제로는 두
        // 줄이 되어 잘림" 오차가 생길 수 있어서 명시적으로 넘겨줌.
        _textScaler = MediaQuery.textScalerOf(context);
        _recomputeLayout();
        final totalContentHeight = _slotTops[_slotCount] + _edgePadding * 2;
        // ⭐ 고정 인디케이터(축 정중앙에 뜬 원)와 안 겹치게 살짝 더 띄움 -
        // 일정을 새로 만들 때 "움직인" 인디케이터와 겹치는 건 상관없음
        // (요청), 가만히 있는 기본 위치와만 안 겹치면 됨. 평소 인디케이터가
        // 작아진 만큼(44→36) 간격도 줄임 - 다만 너무 붙지는 않게(요청) 58→46.
        final rowLeft = _axisX + (18 * 7 / 8).w;
        // ⭐ 2026-09-03(4차) - "선택모드일 때 화면 전체를 옅은 반투명 검정으로
        // 가리되, 선택 중인 아이콘 쪽은 가려지면 안 된다"는 요청 - 한 번의
        // 계산으로 두 세트를 같이 얻어서(.normal = 평소처럼 그리는 전체,
        // .activeOnTop = 선택 중인 슬롯의 아이콘들만 다시 한 번) 아래
        // Stack에서 스크림 아래/위로 나눠 그림.
        final built = _buildScheduleRowWidgets(rowLeft, scheme);

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
            // ⭐ 2026-08-28(2차) - 배경 축 스크롤을 SingleChildScrollView의
            // 기본 드래그가 아니라 이 GestureDetector가 직접 받음(physics는
            // 아래에서 NeverScrollable로 바꿈) - "화면이 끝까지 스크롤돼도
            // 인디케이터는 계속 갈 수 있게" 하려면 클램프되지 않은 원시 드래그
            // 델타가 필요한데, SingleChildScrollView 자체의 스크롤 오프셋은
            // 이미 클램프된 값만 노출하기 때문(_onAxisDragUpdate/_virtualOffset
            // 필드 주석 참고).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // ⭐ 2026-09-03(4차) - "선택모드일 땐 세로 스크롤도 막고"
              // 요청 - 선택모드(_dragSlot != null) 중엔 세로 드래그 인식기를
              // 아예 null로 꺼서, 가로 드래그(선택 변경)와 인식기 경합
              // 자체가 안 생기게 함(대각선 드래그가 세로 스크롤로 새는
              // 문제의 원인이기도 했음).
              onVerticalDragStart: _dragSlot == null ? _onAxisDragStart : null,
              onVerticalDragUpdate:
                  _dragSlot == null ? _onAxisDragUpdate : null,
              onVerticalDragEnd: _dragSlot == null ? _onAxisDragEnd : null,
              // ⭐ 2026-09-03(3차) - "선택모드에서는 화면 어디를 좌우로
              // 드래그하든 그게 바뀌도록" 요청 - 세로 드래그는 이미 이
              // GestureDetector가 축 스크롤용으로 쓰고 있어서, 같은 위젯에
              // 가로 드래그 콜백만 추가함(Flutter GestureDetector는 방향별
              // 인식기를 따로 둬서 실제 손가락 이동 방향으로 알아서 갈림 -
              // 서로 안 부딪힘). 선택모드가 아닐 때(_dragSlot == null)는
              // null을 넘겨서 이 인식기 자체가 아예 안 생기게 함 - 그래야
              // 평소(선택모드 아닐 때)엔 다른 가로 제스처(날짜 스와이프 등)를
              // 전혀 안 건드림.
              onHorizontalDragStart:
                  _dragSlot != null ? _handleSelectionDragStart : null,
              onHorizontalDragUpdate:
                  _dragSlot != null ? _handleSelectionDragUpdate : null,
              onHorizontalDragEnd:
                  _dragSlot != null ? _handleSelectionDragEnd : null,
              child: SingleChildScrollView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
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
                        // ⭐ 2026-08-27(5차) - "00이 01보다 왼쪽에 있다"는 재확인
                        // 피드백 - fontFeatures(tabularFigures)로도 안 고쳐진
                        // 걸 보면, 두 "0" 글리프가 폰트 자체의 커닝(kerning) 등
                        // 이유로 실제 그려지는 잉크가 미묘하게 안쪽으로 붙어서
                        // 시각적으로 좁아 보이는 것으로 추정됨(레이아웃 박스
                        // 자체는 Row.end로 항상 오른쪽 끝이 맞음 - 그래서
                        // "박스가 안 맞다"가 아니라 "글자가 그 박스 안에서 다르게
                        // 그려진다"는 쪽). 폰트/커닝에 기대지 않고 아예 숫자
                        // 하나하나를 고정 폭 칸에 가운데 정렬해서 그리는 방식으로
                        // 바꿔서, "00"과 "01"이 무조건 픽셀 단위로 똑같은 폭을
                        // 차지하게 강제함 - 이러면 폰트가 무슨 짓을 하든 상관없음.
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (final digit
                                in (hour % 24).toString().padLeft(2, '0').split(''))
                              SizedBox(
                                width: _hourDigitCellWidth,
                                child: Text(
                                  digit,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.quicksand(
                                      fontSize: 17.sp,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.timeText),
                                ),
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
                    // ⭐ 2026-09-03(4차) - 평소엔 그냥 이 자리에 그대로 그림.
                    // 선택모드 중엔 AbsorbPointer로 탭/터치를 다 흡수해서
                    // "일정 탭→수정 팝업" 등 다른 동작이 전혀 안 먹히게 막음
                    // (좌우 드래그는 이 위젯들보다 바깥의 GestureDetector가
                    // 받으므로 AbsorbPointer와 무관하게 계속 동작함).
                    Positioned.fill(
                      child: AbsorbPointer(
                        absorbing: _dragSlot != null,
                        child: Stack(children: built.normal),
                      ),
                    ),
                    // ⭐ 선택모드 스크림 - "일정탭(광고/날짜 제외) 나머지 영역을
                    // 옅은 반투명 검정으로" 요청. 이 Positioned.fill은 이
                    // _TimeAxisPicker 자신의 콘텐츠 Stack 범위만 덮으므로,
                    // 상위(_ScheduleManagementTabState)의 헤더/날짜칩/광고는
                    // 애초에 이 위젯 밖이라 자동으로 제외됨. IgnorePointer로
                    // 자체는 터치를 가로채지 않음(제스처는 위 GestureDetector가
                    // 이미 전담).
                    if (_dragSlot != null)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(color: Color(0x73000000)),
                        ),
                      ),
                    // ⭐ 선택 중인 아이콘들은 스크림 "위"에 한 번 더 그려서
                    // 가려지지 않게 함(요청: "선택하는 쪽은 불투명 검정색으로
                    // 가리면 안 된다. 잘 보이게"). built.activeOnTop은
                    // isDraggingThisSlot인 슬롯의 아이콘 위젯들만 담고 있고,
                    // 평소엔 빈 리스트라 이 Positioned.fill은 사실상 아무것도
                    // 안 그림.
                    if (_dragSlot != null)
                      Positioned.fill(
                        child: Stack(children: built.activeOnTop),
                      ),
                    // ⭐ 2026-08-28 - 시간 선택 배지 2개("일정생성 flow 개선"
                    // 요청) - 왼쪽은 축 위의 시각(정각이면 숫자를 감싸고,
                    // 30분이면 숫자 없이 그 사이에 존재), 오른쪽은
                    // "08:00 AM" 형식의 시각 텍스트. 둘 다 배경색은 현재
                    // 화면 배경(scheme.mainBg, _scheduleChipDecoration이
                    // 이미 그 규칙을 구현해둠 - 날짜칩/톱니칩과 완전히 같은
                    // 디자인 언어), 숫자는 기존 시간 숫자색(scheme.timeText)
                    // 그대로. 스크롤 추적(방식 1)/탭(방식 2) 어느 쪽으로
                    // 움직이든 이 Positioned가 _slotTops 좌표계 안에 있어서
                    // (=콘텐츠와 함께 스크롤됨) 화면 밖 좌표 보정이 따로
                    // 필요 없음 - AnimatedPositioned가 슬롯이 바뀔 때마다
                    // "따라 따락" 계단식으로 보간해줌.
                    if (_pickerActive && _selectedSlot != null) ...[
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        top: _edgePadding +
                            _tickDisplayY(_selectedSlot!) -
                            _pickerBadgeHeight / 2,
                        left: _axisX - _pickerBadgeGap - _pickerHourBadgeWidth,
                        width: _pickerHourBadgeWidth,
                        height: _pickerBadgeHeight,
                        child: DecoratedBox(
                          decoration: _scheduleChipDecoration(scheme),
                          child: Center(
                            child: _selectedSlot!.isEven
                                ? Text(
                                    ((_selectedSlot! ~/ 2) % 24)
                                        .toString()
                                        .padLeft(2, '0'),
                                    style: GoogleFonts.quicksand(
                                        fontSize: 17.sp,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.timeText),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        top: _edgePadding +
                            _tickDisplayY(_selectedSlot!) -
                            _pickerBadgeHeight / 2,
                        left: _axisX + _pickerBadgeGap,
                        height: _pickerBadgeHeight,
                        child: DecoratedBox(
                          decoration: _scheduleChipDecoration(scheme),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: (10 * 7 / 8).w),
                            child: Center(
                              child: Builder(builder: (context) {
                                final (hhmm, period) =
                                    _to12Hour(_selectedSlot! * 30);
                                return Text('$hhmm $period',
                                    style: GoogleFonts.quicksand(
                                        fontSize: 17.sp,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                        color: scheme.timeText));
                              }),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ),
            // ⭐ 2026-08-28 - "일정생성 flow 개선" 전면 재작업 - 우측 하단
            // 버튼(_ScheduleFab)은 이제 위치가 항상 고정(비활성/활성 둘 다
            // 이 자리)이고, 상태는 색(회색/원색) + 펄스 애니메이션으로만
            // 표현함. 시간 선택 자체는 위 Stack 안의 배지 2개가 담당 -
            // 이 버튼은 "활성화"와 "확정(시트 열기)" 두 액션의 토글일 뿐.
            Positioned(
              top: _viewportHeight * _idleIndicatorVerticalRatio -
                  _ScheduleFab.wrapperSize / 2,
              left: _viewportWidth -
                  _fabRightMargin -
                  _ScheduleFab.size -
                  (_ScheduleFab.wrapperSize - _ScheduleFab.size) / 2,
              child: _ScheduleFab(
                active: _pickerActive,
                pulse: _pulseController,
                onTap: _onFabTap,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ⭐ 2026-08-28 - "일정생성 flow 개선" 전면 재작업으로 온-axis 드래그
// 인디케이터(부리 달린 원)를 완전히 대체하는 우측 하단 고정 버튼. 위치는
// 항상 같고(_TimeAxisPickerState.build() 참고), 상태만 두 가지:
//  - 비활성(active=false): 지금 아이콘을 흑백(그레이스케일) + 옅은 opacity +
//    어두운 테두리로 "지금은 눌러야 시작하는 버튼"처럼 보이게 함.
//  - 활성(active=true): 원색 그대로 + 둘레에 "여기를 누르라"는 펄스 링이
//    계속 커지며 옅어지는 애니메이션(고전적인 레이더 핑 스타일) - 이미
//    시간이 선택된 상태에서 "한 번 더 누르면 확정"이라는 걸 알려줌.
class _ScheduleFab extends StatelessWidget {
  final bool active;
  final Animation<double> pulse;
  final VoidCallback onTap;
  const _ScheduleFab(
      {required this.active, required this.pulse, required this.onTap});

  static double get size => (50 * 7 / 8).r;
  // ⭐ 펄스 링이 최대로 커졌을 때의 지름 - 이 위젯 전체의 레이아웃 크기는
  // 항상 이 값으로 고정(펄스가 없는 비활성 상태에서도 동일)해서, 활성/
  // 비활성을 오갈 때 위치가 흔들리지 않게 함(호출부가 아이콘 중심을
  // 기준으로 역산해서 배치함 - _TimeAxisPickerState.build() 참고).
  static double get wrapperSize => size * 1.55;

  Widget _icon() {
    final img = ClipOval(
      child: Image(
        image: const AssetImage('assets/icon/app_icon.png'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // ⭐ 2026-08-27(3차) - "가까이서 보면 자글자글하다"는 피드백 -
        // 원본(1024×1024)을 이 작은 크기로 줄일 때 기본 FilterQuality(low)
        // 대신 high를 써서 밉맵 보간이 되게 함.
        filterQuality: FilterQuality.high,
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: active
            ? null
            : Border.all(
                color: Colors.black.withValues(alpha: 0.35),
                width: (1.5 * 7 / 8).r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 7,
              offset: const Offset(0, 2)),
        ],
      ),
      // ⭐ 비활성일 땐 표준 luminance 공식(0.2126R+0.7152G+0.0722B)으로 흑백
      // 처리 + 살짝 투명하게 - "지금은 활성 상태가 아니다"가 한눈에 보이게.
      child: active
          ? img
          : ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: Opacity(opacity: 0.75, child: img),
            ),
    );
  }

  // ⭐ 2026-08-28(2차) - "펄스링이 너무 조용해서 활성 상태가 잘 안 느껴진다"는
  // 재확인 - 링 하나짜리를 더 두껍고 진하게 바꾸는 것만으론 "지금 막 커지기
  // 시작한 순간"에는 여전히 아이콘과 거의 겹쳐서 존재감이 약했음. 대신
  // 위상(phase)이 반 박자 어긋난 링 2개를 동시에 돌려서, 항상 화면 어딘가엔
  // "눈에 띄게 자란" 링이 최소 하나는 보이게 함(고전적 이중 레이더 핑) -
  // 테두리 두께도 2.5→4로, 최대 알파도 0.65→0.85로 올림.
  static const double _ringStrokeWidthRaw = 4;
  static const double _ringMaxAlpha = 0.85;
  Widget _ring(double t) {
    final ringSize = size + (wrapperSize - size) * t;
    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: kAppMainAccent.withValues(alpha: (1 - t) * _ringMaxAlpha),
          width: (_ringStrokeWidthRaw * 7 / 8).r,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: wrapperSize,
        height: wrapperSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  final t1 = pulse.value; // 0(막 시작)→1(다 커지고 다 사라짐)
                  final t2 = (pulse.value + 0.5) % 1.0; // 반 박자 어긋난 두 번째 링
                  return Stack(
                    alignment: Alignment.center,
                    children: [_ring(t1), _ring(t2)],
                  );
                },
              ),
            _icon(),
          ],
        ),
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
  // ⭐ 2026-09-03(4차) - null이면(선택모드 중) 카드 탭 자체를 안 받음(요청:
  // "일정을 탭해서 일정수정 팝업이 나오는 동작도 막아 - 오로지 좌우 드래그로
  // 일정 변경하는 것만 동작하게").
  final VoidCallback? onTap;
  // ⭐ 2026-09-03 - 부모(_TimeAxisPickerState._frontCardHeight)가 이미 실측해둔
  // "이 내용이 두 줄이 필요한가"를 그대로 받아씀(여기서 다시 측정 안 함,
  // 중복 계산 방지 + 폭 기준이 항상 하나로 일치되게). 2줄일 때만 첫
  // 줄(시간)~내용 사이 여백을 더 좁혀서(요청: "1줄일 땐 지금 여백이 자연
  // 스러운데 2줄이 되면 그 여백이 불필요해 보인다") 내용 쪽이 시간 줄에
  // 더 붙어 보이게 함.
  final bool twoLines;
  // ⭐ 2026-09-03(3차) - "누르고 바로 드래그"가 아니라 "탭으로 선택모드
  // 진입(토글) → 그 다음 화면 아무 데서나 좌우 드래그"로 재설계(요청).
  // 아이콘 자체는 이제 탭 하나만 받음(눌러서 스택 선택모드를 켜고 끔) -
  // 실제 드래그 처리는 _TimeAxisPickerState.build()의 최상위
  // GestureDetector(onHorizontalDrag*)가 화면 전체에서 받는다(아래
  // iconUniformSmall/iconIsPreview 참고).
  final VoidCallback? onIconTap;
  // ⭐ 스택 중(group.length>1)이고 선택모드가 이 카드가 속한 슬롯에서 켜져
  // 있으면 true - 이때는 이 카드의 "진짜" 아이콘(소요시간에 따라 모양이
  // 제각각) 대신, 뒤에 숨은 카드들과 통일된 크기 + 카테고리 색으로 잠깐
  // 바꿔 보여준다(요청: "선택모드에서는 아이콘 크기 동일하게 + 색상 표시").
  final bool iconUniformSmall;
  // ⭐ iconUniformSmall인 동안, 지금 이 카드가 "선택 예정" 대상이면 살짝
  // 확대 + 그림자를 더해 미리보기임을 보여줌(요청: "8~12% 확대 + elevation").
  final bool iconIsPreview;
  // ⭐ 2026-08-27 - 예전엔 이 카드 위 드래그도 인디케이터에 얹어서 생성모드로
  // 새 나갔는데("이미 생성된 일정을 눌러도 인디케이터가 우측으로 빠지면서
  // 생성모드로 감" 버그 리포트) - 완전히 제거함. 이제 이 카드는 onTap(편집
  // 모드 진입)만 반응하고, 세로 드래그는 아예 안 받아서(GestureDetector에
  // 등록을 안 함) 제스처 아레나에서 자동으로 부모 스크롤뷰가 가져감 - "카드
  // 위에서 드래그하면 그냥 스크롤됨" 요청과도 맞음. ⭐ 2026-09-03 - onTap은
  // 이제 아이콘 영역에서는 아예 안 걸림(아이콘은 위 onIconTap 전용) - 시간
  // 텍스트/내용 줄에서만 걸리도록 아래 build()에서 개별로 감쌈(요청: "카드를
  // 탭했을 때만 상세 팝업 - 아이콘에서는 안 열리게").
  const _ScheduleRow({
    required this.block,
    required this.timeLabel,
    required this.iconDiameter,
    required this.timeTextColor,
    required this.contentTextColor,
    required this.onTap,
    this.twoLines = false,
    this.onIconTap,
    this.iconUniformSmall = false,
    this.iconIsPreview = false,
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

  // ⭐ 2026-09-03 - "내용이 길어서 한 줄에 다 안 보이면 두 번째 줄까지
  // 쓰자"(요청). 두 번째 줄 하나만큼(폰트 실측 높이 + 줄간격 여유)을
  // heightForStyle에 더한 값 - _buildBody()가 실제로 두 번째 줄을 그릴 때
  // 정확히 이만큼만 더 그리므로, _recomputeLayout()이 이 값으로 슬롯 높이를
  // 예약해두면 다음 슬롯과 안 겹침(heightForStyle의 safety 여유분과 같은
  // 원리 - 여기 값이 실제보다 작으면 겹침, 커도 그냥 여백만 남음).
  static double get _extraLineHeight => (22 * 7 / 8).h;
  static double heightForLines(int lines) =>
      lines >= 2 ? heightForStyle + _extraLineHeight : heightForStyle;

  // ⭐ 이 카드의 내용 텍스트가 주어진 폭(availableWidth) 안에서 한 줄에 다
  // 안 들어가는지(=두 번째 줄이 필요한지) 실측함. _buildBody()가 실제로
  // 그리는 것과 정확히 같은 폰트/크기/자간(_measureStyle, _contentStyle과
  // 동일)을 써야 정확함 - 색상만 측정에 안 씀(줄바꿈에 영향 없음).
  static TextStyle _measureStyle() => GoogleFonts.jua(
      fontSize: 15.sp, fontWeight: FontWeight.w400, letterSpacing: 0.4);

  static bool needsTwoLines(
    String content,
    double availableWidth, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (availableWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: content, style: _measureStyle()),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: availableWidth);
    return painter.didExceedMaxLines;
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
    final fullSpan = _maxIconBgHeight(diameter);
    if (duration <= 120) {
      return diameter + (fullSpan - diameter) * 0.55;
    }
    return fullSpan;
  }

  // ⭐ 2026-09-03(8차) - "지금 앞에 있는 일정이 1시간 미만이라 작은 원이어도,
  // 4시간짜리 아이콘이 생길 그 영역(=이 슬롯에서 나올 수 있는 최대 크기)을
  // 탭하면 선택모드로 들어가게 해줘" 요청 - _iconBgHeight는 "이 block 실제
  // 소요시간"에 따라 커지는 값이라 짧은 일정이 front면 탭 히트 영역도 같이
  // 작아졌었음. 이 getter는 실제 duration과 무관하게 "가능한 가장 큰"(2시간
  // 초과일 때의 fullSpan) 값을 반환 - _buildBody()의 히트 레이어는 이걸
  // 쓰고, 아이콘 자체의 실제 그려지는 모양(_icon()의 _iconBgHeight)은 그대로
  // 실제 duration을 따름(둘을 분리해야 "짧은 일정인데 아이콘이 크게 그려짐"
  // 같은 시각적 회귀가 안 생김).
  double _maxIconBgHeight(double diameter) =>
      diameter + (2 * 7 / 8).h + (26 * 7 / 8).h + (16 * 7 / 8).h;

  // ⭐ 아이콘 자체를 살짝 아래로 눌러서(시각적 위치만, 레이아웃 크기는 그대로)
  // 시간 텍스트와 나란히 보이게 하는 미세조정값.
  // ⭐ 2026-08-27(2차) - "일정 아이콘이 시간보다 살짝 위에서 렌더링된다"는
  // 재확인 피드백 - Row(crossAxisAlignment.center)는 아이콘/텍스트를 각자의
  // "레이아웃 박스" 중심으로 맞추는데, 텍스트 박스는 폰트 자체의 여유
  // 행간(디센더 자리 등)이 아이콘 원의 진짜 중심과 다르게 배분돼서 살짝
  // 어긋나 보임 - 아이콘의 "그려지는 위치"만(레이아웃 폭/높이는 그대로,
  // Stack+Clip.none 트릭이라 가능) 이 값만큼 아래로 밀어서 보정.
  static double get _iconVisualNudgeDown => (2 * 7 / 8).h;

  // ⭐ 2026-09-03 - 뒤에 숨은 스택 원(peek)과 완전히 같은 톤(회색 원 + 흰
  // 테두리 + 그림자 + 흰색 카테고리 아이콘)으로 통일 - "왔다갔다하는 순간엔
  // 가장 작은 원 크기로만" 요청이 "크기만 같게"가 아니라 "그 원 자체와 똑같이
  // 보이게"라고 해석해서, 스타일도 peek 원과 동일하게 맞춤(_buildScheduleRowWidgets의
  // peek 원 Container와 데코레이션이 반드시 같아야 함).
  // ⭐ 2026-09-03(3차) - "선택모드에서는 뒤에 숨은 애들도 아이콘 색상(카테고리
  // 고유색)을 보여달라"는 요청으로 회색 고정 대신 block.color를 씀 - front가
  // 이 모양으로 바뀔 때와 뒤에 숨은 peek 원(_buildScheduleRowWidgets)이
  // 선택모드일 때 완전히 같은 스타일을 쓰도록 데코레이션을 맞춤.
  Widget _uniformSmallIcon(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: block.color,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: iconIsPreview
            ? const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))]
            : const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Padding(
        padding: EdgeInsets.all(diameter * 0.24),
        child: SvgPicture.asset(
          _categoryAsset,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }

  // ⭐ Stack + 레이아웃 전용 SizedBox(diameter×diameter) 트릭 - 실제 배경(pill)은
  // Positioned(top:0)으로 그 위에 겹쳐 그리고 Clip.none으로 아래로 넘치게 둠.
  // 이렇게 하면 배경이 아무리 길어져도 Row/Column의 "크기 계산"에는 항상
  // diameter만 반영돼서, 시간 라벨·내용 텍스트 위치가 전혀 안 흔들림(요청:
  // "시간이랑 내용은 일단 위치 그대로 지키고").
  // ⭐ 2026-09-03(3차) - "누르고 바로 드래그"를 없애고 "탭으로 선택모드 토글"로
  // 재설계 - 아이콘엔 이제 onTap만 붙음. 실제 스택 탐색 드래그는
  // _TimeAxisPickerState의 최상위 GestureDetector가 화면 전체에서 받음(위
  // onIconTap 필드 주석 참고).
  // ⭐ 2026-09-03(4차) - "선택상태/뒤에 숨은 아이콘 크기가 왜 이렇게 작냐,
  // 1시간 이내 기본 정원 크기와 동일하게" 요청으로 0.72 축소 비율을 없애고
  // 1.0(=iconDiameter 그대로)로 바꿈. _buildScheduleRowWidgets의 peekDiameter가
  // 이 값을 그대로 참조하므로 같이 바뀜(스택 안 모든 아이콘 크기 통일 유지).
  static const double _kStackSmallRatio = 1.0;
  // ⭐ 2026-09-03(4차) - "아이콘 하단부(4시간 이상 등 세로로 긴 pill)를 눌러도
  // 일정 팝업이 뜬다" 버그 수정 - GestureDetector를 여기(diameter×diameter로
  // 고정된 SizedBox가 지배하는 Stack) 안에 두면, Flutter의 히트테스트는
  // "자기 박스 크기 밖 좌표는 자식한테 물어보지도 않고 통과시킴"이라서
  // Clip.none으로 그림만 넘친 pill 하단부는 애초에 히트테스트 대상이 될 수
  // 없었음(OverflowBox로 감싸도 마찬가지 - 그 위젯 자신의 히트박스는 여전히
  // 부모가 준 제약(diameter)을 따름). 그래서 탭 처리 자체를 이 함수에서
  // 완전히 떼어내 _buildBody()로 옮김 - 그쪽은 AnimatedPositioned가 이미
  // 세로로 충분히 큰(h) 고정 박스를 주는 계층이라, 거기서 pill의 실제 시각적
  // 범위(_iconBgHeight)만큼 별도 히트 레이어를 얹으면 안전하게 해결됨.
  Widget _icon(double diameter) {
    final small = iconDiameter * _kStackSmallRatio;
    final scale = iconUniformSmall && iconIsPreview ? 1.1 : 1.0;
    final bgHeight = _iconBgHeight(diameter);
    final glyphSize = diameter * 0.52;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(width: diameter, height: diameter),
        if (iconUniformSmall)
          Positioned(
            top: _iconVisualNudgeDown + (diameter - small) / 2,
            left: (diameter - small) / 2,
            child: Transform.scale(
              scale: scale,
              child: _uniformSmallIcon(small),
            ),
          )
        else
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
  // ⭐ 2026-08-27(6차) - "글자끼리 좌우 간격이 너무 붙는다"는 재확인 피드백의
  // 진짜 원인을 찾음: 주아체(Jua)는 Google Fonts에 굵기가 딱 하나(Regular
  // 400)만 있는 폰트라, 여기서 fontWeight: w700을 요청하면 실제 볼드
  // 글리프가 없어서 Flutter/Skia가 "가짜 볼드"(선을 억지로 두껍게 그리는
  // synthesized/faux bold)를 적용함 - 이게 글자 사이 여백을 갉아먹어서
  // 좁아 보이게 만든 것(간격 수치 자체가 줄어든 게 아니라, 두꺼워진 획이
  // 옆 글자의 여백을 침범하는 착시+실제 침범이 섞인 문제). 폰트 자체의
  // 원래 굵기(w400, "볼드"를 요청 안 함)로 되돌려서 가짜 볼드를 아예 안
  // 만들게 함 - 주아체는 원래 획이 두꺼운 손글씨체라 w400이어도 이미
  // "진한" 느낌은 충분함. 혹시 몰라 요청대로 크기도 살짝 키우고(14→15)
  // letterSpacing도 아주 조금 더 줌(0→0.4) - 이중 안전장치.
  TextStyle _contentStyle({double size = 15, Color? color}) => GoogleFonts.jua(
      fontSize: size.sp,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      color: color ?? contentTextColor);

  // ⭐ 2026-08-27 - 세로축 시간 숫자와 스타일 통일(요청: "세로축의 숫자랑
  // 일정에 생성되는 숫자랑 크기+색깔+텍스트 스타일을 전부 맞추자"). 폰트=
  // Quicksand w700(축과 동일), 크기는 축(19sp)보다 작고 예전 값(13sp)보다는
  // 큼(16sp).
  // ⭐ 2026-08-27(2차) - 색은 고정 kScheduleTimeNumberColor 대신
  // timeTextColor(배경색에 따라 유동)로. tabularFigures도 축 숫자와
  // 동일하게 적용(같은 스타일 통일 요청 연장선).
  TextStyle get _timeTextStyle => GoogleFonts.quicksand(
      fontSize: 14.sp,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: timeTextColor);

  // ⭐ 2026-08-27 - "아이콘/시간/그 사이 공간을 탭해도 편집모드로" 요청 -
  // HitTestBehavior.opaque로 GestureDetector 자기 영역(Positioned가 준 전체
  // 칸) 안이면 자식이 안 그린 빈 공간이라도 전부 탭을 잡음(기본값
  // deferToChild는 실제로 뭔가 그려진 픽셀 위에서만 반응해서, 아이콘과 내용
  // 사이 여백을 탭하면 안 먹혔던 것).
  // ⭐ 2026-09-03 - 아이콘은 이제 상세 팝업을 안 열고(가로 드래그 전용,
  // _icon() 참고) "카드"(시간 텍스트 + 내용 줄)만 탭하면 열리게 분리함(요청:
  // "기존 상세 팝업은 아이콘에서는 열리지 않게... 카드를 탭했을 때만"). 예전엔
  // build() 전체를 하나의 GestureDetector로 감쌌는데, 그러면 아이콘 위에서도
  // 탭이 걸려서 분리가 안 됨 - 이제 개별 조각(시간 텍스트/내용 줄)마다 따로
  // 감쌈.
  @override
  Widget build(BuildContext context) => _buildBody();

  // ⭐ 아이콘 + 시간 텍스트 한 줄. 아이콘 자체엔 탭을 안 걸고(위 참고), 시간
  // 텍스트 쪽만 opaque 탭으로 감싸서 그 영역(빈 공간 포함) 전체가 카드 탭으로
  // 인식되게 함(기존 "빈 공간도 탭되게" 원칙 유지).
  Widget _iconAndTimeRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _icon(iconDiameter),
        SizedBox(width: (10 * 7 / 8).w),
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Text(
              timeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _timeTextStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _firstLine() => Transform.translate(
      offset: Offset(0, -iconDiameter / 2), child: _iconAndTimeRow());

  // ⭐ 2026-08-27 - 렌더링 스타일 3번(밑줄/왼쪽 세로 막대 강조)으로 확정,
  // 나머지 7종은 코드째로 삭제(요청).
  // ⭐ 2026-08-27(6차) - 5차에서 "딱딱 붙는 느낌"을 세로 간격 문제로 오판해서
  // 여기(첫 줄~내용 줄 사이 세로 간격)를 원복했었는데, 실제 원인은 세로
  // 간격이 아니라 내용 텍스트 자체의 글자 간(가로) 간격이었음(_contentStyle
  // 참고 - 가짜 볼드 문제). 세로 간격은 "아까가 딱 좋았다"는 재확인으로
  // 다시 좁힘(2→1 + Transform.translate(-2) 겹침, 2차 상태 그대로 복원).
  // ⭐ 2026-09-03 - 2줄일 때만 이 여백을 더 좁힘(요청 - "1줄일 땐 여백이
  // 자연스러운데 2줄이 되면 그 여백이 불필요해 보인다, 시간 표시줄에 좀
  // 더 붙여봐 - 너무 딱 붙일 필요까진 없고 일반적인 간격 정도로"). 기존
  // -2 오프셋에 추가로 더 끌어올림.
  double get _contentPullUp => twoLines ? (27 * 7 / 8).h : (2 * 7 / 8).h;

  Widget _buildBody() {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _firstLine(),
        SizedBox(height: (1 * 7 / 8).h),
        Transform.translate(
          offset: Offset(0, -_contentPullUp),
          // ⭐ 2026-09-03(9차 긴급수정2) - "2줄일 때도 위쪽(아이콘쪽)을 눌러도
          // 팝업이 뜬다" 버그의 진짜 원인 - GestureDetector가 Padding을
          // 감싸고 있었는데, Padding의 "박스 크기"는 inset(왼쪽 여백)까지
          // 포함해서 계산됨 - 즉 이 GestureDetector의 히트 영역이 실제로는
          // x=0(아이콘 칸 포함)부터 시작하고 있었음(육안으로는 Row가
          // iconDiameter+10w만큼 오른쪽에서 시작하는 것처럼 보이지만, 히트
          // 테스트 박스 자체는 Padding 전체였음). Padding을 GestureDetector
          // 밖으로 빼서, 감지기의 히트 박스가 실제 Row(내용 줄)의 자기 자신
          // 박스만 되도록(=x가 iconDiameter+10w부터 시작) 고침 - 이제 몇
          // 줄이든 아이콘 칸(x<iconDiameter)은 이 감지기가 절대 못 건드림.
          child: Padding(
            padding: EdgeInsets.only(left: iconDiameter + (10 * 7 / 8).w),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
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
                      // ⭐ 2026-09-03 - "한 줄에 안 들어가면 두 번째 줄까지"
                      // 요청 - maxLines 1→2. 왼쪽 세로 막대(위 Container)는
                      // IntrinsicHeight+stretch로 이 Text 높이에 자동으로
                      // 맞춰지므로 두 줄이 되면 막대도 저절로 두 배 가까이
                      // 길어짐(별도 코드 불필요). 실제로 몇 줄이 필요한지는
                      // _ScheduleRow.needsTwoLines가 미리 실측해서
                      // _recomputeLayout()의 슬롯 높이 예약에 반영함 - 여기서
                      // 그 실측과 다른 폭으로 그려지면 어긋나므로 이 Text의
                      // 폭(Expanded 안, Row 좌우 여백 동일)이 바뀌면
                      // _TimeAxisPickerState._contentTextWidth 계산도 같이
                      // 고칠 것.
                      child: Text(block.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _contentStyle()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    final overlays = <Widget>[];
    // ⭐ 2026-09-03(4차) - 아이콘 탭 히트 영역을 여기(_ScheduleRow의 최상위 -
    // AnimatedPositioned가 이미 h만큼 세로로 넉넉한 고정 박스를 주는 계층)로
    // 옮김. top은 _firstLine()의 Transform.translate(0,-iconDiameter/2)와
    // 맞춤. 가로는 iconDiameter 폭(아이콘 칸)만 차지하므로 그 옆(내용 텍스트,
    // left: iconDiameter+10w부터 시작)과는 절대 안 겹침 - 내용 탭은 그대로
    // 살아있음.
    // ⭐ 2026-09-03(8차) - "지금 앞 일정이 짧아서(1시간 미만) 작은 원이어도,
    // 4시간짜리 아이콘이 생길 그 영역을 탭하면 선택모드로 가게" 요청 - 높이를
    // 이 block의 실제 duration이 아니라 _maxIconBgHeight(이 슬롯에서 나올 수
    // 있는 가장 큰 아이콘 크기)로 고정. h(AnimatedPositioned가 주는 세로
    // 여유)는 원래부터 duration과 무관하게 항상 이 정도를 담을 수 있게
    // 넉넉히 예약돼 있어서(_ScheduleRow.heightForStyle 참고) 넘치지 않음.
    // ⭐ 2026-09-03(9차 긴급수정2) - "일정이 하나뿐이라도(onIconTap==null)
    // 아이콘쪽은 어디를 탭해도 절대 상세 팝업으로 안 가게" 요청 - 예전엔
    // onIconTap이 없으면 이 오버레이 자체를 안 만들어서 아이콘 칸이 무방비
    // 상태였음(다른 위젯이 뒤에서 그 자리를 가로챌 여지가 있었음 - 실제로
    // 위 content GestureDetector의 Padding 버그가 그랬음). 이제 onIconTap
    // 유무와 무관하게 이 자리를 항상 만들어서, 없으면 그냥 아무 동작 없이
    // 탭만 흡수(opaque)함 - 아이콘 칸은 항상 "여기서 탭이 끝남"이 보장됨.
    overlays.add(Positioned(
      top: -iconDiameter / 2,
      left: 0,
      width: iconDiameter,
      height: _maxIconBgHeight(iconDiameter),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onIconTap,
      ),
    ));
    // ⭐ 2026-09-03(9차) - "시간 줄과 내용 줄 사이 여백을 눌러도 상세 팝업이
    // 뜨게 해줘 - 1줄일 때만(2줄이면 이미 텍스트가 그 자리를 채워서 정상
    // 동작함)" 요청 - 시간 줄의 실제 화면상 아랫변(iconDiameter/2, 첫 줄이
    // Transform으로 위로 diameter/2만큼 밀려서 이만큼이 됨)부터, 내용 줄의
    // 실제 화면상 윗변(내용의 flow 위치 iconDiameter+SizedBox(1h) 에서
    // _contentPullUp만큼 위로 당겨진 지점)까지의 "빈 틈"만 정확히 계산해서
    // 덮음. 2줄이면 _contentPullUp이 커서 이 틈이 0 이하로 계산되므로
    // 자동으로 안 그려짐(추가 분기 불필요).
    // ⭐ 2026-09-03(9차 긴급수정) - "아이콘 탭했는데 팝업이 한 번씩 뜬다"
    // 버그 - 이 여백 오버레이를 left:0(카드 전체 폭)으로 깔았더니, 아이콘
    // 히트 영역(x∈[0,iconDiameter], 위에서 추가)과 y축으로 겹치는 구간이
    // 생겼고, Stack은 나중에 추가된(=더 위에 그려지는) 자식이 히트테스트를
    // 먼저/독점적으로 가로채므로 그 구간의 아이콘 탭을 이 여백 감지기가
    // 가로채 버렸음(카드 onTap 발동 = 팝업). 아이콘 칸(x<iconDiameter)은
    // 완전히 피하고 그 오른쪽(내용이 실제로 시작하는 지점)부터만 덮도록
    // left를 0에서 iconDiameter로 좁힘 - 아이콘 히트 영역과 겹칠 일이
    // 없어짐.
    if (onTap != null) {
      final gapTop = iconDiameter / 2;
      final contentVisualTop = iconDiameter + (1 * 7 / 8).h - _contentPullUp;
      final gapHeight = contentVisualTop - gapTop;
      if (gapHeight > 0) {
        overlays.add(Positioned(
          top: gapTop,
          left: iconDiameter,
          right: 0,
          height: gapHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
          ),
        ));
      }
    }
    if (overlays.isEmpty) return column;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        column,
        ...overlays,
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

// ⭐ 카테고리 아이콘 19종(2026-08-27 10종 -> 2026-09-01 7종 추가 -> 2026-09-03
// 2종 추가: 자전거/요가·필라테스) -
// assets/icons/memo_category/README.md의 매핑과 동일(memo_category_icon_lab_
// screen.dart의 kMemoCategoryIcons도 같은 목록이지만, 그 파일은 "확인용 임시
// 화면"이라 나중에 지워질 수 있어서 여기 독립적으로 같은 목록을 둠 - 그
// 파일이 지워져도 이 화면은 안 깨짐).
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
  // ⭐ 2026-09-01 - 신설 7종. "운동" 아이콘(아령)이 달리기/수영/등산까지
  // 뭉뚱그리는 게 아쉽다는 피드백으로 분리(ml/카테고리_가이드.md 참고).
  ('running', '달리기', 'assets/icons/memo_category/running.svg'),
  ('swimming', '수영', 'assets/icons/memo_category/swimming.svg'),
  ('hiking', '등산', 'assets/icons/memo_category/hiking.svg'),
  ('culture', '문화생활', 'assets/icons/memo_category/culture.svg'),
  ('finance', '금융', 'assets/icons/memo_category/finance.svg'),
  ('housework', '집안일', 'assets/icons/memo_category/housework.svg'),
  ('beauty', '미용', 'assets/icons/memo_category/beauty.svg'),
  ('cycling', '자전거', 'assets/icons/memo_category/cycling.svg'),
  ('yoga', '요가/필라테스', 'assets/icons/memo_category/yoga.svg'),
  // ⭐ 2026-09-01 - 기존 "기타" 아이콘(circle-ellipsis, 말풍선처럼 보인다는
  // 피드백)을 없애고 "누가 봐도 자동분류 실패해서 그냥 아무 도형이나 넣은
  // 것"임을 알 수 있는 순수 도형 아이콘 10종(원/사각형/삼각형/마름모/육각형/
  // 오각형/팔각형/별/여러도형/별표)으로 확정. 전부 key를 'etc'로 그대로 두고
  // (라벨/분류 자체는 여전히 "기타" 하나) 자산 경로만 10개를 나란히 둔 것 -
  // `_handleSave()`가 분류 결과가 'etc'일 때만 이 10개 구간 안에서 순서대로
  // 순환시켜 매번 다른 도형을 배정한다(_nextEtcIconIndex 참고). 실제 카테고리로
  // 맵핑된 나머지 18종은 항상 자기 키에 해당하는 고정 아이콘 하나만 씀 -
  // 이 순환 로직과 무관.
  ('etc', '기타', 'assets/icons/memo_category/etc1.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc2.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc3.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc4.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc5.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc6.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc7.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc8.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc9.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc10.svg'),
];

// ⭐ 2026-09-01 - "기타"로 분류될 때마다 위 10개 도형 아이콘을 순서대로(1→2→
// …→10→1…) 배정하기 위한 누적 카운터. SharedPreferences에 저장(다른 앱 설정과
// 마찬가지로 backup_service.dart의 "전체 스냅샷" 방식에 자동으로 포함되므로
// 백업/복구해도 순환 위치가 그대로 이어짐 - 별도 처리 불필요).
const String _kEtcIconRotationCounterKey = 'schedule_etc_icon_rotation_counter';

/// "기타"로 분류된 새 일정에 배정할 [_kScheduleCategoryIcons] 인덱스를 반환하고,
/// 다음 호출을 위해 카운터를 1 증가시켜 저장한다. 실제 카테고리(예: 'work')로
/// 맵핑됐을 때는 이 함수를 아예 호출하지 않고 기존처럼 `indexWhere`로 고정
/// 아이콘을 그대로 씀 - 순환은 "기타"일 때만 적용된다.
Future<int> _nextEtcIconIndex() async {
  final etcIndices = [
    for (var i = 0; i < _kScheduleCategoryIcons.length; i++)
      if (_kScheduleCategoryIcons[i].$1 == 'etc') i,
  ];
  if (etcIndices.isEmpty) return 0; // 방어적 - 이론상 항상 10개 있음
  final prefs = await SharedPreferences.getInstance();
  final counter = prefs.getInt(_kEtcIconRotationCounterKey) ?? 0;
  await prefs.setInt(_kEtcIconRotationCounterKey, counter + 1);
  return etcIndices[counter % etcIndices.length];
}

// ⭐ 2026-08-27 - 글씨체 5종(고운돋움/개구쟁이/도현체/나눔펜/주아체) 실험을
// 접고 5번(주아체)으로 확정하면서 이 함수/목록 삭제(요청: "코드상으로도
// 삭제"). 이제 _ScheduleRow._contentStyle()이 GoogleFonts.jua를 직접 씀.

// ⭐ 2026-09-01 후속5 - "소요시간 프리셋 칩(10분~5시간) + 시간 미정 토글"은
// 삭제됨(요청) - 이제 소요시간은 시간 선택 시트의 종료 카드 −/+ 스텝(5/30/60분)
// 으로만 조정. _durationPresetLabel(아래)은 그 카드의 "(30m)" 같은 짧은
// 표기용으로 계속 씀.

// ⭐ 2026-08-27(3차) - "1시간 30분"처럼 한글 단위를 쓰면 나중에 30분 단위
// 조정까지 들어갔을 때("1시간 30분" 같은 조합) 레이아웃을 너무 많이 먹어서
// "h"/"m" 표기로 교체(요청) - 예: "30m", "1h", "1h 30m".
String _durationPresetLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

// ⭐ 2026-09-01 후속5(2차) - 일정생성 시트의 종료 카드 소요시간 표시 전용.
// 타임라인 카드 라벨과 달리 한 줄 여유가 있어서 "2시간 30분"처럼 한글로
// 풀어 씀(요청) - _durationPresetLabel(h/m 표기)은 공간이 좁은 타임라인
// 쪽에 그대로 남겨둠.
String _durationKoreanLabel(int minutes) {
  if (minutes < 60) return '$minutes분';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h시간' : '$h시간 $m분';
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

// ⭐ 2026-09-01 후속7 - "키보드가 뜨고 내려갈 때마다 팝업이 미세하게 위아래로
// 움직인다"는 재확인 피드백 - 시트 높이를 한 번만 계산해서 캐싱해도 여전히
// 조금씩 움직였음. 원인: `showModalBottomSheet`가 내부적으로(Flutter 프레임워크
// 자체 구현) builder가 반환한 위젯을 `MediaQuery.viewInsetsOf(context)`만큼의
// 바텀 패딩으로 다시 한 번 감싼다(키보드를 자동으로 피하기 위한 프레임워크
// 기본 동작) - 이건 이 화면 코드 바깥(프레임워크 내부)에서 일어나는 래핑이라
// _CreateBlockSheet 안에서 뭘 하든 피할 수 없었다. 그래서 `showModalBottomSheet`
// 자체를 안 쓰고, 키보드 인셋을 전혀 신경 안 쓰는 `showGeneralDialog`로 직접
// 하단 고정 시트를 구현함 - 화면 맨 아래에 Align으로 고정하고 미끄러져 올라오는
// 전환 애니메이션만 직접 줌. 이러면 시트의 위치/크기가 키보드 유무와 완전히
// 무관해짐(구조적으로 그 경로 자체가 없어짐).
Future<T?> _showFixedBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          type: MaterialType.transparency,
          child: builder(dialogContext),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: child,
      );
    },
  );
}

// ⭐ 2026-09-01 후속5 - 일정생성 시트의 시간 카드 2개(시작/종료) 중 지금 어느
// 쪽이 −/+ 스텝 조정 대상인지.
enum _TimeCardSlot { start, end }

/// ⭐ 2026-09-05 - 일정 알림 UI 껍데기의 임시 저장소. `date_schedules`에 아직
/// 실제 컬럼이 없어서(DB 스키마 변경 전) 이 세션 동안만 메모리에 들고
/// 있음 - 앱을 재시작하면 사라짐. 실제 DB 컬럼이 생기면 이 캐시는 통째로
/// 걷어내고 그 컬럼 값으로 바로 대체할 것.
/// 키: `'${date}_$startMinutes'` - 이 시트는 수정 모드에서 시작 시각을 못
/// 바꾸므로(`_openEditSheet` 주석 참고) 한 일정의 생애주기 동안 이 키가 안
/// 바뀌어 안전하게 식별자로 쓸 수 있음.
final Map<String, ({bool enabled, int offsetMinutes})> _scheduleNotifyDraftCache = {};

class _CreateBlockSheet extends StatefulWidget {
  final int startMinutes;
  // ⭐ 2026-09-05 - _scheduleNotifyDraftCache 조회/기록용 키를 만들려면 날짜도
  // 필요함(생성 모드는 부모의 dateKey, 수정 모드는 existing.date와 항상 같은
  // 값이지만 그때그때 새로 만들지 않고 그냥 항상 넘겨받음).
  final String dateKey;
  // ⭐ null이면 새로 만드는 중, 값이 있으면 그 일정을 수정하는 중(제목/내용/
  // 소요시간만 - 시작 시간은 인디케이터 전용이라 여기선 고정).
  final DateSchedule? existing;
  const _CreateBlockSheet({required this.startMinutes, required this.dateKey, this.existing});

  // ⭐ Navigator.pop(context, deleteSignal)로 "삭제를 눌렀다"를 알림 - 저장
  // 결과(DateSchedule)와 구분해야 해서 별도 sentinel 값을 씀.
  static const Object deleteSignal = '__delete__';

  @override
  State<_CreateBlockSheet> createState() => _CreateBlockSheetState();
}

class _CreateBlockSheetState extends State<_CreateBlockSheet> {
  late final _contentController =
      TextEditingController(text: widget.existing?.content ?? '');
  // ⭐ 2026-08-27 - 스타일/폰트/아이콘 선택 팝업 전부 삭제(요청: "팝업 간소화,
  // 스타일 3번·글씨체 5번으로 확정"). 아이콘은 이제 항상 자동분류만 씀 -
  // _iconManuallySet 같은 "수동 우선" 개념 자체가 없어짐(고를 UI가 없으니까).
  bool _autoClassifying = false;

  // ⭐ 2026-09-05 - 일정 알림 UI 껍데기(전체근무표_개선안_및_일정알림_설계메모.md
  // 참고). 아직 DB 컬럼도, 실제 예약 로직도 없음 - _scheduleNotifyDraftCache
  // (세션 한정 메모리 캐시)로만 왔다갔다 함. 다음 세션에서 DB(date_schedules
  // v23 검토)/알림 예약을 붙일 때 이 캐시를 통째로 걷어내고 그 컬럼 값으로
  // 대체할 것. late인 이유 - initState에서 캐시를 조회해 프리필해야 해서
  // 필드 초기화 시점(위젯 생성자 실행 전)엔 값을 못 정함.
  late bool _notifyEnabled;
  late int _notifyOffsetMinutes; // 0=정시, 5/10/30=N분 전
  static const List<int> _kNotifyOffsetOptions = [0, 5, 10, 30];

  // ⭐ 2026-09-03(2차) - 처음엔 showDialog(AlertDialog)로 만들었다가, "텍스트필드
  // 활성화 중에 삭제를 누르면 다이얼로그가 위에서 뚝 떨어지고, 동시에 키보드도
  // 내려가고, 시트 전체도 살짝 움직여서 너무 산만하다"는 지적 + "취소를 누르면
  // 텍스트필드가 다시 활성화되며 키보드가 올라온다"는 지적 둘 다 받음(요청).
  // 원인: showDialog는 새 Route(=새 FocusScope)를 Navigator에 push하는데, 이
  // 시트가 텍스트필드에 포커스를 갖고 있던 상태라면 그 Route 전환 자체가
  // 포커스를 새 Route로 옮겼다가(키보드가 내려감) 되돌리는(포커스 복원 -
  // 텍스트필드가 다시 활성화됨) 과정을 거침 - 이 파일이 이미 한 번 같은 종류의
  // 문제(_showFixedBottomSheet 주석 참고 - "키보드 뜨고 내려갈 때마다 팝업이
  // 움직인다")를 "새 Route를 아예 안 쓰는" 방식으로 해결한 전례가 있어서,
  // 여기도 같은 원칙 적용: 새 Route(다이얼로그) 대신 이 시트 안에서
  // _confirmingDelete만 토글해서 Stack으로 확인 문구를 얹는다. Route/FocusScope
  // 전환이 아예 없으니 텍스트필드의 포커스/키보드 상태가 이 과정 내내 전혀
  // 건드려지지 않음(있었으면 계속 있고, 없었으면 계속 없음) - 두 지적 모두
  // 근본 원인 자체가 사라짐.
  bool _confirmingDelete = false;

  // ⭐ 2026-09-03(3차) - 위 오버레이(반투명 검정 스크림 + 흰 카드) 방식을
  // 시도해봤는데 두 가지 문제가 새로 생김:
  //   1) "팝업의 90%가 반투명 검정으로 덮인다" - 의도한 디자인이었지만 막상
  //      보니 너무 무겁고 산만함(애초에 "그냥 나타나게" 요청과 안 맞음).
  //   2) 키보드가 떠 있는 상태에서 삭제를 누르면, 확인 카드가 시트 "가운데"에
  //      뜨는데 그 자리가 하필 키보드에 가려진 영역이라 아예 안 보이는 문제.
  // 두 문제 다 "화면 가운데에 새로 뭔가를 띄운다"는 접근 자체의 부작용이라,
  // 아예 스크림/오버레이 없이 맨 아래 버튼 Row 자체를 그 자리에서
  // (취소/저장) → (경고 문구 + 취소/삭제)로 바꿔치기하는 방식으로 재설계함.
  // 버튼 Row는 시트 맨 아래, 키보드 바로 위(항상 보이는 자리)에 고정돼
  // 있으므로 키보드가 떠 있어도 항상 그대로 보임 - 시트 위쪽(내용/시간)은
  // 전혀 안 가려지고 그대로 보이는 채로 유지됨.

  // ⭐ 2026-08-31("D번", 2차 수정) - 5분 단위 미세조정. widget.startMinutes는
  // "사용자가 생성 버튼을 누른 30분 슬롯" - 조정 가능 범위(±25분)의 중심으로만
  // 쓰인다. 실제 타임라인 위 물리적 표시 위치(slotMinutes)는 여기서 고정하는
  // 값이 아니라 최종 startMinutes 하나로 그때그때 계산되는 순수 값이라
  // (date_schedule.dart의 computeSlotMinutes 참고 - "정각이면 그 정각, 아니면
  // 그 시간대의 30분 자리") 미세조정을 하면 실제로 자리가 바뀔 수 있음(예:
  // 10시 슬롯에서 -5분 하면 9시 55분이 되고, 표시 위치도 9시 30분으로 바뀜) -
  // _fineAdjustBoundCenter가 정하는 건 "얼마나 멀리 조정할 수 있는지"일
  // 뿐이지 "어디에 표시될지"가 아니다.
  int get _fineAdjustBoundCenter => widget.startMinutes;
  late int _preciseMinutes =
      widget.existing?.startMinutes ?? widget.startMinutes;

  // ⭐ 2026-09-01 후속5(2차) - "시작 카드에서 −+5분을 하면 종료 시각도 같이
  // 밀려서 소요시간이 항상 고정된 값(예: 30분)으로만 보인다"는 재확인 피드백 -
  // 종료 시각을 "시작+소요시간" 파생값이 아니라 **독립된 절대 시각**
  // (_endMinutes)으로 바꿈. 그래서 시작을 조정하면 종료 시각은 그 자리에
  // 그대로 있고, 그만큼 소요시간(표시용, _displayDurationMinutes)만 바뀐다 -
  // 종료 카드를 직접 조정할 때만 _endMinutes 자체가 움직임. 기본값은 여전히
  // "시작+30분"(요청: "우측은 기본으로 +30").
  late int _endMinutes = (widget.existing != null
          ? widget.existing!.startMinutes + (widget.existing!.durationMinutes ?? 30)
          : widget.startMinutes + 30)
      .clamp(0, _dayEndMinutes);

  // ⭐ "−"/"+" 토글 - 다음 스텝의 방향. 스펙: "둘 중 하나는 무조건 선택,
  // 하나만 선택된 상태" - 토글 자체가 시간을 바꾸지 않고, 그 다음 스텝 버튼
  // 탭의 부호만 정함(활성 카드가 시작이면 5분 스텝 하나, 종료면 5/30/60분
  // 스텝 세 개에 공통으로 적용).
  bool _adjustDown = false;

  static const int _fineAdjustRangeMinutes = 25;
  static const int _minDurationMinutes = 5;
  // ⭐ "23시에 만들면 1시간 추가가 내일로 넘어간다"는 케이스 - 이번엔 오늘
  // 하루 안(24:00)으로만 한정해서 만들자는 요청(다음날로 넘어가는 일정 자체를
  // 아직 지원 안 함) - 종료 시각은 절대 24:00(=1440분)을 못 넘게 캡을 씀.
  static const int _dayEndMinutes = 24 * 60;

  // ⭐ 2026-09-01 후속5 - 시간 선택 카드 2개(시작/종료) 중 지금 조정 대상.
  // 생성 모드는 시작 카드가 기본 활성(요청: "처음은 앞 07:00이 활성상태"),
  // 수정 모드는 시작 시각 자체를 못 바꾸므로 항상 종료 카드만 활성.
  late _TimeCardSlot _activeCard =
      _isEditing ? _TimeCardSlot.end : _TimeCardSlot.start;

  int get _displayStartMinutes =>
      _isEditing ? widget.existing!.startMinutes : _preciseMinutes;
  int get _displayEndMinutes => _endMinutes;
  int get _displayDurationMinutes => _displayEndMinutes - _displayStartMinutes;

  void _selectCard(_TimeCardSlot slot) {
    if (slot == _TimeCardSlot.start && _isEditing) return; // 수정 모드: 시작 카드 비활성
    // ⭐ 2026-09-01 - "내용 텍스트필드에 입력하다가 아래 시간 카드를 탭하면
    // 포커스가 자연스럽게 넘어가면서 키보드도 같이 내려가야 한다"는 요청 -
    // 예전엔 시간 카드를 탭해도 텍스트필드가 포커스를 그대로 쥐고 있어서
    // 키보드가 카드 위에 계속 떠 있었음. 여기서 포커스를 명시적으로 풀어주면
    // Flutter가 알아서 키보드를 내리고, 시간 카드 쪽 활성 표시(_activeCard)는
    // 바로 아래 setState로 갱신됨 - 사용자 입장에선 "카드를 탭하는 순간
    // 키보드가 내려가며 그 카드가 활성화"로 자연스럽게 이어져 보임.
    _contentFocusNode.unfocus();
    setState(() => _activeCard = slot);
  }

  /// 활성 카드에 맞춰 [stepMinutes]만큼(부호는 _adjustDown이 정함) 조정.
  /// 시작 카드 - widget.startMinutes 기준 ±25분 안에서, 그리고 종료 시각보다
  /// 최소 5분 이상 앞서도록 _preciseMinutes만 이동(종료 시각 _endMinutes는
  /// 그대로 - 소요시간이 그만큼 달라짐). 종료 카드 - _endMinutes 자체를
  /// "시작+5분"~"오늘 자정"(24:00) 범위에서 조정(시작 시각은 그대로).
  void _adjustActiveCard(int stepMinutes) {
    final delta = _adjustDown ? -stepMinutes : stepMinutes;
    if (_activeCard == _TimeCardSlot.start) {
      final upperBound = _fineAdjustBoundCenter + _fineAdjustRangeMinutes;
      final startCap = _endMinutes - _minDurationMinutes;
      // ⭐ 2026-09-04 - M6 수정(전체_코드_점검_리포트_2026-09-04.md). 00:00
      // 슬롯(_fineAdjustBoundCenter == 0)에서 하한이 그대로 0-25=-25가 되어
      // "−" 방향으로 내리면 음수 시각이 저장될 수 있었음 - 하루의 시작(0분)
      // 아래로는 못 내려가게 0으로 추가 클램프.
      final lowerBound = _fineAdjustBoundCenter - _fineAdjustRangeMinutes;
      final next = (_preciseMinutes + delta).clamp(
        lowerBound < 0 ? 0 : lowerBound,
        upperBound < startCap ? upperBound : startCap,
      );
      if (next == _preciseMinutes) return;
      setState(() => _preciseMinutes = next);
    } else {
      final next = (_endMinutes + delta).clamp(_displayStartMinutes + _minDurationMinutes, _dayEndMinutes);
      if (next == _endMinutes) return;
      setState(() => _endMinutes = next);
    }
  }

  bool get _isEditing => widget.existing != null;

  // ⭐ 2026-09-03 - 영어 로케일 분기용. 소요시간 표시(_durationKoreanLabel vs
  // _durationPresetLabel)와 자동분류 스킵 여부 둘 다에 씀.
  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';

  // ⭐ 2026-09-01 후속8 - "키보드가 뜨고 내려갈 때마다 시트가 미세하게
  // 위아래로 움직인다"는 재확인 피드백. 근본 원인은 이 앱의
  // `android:windowSoftInputMode="adjustResize"`(AndroidManifest.xml) -
  // 키보드가 뜨면 안드로이드가 렌더링 윈도우 자체를 물리적으로 줄여서,
  // `MediaQuery.size.height`가 실제로 작아진다(Flutter가 흉내내는 게 아니라
  // 진짜 화면이 줄어듦). 이 상태에서 시트를 완전히 고정된 절대 위치에
  // 두려고 하면, 줄어든 화면 바깥(더 이상 존재하지 않는 픽셀)에 그리려는
  // 꼴이 되어 오히려 내용이 잘릴 수 있음 - 즉 "완전히 안 움직이게" 만드는
  // 건 이 모드를 유지하는 한 물리적으로 불가능함(전체 화면 키보드 모드
  // 자체를 바꾸는 건 앱 전역에 영향을 주는 별도 사안이라 이번엔 보류하기로
  // 확인됨). 대신 "고정 높이로 캐시했다가 안 맞으면 순간이동" 대신, 화면
  // 크기를 매번 그대로(비캐시) 반영하되 `AnimatedContainer`로 그 변화를
  // 부드럽게 보간되게 해서 - 어차피 피할 수 없는 이 미세한 크기/위치 변화가
  // "덜컥거림"이 아니라 "의도된 부드러운 리사이즈"처럼 보이게 함(스마트하게
  // 완화 - 요청대로 adjustResize 자체나 전체 구조는 안 건드림).
  final _contentFocusNode = FocusNode();

  // ⭐ 2026-09-03(9차) - "팝업 뜨자마자 키보드가 자동으로 올라온다, 없애자 -
  // 기본은 키보드 없는 채로 뜨고, 쓰고 싶을 때 텍스트필드를 직접 눌러서
  // 켜는 걸로" 요청으로 initState의 자동 requestFocus()를 제거함. TextField
  // 자체는 focusNode를 그대로 갖고 있어서 탭하면 평소처럼 포커스/키보드가
  // 뜸 - 여기서 없앤 건 "열리자마자 자동으로" 포커스를 강제하던 부분뿐.
  // ⭐ 2026-09-04 - 위 변경이 수정(_isEditing==true) 팝업만 겨냥한 요청이었는데
  // 생성 팝업까지 같이 꺼져버렸다는 지적으로, 원래 동작(생성 시 내용
  // 텍스트필드 자동 포커스)을 생성 쪽에만 복원함 - 수정 팝업은 그대로 비활성
  // 유지. addPostFrameCallback을 쓰는 이유: initState 시점엔 TextField가 아직
  // 트리에 붙기 전이라 requestFocus()가 씹힐 수 있음.
  @override
  void initState() {
    super.initState();
    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _contentFocusNode.requestFocus();
      });
    }
    // ⭐ 2026-09-05 - 수정 모드에서 이전에 설정해둔 알림 초안을 그대로 복원
    // (생성 모드는 캐시에 아직 아무것도 없으니 항상 기본값). 위 캐시 주석
    // 참고 - 앱을 새로 켜면 이 캐시 자체가 비어서 기본값으로 돌아감(의도된
    // 한계, 진짜 DB 컬럼이 생기기 전까지).
    final cached = _isEditing
        ? _scheduleNotifyDraftCache['${widget.dateKey}_${widget.existing!.startMinutes}']
        : null;
    _notifyEnabled = cached?.enabled ?? false;
    _notifyOffsetMinutes = cached?.offsetMinutes ?? 0;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  // ⭐ 제목이 없어졌으니 이제 "내용"이 유일한 필수 입력.
  bool get _isValid => _contentController.text.trim().isNotEmpty;

  // ⭐ 2026-08-27 - 저장 버튼 핸들러. 아이콘 선택 팝업이 없어졌으므로 항상
  // 내용 텍스트로 자동분류(MemoCategoryClassifier)함 - 분류에 실패(모델 로드
  // 전 등)하면 조용히 기본값(0=업무)으로 저장, 이것 때문에 저장 자체가
  // 막히면 안 됨.
  // ⭐ 2026-09-03 - MemoCategoryClassifier는 순수 한국어 키워드/학습 데이터로만
  // 만들어져 있어서, 영어로 적은 내용은 사실상 못 알아듣는다(전부 "기타"로
  // 빠지거나 부정확). 영어 로케일에서는 아예 분류를 시도하지 않고 - 어차피
  // "기타"로 떨어질 걸 굳이 모델 로드까지 하는 낭비를 피함 - "기타"일 때
  // 이미 쓰던 도형 10종 순환 배정(_nextEtcIconIndex)만 바로 적용한다. 한국어는
  // 기존 동작 그대로.
  Future<void> _handleSave() async {
    var iconIndex = 0;
    String? predictedCategory;
    if (!_isKorean) {
      predictedCategory = 'etc';
      iconIndex = await _nextEtcIconIndex();
      if (!mounted) return;
      _finishSave(iconIndex, predictedCategory);
      return;
    }
    setState(() => _autoClassifying = true);
    try {
      await MemoCategoryClassifier.instance.ensureLoaded();
      final prediction = MemoCategoryClassifier.instance
          .classify(_contentController.text.trim());
      predictedCategory = prediction.categoryKey;
      if (prediction.categoryKey == 'etc') {
        // ⭐ 2026-09-01 - "기타"는 고정 아이콘 하나가 아니라 순수 도형 10종을
        // 순서대로 순환 배정(_nextEtcIconIndex 참고) - 매번 같은 동그라미만
        // 나오던 문제 해결. 실제 카테고리로 맵핑됐을 때는 아래 else와 동일하게
        // 그 키의 고정 아이콘 하나만 계속 씀(순환 없음).
        iconIndex = await _nextEtcIconIndex();
      } else {
        final matched = _kScheduleCategoryIcons
            .indexWhere((e) => e.$1 == prediction.categoryKey);
        if (matched != -1) iconIndex = matched;
      }
    } catch (e) {
      debugPrint('⚠️ 카테고리 자동분류 실패(기본 아이콘으로 저장): $e');
    } finally {
      if (mounted) setState(() => _autoClassifying = false);
    }
    if (!mounted) return;
    _finishSave(iconIndex, predictedCategory);
  }

  void _finishSave(int iconIndex, String? predictedCategory) {
    // ⭐ 수정 모드는 시작 시각을 안 바꾸므로 widget.existing의 원래 값을 그대로
    // 유지, 생성 모드는 5분 미세조정이 반영된 _preciseMinutes를 씀 - 아래
    // DateSchedule과 알림 초안 캐시 키 둘 다 이 값을 같이 씀(같은 일정의 같은
    // 시작 시각이어야 하므로).
    final startMinutes = _isEditing ? widget.existing!.startMinutes : _preciseMinutes;
    // ⭐ 2026-09-05 - 일정 알림 UI 껍데기 저장(위 _scheduleNotifyDraftCache
    // 주석 참고 - 진짜 DB가 아니라 이 세션 동안만 유지되는 캐시).
    _scheduleNotifyDraftCache['${widget.dateKey}_$startMinutes'] =
        (enabled: _notifyEnabled, offsetMinutes: _notifyOffsetMinutes);
    Navigator.pop(
      context,
      DateSchedule(
        date: '', // _openCreateSheet/_openEditSheet가 실제 날짜로 덮어씀
        content: _contentController.text.trim(),
        // slotMinutes(물리적 표시 위치)는 여기서 안 정함 - DateSchedule의
        // getter가 이 startMinutes로부터 알아서 계산함(computeSlotMinutes).
        startMinutes: startMinutes,
        durationMinutes: _displayDurationMinutes,
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
    // ⭐ 2026-09-01 후속8 - adjustResize 때문에 이 값 자체는 키보드가 뜨면
    // 실제로 작아짐(위 _contentFocusNode 주석 참고) - 이제 캐시하지 않고
    // 매번 그대로 반영하되, 그 변화를 AnimatedContainer로 부드럽게 감쌈.
    final sheetHeight = MediaQuery.of(context).size.height * 0.76;
    return SafeArea(
      top: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: sheetHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
        // ⭐ 후속6 - "취소/생성 버튼을 맨 아래로 내려달라"는 요청 - 내용은
        // Expanded+SingleChildScrollView로 스크롤되게 두고, 버튼 Row는 그
        // 바깥 Column에 별도로 둬서 항상 시트의 물리적 맨 아래에 고정되게 함
        // (이전엔 버튼도 스크롤 영역 Column 안에 있어서, 내용이 짧으면 버튼이
        // 시트 중간쯤에서 끝나고 그 아래로 빈 공간이 남았음).
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
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
              // ⭐ 2026-09-03(4차) - 삭제 버튼을 이 제목 줄에서 뺌(요청: "삭제
              // 버튼을 취소/저장 그 위 어딘가로 보내자") - 키보드가 떠 있는
              // 상태에서도 이 제목 줄은 눌리는데, 삭제를 누르면 확인 UI가
              // 시트 맨 아래(취소/저장 자리)에서 바뀌니까 화면 위쪽(이 줄)을
              // 보고 있던 사용자는 그 변화를 못 봄 - 삭제 버튼 자체를 그
              // 확인 UI가 나타나는 자리 바로 위로 옮겨서 항상 같은 시야 안에
              // 있게 함(아래 취소/저장 Row 바로 위 참고).
              Text(
                _isEditing ? context.l10n.scheduleEditTitle : context.l10n.scheduleNewTitle,
                style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    color: kAppChipBorder),
              ),
              SizedBox(height: 20.h),
              // ⭐ 2026-08-31 - "줄바꿔서 입력해도 어차피 안 보인다"는 확인으로
              // maxLines 3(여러 줄) → 1(한 줄)로 변경. autofocus는 initState의
              // 지연 포커스 요청으로 대체(위 focusNode 주석 참고).
              TextField(
                controller: _contentController,
                focusNode: _contentFocusNode,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_isValid && !_autoClassifying) _handleSave();
                },
                decoration: InputDecoration(
                  labelText: context.l10n.scheduleContentFieldLabel,
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
              Text(context.l10n.scheduleTimeSectionLabel,
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: kAppChipBorder.withValues(alpha: 0.6))),
              SizedBox(height: 8.h),
              // ⭐ 2026-09-01 후속5 - "시계아이콘 07:00 AM / 07:30 AM (30m)"
              // 한 줄짜리 표시 + "시간 미정/프리셋 칩 9개" 목록을 전부 걷어내고,
              // 가로 카드 2개(시작/종료)로 재설계(요청). 카드를 탭하면 그 카드가
              // "활성"이 되고, 그 아래 −/+ 스텝 버튼이 그 카드에 적용된다 -
              // 시작 카드는 5분 스텝 하나(기존 미세조정 그대로), 종료 카드는
              // 5분/30분/1시간 세 스텝. 새 일정은 시작 카드가 기본 활성(요청:
              // "처음은 앞 07:00이 활성상태") - 아무것도 안 건드리고 바로
              // "생성"을 눌러도 시작+30분짜리 일정이 그대로 만들어진다.
              Row(
                children: [
                  Expanded(
                    child: _TimeCardButton(
                      icon: Icons.schedule,
                      label: _scheduleTimeLabel(_displayStartMinutes, null),
                      active: _activeCard == _TimeCardSlot.start,
                      enabled: !_isEditing, // 수정 모드는 시작 시각 고정 - 탭 불가
                      onTap: () => _selectCard(_TimeCardSlot.start),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Text('-',
                        style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: kAppChipBorder.withValues(alpha: 0.3))),
                  ),
                  Expanded(
                    child: _TimeCardButton(
                      icon: null,
                      label: _scheduleTimeLabel(_displayEndMinutes, null),
                      // ⭐ 2026-09-01 후속5(2차) - 타임라인 카드/라벨("30m", "1h
                      // 30m")과 달리 이 시트는 카드 안에 한 줄 정도는 여유가
                      // 있어서 "2시간 30분"처럼 한글로 풀어 씀(요청). ⭐ 2026-09-03 -
                      // 영어 로케일은 _durationPresetLabel("1h 30m")로 대체.
                      sublabel: '(${_isKorean ? _durationKoreanLabel(_displayDurationMinutes) : _durationPresetLabel(_displayDurationMinutes)})',
                      active: _activeCard == _TimeCardSlot.end,
                      enabled: true,
                      onTap: () => _selectCard(_TimeCardSlot.end),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  _FineAdjustToggle(
                    label: '−',
                    selected: _adjustDown,
                    onTap: () => setState(() => _adjustDown = true),
                  ),
                  SizedBox(width: 6.w),
                  _FineAdjustToggle(
                    label: '+',
                    selected: !_adjustDown,
                    onTap: () => setState(() => _adjustDown = false),
                  ),
                  SizedBox(width: 10.w),
                  _StepChip(label: _isKorean ? '5분' : _durationPresetLabel(5), onTap: () => _adjustActiveCard(5)),
                  // ⭐ 종료 카드가 활성일 때만 30분/1시간 스텝도 같이 보여줌
                  // (요청: "우측 카드를 셀렉트하면 −+5분은 그대로 있고 거기에
                  // 30분 1시간 버튼이 추가되게"). ⭐ 2026-09-03 - 영어 로케일은
                  // _durationPresetLabel의 h/m 표기("30m"/"1h")를 그대로 재사용
                  // (이미 이 파일에 있는 컴팩트 표기라 새 l10n 키 없이 씀).
                  if (_activeCard == _TimeCardSlot.end) ...[
                    SizedBox(width: 6.w),
                    _StepChip(label: _isKorean ? '30분' : _durationPresetLabel(30), onTap: () => _adjustActiveCard(30)),
                    SizedBox(width: 6.w),
                    _StepChip(label: _isKorean ? '1시간' : _durationPresetLabel(60), onTap: () => _adjustActiveCard(60)),
                  ],
                ],
              ),
              // ⭐ 2026-09-01 후속5(2차) - "자리에 표시돼요" 안내 문구와 "아이콘은
              // 내용으로 자동 판단해서 붙여요" 캡션 둘 다 삭제(요청) - 실제
              // 동작(30분 슬롯 스냅/아이콘 자동분류) 자체는 그대로 유지, 화면에
              // 안내 텍스트만 안 보여줌.
              SizedBox(height: 22.h),
              // ⭐ 2026-09-05 - 일정 알림 UI 껍데기. work_hours_settings_screen.dart의
              // Switch(온/오프 전용)와 day_offset_chip.dart의 AppShiftChip 토글
              // 그룹(하나 고르기)을 그대로 재사용 - 이 화면만의 새 부품을 안 만듦.
              Text(context.l10n.scheduleNotifySectionLabel,
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: kAppChipBorder.withValues(alpha: 0.6))),
              SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.scheduleNotifyToggleLabel,
                      style: TextStyle(fontSize: 14.5.sp, fontWeight: FontWeight.w600, color: kAppChipBorder),
                    ),
                  ),
                  Switch(
                    value: _notifyEnabled,
                    onChanged: (v) => setState(() => _notifyEnabled = v),
                    activeColor: kAppMainAccent,
                  ),
                ],
              ),
              if (_notifyEnabled) ...[
                SizedBox(height: 4.h),
                // ⭐ "그냥 알림"이라는 원래 요청 그대로 - 기존 알람(벨소리/스누즈/
                // 잠금화면)과 이게 왜 다른지 사용자가 헷갈리지 않도록, 시스템
                // 알림 설정(소리/진동/무음)을 그대로 따르는 가벼운 알림 1건이라는
                // 걸 여기서 미리 알려줌.
                Text(context.l10n.scheduleNotifyDescription,
                    style: TextStyle(fontSize: 11.5.sp, color: kAppChipBorder.withValues(alpha: 0.5))),
                SizedBox(height: 10.h),
                Text(context.l10n.scheduleNotifyOffsetQuestion,
                    style: TextStyle(fontSize: 12.5.sp, color: kAppChipBorder.withValues(alpha: 0.6))),
                SizedBox(height: 8.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: _kNotifyOffsetOptions.map((minutes) {
                    final label = minutes == 0
                        ? context.l10n.scheduleNotifyOffsetOnTime
                        : context.l10n.scheduleNotifyOffsetBefore(minutes);
                    return AppShiftChip(
                      label: label,
                      dense: true,
                      selected: _notifyOffsetMinutes == minutes,
                      onTap: () => setState(() => _notifyOffsetMinutes = minutes),
                    );
                  }).toList(),
                ),
              ],
                  ],
                ),
              ),
            ),
            SizedBox(height: 14.h),
            // ⭐ 2026-09-01 후속6 - "취소/생성 버튼을 맨 아래로 내려달라"는
            // 요청으로 위 스크롤 영역(Expanded) 밖, 이 Column의 마지막
            // 자식으로 옮김 - 내용이 짧아도 항상 시트 맨 아래에 고정됨.
            // 버튼 스타일 - "생성도 메인 버튼(AppButton) 말고 취소랑 같은
            // second button 모양에 색만 앱 컨셉으로" 요청으로 AppButton →
            // AppSecondButton(variant: primary, kAppMainAccent 채움)으로 교체.
            // ⭐ 2026-09-03(4차) - 삭제 버튼을 제목 줄에서 이 자리(취소/저장
            // Row 바로 위)로 옮김 - 눌렀을 때 바뀌는 자리(바로 아래)가 항상
            // 같은 화면 안에 있게 하기 위함(위 제목 줄 쪽 주석 참고). 확인
            // 중이 아닐 때만 보임 - 확인 중엔 아래 Row 자체가 경고문구+버튼으로
            // 바뀌므로 이 트리거는 필요 없음.
            if (_isEditing && !_confirmingDelete) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _confirmingDelete = true),
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFD64545), size: 18),
                  label: Text(context.l10n.commonDelete,
                      style: const TextStyle(color: Color(0xFFD64545))),
                ),
              ),
              SizedBox(height: 4.h),
            ],
            // ⭐ 2026-09-03(3차) - 삭제 확인 중(_confirmingDelete)이면 이 자리
            // (시트 맨 아래, 키보드 위에 항상 보이는 고정 위치)를 그대로
            // "경고 문구 + 취소/삭제" 버튼으로 바꿔치기함 - 위 클래스 docstring
            // 참고(스크림/오버레이 방식의 두 문제를 이 방식으로 없앰).
            if (_confirmingDelete) ...[
              Text(context.l10n.scheduleDeleteConfirmBody,
                  style: TextStyle(fontSize: 12.sp, color: kAppChipBorder.withValues(alpha: 0.6))),
              SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(
                    child: AppSecondButton(
                      variant: AppSecondButtonVariant.neutral,
                      onPressed: () => setState(() => _confirmingDelete = false),
                      child: Text(context.l10n.commonCancel),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: AppSecondButton(
                      variant: AppSecondButtonVariant.danger,
                      onPressed: () {
                        // ⭐ 일정 자체가 삭제되니 알림 초안 캐시도 같이 정리 -
                        // 안 지우면 나중에 같은 날짜+시각에 새 일정을 만들 때
                        // 엉뚱하게 옛 값이 프리필될 수 있음(orphan 방지).
                        _scheduleNotifyDraftCache.remove('${widget.dateKey}_${widget.existing!.startMinutes}');
                        Navigator.pop(context, _CreateBlockSheet.deleteSignal);
                      },
                      child: Text(context.l10n.commonDelete),
                    ),
                  ),
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: AppSecondButton(
                      variant: AppSecondButtonVariant.neutral,
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.commonCancel),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: AppSecondButton(
                      variant: AppSecondButtonVariant.primary,
                      onPressed:
                          (_isValid && !_autoClassifying) ? _handleSave : null,
                      child: _autoClassifying
                          ? SizedBox(
                              width: 18.w,
                              height: 18.w,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isEditing ? context.l10n.commonSave : context.l10n.scheduleCreateButton),
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

// ⭐ 2026-09-01 후속5 - 일정생성 시트의 시작/종료 시간 카드 1개. "거창하게
// 하지 말고 지금처럼 간단하게 - 대신 활성/비활성 상태만 나타내면 됨"(요청) -
// 기존 "시간" 정보 박스(강조색 옅은 배경)와 똑같은 톤을 활성 카드에 쓰고,
// 비활성 카드는 다른 칩들과 동일한 중립색(Color(0xFFF4F6FC))을 씀.
class _TimeCardButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String? sublabel;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _TimeCardButton({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? kAppMainAccent : kAppChipBorder.withValues(alpha: 0.55);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: active ? kAppMainAccent.withValues(alpha: 0.08) : const Color(0xFFF4F6FC),
          borderRadius: BorderRadius.circular(12.r),
          border: active ? Border.all(color: kAppMainAccent.withValues(alpha: 0.4)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16.sp, color: color),
              SizedBox(width: 6.w),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: color),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ⭐ 2026-09-01 후속5 - 시작/종료 카드 아래 스텝 버튼(5분/30분/1시간) 공용
// 모양 - 기존 "5분" 버튼과 동일한 스타일(강조색 필+흰 글씨의 pill)을 재사용.
class _StepChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: kAppMainAccent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

// ⭐ 2026-08-31("D번") - 5분 미세조정의 "−"/"+" 방향 토글 한 칸. 스펙: "둘 중
// 하나는 무조건 선택, 하나만 선택된 상태" - 라디오 버튼처럼 항상 정확히 하나만
// 활성화됨(_CreateBlockSheetState._adjustDown이 그 상태를 들고 있음).
class _FineAdjustToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FineAdjustToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.w,
        height: 36.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? kAppMainAccent : const Color(0xFFF4F6FC),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : kAppChipBorder.withValues(alpha: 0.6),
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
        title: Text(context.l10n.scheduleSettingsTitle),
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
            Text(context.l10n.scheduleBackgroundLabel,
                style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: kAppChipBorder)),
            SizedBox(height: 4.h),
            Text(
              context.l10n.scheduleBackgroundDescription,
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
