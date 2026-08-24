import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../models/shift_schedule.dart';
import '../models/calendar_theme.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../services/update_service.dart';
import '../models/alarm.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../main.dart';  // ⭐ MainScreen import
import '../constants/alarm_limits.dart';
import '../constants/shift_name_limits.dart';
import '../utils/shift_name_util.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shift_chip.dart';
import '../widgets/word_safe_spans.dart';
import '../widgets/app_button.dart';

// 알람 설정 (시간 + 타입)
class AlarmSetting {
  final TimeOfDay time;
  final int alarmTypeId;  // 1: 소리+진동, 2: 진동, 3: 무음

  AlarmSetting({required this.time, this.alarmTypeId = 1});

  AlarmSetting copyWith({TimeOfDay? time, int? alarmTypeId}) {
    return AlarmSetting(
      time: time ?? this.time,
      alarmTypeId: alarmTypeId ?? this.alarmTypeId,
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {  // ⭐ 변경
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();  // ⭐ 변경
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {  // ⭐ 변경
  // ⭐ 커스텀 근무 형태 최대 개수(예전엔 리터럴 7이 여러 곳에 흩어져 있었음).
  static const int _maxCustomShiftTypes = 7;

  int _step = 0;
  // ⭐ 2026-08-24 - 예전엔 "고정적으로 순환하는 교대 근무인가요?" 선택 화면에서
  // 사용자가 예/아니오를 고르기 전까지 null(미정)이었음. 그 선택 화면을 없애고
  // "규칙적" 분기를 새 첫 화면으로 승격하면서, 기본값을 true로 바꿈 - "선택 안
  // 함" 상태가 이제 존재하지 않음. 불규칙 경로는 첫 화면의 "여기" 링크로 진입.
  bool? _isRegular = true;
  List<String> _pattern = [];
  int? _todayIndex;

  List<String> _baseShiftTypes = [];
  bool _baseShiftTypesInitialized = false;
  List<String> _customShiftTypes = [];
  List<String> get _allShiftTypes => [..._baseShiftTypes, ..._customShiftTypes];
  Map<String, List<AlarmSetting>> _shiftAlarms = {};
  List<String> _selectedShifts = [];  // 불규칙용

  // ⭐ 2026-08-24 - _buildShiftTypeCreation()의 "여기" 하이퍼링크(불규칙 전환)용.
  // RichText의 TextSpan.recognizer는 State가 살아있는 동안 재사용해야 하는
  // 객체라 build()마다 새로 만들지 않고 필드로 보관 - dispose()에서 해제함.
  final TapGestureRecognizer _switchToIrregularRecognizer = TapGestureRecognizer();

  List<String> get _uniqueShifts {
    return _pattern.toSet().toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ⭐ 기본 근무 카드(주간/야간/오전/오후/휴무)는 로케일에 맞는 이름으로 딱 한 번만
    // 초기화함 - context가 필요해서 필드 선언 시점(build 이전)엔 만들 수 없음.
    if (!_baseShiftTypesInitialized) {
      _baseShiftTypesInitialized = true;
      _baseShiftTypes = [
        context.l10n.shiftDay,
        context.l10n.shiftNight,
        context.l10n.shiftMorning,
        context.l10n.shiftAfternoon,
        context.l10n.shiftDayOff,
      ];
    }
  }

  @override
  void dispose() {
    _switchToIrregularRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,  // step 0에서만 앱 종료 허용
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        // ⭐ 2026-08-24 - AppTheme.lightTheme.scaffoldBackgroundColor(현재 흰색)와
        // 같은 값을 여기 인스턴스에도 직접 명시함 - 그건 static 필드라 hot
        // reload로는 재평가 안 되므로(hot restart/재실행 때만 초기화), 개발 중
        // 배경 톤을 바꿔가며 확인할 때 여기 명시해두면 build()가 다시 불릴
        // 때마다 항상 최신 값으로 나옴.
        backgroundColor: Colors.white,
        appBar: AppBar(
          // ⭐ 2026-08-24 - title을 Center()로 감쌌던 건 AppBarTheme에
          // centerTitle이 없어서 안드로이드 기본값(false)이 적용되던 시절의
          // 임시방편이었음 - leading 유무에 따라 타이틀 위치가 살짝 어긋나는
          // 문제가 있었음(그 폭만큼 오른쪽으로 치우쳐 보임). 이제
          // app_theme.dart의 AppBarTheme.centerTitle: true가 이걸 제대로
          // 처리하므로(leading 폭과 무관하게 항상 화면 정중앙), 이 Center()는
          // 더 이상 필요 없어 제거함 - 첫 화면(뒤로가기 없음)이든 그 이후
          // 화면(뒤로가기 있음)이든 타이틀이 항상 같은 자리에 옴.
          title: Text(context.l10n.onboardingCreateSchedule),
          leading: _step > 0
              ? IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: _goBack,
                )
              : null,
        ),
        body: SafeArea(
          child: _buildStep(),
        ),
      ),
    );
  }

  // ⭐ 2026-08-24 - "고정적으로 순환하는 교대 근무인가요?" 선택 화면(구 step 0)을
  // 삭제하고, "예-규칙적"을 눌렀을 때 가던 화면(구 step 1의 규칙적 분기,
  // _buildShiftTypeCreation)을 새 첫 화면으로 승격함. 이후 모든 스텝 번호를
  // 1씩 당김(구 1→신 0, 구 2→신 1, ... 구 5→신 4) - _isRegular 기본값도
  // null에서 true로.
  //
  // ⭐ 2026-08-24 재설계 - 불규칙 플로우 단순화. 근무명 지정(step0)은 규칙/불규칙
  // 둘 다 똑같이 거치므로("어차피 불규칙으로 가도 근무명은 똑같이 설정해야
  // 됨"), 둘째 화면("여기" 링크가 있는 _buildPatternInput, step1)에서 바로
  // "근무별 고정 알람을 설정하세요"(_buildMainAlarmSetup, case2의 원래
  // isRegular==false 슬롯)로 건너뛸 수 있게 함 - 옛 불규칙 전용 화면들
  // (_buildShiftTypesInput, _buildSelectShiftsForAlarm)은 삭제함(더 이상 도달할
  // 경로가 없었음).
  //
  // 동작 원리: "여기"를 누르면 isRegular=false + _selectedShifts=모든 근무명 +
  // _step=2를 한 번에 설정함(_buildPatternInput() 참고) - case2가 원래부터
  // isRegular==false일 때 _buildMainAlarmSetup()을 가리키므로 새 분기가 필요
  // 없음. step0/1은 이제 isRegular와 무관하게 화면이 하나뿐이라 삼항을 없앰
  // (이 경로들에서 isRegular가 false가 될 수 없어짐 - 아래 case 주석 참고).
  // 뒤로가기(_goBack())는 "step1로 돌아오면 isRegular를 항상 true로 리셋"
  // 하나의 규칙으로 전부 처리됨 - step2(알람설정, isRegular=false)에서 한 번
  // 뒤로가면 여전히 그 화면을 다시 보여주고(자연스러운 "방금 그 화면"),
  // 거기서 한 번 더 뒤로가야 step1(_buildPatternInput)에 도착하며 그 순간
  // isRegular가 true로 리셋됨 - 근무명은 _allShiftTypes에 계속 그대로
  // 남아있으므로(이 흐름 전체에서 건드리지 않음) 거기서 다시 규칙적 패턴을
  // 이어서 만들 수도 있음.
  Widget _buildStep() {
    switch (_step) {
      case 0:
        // ⭐ step0에서 isRegular가 false일 수 있는 경로가 이제 없음("여기"는
        // step1에서만 누를 수 있고, 그 즉시 step2로 건너뜀 - 아래 _buildStep()
        // 클래스 주석과 _goBack() 참고) - 삼항 없이 이 화면 하나만.
        return _buildShiftTypeCreation();
      case 1:
        // ⭐ 같은 이유로 step1도 isRegular와 무관하게 항상 이 화면 하나 -
        // "여기"를 누르면 step이 곧장 2로 바뀌므로 step1에 머무른 채
        // isRegular만 false가 되는 경우가 없음.
        return _buildPatternInput();
      case 2:
        return _isRegular == true ? _buildTodayIndexInput() : _buildMainAlarmSetup();
      case 3:
        return _isRegular == true ? _buildMainAlarmSetup() : _buildComplete();
      case 4:
        return _buildComplete();
      default:
        return Container();
    }
  }

  // ⭐ 2026-08-24 - 뒤로가기 공통 처리(PopScope + AppBar 아이콘 둘 다 이걸 씀).
  // step1(_buildPatternInput)로 "돌아오는" 모든 경로에서 isRegular를 true로
  // 리셋함 - step1은 이제 항상 규칙적 화면 하나뿐이라, 거기 서 있는 동안은
  // 항상 "다시 규칙 패턴을 이어 만들 수 있는" 상태여야 함(사용자 요구사항:
  // "여기를 눌러 알람설정까지 갔다가 뒤로 나오면 다시 규칙 패턴으로 갈 수도
  // 있어야 한다"). 그 뒤(step2/3)에서 알람설정 화면을 보고 있었다면(isRegular
  // false) 그것도 이 리셋 한 번으로 자연스럽게 해소됨 - step2로 뒤로가면
  // 여전히 isRegular==false라 case2가 알람설정 화면을 다시 보여주고(맞는
  // 동작), 거기서 한 번 더 뒤로가면 step1에 도착하는 이 시점에 비로소 true로
  // 리셋됨.
  void _goBack() {
    if (_step == 0) return;
    setState(() {
      _step--;
      if (_step == 1) _isRegular = true;
    });
  }

  // ⭐ 2026-08-24 - 온보딩 새 첫 화면(구 step1 규칙적 분기가 승격됨). 텍스트/칩
  // 디자인/레이아웃을 전면 개편함:
  // - 문구를 "내 교대 패턴에 해당되는 근무명 지정" + 부연설명 2줄 + "여기" 링크로
  //   교체(onboardingShiftNameTitle/SubHint/SwitchToIrregular* - app_ko.arb 참고).
  //   기존 글자수 제한 안내(onboardingShiftLimitHint)는 이 화면에서 더 이상
  //   보여주지 않음 - _showAddCustomDialog()의 입력창 자체에 maxLength가 걸려
  //   있어 실제 제약은 그대로 유지됨.
  // - 근무명 태그를 ElevatedButton 대신 AppShiftChip으로 교체(app_shift_chip.dart) -
  //   버튼과 시각적으로 구분되는 별도 디자인.
  // - 레이아웃을 _buildPatternInput()과 동일한 구조(Expanded로 남는 공간을
  //   스크롤 영역에 주고, "다음" 버튼은 그 아래 고정)로 바꿔서, 칩 개수가
  //   적을 때도 "다음" 버튼이 항상 화면 맨 아래(다른 온보딩 화면과 같은 위치)에
  //   오도록 함 - 예전엔 SingleChildScrollView 하나로 전체를 감싸서 콘텐츠
  //   양에 따라 버튼 위치가 위아래로 들쭉날쭉했음.
  Widget _buildShiftTypeCreation() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.onboardingShiftNameTitle,
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6.h),
          // ⭐ 2026-08-24 - "근무별 고정 알람을 설정하세요" 화면(_buildMainAlarmSetup)의
          // 부연설명과 스타일을 맞춤(14.sp, onSurface, 굵기 없음 - 예전엔 13.sp에
          // onSurfaceVariant라 서로 색·굵기가 달랐음) + 괄호 제거(그쪽 화면은
          // 원래 괄호 없이 더 잘 보였음). wordSafeSpans()로 단어(공백 기준) 중간에서
          // 줄바꿈되는 걸 막음 - "있습니다"가 "있습니\n다"처럼 잘리던 문제 수정.
          Text.rich(
            TextSpan(
              children: wordSafeSpans(
                context.l10n.onboardingShiftNameSubHint,
                TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
          // ⭐ 2026-08-24 - "만약 규칙적이지 않다면 여기를 눌러주세요" 링크는
          // 둘째 화면(_buildPatternInput, "버튼을 탭해서 패턴을 완성해주세요")
          // 으로 옮김 - 불규칙 플로우도 근무명 지정은 똑같이 거쳐야 하니, "패턴이
          // 있는지" 판단하는 맥락(둘째 화면)에서 물어보는 게 더 자연스러움.
          SizedBox(height: 24.h),

          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  ..._allShiftTypes.map((name) {
                    // ⭐ 기본 카드(주간/야간/오전/오후/휴무)도 커스텀 카드와 동일하게
                    // 삭제 가능하도록 X 버튼을 항상 표시함 (예전엔 커스텀 카드만 가능했음).
                    return AppShiftChip(
                      label: name,
                      onDelete: () => _deleteShiftType(name),
                    );
                  }),

                  // ⭐ 2026-08-24 - 공용 버튼(AppButton)으로 다시 교체. 예전엔
                  // Wrap 안에서 가로를 다 차지해버리는 버그가 있었는데(Container의
                  // alignment가 루즈 제약에서도 최대 폭까지 확장해버리는 성질
                  // 때문 - app_button.dart 클래스 주석 참고), 그 위젯 내부 구조를
                  // 고쳐서 이제 SizedBox로 감싸지 않으면 내용물 크기만큼만 차지함 -
                  // 지금처럼 Wrap 안에 그냥 놓으면 원래 크기 그대로 나옴.
                  AppButton(
                    onPressed: _customShiftTypes.length < _maxCustomShiftTypes ? _showAddCustomDialog : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 16.sp),
                        SizedBox(width: 0.3.w),
                        Text(context.l10n.commonAdd),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // ⭐ 2026-08-24 - 이 버튼만 로컬로 키웠던 걸 되돌림("너무 크다" +
          // 전환 시 순간적으로 bottom overflow가 뜨던 원인이었던 것으로 보임 -
          // 이 화면은 이미 제목+부연설명+칩 영역+버튼으로 꽉 찬 구조라 버튼이
          // 커진 만큼 남는 공간을 넘어섰던 것). 버튼 글자 크기는 화면마다 따로
          // 손대지 않고 app_theme.dart의 공통 ElevatedButtonTheme 하나로만
          // 관리함 - 다른 "다음" 버튼들과 동일하게 스타일 없이 기본값을 씀.
          SizedBox(
            width: double.infinity,
            child: AppButton(
              onPressed: () {
                setState(() => _step = 1);
              },
              child: Text(context.l10n.commonNext),
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 2026-08-24 - _buildShiftTypesInput()(불규칙용 근무명 지정 화면 복제본)과
  // _buildSelectShiftsForAlarm()(불규칙용 "실제 사용할 근무 선택" 화면)을
  // 삭제함 - _buildStep()을 "여기" 지름길 방식으로 재설계하면서 이 두 화면에
  // 도달하는 경로 자체가 완전히 사라짐(_isRegular가 false가 되는 시점이
  // _step==1일 때뿐이라, _step==0이나 옛 case1의 그 위치에서 false가 되는
  // 경우가 구조적으로 없음 - _buildStep()의 클래스 주석 참고). 근무명 지정은
  // 이제 규칙/불규칙 상관없이 _buildShiftTypeCreation() 하나로 통일됨.
  Widget _buildPatternInput() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.onboardingTapToCompletePattern,
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6.h),
          // ⭐ 2026-08-24 - "여기" 링크: 불규칙 플로우 단순화. 규칙/불규칙 둘 다
          // 근무명 지정(_buildShiftTypeCreation)은 이미 동일하게 거쳤으므로,
          // 여기서 누르면 그 근무명들(_allShiftTypes)을 그대로 _selectedShifts에
          // 담아 step을 2로 바로 건너뛰어 "근무별 고정 알람을 설정하세요"
          // 화면으로 감(그 자리는 원래부터 불규칙용 슬롯이었음 - case2의
          // isRegular==false 분기, 손 안 댐). _shiftAlarms는 일부러 안 지움 -
          // "여기"를 눌렀다 뒤로 갔다를 반복해도 이미 설정한 알람이 안 사라지게.
          // 뒤로가기 시 step1로 돌아오면 _goBack()이 isRegular를 다시 true로
          // 되돌려 이 화면(패턴 입력)을 보여줌 - 거기서 다시 규칙 패턴을
          // 이어 만들 수도 있음.
          Text.rich(
            TextSpan(
              children: [
                ...wordSafeSpans(
                  context.l10n.onboardingSwitchToIrregularPrefix,
                  TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface),
                ),
                TextSpan(
                  text: context.l10n.onboardingSwitchToIrregularLink,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: kAppMainAccent,
                    decoration: TextDecoration.underline,
                    decorationColor: kAppMainAccent,
                  ),
                  recognizer: (_switchToIrregularRecognizer
                    ..onTap = () {
                      setState(() {
                        _isRegular = false;
                        _selectedShifts = List.from(_allShiftTypes);
                        _step = 2;
                      });
                    }),
                ),
                ...wordSafeSpans(
                  context.l10n.onboardingSwitchToIrregularSuffix,
                  TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),

          // ⭐ 2026-08-24 - 근무명 지정 화면(_buildShiftTypeCreation)과 같은
          // 칩 디자인으로 통일. 아래 완성된 패턴을 보여주는 그리드
          // (_buildPatternGrid)는 이번 범위 아님 - 그대로 둠.
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: _allShiftTypes.map((name) => AppShiftChip(
              label: name,
              enabled: _pattern.length < 40,
              onTap: () => _addToPattern(name),
            )).toList(),
          ),

          SizedBox(height: 16.h),

          Text(
            context.l10n.onboardingPatternHint,
            style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: 8.h),
          
          Expanded(
            child: _buildPatternGrid(isSelectable: false),
          ),
          
          SizedBox(height: 16.h),
          
          SizedBox(
            width: double.infinity,
            child: AppButton(
              onPressed: _pattern.isEmpty ? null : () {
                setState(() => _step = 2);
              },
              child: Text(context.l10n.commonNext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternGrid({required bool isSelectable}) {
  if (_pattern.isEmpty) {
    return Center(
      child: Text(
        context.l10n.onboardingNoPattern,
        style: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  return GridView.builder(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 6,  // ⭐ 6열 고정
      crossAxisSpacing: 6.w,  // ⭐ 간격 살짝 줄임 (8.w → 6.w)
      mainAxisSpacing: 6.h,   // ⭐ 간격 살짝 줄임 (8.h → 6.h)
      childAspectRatio: 1.0, // ⭐ 거의 정사각형 (0.85 → 0.95)
    ),
    itemCount: _pattern.length,
    itemBuilder: (context, index) {
      final isSelected = isSelectable && _todayIndex == index;

      // ⭐ 2026-08-24 - "탭했을 때 반응이 잘 안 느껴진다"는 피드백으로 splash/
      // highlight 색을 명시하고, Container의 radius(8.r)와 맞춘 borderRadius를
      // InkWell에도 지정함(예전엔 없어서 리플이 각진 사각형으로 어긋나 보였음).
      return InkWell(
        borderRadius: BorderRadius.circular(8.r),
        splashColor: kAppMainAccent.withValues(alpha: 0.25),
        highlightColor: kAppMainAccent.withValues(alpha: 0.15),
        onTap: isSelectable
            ? () {
                setState(() => _todayIndex = index);
              }
            : () {
                _removeFromPattern(index);
              },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.outline,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 4.w, top: 2.h),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 9.sp,  // ⭐ 번호도 살짝 축소 (10.sp → 9.sp)
                      color: isSelected ? Theme.of(context).colorScheme.onSecondary.withOpacity(0.7) : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

              Expanded(
                child: Center(
                  child: Text(
                    _pattern[index],
                    style: TextStyle(
                      fontSize: 11.sp,  // ⭐ 근무명 축소 (14.sp → 12.sp)
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Theme.of(context).colorScheme.onSecondary : Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,  // ⭐ 1줄 강제
                    overflow: TextOverflow.ellipsis,  // ⭐ 넘치면 ... 처리
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  // ⭐ 기본 카드(주간/야간/오전/오후/휴무)도 커스텀 카드와 동일하게 삭제 가능하도록
  // 일반화함. 카드가 0개가 되면 다음 단계(패턴 구성/근무 선택) 자체가 불가능해지므로
  // 최소 1개는 남기게 막음. 이 단계는 패턴 구성 전이라 보통 _pattern이 비어있지만,
  // 혹시 몰라 방어적으로 같이 정리함.
  void _deleteShiftType(String name) {
    if (_allShiftTypes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.onboardingNeedAtLeastOneShift)),
      );
      return;
    }
    setState(() {
      _baseShiftTypes.remove(name);
      _customShiftTypes.remove(name);
      _pattern.removeWhere((shift) => shift == name);
      _selectedShifts.remove(name);
    });
  }

  void _showAddCustomDialog() {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.onboardingAddShiftName),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLength: kMaxShiftNameLength,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.onboardingShiftNameHint(kMaxShiftNameLength),
              counterText: '',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.onboardingEnterShiftName)),
                );
                return;
              }
              if (text.length > kMaxShiftNameLength) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.onboardingCharLimitError(kMaxShiftNameLength))),
                );
                return;
              }
              if (_allShiftTypes.contains(text)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.onboardingDuplicateShiftName)),
                );
                return;
              }

              setState(() {
                _customShiftTypes.add(text);
              });
              Navigator.pop(context);
            },
            child: Text(context.l10n.commonAdd),
          ),
        ],
      ),
    );
  }

  void _addToPattern(String shift) {
    if (_pattern.length < 40) {
      setState(() => _pattern.add(shift));
    }
  }

  void _removeFromPattern(int index) {
    setState(() {
      _pattern.removeAt(index);
    });
  }

  Widget _buildMainAlarmSetup() {
  // ⭐ CRITICAL FIX: 패턴에 실제로 쓰인 근무(_uniqueShifts)만이 아니라 만들어둔 모든
  // 카드(_allShiftTypes)에 대해 알람을 설정할 수 있게 함 - 패턴엔 없어도(예: 오전/오후)
  // 나중에 달력에서 그날만 근무 변경할 때 알람이 바로 적용되려면 여기서 미리 설정
  // 가능해야 함.
  final shiftsToSetup = _isRegular == true ? _allShiftTypes : _selectedShifts;
  
  return Padding(
    padding: EdgeInsets.all(24.w),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.onboardingSetFixedAlarmPerShift,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
        ),
        // ⭐ 2026-08-24 - 근무명 지정 화면(_buildShiftTypeCreation)의 부연설명을
        // 이 화면 스타일에 맞추면서 같이 적용한 wordSafeSpans()를 여기도 동일하게
        // 적용 - 이 화면이 스타일 기준이 됐으니 줄바꿈 안전성도 같이 맞춤.
        Text.rich(
          TextSpan(
            children: wordSafeSpans(
              context.l10n.onboardingMaxAlarmsPerShift(kMaxAlarmTemplatesPerShift),
              TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ),
        Text.rich(
          TextSpan(
            children: wordSafeSpans(
              context.l10n.onboardingCanChangeInSettings,
              TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ),
        SizedBox(height: 24.h),
        
        Expanded(
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120.w,
              crossAxisSpacing: 12.w,
              mainAxisSpacing: 12.h,
              childAspectRatio: 0.70,
            ),
            itemCount: shiftsToSetup.length,
            itemBuilder: (context, index) {
              final shift = shiftsToSetup[index];
              final alarms = _shiftAlarms[shift] ?? [];

              return _buildShiftAlarmCard(shift, alarms);
            },
          ),
        ),
        
        SizedBox(height: 16.h),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            onPressed: () {
              // ⭐ 2026-08-24 - 스텝 재번호(구 5→신4, 구4→신3) 때 이 삼항식 안의
              // 값들을 놓쳤던 버그 수정. _buildStep()의 case 검색 정규식이
              // "_step = <숫자>" 형태만 잡았는데 이 줄은 "_step = 조건 ? 5 : 4"라
              // 안 걸렸음 - 그 결과 규칙적 플로우는 존재하지 않는 case 5로
              // 가서 default(빈 Container)가 뜨고, 뒤로가기로 step4(완료 화면)에
              // 도착해야 보이는 것처럼 보였던 것. 같은 함수(_buildMainAlarmSetup)를
              // 규칙적(새 step3)/불규칙(새 step2) 양쪽이 공유해서 다음 스텝이
              // 서로 다름 - 규칙적은 새 step4(_buildComplete 고정), 불규칙은
              // 새 step3(case3의 삼항이 false일 때 _buildComplete).
              setState(() => _step = _isRegular == true ? 4 : 3);
            },
            child: Text(context.l10n.commonNext),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildShiftAlarmCard(String shift, List<AlarmSetting> alarms) {
    return InkWell(
      onTap: () => _showAlarmTimeDialog(shift),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: alarms.isEmpty ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurface,
            width: 2,
          ),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          children: [
            Text(
              shift,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 12.h),

            Expanded(
              // ⭐ 근무당 알람이 kMaxAlarmTemplatesPerShift(5)개까지 늘어나면서 이
              // 카드는 GridView 셀이라 높이가 고정인데 Center+Column(비스크롤)이라
              // 4~5개부턴 세로로 넘쳐서 렌더 오류가 났음(RenderFlex overflowed) -
              // 스크롤 가능하게 바꿔서 몇 개든 안전하게 다 보이게 함.
              child: alarms.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.onboardingTapToSet,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: alarms.map((alarm) => Padding(
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getAlarmTypeEmoji(alarm.alarmTypeId),
                                style: TextStyle(fontSize: 12.sp),
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                _formatTime(alarm.time),
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getAlarmTypeEmoji(int alarmTypeId) {
    switch (alarmTypeId) {
      case 1: return '🔔';  // 소리+진동
      case 2: return '📳';  // 진동
      case 3: return '🔇';  // 무음
      default: return '🔔';
    }
  }

  void _showAlarmTimeDialog(String shift) {
    showDialog(
      context: context,
      builder: (context) => _AlarmTimeDialog(
        shift: shift,
        initialAlarms: _shiftAlarms[shift] ?? [],
        onSave: (alarms) {
          setState(() {
            _shiftAlarms[shift] = alarms;
          });
        },
      ),
    );
  }

  Widget _buildTodayIndexInput() {
    final today = DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    final dateText = DateFormat.MMMd(locale).format(today);

    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.onboardingTodayShiftQuestion(dateText),
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          
          Expanded(
            child: _buildPatternGrid(isSelectable: true),
          ),
          
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              onPressed: _todayIndex == null ? null : () {
                setState(() => _step = 3);
              },
              child: Text(context.l10n.commonNext),
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 2026-08-24 - "시작하기" 버튼을 다른 온보딩 화면들과 같은 위치(화면 맨 아래)로
  // 옮김 - 예전엔 아이콘+텍스트와 한 그룹으로 화면 중앙에 같이 떠 있었음. 아이콘+
  // 제목은 Expanded+Center로 남는 공간 안에서 계속 중앙 정렬되고, 버튼만 그 아래
  // 고정됨(다른 화면들의 Expanded 스크롤영역 + 하단 고정 버튼 구조와 동일).
  Widget _buildComplete() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 100.sp, color: Colors.green),
                  SizedBox(height: 24.h),
                  Text(
                    context.l10n.onboardingAllSet,
                    style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              onPressed: _saveAndFinish,
              child: Text(context.l10n.commonGetStarted),
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 근무명 색상 생성 - 2026-08-19부터 "근무명 색상 변경" 기능 복원과 함께
  // 온보딩 전용 파스텔 팔레트 계산(패턴 등장 순서 기반)을 버리고, 실제 화면
  // (calendar_tab.dart)이 쓰는 것과 동일한 effectiveShiftColors()로 통일함 - 그래야
  // 온보딩 직후 위젯/전체근무표(shiftColors 캐시를 읽는 쪽)가 실제 달력 탭과 같은
  // 색을 보여줌(온보딩 시점엔 아직 사용자가 색을 하나도 지정 안 했으니
  // customColors는 없음 - 그래서 결과는 곧 kDefaultCalendarThemeId 디폴트 그대로).
  // 순서는 shiftTypes(=_allShiftTypes, 아래서 그대로 넘김) 기준 - calendar_tab.dart도
  // 항상 이 순서로 계산하므로 이렇게 맞춰야 이후 색이 안 어긋남.
  Map<String, int> _generateShiftColors() {
    return effectiveShiftColors(_allShiftTypes, kDefaultCalendarThemeId, null)
        .map((name, color) => MapEntry(name, color.value));
  }

Future<void> _saveAlarmTemplates() async {
  for (var entry in _shiftAlarms.entries) {
    final shift = entry.key;
    final alarms = entry.value;

    for (var alarm in alarms) {
      await DatabaseService.instance.insertAlarmTemplate(
        shiftType: shift,
        time: _formatTime(alarm.time),
        alarmTypeId: alarm.alarmTypeId,  // 사용자가 선택한 타입
      );
    }
  }

  print('✅ 알람 템플릿 저장 완료');
}

 // onboarding_screen.dart의 _saveAndFinish() 수정

// onboarding_screen.dart - _saveAndFinish()
Future<void> _saveAndFinish() async {
  final shiftColors = _generateShiftColors();
  
  List<String> activeShifts;
  if (_isRegular!) {
    activeShifts = _pattern.toSet().toList();
  } else {
    activeShifts = _selectedShifts;
  }
  
  final schedule = ShiftSchedule(
    isRegular: _isRegular!,
    pattern: _isRegular! ? _pattern : null,
    todayIndex: _todayIndex,
    shiftTypes: _allShiftTypes,
    activeShiftTypes: activeShifts,
    startDate: DateTime.now(),
    shiftColors: shiftColors,
  );

  await ref.read(scheduleProvider.notifier).saveSchedule(schedule);
  await _saveAlarmTemplates();

  // ⭐ 기존 알람 전체 삭제 (Native + DB)
  // ⭐ CRITICAL FIX: 예전엔 cancelAlarm 하나만 실패해도(권한 문제 등) 예외가 전체를
  // 끊고 나가서, 그 아래 deleteAllAlarms()가 아예 실행이 안 될 수 있었음 - 그러면
  // DB에 예전 알람들이 그대로 남은 채로 새 10일치가 추가돼서, 옛 알람(다른 타입/
  // 사운드로 설정됐던)과 새로 만든 알람이 섞여 울릴 수 있었음. 각 알람 취소를
  // 개별로 방어해서, 무슨 일이 있어도 DB 삭제까지는 반드시 실행되게 함.
  try {
    final allAlarms = await DatabaseService.instance.getAllAlarms();
    for (final alarm in allAlarms) {
      if (alarm.id != null) {
        try {
          await AlarmService().cancelAlarm(alarm.id!);
        } catch (e) {
          print('⚠️ 개별 알람 취소 실패 (ID: ${alarm.id}): $e');
        }
      }
    }
    await DatabaseService.instance.deleteAllAlarms();
    print('🗑️ 온보딩: 기존 알람 전체 삭제 완료');
  } catch (e) {
    print('⚠️ 기존 알람 삭제 실패: $e');
  }

  // ⭐ 10일치 알람 생성 (1회만!)
  if (_isRegular!) {
    await _generate10DaysAlarms(schedule);
  }


  // AlarmNotifier 갱신
  if (mounted) {
    try {
      await ref.read(alarmNotifierProvider.notifier).refresh();
      print('✅ 온보딩 완료 - AlarmNotifier 갱신 완료');
    } catch (e) {
      print('❌ AlarmNotifier 갱신 실패: $e');
    }
  }

  // ⭐ "업데이트 후 첫 실행 안내가 기존 유저에게 안 뜬다" 버그 수정의 일부
  // (update_service.dart의 markOnboardingBaselineVersion 주석 참고) - 지금
  // 온보딩을 마치는 사람은 "방금 이 버전으로 막 시작한" 사람이니, 이 버전을
  // 기준선으로 남겨서 나중에 릴리즈 노트가 신규 유저에게 잘못 뜨지 않게 함.
  await UpdateService.markOnboardingBaselineVersion();

  // ⭐ 온보딩 완료 후 무조건 달력탭으로 이동
  if (mounted) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => MainScreen(initialIndex: 1),  // 달력탭
      ),
    );
  }
}

  // onboarding_screen.dart에서 수정

Future<void> _generate10DaysAlarms(ShiftSchedule schedule) async {
  print('🔄 10일치 알람 생성 시작...');

  final List<Alarm> alarms = [];
  final today = DateTime.now();

  for (var i = 0; i < kAlarmRefreshWindowDays; i++) {
    // ⭐ DST 안전: Duration(days: i) 더하기는 "정확히 24*i시간 뒤"라서, 자정 근처
    // 시각에 서머타임 전환이 겹치면 원래 의도한 달력 날짜와 다른 날로 넘어갈 수
    // 있음. DateTime(y, m, d+i)는 달의 일수를 넘어가도 알아서 정규화되면서
    // 해당 달력 날짜의 로컬 자정을 정확히 가리킴.
    final date = DateTime(today.year, today.month, today.day + i);
    final shiftType = schedule.getShiftForDate(date);

    if (shiftType == kUnsetShiftSentinel) continue;

    final alarmSettings = _shiftAlarms[shiftType] ?? [];

    for (var setting in alarmSettings) {
      final alarmTime = DateTime(
        date.year,
        date.month,
        date.day,
        setting.time.hour,
        setting.time.minute,
      );

      if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) continue;

      final alarm = Alarm(
        time: _formatTime(setting.time),
        date: alarmTime,
        type: 'fixed',
        alarmTypeId: setting.alarmTypeId,  // 사용자가 선택한 타입
        shiftType: shiftType,
      );

      alarms.add(alarm);
    }
  }
  
  if (alarms.isNotEmpty) {
    // DB 저장
    await DatabaseService.instance.insertAlarmsInBatch(alarms);
    
    // ⭐ 변경: 저장된 알람 다시 읽어서 DB ID로 Native 등록
    final savedAlarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in savedAlarms) {
      if (alarm.date != null && alarm.date!.isAfter(DateTime.now())) {
        await AlarmService().scheduleAlarm(
          id: alarm.id!,  // ⭐ DB ID 사용
          dateTime: alarm.date!,
          label: alarm.shiftType ?? context.l10n.alarmTitle,
          soundType: 'loud',
        );
      }
    }
    
    // ⭐ 삭제: refresh() 불필요
    // if (mounted) {
    //   ref.read(alarmNotifierProvider.notifier).refresh();
    // }
  }
  
  print('✅ ${alarms.length}개 알람 생성 완료');
}
}

// 알람 시간 설정 다이얼로그
class _AlarmTimeDialog extends StatefulWidget {
  final String shift;
  final List<AlarmSetting> initialAlarms;
  final Function(List<AlarmSetting>) onSave;

  const _AlarmTimeDialog({
    required this.shift,
    required this.initialAlarms,
    required this.onSave,
  });

  @override
  State<_AlarmTimeDialog> createState() => _AlarmTimeDialogState();
}

class _AlarmTimeDialogState extends State<_AlarmTimeDialog> {
  late List<AlarmSetting> _alarms;

  @override
  void initState() {
    super.initState();
    _alarms = List.from(widget.initialAlarms);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.onboardingFixedAlarmDialogTitle(widget.shift)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.onboardingFixedAlarmMaxHint(kMaxAlarmTemplatesPerShift),
              style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: 16.h),

            ..._alarms.asMap().entries.map((entry) {
              final alarm = entry.value;
              return Container(
                margin: EdgeInsets.only(bottom: 12.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 시간 + 삭제 버튼
                    Row(
                      children: [
                        // ⭐ 시간 영역 탭하면 시간 수정
                        InkWell(
                          onTap: () => _editAlarmTime(entry.key),
                          borderRadius: BorderRadius.circular(8.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.alarm, size: 20.sp, color: Theme.of(context).colorScheme.secondary),
                                SizedBox(width: 8.w),
                                Text(
                                  '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error, size: 20.sp),
                          onPressed: () {
                            setState(() {
                              _alarms.removeAt(entry.key);
                            });
                          },
                          constraints: BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    // 알람 타입 선택 버튼들
                    Row(
                      children: [
                        _buildTypeButton(entry.key, 1, '🔔', context.l10n.alarmSoundVibration),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 2, '📳', context.l10n.alarmVibration),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 3, '🔇', context.l10n.alarmSilent),
                      ],
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 8.h),

            if (_alarms.length < kMaxAlarmTemplatesPerShift)
              OutlinedButton.icon(
                onPressed: _addAlarm,
                icon: Icon(Icons.add),
                label: Text(context.l10n.alarmAdd),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 44.h),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          // ⭐ 2026-08-24 버그 수정 - 예전엔 _alarms.isEmpty일 때 저장 버튼이
          // 비활성화됐음. 알람을 3개→2개→1개→0개 순으로 지우다가 0개가 되는
          // 순간 저장이 막혀서 "알람 없음"으로 저장할 방법이 없었음(사용자 확인
          // 재현: 저장 후 재진입해서 전부 삭제하려는 경우). settings_tab.dart의
          // 동일한 다이얼로그(고정 알람 수정)는 애초에 이 가드가 없어서 항상
          // 저장 가능했음 - 여기만 어긋나 있던 것이라 그쪽과 동일하게 무조건
          // 저장 가능하도록 가드를 제거함.
          onPressed: () {
            _alarms.sort((a, b) {
              final aMinutes = a.time.hour * 60 + a.time.minute;
              final bMinutes = b.time.hour * 60 + b.time.minute;
              return aMinutes.compareTo(bMinutes);
            });

            widget.onSave(_alarms);
            Navigator.pop(context);
          },
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }

  // 알람 타입 선택 버튼
  Widget _buildTypeButton(int index, int typeId, String emoji, String label) {
    final isSelected = _alarms[index].alarmTypeId == typeId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _alarms[index] = _alarms[index].copyWith(alarmTypeId: typeId);
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected
              ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.shade800  // 다크모드: 진한 주황 (대비율 6.74:1)
                  : Colors.orange.shade700)  // 화이트모드: 진한 주황 (대비율 5.73:1)
              : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: TextStyle(fontSize: 16.sp)),
              SizedBox(height: 2.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,  // 선택 시 흰색으로 통일
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 알람 시간 수정
  Future<void> _editAlarmTime(int index) async {
    final currentAlarm = _alarms[index];
    await showDialog(
      context: context,
      builder: (context) => _SamsungStyleTimePicker(
        initialTime: currentAlarm.time,
        onTimeSelected: (time) async {
          // ⭐ 중복 체크 (자기 자신 제외)
          final isDuplicate = _alarms.asMap().entries.any((entry) {
            return entry.key != index &&
                   entry.value.time.hour == time.hour &&
                   entry.value.time.minute == time.minute;
          });

          if (isDuplicate) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.tertiary, size: 28),
                    SizedBox(width: 8),
                    Text(context.l10n.alarmDuplicate),
                  ],
                ),
                content: Text(
                  context.l10n.alarmAlreadyExistsAtTime(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  ),
                  style: TextStyle(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.commonOk, style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
            return;
          }

          setState(() {
            _alarms[index] = currentAlarm.copyWith(time: time);
          });
        },
      ),
    );
  }

  Future<void> _addAlarm() async {
    await showDialog(
      context: context,
      builder: (context) => _SamsungStyleTimePicker(
        onTimeSelected: (time) async {
          // ⭐ 중복 체크
          final isDuplicate = _alarms.any((alarm) =>
            alarm.time.hour == time.hour && alarm.time.minute == time.minute
          );

          if (isDuplicate) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.tertiary, size: 28),
                    SizedBox(width: 8),
                    Text(context.l10n.alarmDuplicate),
                  ],
                ),
                content: Text(
                  context.l10n.alarmAlreadyExistsAtTime(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  ),
                  style: TextStyle(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.commonOk, style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
            return;
          }

          setState(() {
            // 기본값: 소리 (alarmTypeId = 1)
            _alarms.add(AlarmSetting(time: time, alarmTypeId: 1));
          });
        },
      ),
    );
  }
}

class _SamsungStyleTimePicker extends StatefulWidget {
  final Function(TimeOfDay) onTimeSelected;
  final TimeOfDay? initialTime;  // ⭐ 초기 시간 (수정 시 사용)

  const _SamsungStyleTimePicker({
    required this.onTimeSelected,
    this.initialTime,
  });

  @override
  State<_SamsungStyleTimePicker> createState() => _SamsungStyleTimePickerState();
}

class _SamsungStyleTimePickerState extends State<_SamsungStyleTimePicker> {
  bool _isAM = true;
  int _hour = 9;
  int _minute = 0;

  @override
  void initState() {
    super.initState();
    // ⭐ 초기 시간이 있으면 설정
    if (widget.initialTime != null) {
      final t = widget.initialTime!;
      _minute = t.minute;
      if (t.hour == 0) {
        _isAM = true;
        _hour = 12;
      } else if (t.hour < 12) {
        _isAM = true;
        _hour = t.hour;
      } else if (t.hour == 12) {
        _isAM = false;
        _hour = 12;
      } else {
        _isAM = false;
        _hour = t.hour - 12;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.commonSelectTime,
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = true;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isAM ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.outline,
                            width: _isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        child: Center(
                          child: Text(
                            context.l10n.commonAm,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 8.h),
                    
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = false;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: !_isAM ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.outline,
                            width: !_isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        child: Center(
                          child: Text(
                            context.l10n.commonPm,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(width: 16.w),

                // ⭐ 시간 NumberPicker 수정
                _TappableNumberPicker(
                  value: _hour,
                  minValue: 1,
                  maxValue: 12,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                  onChanged: (value) {
                    setState(() {
                      if (_hour == 11 && value == 12) {
                        _isAM = !_isAM;
                      } else if (_hour == 12 && value == 11) {
                        _isAM = !_isAM;
                      }
                      _hour = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Theme.of(context).colorScheme.outline),
                      bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
                
                Text(':', style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold)),

                // ⭐ 분 NumberPicker 수정
                _TappableNumberPicker(
                  value: _minute,
                  minValue: 0,
                  maxValue: 59,
                  zeroPad: true,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                  onChanged: (value) {
                    setState(() {
                      _minute = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Theme.of(context).colorScheme.outline),
                      bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 24.h),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
                ),
                SizedBox(width: 8.w),
                ElevatedButton(
                  onPressed: () async {
                    int hour24;
                    if (_isAM) {
                      hour24 = _hour == 12 ? 0 : _hour;
                    } else {
                      hour24 = _hour == 12 ? 12 : _hour + 12;
                    }

                    await widget.onTimeSelected(TimeOfDay(hour: hour24, minute: _minute));
                    if (mounted) Navigator.pop(context);
                  },
                  child: Text(context.l10n.commonOk),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ⭐ 탭 가능한 NumberPicker (스와이프 + 즉시 탭 지원)
class _TappableNumberPicker extends StatefulWidget {
  final int value;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;
  final bool infiniteLoop;
  final bool zeroPad;
  final double itemHeight;
  final double itemWidth;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final BoxDecoration? decoration;

  const _TappableNumberPicker({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
    this.infiniteLoop = false,
    this.zeroPad = false,
    this.itemHeight = 50.0,
    this.itemWidth = 60.0,
    this.textStyle,
    this.selectedTextStyle,
    this.decoration,
  });

  @override
  State<_TappableNumberPicker> createState() => _TappableNumberPickerState();
}

class _TappableNumberPickerState extends State<_TappableNumberPicker> {
  late FixedExtentScrollController _controller;
  static const int _infiniteOffset = 5000;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.value - widget.minValue;
    _controller = FixedExtentScrollController(
      initialItem: widget.infiniteLoop ? initialIndex + _infiniteOffset * _itemCount : initialIndex,
    );
  }

  @override
  void didUpdateWidget(_TappableNumberPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final currentIndex = _controller.selectedItem;
      final currentValue = _indexToValue(currentIndex);
      if (currentValue != widget.value) {
        final targetIndex = _valueToIndex(widget.value);
        _controller.jumpToItem(targetIndex);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _itemCount => widget.maxValue - widget.minValue + 1;

  int _indexToValue(int index) {
    if (widget.infiniteLoop) {
      final normalizedIndex = index % _itemCount;
      return widget.minValue + normalizedIndex;
    }
    return widget.minValue + index;
  }

  int _valueToIndex(int value) {
    final baseIndex = value - widget.minValue;
    if (widget.infiniteLoop) {
      final currentIndex = _controller.selectedItem;
      final currentCycle = currentIndex ~/ _itemCount;
      return baseIndex + currentCycle * _itemCount;
    }
    return baseIndex;
  }

  void _handleTap(int targetValue) {
    final targetIndex = _valueToIndex(targetValue);
    _controller.jumpToItem(targetIndex);  // ⭐ 즉시 점프 (애니메이션 없음)
    HapticFeedback.selectionClick();
    widget.onChanged(targetValue);
  }

  String _formatNumber(int value) {
    return widget.zeroPad ? value.toString().padLeft(2, '0') : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.itemHeight * 3,
      width: widget.itemWidth,
      decoration: widget.decoration,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: widget.itemHeight,
        physics: const FixedExtentScrollPhysics(),
        diameterRatio: 1.2,
        perspective: 0.003,
        squeeze: 1.0,
        onSelectedItemChanged: (index) {
          final value = _indexToValue(index);
          HapticFeedback.selectionClick();
          widget.onChanged(value);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          builder: (context, index) {
            if (!widget.infiniteLoop && (index < 0 || index >= _itemCount)) {
              return null;
            }

            final value = _indexToValue(index);
            final isSelected = value == widget.value;

            return GestureDetector(
              onTap: () => _handleTap(value),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Text(
                  _formatNumber(value),
                  style: isSelected
                      ? (widget.selectedTextStyle ?? TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface))
                      : (widget.textStyle ?? TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ),
            );
          },
          childCount: widget.infiniteLoop ? null : _itemCount,
        ),
      ),
    );
  }
}