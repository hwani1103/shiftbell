// lib/screens/calendar_theme_picker_screen.dart
//
// ⭐ 설정 탭 "달력 테마" 진입점 - 실제 테마를 고르는 화면. 카드게임 같은
// 가운데-확대 원근감 캐러셀로 9개 테마를 좌우 스와이프하며 훑어봄.
//
// ⭐ 미리보기는 "그냥 이미지처럼" 보여주면 된다는 요청대로 반응형 상호작용은
// 다 꺼두지만(IgnorePointer), 실제 그림 자체는 새로 그리지 않고
// CalendarThemeLabScreen(=calendar_theme_lab_screen.dart, 9개 테마를 이미
// 전부 구현해둔 그 화면)을 initialPage로 원하는 테마에 바로 진입시켜서 그대로
// 재사용함 - "코드를 가져다 써, 새로 만들지 마라"는 원칙 그대로 지킴.
// FittedBox로 실제 기기 크기 그대로 그려진 화면을 카드 크기에 맞게 축소해서
// 보여주는 방식이라(레이아웃을 다시 계산하는 게 아니라 그린 결과를 그대로
// 축소) 실제 앱에서 보이는 모습과 100% 동일함.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/calendar_theme.dart';
import '../models/shift_schedule.dart';
import '../providers/calendar_theme_provider.dart';
import '../providers/schedule_provider.dart';
import 'calendar_theme_lab_screen.dart';

class CalendarThemePickerScreen extends ConsumerStatefulWidget {
  // ⭐ "테마로 적용 누르면 바로 메인 달력탭으로 넘어가게" 요청 - 이 화면은
  // SettingsTab(MainScreen의 탭 중 하나)에서 push된 것이라, 적용 직후 그냥
  // pop만 하면 다시 설정 탭으로 돌아갈 뿐임. SettingsTab이 이미 갖고 있는
  // "달력 탭으로 이동" 콜백(다른 기능에서도 쓰던 것)을 그대로 받아서 적용
  // 직후 호출함 - MainScreen에 새 이동 로직을 만들지 않고 기존 걸 재사용.
  final VoidCallback? onApplied;
  const CalendarThemePickerScreen({super.key, this.onApplied});

  @override
  ConsumerState<CalendarThemePickerScreen> createState() => _CalendarThemePickerScreenState();
}

class _CalendarThemePickerScreenState extends ConsumerState<CalendarThemePickerScreen> {
  // ⭐ viewportFraction < 1이라 좌우 카드가 살짝 보임 - 그 여백에 AnimatedBuilder로
  // 스케일/높이를 계산해서 "가운데 크게, 양옆 작고 살짝 위로 뜬" 원근감을 냄.
  late final PageController _pageController;
  late int _previewIndex;

  @override
  void initState() {
    super.initState();
    final current = ref.read(calendarThemeProvider);
    _previewIndex = kAllCalendarThemeIds.indexOf(current);
    _pageController = PageController(viewportFraction: 0.62, initialPage: _previewIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(calendarThemeProvider);
    final deviceSize = MediaQuery.sizeOf(context);

    return Scaffold(
      appBar: AppBar(title: Text('달력 테마', style: TextStyle(fontSize: 18.sp))),
      // ⭐ "적용 버튼이 SafeArea를 안 받아서 제스처 네비게이션 바에 가깝다"는
      // 피드백 - body 전체를 SafeArea로 감싸서 하단 버튼이 항상 안전영역
      // 안쪽에 오게 함.
      body: SafeArea(
        child: Column(
        children: [
          SizedBox(height: 12.h),
          Text(
            kAllCalendarThemeIds[_previewIndex].label,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4.h),
          Text(
            '좌우로 넘겨서 골라보세요',
            style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: kAllCalendarThemeIds.length,
              onPageChanged: (i) => setState(() => _previewIndex = i),
              itemBuilder: (context, index) {
                return AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    // ⭐ 현재 페이지와의 거리로 원근감 계산 - 아직 컨트롤러가
                    // 레이아웃 전이면(page가 null) initialPage 기준으로 계산.
                    double page = _pageController.hasClients && _pageController.page != null
                        ? _pageController.page!
                        : _pageController.initialPage.toDouble();
                    final distance = (page - index).clamp(-1.0, 1.0).abs();
                    final scale = 1.0 - distance * 0.22; // 가운데 1.0 → 양옆 0.78
                    final lift = distance * 26.h; // 양옆일수록 아래로(=가운데가 위로 뜸)
                    return Transform.translate(
                      offset: Offset(0, lift),
                      child: Transform.scale(scale: scale, child: child),
                    );
                  },
                  child: _themeCard(index, deviceSize, isSelected: kAllCalendarThemeIds[index] == selected),
                );
              },
            ),
          ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 20.h),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final themeId = kAllCalendarThemeIds[_previewIndex];
                  await ref.read(calendarThemeProvider.notifier).setTheme(themeId);
                  // ⭐ 위젯(Native)은 여전히 DB의 shift_colors 컬럼을 직접 읽으므로
                  // (android/.../CalendarWidgetScheduleResolver.kt - 이 부분은 아직
                  // 안 건드림, 네이티브 쪽까지 테마별로 다시 그리는 건 후속 작업),
                  // 테마를 바꿀 때마다 새 팔레트로 계산한 색을 그 컬럼에도 그대로
                  // 다시 써줘서 위젯과 실제 앱이 서로 다른 색을 보여주는 걸 막음.
                  // updateSchedule()이 이미 DB 저장 + 위젯 갱신 신호까지 다 해주는
                  // 기존 경로라 그대로 재사용함.
                  final schedule = ref.read(scheduleProvider).value;
                  if (schedule != null) {
                    // ⭐ 테마별 전용 팔레트/로테이션(assignShiftColorsForTheme)을
                    // 위젯 캐시에도 동일하게 반영 - 라이트/다크 두 팔레트만 있던
                    // 시절의 assignShiftColors(isDark:)를 그대로 쓰면 위젯이
                    // 실제 앱과 다른(구버전) 색을 보여주게 됨.
                    final newColors = assignShiftColorsForTheme(schedule.shiftTypes, themeId)
                        .map((name, color) => MapEntry(name, color.value));
                    await ref.read(scheduleProvider.notifier).updateSchedule(ShiftSchedule(
                      id: schedule.id,
                      isRegular: schedule.isRegular,
                      pattern: schedule.pattern,
                      todayIndex: schedule.todayIndex,
                      shiftTypes: schedule.shiftTypes,
                      activeShiftTypes: schedule.activeShiftTypes,
                      startDate: schedule.startDate,
                      shiftColors: newColors,
                      assignedDates: schedule.assignedDates,
                      shiftDurations: schedule.shiftDurations,
                    ));
                  }
                  if (!context.mounted) return;
                  // ⭐ "적용 누르면 바로 메인 달력탭으로 넘어가게" 요청 - 스낵바로
                  // 안내만 하고 이 화면에 계속 머무르는 대신, 설정 화면까지
                  // 통째로 pop한 뒤 곧장 달력 탭으로 전환함.
                  Navigator.pop(context);
                  widget.onApplied?.call();
                },
                style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                child: Text(
                  kAllCalendarThemeIds[_previewIndex] == selected ? '현재 적용된 테마' : '이 테마로 적용',
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _themeCard(int index, Size deviceSize, {required bool isSelected}) {
    // ⭐ "밑에 반투명 회색 여백이 30%나 남고, 위쪽은 오히려 radius가 짤린다"는
    // 재재지적 - 진짜 원인을 찾음: 이 카드는 PageView.builder의 itemBuilder
    // 안에서 만들어지는데, PageView는 자기 자식(각 페이지)에게 가로·세로 둘 다
    // "고정된(tight)" 크기를 강제로 줌. AspectRatio는 부모가 "여유 있는(loose)"
    // 크기를 줄 때만 원하는 비율로 스스로 크기를 정할 수 있는 위젯이라, 이렇게
    // 양쪽 다 고정된 상황에서는 aspectRatio 값 자체가 완전히 무시되고 그냥
    // PageView가 준 크기(=카드 세로 여백까지 포함한 페이지 전체 높이)를 그대로
    // 씀 - 그래서 계산한 비율이 아무리 정확해도 카드 자체가 계속 페이지 높이
    // 만큼 늘어나 있었던 것(내용은 정확한 비율로 차 있고, 그 아래 남는 만큼이
    // 통째로 빈 배경으로 보였음). 고쳐야 할 건 계산식이 아니라 "AspectRatio가
    // 실제로 적용되게 만드는 것" - Center로 한 번 감싸서 AspectRatio에게
    // loose 제약을 주면, 그제서야 진짜로 지정한 비율만큼만 스스로 크기를
    // 정하고 나머지 남는 세로 공간은 카드 밖(위/아래 여백)으로 자연스럽게 빠짐.
    final navBarHeight = kBottomNavigationBarHeight + MediaQuery.paddingOf(context).bottom;
    final bodyHeight = deviceSize.height - navBarHeight;
    // ⭐ "달력 이미지가 카드 테두리의 border radius를 침범한다"는 지적 -
    // 내용이 카드의 진짜 사각형 경계에 완전히 딱 붙어서 그려지면, 둥근 모서리
    // clip이 그 위에 그대로 걸쳐서 네 귀퉁이가 살짝 잘려 보임(사진을 둥근
    // 카드에 여백 없이 꽉 채울 때 흔한 현상). "달력 크기는 유지하고 테두리를
    // 더 크게" 요청대로 - 내용(달력) 크기는 그대로 두고, 카드 자체를 사방으로
    // buffer만큼 더 크게 잡아서 내용과 카드 테두리 사이에 여백을 둠 - 이제
    // 어느 모서리도 둥근 테두리가 내용을 침범하지 않음.
    final bufferW = 8.w;
    final bufferH = 10.h;
    final cardWidth = deviceSize.width + bufferW * 2;
    final cardHeight = bodyHeight + bufferH * 2;
    final aspectRatio = cardWidth / cardHeight;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
          // ⭐ 선택 표시는 우측 상단 체크 배지 대신(테마마다 헤더 버튼이 하필
          // 그 자리에 있어서 겹쳐 가려지는 문제가 있었음) 카드 테두리 색/두께
          // 차이 + 아래 "현재 적용된 테마" 버튼 문구만으로 충분히 구분되므로
          // 배지 자체를 없앰 - 어떤 테마 헤더 디자인과도 절대 안 겹침.
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: bufferW, vertical: bufferH),
            child: IgnorePointer(
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: deviceSize.width,
                  height: bodyHeight,
                  child: CalendarThemeLabScreen(initialPage: index),
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}
