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
import '../providers/schedule_provider.dart';
import '../services/memo_category_classifier.dart';
import '../theme/app_colors.dart';

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

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (widget.onSwipeToCalendar != null &&
            details.primaryVelocity != null) {
          if (details.primaryVelocity! > 500) {
            widget.onSwipeToCalendar!();
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFBFF),
        body: Column(
          children: [
            _buildHeader(dateLabel, selectedShiftName, selectedHasShift,
                selectedShiftColor),
            _buildDateStrip(daysInMonth),
            Container(height: 1, color: kAppChipBorder.withValues(alpha: 0.08)),
            Expanded(
                child: _TimeAxisPicker(
                    key: ValueKey(dateKey),
                    dateKey: dateKey,
                    hasShiftToday: selectedHasShift)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      String dateLabel, String shiftName, bool hasShift, Color? shiftColor) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
          child: Row(
            children: [
              _MonthNavButton(
                  icon: Icons.chevron_left, onTap: () => _shiftMonth(-1)),
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
                            color: kAppChipBorder),
                      ),
                      if (hasShift)
                        _ShiftPill(shiftName: shiftName, color: shiftColor),
                    ],
                  ),
                ),
              ),
              _MonthNavButton(
                  icon: Icons.chevron_right, onTap: () => _shiftMonth(1)),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ "그냥 숫자만" - 요일 라벨 없이 날짜 숫자만. 편집모드 토글이 없어져서
  // 다시 전체 폭을 다 씀(트레일링 아이콘 자리 없앰).
  Widget _buildDateStrip(int daysInMonth) {
    return Container(
      color: Colors.white,
      height: _dateChipHeight.h + 14.h,
      child: ListView.separated(
        controller: _dateStripController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        itemCount: daysInMonth,
        separatorBuilder: (_, __) => SizedBox(width: _dateChipGap.w),
        itemBuilder: (context, index) {
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
              decoration: BoxDecoration(
                color: isSelected ? kAppMainAccent : const Color(0xFFF4F6FC),
                borderRadius: BorderRadius.circular(11.r),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: kAppMainAccent.withValues(alpha: 0.35),
                            blurRadius: 7,
                            offset: const Offset(0, 3))
                      ]
                    : null,
                border: !isSelected && isToday
                    ? Border.all(
                        color: kAppMainAccent.withValues(alpha: 0.5),
                        width: 1.3)
                    : null,
              ),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : kAppChipBorder,
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
  final VoidCallback onTap;
  const _MonthNavButton({required this.icon, required this.onTap});

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
          child: Icon(icon,
              size: 22.sp, color: kAppChipBorder.withValues(alpha: 0.55)),
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
  const _TimeAxisPicker(
      {super.key, required this.hasShiftToday, required this.dateKey});

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
  // ⭐ 인디케이터 래퍼(Container)의 상하 패딩. _indicatorWrapperHeight(아래)가
  // 이 값과 아이콘 크기로부터 "계산되어야" 실제 렌더 높이와 항상 정확히
  // 일치함 - 패딩만 스케일되고 높이 상수는 고정값이면(예전 버그) 화면
  // 배율에 따라 인디케이터가 화살표가 가리키는 지점과 미세하게 어긋남
  // (그게 정각/30분 눈금 비대칭 버그의 원인 중 하나였음 - 이제 그 위험을
  // 아예 없애기 위해 패딩과 아이콘 크기 둘 다 같은 축(.h/.r)으로 스케일함).
  static double get _indicatorVerticalPadding => (14 * 7 / 8).h;
  // ⭐ 평소(안 만질 때)엔 작게, 탭해서 활성화되면 그보다 크게 - 크기 차이가
  // 나므로 래퍼 높이도 상태에 따라 달라져야 함(아래 getter 참고).
  double get _indicatorWrapperHeight =>
      (_isDragging
          ? _AxisIndicator._activeIconSize
          : _AxisIndicator._idleIconSize) +
      _indicatorVerticalPadding * 2;
  // ⭐ 숫자/눈금을 축 왼쪽으로 옮기면서(요청) 그만큼 왼쪽 여백이 더 필요해짐
  // (숫자 텍스트 + 눈금이 들어갈 자리) - 26→58로 늘림.
  static double get _axisLeftMargin => (58 * 7 / 8).w;
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
  // ⭐ 세로축 선의 두께 + 정각/30분 눈금 두께 - 전부 원형/선 두께처럼
  // 가로세로 구분 없는 값이라 .r로 통일. 각 눈금의 Positioned top 오프셋이
  // "-두께/2"로 이 값에서 직접 파생되므로, 여기 값만 바꾸면 중앙 정렬이
  // 항상 그대로 유지됨.
  static double get _axisLineWidth => (4 * 7 / 8).r;
  static double get _hourTickThickness => (3 * 7 / 8).r;
  static double get _halfTickThickness => (2.5 * 7 / 8).r;

  final ScrollController _controller = ScrollController();
  double _initialMinutes = 0; // 최초 진입 시 중앙에 놓일 시각(현재 시각)
  bool _jumpedToInitial = false;

  // ⭐ 2026-08-27 - date_schedules 테이블(DB v20)에서 영구 저장으로 전환.
  // build()마다 dateScheduleProvider를 watch해서 최신값으로 갱신함(아래
  // build() 참고) - 여기 초기값은 그 갱신 전까지의 플레이스홀더일 뿐.
  List<DateSchedule> _blocks = const [];

  // ⭐ 인디케이터 드래그 상태 - null이면 평소(축 정중앙 고정) 상태.
  // 콘텐츠 좌표계(= _slotTops와 같은 기준, 스크롤 offset과 비교 가능한 값)의
  // 절대 위치를 담음 - 드래그 중엔 배경 스크롤을 잠가두므로 화면 delta를
  // 그대로 누적해도 콘텐츠 좌표 delta와 같음.
  double? _dragContentY;
  double? _downContentY; // 누른 순간의 콘텐츠 좌표 - "정말 움직였는지" 판정 기준점
  bool _hasMovedSinceDown = false; // "탭만 하고 안 움직였으면 취소" 판정용
  Timer? _edgeTimer;

  // ⭐ 아주 작은 손떨림까지 "이동"으로 잡으면 그냥 탭했다 떼는 것도 취소가
  // 안 됨(버그 재발) - 최소 이 정도(콘텐츠 좌표 기준)는 움직여야 "진짜
  // 이동"으로 침. Flutter 제스처 인식기의 터치 슬롭에 기대지 않고 직접
  // 판정하는 이유는 위 Listener 관련 주석 참고.
  static const double _moveThreshold = 6;

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
    _initialMinutes = _computeInitialCenterMinutes();
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
  double _computeInitialCenterMinutes() {
    final hasEmptyState = !widget.hasShiftToday && _blocks.isEmpty;
    if (hasEmptyState) {
      // TODO(근무시간 입력 기능 붙을 때): widget.hasShiftToday 대신 그날의
      // 실제 근무 유형 + 근무별 근무시간 설정을 받아서, 주간/야간 등 유형별로
      // "근무 후" 시각을 반환하도록 분기 추가.
      return 9 * 60; // 09:00
    }
    final now = DateTime.now();
    return (now.hour * 60 + now.minute).toDouble();
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _formatMinutes(num minutes) {
    final total = minutes.round().clamp(0, _slotCount * 30);
    final h = (total ~/ 60) % 24;
    final m = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // ⭐ "00:00 ~ 03:00 (3시간)"처럼 범위 + 소요시간을 한 줄로. 소요시간 포맷은
  // 이미 있던 _durationPresetLabel(프리셋 칩 라벨)을 그대로 재사용함.
  String _timeRangeLabel(DateSchedule block) {
    final start = _formatMinutes(block.startMinutes);
    final end = _formatMinutes(block.startMinutes + block.durationMinutes);
    return '$start ~ $end (${_durationPresetLabel(block.durationMinutes)})';
  }

  // ⭐ "정확히 동일한 시간 범위"의 일정은 중복 생성을 막음 - 그런 경우는
  // 기존 일정에 내용을 같이 적으면 되니까. [exclude]는 수정 시 자기 자신은
  // 비교 대상에서 빼기 위함.
  bool _hasDuplicateRange(int start, int duration, {DateSchedule? exclude}) {
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
        double sum = 0;
        for (final b in blocksHere) {
          sum += _ScheduleRow.heightForStyle(b.styleIndex);
        }
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
  List<Widget> _buildScheduleRowWidgets(double rowLeft) {
    final widgets = <Widget>[];
    for (final entry in _grouped.entries) {
      double offset = 0;
      for (final block in entry.value) {
        final h = _ScheduleRow.heightForStyle(block.styleIndex);
        widgets.add(Positioned(
          top: _edgePadding + _slotTops[entry.key] + offset,
          left: rowLeft,
          right: 16.w,
          height: h,
          child: _ScheduleRow(
            block: block,
            timeLabel: _timeRangeLabel(block),
            iconDiameter: _iconDiameter,
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

  // ⭐ 지금 손가락이 실제로 가리키는(가려버리는) 슬롯 - 표시/생성 둘 다
  // 이걸 그대로 안 쓰고 아래 _displaySlot(2칸 위)을 씀.
  int get _rawDragSlot =>
      _dragContentY == null ? -1 : _slotIndexAtContentY(_dragContentY!);

  // ⭐ 화면에 보이고, 실제로 생성되는 슬롯 - 손가락에 가려지지 않도록 항상
  // 실제 위치보다 2칸(1시간) 위.
  int get _displaySlot =>
      (_rawDragSlot - _activeDisplayOffsetSlots).clamp(0, _slotCount - 1);

  // ⭐ 인디케이터가 지금 가리키는 화면 Y:
  //  - 평소(안 만질 때): 항상 뷰포트 정중앙.
  //  - 누르는 즉시(요청: "누르면 시각에 가서 붙는 구조"): 움직이기 전이라도
  //    바로 _displaySlot 위치로 스냅해서 보여줌 - "탭 직후 아직 안 움직인
  //    상태"와 "그 자리에서 손을 떼면 취소되는지"는 완전히 별개 판정
  //    (_hasMovedSinceDown, onPointerUp에서만 봄)이라 여기선 신경 안 씀.
  double get _indicatorScreenY {
    if (_dragContentY == null) return _viewportHeight / 2;
    final scrollOffset = _controller.hasClients ? _controller.offset : 0.0;
    return _edgePadding + _slotTops[_displaySlot] - scrollOffset;
  }

  bool get _isDragging => _dragContentY != null;

  // ⭐ 평소(안 만질 때) - 화살표 없는 동그라미가 축 정중앙에 오도록. 래퍼에
  // GestureDetector용 좌우 패딩(10.w)이 있어서 그만큼 보정함. (참고: private
  // 멤버는 클래스가 아니라 파일=라이브러리 단위라 같은 파일 안이면
  // _AxisIndicator._iconSize처럼 밖에서도 그대로 접근 가능함.)
  double get _idleIndicatorLeft =>
      _axisX - _AxisIndicator._idleIconSize / 2 - 10.w;

  // ⭐ 숫자/눈금이 이제 축 왼쪽으로 옮겨가서, 인디케이터(활성 상태)는 축
  // 오른쪽에 거의 맞닿을 정도로 붙여도 더 이상 숫자를 가리지 않음(요청).
  // ⭐ 이 값은 항상 고정(-10.w, 컨테이너 좌우 패딩 보정용)임 - 화살표
  // 끝(부리 꼭짓점)이 이 좌표계의 로컬 x=0에 그려지므로, 여기에 패딩(10.w)만
  // 다시 더하면 항상 정확히 축 선(_axisX)에 맞닿음. "아이콘을 축에서 더
  // 떨어뜨리고 화살표를 더 길게"는 _AxisIndicator._activeBeakLength 하나만
  // 바꾸면 됨(부리 꼭짓점은 그대로 axisX에 고정된 채, 아이콘만 그만큼 더
  // 밀려남) - 간격 상수를 두 곳에 따로 두면 화면 배율에 따라 어긋나므로
  // 일부러 한 곳(_AxisIndicator)에만 둠.
  double get _activeIndicatorLeft => _axisX - 10.w;

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
      _dragContentY = _unshiftedCenterPosition();
      _downContentY = _dragContentY;
      _hasMovedSinceDown = false;
    });
  }

  void _onIndicatorDragUpdate(DragUpdateDetails details) {
    if (_dragContentY == null) return;
    setState(() {
      _dragContentY =
          (_dragContentY! + details.delta.dy).clamp(0.0, _slotTops[_slotCount]);
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
    final currentSlot = _slotIndexAtContentY(_dragContentY!);
    final targetSlot = (currentSlot + direction).clamp(0, _slotCount - 1);
    if (targetSlot == currentSlot) {
      _edgeTimer?.cancel();
      _edgeTimer = null;
      return;
    }
    final delta = _slotTops[targetSlot] - _slotTops[currentSlot];
    final newOffset = (_controller.offset + delta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    setState(() {
      _dragContentY = _dragContentY! + delta;
      _hasMovedSinceDown = true;
    });
    _controller.jumpTo(newOffset);
  }

  @override
  Widget build(BuildContext context) {
    _blocks =
        ref.watch(dateScheduleProvider)[widget.dateKey] ?? const [];
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
        final rowLeft = _axisX + 26.w;

        if (!_jumpedToInitial) {
          _jumpedToInitial = true;
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
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              kAppMainAccent.withValues(alpha: 0.25),
                              kAppMainAccent.withValues(alpha: 0.75),
                              kAppMainAccent.withValues(alpha: 0.25),
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(_axisLineWidth / 2),
                          boxShadow: [
                            BoxShadow(
                              color: kAppMainAccent.withValues(alpha: 0.25),
                              blurRadius: 6.r,
                              spreadRadius: 0.5.r,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ⭐ 정각 눈금 + 숫자 - 요청대로 축 왼쪽으로 옮김(시간이
                    // 왼쪽, 축은 그 오른쪽). 눈금 끝도 둥글게. 색상을 메인
                    // 색상 계열로 통일하고, 숫자는 딱딱한 기본 서체 대신
                    // 더 둥글둥글한 서체(Quicksand)로 바꿈("너무 딱딱하다"
                    // 피드백).
                    for (int hour = 0; hour <= 24; hour++)
                      Positioned(
                        top: _edgePadding +
                            _slotTops[(hour * 2).clamp(0, _slotCount)] -
                            _hourTickBoxHeight / 2,
                        left: 0,
                        width: _axisX,
                        height: _hourTickBoxHeight,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              (hour % 24).toString().padLeft(2, '0'),
                              style: GoogleFonts.quicksand(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w700,
                                  color: kAppMainAccent),
                            ),
                            SizedBox(width: 8.w),
                            Container(
                              width: 18.w,
                              height: _hourTickThickness,
                              decoration: BoxDecoration(
                                  color: kAppMainAccent.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(
                                      _hourTickThickness / 2)),
                            ),
                          ],
                        ),
                      ),
                    // 30분 눈금 - 숫자 없이 짧은 선만, 축 왼쪽에 끝이 닿게(둥근 끝).
                    // 정각 눈금보다 옅은 톤으로 둬서 위계(정각> 30분)를 줌.
                    for (int slot = 1; slot < _slotCount; slot += 2)
                      Positioned(
                        top: _edgePadding +
                            _slotTops[slot] -
                            _halfTickThickness / 2,
                        left: _axisX - 14.w,
                        child: Container(
                          width: 14.w,
                          height: _halfTickThickness,
                          decoration: BoxDecoration(
                              color: kAppMainAccent.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(
                                  _halfTickThickness / 2)),
                        ),
                      ),
                    // ⭐ 일정들 - 시작 슬롯 기준으로 아이콘+내용 한 줄씩. 같은
                    // 슬롯에서 시작하는 게 여러 개면 그 슬롯 안에서 세로로 쌓임
                    // (_recomputeLayout이 이미 그만큼 슬롯을 늘려둠). 스타일마다
                    // 필요한 높이가 달라서(_ScheduleRow.heightForStyle) 고정
                    // 간격이 아니라 각 일정의 실제 높이를 누적해서 배치함
                    // (_buildScheduleRowWidgets).
                    ..._buildScheduleRowWidgets(rowLeft),
                  ],
                ),
              ),
            ),
            // ⭐ 인디케이터 - 평소엔 화살표 없는 동그라미로 축 정중앙에 떠서
            // 스크롤을 따라감. 손을 대는 즉시(onVerticalDragDown) 시간 숫자
            // 바로 오른쪽으로 옮겨오면서 "왼쪽을 가리키는 부리" 모양으로 바뀜.
            // 그대로 움직이지 않고 손을 떼면 그냥 취소(_hasMovedSinceDown),
            // 위/아래로 움직인 뒤 떼면 그 시각으로 일정 생성 시트가 뜸.
            //
            // ⭐ 2026-08-27 - 히트테스트 영역을 화면 전체로 넓혔다가(일정
            // 카드 위에서 드래그가 안 먹는 버그 대응) 바로 원복함 - 그렇게
            // 하니 "인디케이터 아닌 곳에서 스크롤하려 해도 인디케이터가
            // 반응한다"는 새 버그가 생겼음(onVerticalDragDown이 화면 아무
            // 데나 손을 대는 순간 무조건 먼저 불려서, 배경 스크롤과 매번
            // 아레나 경합이 붙어버림 - 축 전체를 덮는 방식 자체가 "빈
            // 공간에서의 순수 스크롤"과 구조적으로 충돌함). 그래서 인디케이터
            // 자체의 히트테스트 영역은 다시 아이콘 크기로 되돌리고, "일정
            // 카드 위에서도 드래그가 되게" 하는 부분은 각 _ScheduleRow의
            // GestureDetector에 같은 콜백을 같이 달아주는 방식으로 대신함
            // (아래 _buildScheduleRowWidgets에 인디케이터 콜백을 넘겨줌) -
            // 그러면 "일정 카드 위"에서만 영향이 있고, 나머지 빈 공간의
            // 스크롤은 예전처럼 전혀 안 건드림.
            Positioned(
              top: _indicatorScreenY - _indicatorWrapperHeight / 2,
              left: _isDragging ? _activeIndicatorLeft : _idleIndicatorLeft,
              child: GestureDetector(
                onVerticalDragDown: _onIndicatorDragDown,
                onVerticalDragUpdate: _onIndicatorDragUpdate,
                onVerticalDragEnd: _onIndicatorDragEnd,
                onVerticalDragCancel: _onIndicatorDragCancel,
                child: Container(
                  color: Colors.transparent,
                  padding: EdgeInsets.symmetric(
                      vertical: _indicatorVerticalPadding, horizontal: 10.w),
                  child: _AxisIndicator(showBeak: _isDragging),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ⭐ 인디케이터 - 평소(showBeak=false)엔 화살표 없는 작은 동그라미, 드래그 중
// (showBeak=true)엔 그보다 살짝 큰 동그라미 + 왼쪽을 가리키는 부리가 붙은
// 모양으로 바뀜(요청: 평소엔 더 작게, 탭되면 더 크게 + 화살표도 비례해서
// 더 크고 길게). 흰 테두리 링은 없음(요청: "내 앱 아이콘에도 그거 없다").
class _AxisIndicator extends StatelessWidget {
  final bool showBeak;
  const _AxisIndicator({required this.showBeak});

  // ⭐ 평소엔 작게(44→36→28), 탭해서 활성화되면 그보다 크게(44→50). 원형
  // 크기라 가로세로 구분 없는 .r로 스케일(리팩터, 2026-08-26 - 이 파일
  // 상단 _TimeAxisPickerState 주석 참고).
  static double get _idleIconSize => (28 * 7 / 8).r;
  static double get _activeIconSize => (50 * 7 / 8).r;
  // ⭐ 화살표(부리) 길이 = 축 선~아이콘 사이 간격. 부리 꼭짓점은 항상 이
  // 위젯의 로컬 x=0에 그려지고, 이 위젯 자체가 축 선에서 패딩만큼만
  // 떨어진 자리에 고정되므로(_TimeAxisPickerState._activeIndicatorLeft),
  // 이 값을 키우면 꼭짓점은 축에 그대로 붙은 채 아이콘만 더 멀리 밀려남.
  // 16→10 - "아이콘이 아직도 축에서 너무 멀다"는 피드백으로 다시 줄임(손가락이
  // 숫자를 가리는 문제는 이제 _activeDisplayOffsetSlots로 따로 해결하므로,
  // 굳이 멀리 안 띄워도 됨). ⭐ 10→4로 더 줄였다가 원복함 - 그건 이 화살표가
  // 아니라 일정 목록의 아이콘(rowLeft)을 축에 붙여달라는 요청이었음.
  static double get _activeBeakLength => (10 * 7 / 8).r;
  static double get _activeBeakHeight => (16 * 7 / 8).r;

  Widget _icon(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 7,
              offset: const Offset(0, 2))
        ],
      ),
      child: const ClipOval(
        child: Image(
            image: AssetImage('assets/icon/app_icon.png'), fit: BoxFit.cover),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!showBeak) {
      return SizedBox(
          width: _idleIconSize,
          height: _idleIconSize,
          child: _icon(_idleIconSize));
    }
    return SizedBox(
      width: _activeIconSize + _activeBeakLength,
      height: _activeIconSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ⭐ 부리 끝(왼쪽 꼭짓점)이 정확히 x=0(=이 위젯의 왼쪽 끝)에 오고,
          // 이 위젯 자체가 축 선에서 정확히 _activeBeakLength만큼 떨어진
          // 자리에 놓이므로(_activeIndicatorLeft), 부리 끝은 항상 축 선에
          // 정확히 맞닿음.
          Positioned(
            left: 0,
            top: _activeIconSize / 2 - _activeBeakHeight / 2,
            child: CustomPaint(
              size: Size(_activeBeakLength, _activeBeakHeight),
              painter: const _LeftBeakPainter(color: kAppMainAccent),
            ),
          ),
          Positioned(
              left: _activeBeakLength, top: 0, child: _icon(_activeIconSize)),
        ],
      ),
    );
  }
}

class _LeftBeakPainter extends CustomPainter {
  final Color color;
  const _LeftBeakPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LeftBeakPainter oldDelegate) =>
      oldDelegate.color != color;
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
    required this.onTap,
  });

  // ⭐ 스타일별로 실제 필요한 세로 공간. iconDiameter는 axisPicker와 동일한
  // 스케일 getter를 그대로 참조함(같은 파일=라이브러리라 접근 가능).
  static double heightForStyle(int style) {
    final iconD = _TimeAxisPickerState._iconDiameter;
    const safety = 12.0; // 폰트별 줄높이 편차 대비 여유분
    switch (style) {
      case 2: // 말풍선 2단
        return iconD + 4.h + 30.h + iconD / 2 + safety;
      case 3: // 밑줄 강조
        return iconD + 6.h + 26.h + iconD / 2 + safety;
      case 4: // 테두리 카드
      case 5: // 연한 배경 카드
        return iconD + 6.h + 46.h + iconD / 2 + safety;
      case 6: // 통합 카드
        return iconD / 2 + 78.h + iconD / 2 + safety;
      case 7: // 시간 우측 정렬(한 줄)
        return iconD + iconD / 2 + safety;
      case 8: // 미니멀(말풍선 없이)
        return iconD + 6.h + 26.h + iconD / 2 + safety;
      case 1: // 기본
      default:
        return iconD + 6.h + 26.h + iconD / 2 + safety;
    }
  }

  String get _categoryAsset => _kScheduleCategoryIcons[
          block.iconIndex.clamp(0, _kScheduleCategoryIcons.length - 1)]
      .$3;

  Widget _icon(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: block.color, shape: BoxShape.circle),
      padding: EdgeInsets.all(diameter * 0.24),
      child: SvgPicture.asset(
        _categoryAsset,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      ),
    );
  }

  TextStyle _contentStyle({double size = 14, Color? color}) =>
      _contentFontStyle(block.fontIndex,
          fontSize: size.sp, color: color ?? kAppChipBorder);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _buildStyle(context),
    );
  }

  Widget _buildStyle(BuildContext context) {
    switch (block.styleIndex) {
      case 2:
        return _style2BubblePair();
      case 3:
        return _style3Underline();
      case 4:
        return _style4Outlined();
      case 5:
        return _style5SoftCard();
      case 6:
        return _style6UnifiedCard();
      case 7:
        return _style7RightTime();
      case 8:
        return _style8Minimal();
      case 1:
      default:
        return _style1Baseline();
    }
  }

  // ⭐ 아이콘 + 시간 말풍선 한 줄 - 모든 스타일이 공유하는 "첫 줄" 조각.
  // Row.crossAxisAlignment.center에 맡겨두면 텍스트/말풍선이 항상 아이콘
  // 정중앙에 자동으로 맞춰짐(수치 튜닝 불필요).
  Widget _iconAndTimeBubbleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _icon(iconDiameter),
        SizedBox(width: 10.w),
        Flexible(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: block.color,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Text(
              timeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _firstLine() => Transform.translate(
      offset: Offset(0, -iconDiameter / 2), child: _iconAndTimeBubbleRow());

  // ⭐ 스타일 1 - 기본. 시간 말풍선 아래 내용을 그냥 검정 텍스트로.
  Widget _style1Baseline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _firstLine(),
        SizedBox(height: 6.h),
        Padding(
          padding: EdgeInsets.only(left: iconDiameter + 10.w),
          child: Text(block.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _contentStyle()),
        ),
      ],
    );
  }

  // ⭐ 스타일 2 - 말풍선 2단. 시간 말풍선 아래에 더 얇고 더 넓은(오른쪽까지)
  // 말풍선을 하나 더 두고 그 안에 내용(시간보다 작은 글씨)을 담음.
  Widget _style2BubblePair() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _firstLine(),
        SizedBox(height: 4.h),
        Padding(
          padding: EdgeInsets.only(left: iconDiameter + 10.w),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: block.color,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(block.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _contentStyle(size: 12, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  // ⭐ 스타일 3 - 밑줄(왼쪽 세로 바) 강조. 인용구처럼 왼쪽에 색 막대를 세움.
  Widget _style3Underline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _firstLine(),
        SizedBox(height: 6.h),
        Padding(
          padding: EdgeInsets.only(left: iconDiameter + 10.w),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3.w,
                  decoration: BoxDecoration(
                      color: block.color,
                      borderRadius: BorderRadius.circular(2.r)),
                ),
                SizedBox(width: 8.w),
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
      ],
    );
  }

  // ⭐ 스타일 4 - 테두리만 있는 카드(배경 없음, 아이콘 색 테두리).
  Widget _style4Outlined() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _firstLine(),
        SizedBox(height: 6.h),
        Padding(
          padding: EdgeInsets.only(left: iconDiameter + 10.w),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              border: Border.all(color: block.color.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(block.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _contentStyle()),
          ),
        ),
      ],
    );
  }

  // ⭐ 스타일 5 - 연한 배경 카드(아이콘 색의 옅은 틴트로 채움).
  Widget _style5SoftCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _firstLine(),
        SizedBox(height: 6.h),
        Padding(
          padding: EdgeInsets.only(left: iconDiameter + 10.w),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: block.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(block.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _contentStyle()),
          ),
        ),
      ],
    );
  }

  // ⭐ 스타일 6 - 통합 카드. 시간+내용을 하나의 큰(옅은 색) 카드에 함께
  // 담고, 아이콘은 카드 왼쪽 위 모서리에 살짝 걸치듯 배치(뱃지 느낌).
  // 정밀한 세로 여백 계산이 필요한 스타일 - heightForStyle(6)과 반드시
  // 같은 수치(iconD/2 시작, 78.h짜리 카드)를 써야 다음 일정과 안 겹침.
  Widget _style6UnifiedCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(top: iconDiameter / 2),
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.only(left: iconDiameter / 2 + 8.w),
            padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 12.h),
            decoration: BoxDecoration(
              color: block.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: block.color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w800,
                        color: block.color)),
                SizedBox(height: 4.h),
                Text(block.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _contentStyle()),
              ],
            ),
          ),
        ),
        Positioned(top: 0, left: 0, child: _icon(iconDiameter)),
      ],
    );
  }

  // ⭐ 스타일 7 - 시간을 오른쪽 끝의 작은 칩으로 밀어내고, 내용이 첫 줄
  // 전체 너비를 차지함(내용이 주인공, 시간은 보조 정보). 내용이 아래에
  // 따로 있지 않고 이 한 줄로 끝나는 유일한 스타일.
  Widget _style7RightTime() {
    return Transform.translate(
      offset: Offset(0, -iconDiameter / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _icon(iconDiameter),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(block.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _contentStyle(size: 15)),
          ),
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
            decoration: BoxDecoration(
                color: block.color, borderRadius: BorderRadius.circular(999)),
            child: Text(timeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ⭐ 스타일 8 - 미니멀. 말풍선 없이 시간도 그냥 색 텍스트로(더 조용한 느낌).
  Widget _style8Minimal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: Offset(0, -iconDiameter / 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _icon(iconDiameter),
              SizedBox(width: 10.w),
              Text(timeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: block.color)),
            ],
          ),
        ),
        SizedBox(height: 6.h),
        Padding(
          padding: EdgeInsets.only(left: iconDiameter + 10.w),
          child: Text(block.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _contentStyle()),
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

// ⭐ 내용 텍스트 폰트 5종(요청: "한글 폰트 좀 예쁜거 몇개 받아봐, 5개정도") -
// google_fonts 패키지로 런타임에 받아옴(축 숫자에 쓴 Quicksand와 같은 방식).
// 전부 한글을 지원하는 구글 폰트 중 결이 서로 다른 것들로 골랐음: 1은 무난한
// 기본값, 2~5는 손글씨/포스터/펜글씨/동글동글 등 뚜렷하게 다른 인상.
const List<String> _kContentFontNames = [
  '고운돋움',
  '개구쟁이',
  '도현체',
  '나눔펜',
  '주아체',
];

TextStyle _contentFontStyle(
  int fontIndex, {
  required double fontSize,
  FontWeight fontWeight = FontWeight.w500,
  required Color color,
}) {
  switch (fontIndex) {
    case 2:
      return GoogleFonts.gaegu(
          fontSize: fontSize, fontWeight: fontWeight, color: color);
    case 3:
      return GoogleFonts.doHyeon(
          fontSize: fontSize, fontWeight: fontWeight, color: color);
    case 4:
      return GoogleFonts.nanumPenScript(
          fontSize: fontSize, fontWeight: fontWeight, color: color);
    case 5:
      return GoogleFonts.jua(
          fontSize: fontSize, fontWeight: fontWeight, color: color);
    case 1:
    default:
      return GoogleFonts.gowunDodum(
          fontSize: fontSize, fontWeight: fontWeight, color: color);
  }
}

// ⭐ 소요시간 프리셋 - "10분/15분/20분/30분/45분/1시간/2시간/4시간/5시간" 요청.
// 자유 입력 대신 프리셋 칩으로 고른 이유: 어차피 시작 시간도 30분 단위로
// 스냅해서 고르는 화면인데, 종료 시간까지 분 단위로 세밀하게 입력받으면
// 오히려 "축에서 손가락으로 척 찍는" 앞 단계와 결이 안 맞음 - 한 번 더
// 탭하는 것만으로 끝나는 칩이 가장 빠르고, 실제로 교대근무자가 쓸 만한
// 흔한 길이(짧은 휴식~긴 근무 블록)를 그대로 나열한 것도 이 목록의 근거.
const List<int> _kDurationPresets = [10, 15, 20, 30, 45, 60, 120, 240, 300];

String _durationPresetLabel(int minutes) {
  if (minutes < 60) return '$minutes분';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h시간' : '$h시간 $m분';
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
  late int _selectedDuration = widget.existing?.durationMinutes ?? 30;
  // ⭐ 스타일(1~8)/폰트(1~5)/아이콘(0~9) 실험용 선택 - 요청: "번호로 지정할
  // 수 있게 팝업에 해놔줘, 순서대로가 아니라 내가 골라서 테스트하게".
  late int _selectedStyle = widget.existing?.styleIndex ?? 1;
  late int _selectedFont = widget.existing?.fontIndex ?? 1;
  late int _selectedIcon = widget.existing?.iconIndex ?? 0;
  // ⭐ Phase 5(메모_자동분류_ML_계획.md) - 사용자가 아이콘을 직접 고르지 않고
  // 저장하면, 내용 텍스트로 자동분류(MemoCategoryClassifier)해서 아이콘을
  // 대신 골라줌. 기존 일정을 수정할 땐(이미 아이콘이 있었으므로) 다시 자동
  // 배정하지 않고 그 값을 "수동 선택"으로 취급 - 사용자가 실제로 아이콘
  // 칩을 탭하면 그때부터 항상 수동 우선.
  late bool _iconManuallySet = widget.existing != null;
  bool _autoClassifying = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  String _fmt(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // ⭐ 제목이 없어졌으니 이제 "내용"이 유일한 필수 입력.
  bool get _isValid => _contentController.text.trim().isNotEmpty;

  // ⭐ 스타일/폰트 선택용 - 그냥 숫자 원형 칩(1~count). "순서대로 자동
  // 배정"이 아니라 직접 골라서 테스트하기 편하게(요청).
  Widget _numberChips(int count, int selected, ValueChanged<int> onSelect) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (int i = 1; i <= count; i++)
          GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width: 34.w,
              height: 34.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected == i ? kAppMainAccent : const Color(0xFFF4F6FC),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$i',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w800,
                  color: selected == i
                      ? Colors.white
                      : kAppChipBorder.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ⭐ 카테고리 아이콘 선택용 - 실제 아이콘 모양 + 번호(1~10)를 같이 보여줌.
  Widget _iconChips() {
    return Wrap(
      spacing: 10.w,
      runSpacing: 10.h,
      children: [
        for (int i = 0; i < _kScheduleCategoryIcons.length; i++)
          GestureDetector(
            onTap: () => setState(() {
              _selectedIcon = i;
              _iconManuallySet = true;
            }),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: _selectedIcon == i
                        ? kAppMainAccent
                        : const Color(0xFFF4F6FC),
                    shape: BoxShape.circle,
                  ),
                  padding: EdgeInsets.all(10.w),
                  child: SvgPicture.asset(
                    _kScheduleCategoryIcons[i].$3,
                    colorFilter: ColorFilter.mode(
                      _selectedIcon == i
                          ? Colors.white
                          : kAppChipBorder.withValues(alpha: 0.55),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                SizedBox(height: 3.h),
                Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 10.sp,
                        color: kAppChipBorder.withValues(alpha: 0.5))),
              ],
            ),
          ),
      ],
    );
  }

  // ⭐ Phase 5 - 저장 버튼 핸들러. 아이콘을 직접 안 골랐으면(_iconManuallySet
  // false) 내용 텍스트를 MemoCategoryClassifier로 분류해서 그 카테고리의
  // 아이콘 인덱스를 대신 씀. 분류에 실패(모델 로드 전 등)하면 조용히 기본값
  // (0=업무)으로 저장 - 아이콘 자동배정은 편의 기능이라 이것 때문에 저장
  // 자체가 막히면 안 됨.
  Future<void> _handleSave() async {
    var iconIndex = _selectedIcon;
    // ⭐ 재학습용 신호(메모_자동분류_ML_계획.md Phase 5) - 이번에 새로 자동분류
    // 안 했으면(=아이콘을 직접 만졌거나 그냥 다른 필드만 수정) 기존 예측값을
    // 그대로 들고 감. isUserCorrected는 아래에서 "최종 아이콘 != 예측 카테고리"로
    // 계산하므로, 수정 중에 아이콘을 바꾸면 자동으로 "정정함"이 잡힘.
    var predictedCategory = widget.existing?.predictedCategory;
    if (!_iconManuallySet) {
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
    }
    if (!mounted) return;
    final finalCategoryKey =
        _kScheduleCategoryIcons[iconIndex.clamp(0, _kScheduleCategoryIcons.length - 1)].$1;
    Navigator.pop(
      context,
      DateSchedule(
        date: '', // _openCreateSheet/_openEditSheet가 실제 날짜로 덮어씀
        content: _contentController.text.trim(),
        startMinutes: widget.startMinutes,
        durationMinutes: _selectedDuration,
        styleIndex: _selectedStyle,
        fontIndex: _selectedFont,
        iconIndex: iconIndex,
        predictedCategory: predictedCategory,
        isUserCorrected:
            predictedCategory != null && predictedCategory != finalCategoryKey,
        createdAt: '', // 위와 동일 - 호출부가 덮어씀
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final endMinutes =
        (widget.startMinutes + _selectedDuration).clamp(0, 24 * 60);

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
                    Text(
                      '${_fmt(widget.startMinutes)} – ${_fmt(endMinutes)}',
                      style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w800,
                          color: kAppMainAccent),
                    ),
                    SizedBox(width: 8.w),
                    Text('(${_durationPresetLabel(_selectedDuration)})',
                        style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: kAppMainAccent.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              SizedBox(height: 10.h),
              Text('시작 시간 + 얼마나?',
                  style: TextStyle(
                      fontSize: 11.5.sp,
                      color: kAppChipBorder.withValues(alpha: 0.45))),
              SizedBox(height: 8.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
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
              SizedBox(height: 22.h),
              // ⭐ 실험용 - 렌더링 스타일 1~8번 (_ScheduleRow 참고).
              Text('스타일 (1~8, 실험용)',
                  style: TextStyle(
                      fontSize: 11.5.sp,
                      color: kAppChipBorder.withValues(alpha: 0.45))),
              SizedBox(height: 8.h),
              _numberChips(
                  8, _selectedStyle, (v) => setState(() => _selectedStyle = v)),
              SizedBox(height: 18.h),
              // ⭐ 실험용 - 내용 텍스트 폰트 1~5번.
              Text('글씨체 (1~5, 실험용)',
                  style: TextStyle(
                      fontSize: 11.5.sp,
                      color: kAppChipBorder.withValues(alpha: 0.45))),
              SizedBox(height: 8.h),
              _numberChips(
                  5, _selectedFont, (v) => setState(() => _selectedFont = v)),
              SizedBox(height: 4.h),
              Text(
                '$_selectedFont번: ${_kContentFontNames[_selectedFont - 1]} - ${_contentController.text.isEmpty ? "미리보기 텍스트" : _contentController.text}',
                style: _contentFontStyle(_selectedFont,
                    fontSize: 14.sp, color: kAppChipBorder),
              ),
              SizedBox(height: 18.h),
              // ⭐ 카테고리 아이콘 - 지금 색칠된 원 자리에 이 아이콘이 흰색으로
              // 들어감(요청).
              // ⭐ Phase 5 - 아이콘을 직접 안 고르면 내용으로 자동 판단해서
              // 붙여줌(고르면 항상 그 선택이 우선).
              Text(
                _iconManuallySet ? '아이콘' : '아이콘 (직접 안 고르면 내용으로 자동 판단해요)',
                style: TextStyle(
                    fontSize: 11.5.sp,
                    color: kAppChipBorder.withValues(alpha: 0.45)),
              ),
              SizedBox(height: 8.h),
              _iconChips(),
              SizedBox(height: 28.h),
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
