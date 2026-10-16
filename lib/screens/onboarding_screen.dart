import '../widgets/fixed_alarm_summary_card.dart';
import '../widgets/app_ui_feedback.dart';
import '../widgets/fixed_alarm_editor_dialog.dart';
import '../widgets/app_ui_theme_scope.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/permission_warning_banner.dart';
import 'package:flutter/material.dart';
import '../models/shift_schedule.dart';
import '../models/calendar_theme.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/calendar_theme_provider.dart';
import '../providers/alarm_provider.dart';
import '../main.dart'; // ⭐ MainScreen import
import '../constants/alarm_limits.dart';
import '../constants/layout_limits.dart';
import '../constants/shift_name_limits.dart';
import '../widgets/shift_name_text_field.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_ui_theme.dart';
import '../widgets/app_ui_components.dart';
import '../constants/alarm_day_offset.dart';
import '../services/alarm_generation_service.dart';
import '../services/app_analytics.dart';

// 알람 설정 (시간 + 타입 + 전날/당일/다음날)
class AlarmSetting {
  final TimeOfDay time;
  final int alarmTypeId; // 1: 소리+진동, 2: 진동, 3: 무음
  final int dayOffset; // -1: 전날, 0: 당일(기본값), 1: 다음날

  AlarmSetting(
      {required this.time,
      this.alarmTypeId = 1,
      this.dayOffset = kAlarmDaySame});

  AlarmSetting copyWith({TimeOfDay? time, int? alarmTypeId, int? dayOffset}) {
    return AlarmSetting(
      time: time ?? this.time,
      alarmTypeId: alarmTypeId ?? this.alarmTypeId,
      dayOffset: dayOffset ?? this.dayOffset,
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  // ⭐ 변경
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() =>
      _OnboardingScreenState(); // ⭐ 변경
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // ⭐ 변경
  // ⭐ 커스텀 근무 형태 최대 개수(예전엔 리터럴 7이 여러 곳에 흩어져 있었음).
  static const int _maxCustomShiftTypes = kMaxCustomShiftTypes;

  int _step = 0;
  bool _choosingToday = false;
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
  List<String> _selectedShifts = []; // 불규칙용

  List<String> get _uniqueShifts {
    return _pattern.toSet().toList();
  }

  final _patternPreviewController = ScrollController();
  final _lastPatternSlotKey = GlobalKey();

  @override
  void dispose() {
    _patternPreviewController.dispose();
    super.dispose();
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
        context.l10n.shiftAnnualLeave,
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppUiThemeScope(builder: _buildSetupScreen);
  }

  int get _totalSteps => 3;
  int get _visibleStepNumber => _step + 1;

  void _goBack() {
    if (_step == 0) return;
    setState(() {
      _step--;
      if (_step == 1) {
        _isRegular = true;
      }
    });
  }

  Widget _buildSetupScreen(BuildContext themeContext) => PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _goBack();
        },
        child: Theme(
          data: AppUiTheme.withPalette(
              Theme.of(themeContext), AppUiPalette.of(themeContext)),
          child: Builder(
              builder: (uiContext) => Scaffold(
                    backgroundColor: AppUiPalette.of(uiContext).background,
                    appBar: AppBar(
                      automaticallyImplyLeading: false,
                      leading: _step > 0
                          ? IconButton(
                              onPressed: _goBack,
                              icon: const Icon(Icons.arrow_back))
                          : null,
                      title: AppUiText(uiContext.l10n.onboardingStart,
                          role: AppTextRole.toolbar),
                      actions: [
                        Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: Center(
                                child: AppUiText(
                                    '$_visibleStepNumber / $_totalSteps',
                                    role: AppTextRole.progress,
                                    tone: AppTextTone.secondary)))
                      ],
                    ),
                    body: AdaptiveFormBody(
                        child: SafeArea(
                            top: false,
                            child: _step == 0
                                ? _buildShiftTypeCreation(uiContext)
                                : _step == 1
                                    ? _buildPatternInput(uiContext)
                                    : _buildMainAlarmSetup(uiContext))),
                  )),
        ),
      );

  Widget _buildShiftTypeCreation(BuildContext uiContext) => Padding(
        padding: const EdgeInsets.all(AppUiMetrics.pagePadding),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppUiText(uiContext.l10n.onboardingShiftNameTitle,
                  key: const ValueKey('onboarding-page-heading'),
                  role: AppTextRole.title),
              const SizedBox(height: 8),
              AppUiText(uiContext.l10n.onboardingShiftNameSubHint,
                  tone: AppTextTone.secondary),
              const SizedBox(height: 16),
              AppUiCard(
                  padding:
                      const EdgeInsets.all(AppUiMetrics.compactCardPadding),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppUiText(uiContext.l10n.onboardingProvidedShiftNames,
                            role: AppTextRole.section),
                        const SizedBox(height: AppUiMetrics.gap),
                        _buildShiftNameGrid(uiContext),
                        const SizedBox(height: AppUiMetrics.gap),
                        AppUiButton(
                            label: uiContext.l10n.onboardingAddShiftName,
                            action: AppUiAction.secondary,
                            icon: Icons.add,
                            onPressed:
                                _customShiftTypes.length < _maxCustomShiftTypes
                                    ? () => _showAddCustomDialog(uiContext)
                                    : null),
                        const SizedBox(height: 12),
                        AppUiText(
                            uiContext.l10n.onboardingRemoveUnusedShiftNamesHint,
                            role: AppTextRole.supporting,
                            tone: AppTextTone.secondary),
                      ])),
              const SizedBox(height: AppUiMetrics.gap),
              AppUiText(uiContext.l10n.onboardingShiftNamesReadyHint,
                  tone: AppTextTone.secondary),
              const SizedBox(height: 24),
            ]),
          )),
          const SizedBox(height: AppUiMetrics.gap),
          AppUiButton(
              label: uiContext.l10n.onboardingNextPattern,
              onPressed: _allShiftTypes.isNotEmpty
                  ? () => setState(() => _step = 1)
                  : null),
        ]),
      );

  // ⭐ 2026-08-24 - _buildShiftTypesInput()(불규칙용 근무명 지정 화면 복제본)과
  // _buildSelectShiftsForAlarm()(불규칙용 "실제 사용할 근무 선택" 화면)을
  // 삭제함 - _buildStep()을 "여기" 지름길 방식으로 재설계하면서 이 두 화면에
  // 도달하는 경로 자체가 완전히 사라짐(_isRegular가 false가 되는 시점이
  // _step==1일 때뿐이라, _step==0이나 옛 case1의 그 위치에서 false가 되는
  // 경우가 구조적으로 없음 - _buildStep()의 클래스 주석 참고). 근무명 지정은
  // 이제 규칙/불규칙 상관없이 _buildShiftTypeCreation() 하나로 통일됨.
  Widget _buildShiftNameGrid(BuildContext uiContext, {bool pattern = false}) =>
      LayoutBuilder(builder: (context, box) {
        const gap = 6.0;
        final height = AppUiShiftChip.heightFor(AppChipSize.regular);
        final visibleRows = ((_allShiftTypes.length + 3) ~/ 4).clamp(1, 2);
        final width = (box.maxWidth - gap * 3) / 4;
        return SizedBox(
          key: ValueKey(
              pattern ? 'onboarding-shift-choices' : 'onboarding-shift-names'),
          height: visibleRows * height + (visibleRows - 1) * gap,
          child: SingleChildScrollView(
              primary: false,
              child: Wrap(spacing: gap, runSpacing: gap, children: [
                for (final name in _allShiftTypes)
                  SizedBox(
                      width: width,
                      height: height,
                      child: AppUiShiftChip(
                          name: name,
                          enabled: !pattern ||
                              (_pattern.length < 40 && !_choosingToday),
                          onTap: pattern
                              ? () => _addToPattern(name)
                              : () => _removeShiftType(name))),
              ])),
        );
      });

  Widget _buildPatternInput(BuildContext uiContext) => Padding(
      padding: const EdgeInsets.all(AppUiMetrics.pagePadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: LayoutBuilder(builder: (context, viewport) {
          // Reserve the card before any pattern is entered. Small/landscape
          // screens can scroll this region; the two bottom actions stay visible.
          double textHeight(String text, AppTextRole role, double width) {
            final painter = TextPainter(
                text: TextSpan(
                    text: text, style: AppTypography.style(uiContext, role)),
                textDirection: Directionality.of(uiContext),
                textScaler: TextScaler.noScaling)
              ..layout(maxWidth: width);
            final result = painter.height;
            painter.dispose();
            return result;
          }

          final width = viewport.maxWidth;
          final sourceRows = ((_allShiftTypes.length + 3) ~/ 4).clamp(1, 2);
          final sourceHeight =
              sourceRows * AppUiShiftChip.heightFor(AppChipSize.regular) +
                  (sourceRows - 1) * 6;
          double textWidth(String text, AppTextRole role) {
            final painter = TextPainter(
                text: TextSpan(
                    text: text, style: AppTypography.style(uiContext, role)),
                textDirection: Directionality.of(uiContext),
                locale: Localizations.localeOf(uiContext),
                textScaler: TextScaler.noScaling)
              ..layout();
            final result = painter.width;
            painter.dispose();
            return result;
          }

          final cardInsets = AppUiMetrics.compactCardPadding * 2 + 2;
          final cardWidth = width - cardInsets;
          final patternLabelWidth = textWidth(
              uiContext.l10n.onboardingPatternLabel, AppTextRole.section);
          final hintHeight = textHeight(uiContext.l10n.onboardingPatternHint,
              AppTextRole.supporting, cardWidth - patternLabelWidth - 8);
          final labelHeight = textHeight(uiContext.l10n.onboardingPatternLabel,
              AppTextRole.section, cardWidth);
          final footerHeight = _patternFooterHeight(uiContext, cardWidth);
          final minHeight =
              (8 + 16 + AppUiMetrics.gap + cardInsets * 2 + 12 + 8 + 12) +
                  sourceHeight +
                  AppUiShiftChip.heightFor(AppChipSize.regular) +
                  textHeight(uiContext.l10n.onboardingTapToCompletePattern,
                      AppTextRole.title, width) +
                  textHeight(uiContext.l10n.onboardingPatternHowTo,
                      AppTextRole.body, width) +
                  textHeight(uiContext.l10n.onboardingSelectedShiftNames,
                      AppTextRole.section, cardWidth) +
                  (hintHeight > labelHeight ? hintHeight : labelHeight) +
                  footerHeight;
          final height =
              viewport.maxHeight < minHeight ? minHeight : viewport.maxHeight;
          return SingleChildScrollView(
              primary: false,
              child: SizedBox(
                  height: height,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppUiText(uiContext.l10n.onboardingTapToCompletePattern,
                            key: const ValueKey('onboarding-page-heading'),
                            role: AppTextRole.title),
                        const SizedBox(height: 8),
                        AppUiText(uiContext.l10n.onboardingPatternHowTo,
                            tone: AppTextTone.secondary),
                        const SizedBox(height: 16),
                        AppUiCard(
                            padding: const EdgeInsets.all(
                                AppUiMetrics.compactCardPadding),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AppUiText(
                                      uiContext
                                          .l10n.onboardingSelectedShiftNames,
                                      role: AppTextRole.section),
                                  const SizedBox(height: AppUiMetrics.gap),
                                  _buildShiftNameGrid(uiContext, pattern: true),
                                ])),
                        const SizedBox(height: 12),
                        Expanded(child: _buildPatternCard(uiContext)),
                      ])));
        })),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppUiText(uiContext.l10n.onboardingIrregularChoiceDescription,
                  tone: AppTextTone.secondary),
              AppUiButton(
                  label: uiContext.l10n.onboardingIrregularChoiceTitle,
                  compact: true,
                  action: AppUiAction.secondary,
                  onPressed: () => setState(() {
                        _isRegular = false;
                        _selectedShifts = List.from(_allShiftTypes);
                        _step = 2;
                      })),
            ]),
        const SizedBox(height: 8),
        AppUiButton(
            label: uiContext.l10n.onboardingNextAlarms,
            onPressed:
                !_choosingToday || _pattern.length < 2 || _todayIndex == null
                    ? null
                    : () => setState(() {
                          _isRegular = true;
                          _step = 2;
                        })),
      ]));

  double _patternFooterHeight(BuildContext context, double width) {
    double height(String text, AppTextRole role, double maxWidth) {
      final painter = TextPainter(
          text: TextSpan(text: text, style: AppTypography.style(context, role)),
          textDirection: Directionality.of(context),
          locale: Localizations.localeOf(context),
          textScaler: TextScaler.noScaling)
        ..layout(maxWidth: maxWidth);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final editHeight = height(context.l10n.onboardingEditPattern,
            AppTextRole.button, width / 2 - 24) +
        16;
    final finishHeight = height(context.l10n.onboardingCompletePattern,
            AppTextRole.button, width - 40) +
        24;
    final selectionHeight = height(context.l10n.onboardingTodayPositionHint,
            AppTextRole.section, width) +
        8 +
        (editHeight > 48 ? editHeight : 48);
    return selectionHeight > finishHeight ? selectionHeight : finishHeight;
  }

  Widget _buildPatternCard(BuildContext uiContext) => AppUiCard(
      key: const ValueKey('onboarding-pattern-card'),
      padding: const EdgeInsets.all(AppUiMetrics.compactCardPadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppUiText(uiContext.l10n.onboardingPatternLabel,
              role: AppTextRole.section),
          const SizedBox(width: 8),
          Expanded(
              child: Visibility(
                  visible: !_choosingToday,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: AppUiText(uiContext.l10n.onboardingPatternHint,
                      role: AppTextRole.supporting,
                      tone: AppTextTone.secondary,
                      textAlign: TextAlign.right))),
        ]),
        const SizedBox(height: 8),
        Expanded(child: LayoutBuilder(builder: (context, box) {
          const columns = 4;
          const gap = 4.0;
          final width = (box.maxWidth - (columns - 1) * gap) / columns;
          final height = AppUiShiftChip.heightFor(AppChipSize.regular);
          return SizedBox(
              key: const ValueKey('onboarding-pattern-preview'),
              child: SingleChildScrollView(
                  controller: _patternPreviewController,
                  child: Wrap(spacing: gap, runSpacing: gap, children: [
                    for (var i = 0; i < _pattern.length; i++)
                      SizedBox(
                          key: i == _pattern.length - 1
                              ? _lastPatternSlotKey
                              : null,
                          width: width,
                          height: height,
                          child: AppUiShiftChip(
                              key: ValueKey(
                                  'onboarding-pattern-slot-' + i.toString()),
                              name: _pattern[i],
                              index: i + 1,
                              size: AppChipSize.regular,
                              selected: _todayIndex == i,
                              selectionMode: _choosingToday,
                              badge: _todayIndex == i
                                  ? uiContext.l10n.onboardingTodayMarker
                                  : null,
                              onTap: () {
                                if (_choosingToday) {
                                  setState(() => _todayIndex = i);
                                } else {
                                  _removeFromPattern(i);
                                }
                              })),
                  ])));
        })),
        const SizedBox(height: 12),
        LayoutBuilder(
            builder: (context, box) => SizedBox(
                key: const ValueKey('onboarding-pattern-action-area'),
                height: _patternFooterHeight(uiContext, box.maxWidth),
                child: Stack(children: [
                  Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSwitcher(
                          duration: Duration(
                              milliseconds:
                                  MediaQuery.disableAnimationsOf(uiContext)
                                      ? 0
                                      : 220),
                          switchInCurve:
                              const Interval(.6, 1, curve: Curves.easeOut),
                          child: _choosingToday
                              ? AppUiAttention(
                                  enabled: _todayIndex == null,
                                  child: AppUiText(
                                      uiContext
                                          .l10n.onboardingTodayPositionHint,
                                      key: const ValueKey(
                                          'onboarding-today-guide'),
                                      role: AppTextRole.section,
                                      tone: AppTextTone.selection,
                                      textAlign: TextAlign.center))
                              : const SizedBox.shrink())),
                  AnimatedAlign(
                    duration: AppUiMotion.transitionDuration(uiContext),
                    curve: Curves.easeOutCubic,
                    alignment: _choosingToday
                        ? Alignment.bottomRight
                        : Alignment.center,
                    child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: _choosingToday
                                ? box.maxWidth / 2
                                : box.maxWidth),
                        child: AppUiButton(
                            key: const ValueKey('onboarding-pattern-complete'),
                            label: _choosingToday
                                ? uiContext.l10n.onboardingEditPattern
                                : uiContext.l10n.onboardingCompletePattern,
                            compact: _choosingToday,
                            action: _choosingToday
                                ? AppUiAction.secondary
                                : AppUiAction.primary,
                            onPressed: _pattern.length < 2
                                ? null
                                : () => setState(() {
                                      _choosingToday = !_choosingToday;
                                      _todayIndex = null;
                                      if (_choosingToday &&
                                          _patternPreviewController.hasClients)
                                        _patternPreviewController.jumpTo(0);
                                    }))),
                  ),
                ]))),
      ]));

  Future<void> _showAddCustomDialog(BuildContext uiContext) async {
    final controller = TextEditingController();
    String? error;
    await showAppUiDialog<void>(
      context: uiContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AppUiDialog(
          title: dialogContext.l10n.onboardingAddShiftName,
          content: SizedBox(
              width: AppLayout.of(dialogContext).dialogWidth,
              child: ShiftNameTextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: dialogContext.l10n.shiftName,
                  helperText: dialogContext.l10n.onboardingShortNamesHint,
                  errorText: error,
                ),
              )),
          actions: [
            AppUiButton(
                label: dialogContext.l10n.commonCancel,
                action: AppUiAction.secondary,
                onPressed: () => Navigator.of(dialogContext).pop()),
            AppUiButton(
                label: dialogContext.l10n.commonAdd,
                onPressed: () {
                  final text = controller.text.trim();
                  final issue =
                      validateShiftName(text, otherNames: _allShiftTypes);
                  if (issue != null) {
                    setDialogState(() => error =
                        _shiftNameIssueMessage(dialogContext, issue, text));
                    return;
                  }
                  setState(() => _customShiftTypes.add(text));
                  Navigator.of(dialogContext).pop();
                }),
          ],
        ),
      ),
    );
    // The route reverse animation may still paint its text field after pop.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  void _removeShiftType(String name) {
    setState(() {
      _baseShiftTypes.remove(name);
      _customShiftTypes.remove(name);
      if (_pattern.contains(name)) {
        _pattern.removeWhere((shift) => shift == name);
        _todayIndex = null;
        _choosingToday = false;
      }
      _shiftAlarms.remove(name);
      _selectedShifts.remove(name);
    });
  }

  void _addToPattern(String shift) {
    if (_pattern.length < 40) {
      setState(() {
        _pattern.add(shift);
        _todayIndex = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lastPatternSlotKey.currentContext != null) {
          Scrollable.ensureVisible(_lastPatternSlotKey.currentContext!,
              alignment: .8, duration: const Duration(milliseconds: 160));
        }
        if (mounted && _patternPreviewController.hasClients) {
          _patternPreviewController.animateTo(
              _patternPreviewController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut);
        }
      });
    }
  }

  void _removeFromPattern(int index) {
    setState(() {
      _pattern.removeAt(index);
      _todayIndex = null;
    });
  }

  Widget _buildMainAlarmSetup(BuildContext uiContext) {
    final shifts = _isRegular == true ? _uniqueShifts : _selectedShifts;
    return Padding(
        padding: const EdgeInsets.all(AppUiMetrics.pagePadding),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: SingleChildScrollView(
                  key: const ValueKey('onboarding-alarm-list'),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppUiText(
                            uiContext.l10n.onboardingSetFixedAlarmPerShift,
                            role: AppTextRole.title),
                        const SizedBox(height: 8),
                        AppUiText(
                            uiContext.l10n.onboardingMaxAlarmsPerShift(
                                kMaxAlarmTemplatesPerShift),
                            tone: AppTextTone.secondary),
                        const SizedBox(height: 12),
                        AppUiCard(
                            padding: const EdgeInsets.all(
                                AppUiMetrics.compactCardPadding),
                            child: Row(children: [
                              const Icon(Icons.notifications_none_rounded,
                                  size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: AppUiText(
                                      uiContext.l10n.onboardingAlarmOptional,
                                      role: AppTextRole.supporting)),
                            ])),
                        const SizedBox(height: 16),
                        for (final shift in shifts) ...[
                          _buildShiftAlarmCard(
                              uiContext, shift, _shiftAlarms[shift] ?? []),
                          const SizedBox(height: 12),
                        ],
                        AppUiText(uiContext.l10n.onboardingCanChangeInSettings,
                            role: AppTextRole.supporting,
                            tone: AppTextTone.secondary),
                      ]))),
          const PermissionWarningBanner(),
          const SizedBox(height: 12),
          AppUiButton(
              label: _finishing
                  ? uiContext.l10n.onboardingSaving
                  : uiContext.l10n.onboardingFinishSetup,
              onPressed: _finishing ? null : _saveAndFinish),
        ]));
  }

  Widget _buildShiftAlarmCard(
          BuildContext uiContext, String shift, List<AlarmSetting> alarms) =>
      FixedAlarmSummaryCard(
          key: ValueKey('onboarding-alarm-card-' + shift),
          editKey: ValueKey('onboarding-alarm-edit-' + shift),
          shift: shift,
          alarms: alarms,
          onEdit: () => _showAlarmTimeDialog(uiContext, shift));

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _showAlarmTimeDialog(BuildContext uiContext, String shift) {
    showAppUiDialog(
      context: uiContext,
      builder: (context) => FixedAlarmEditorDialog(
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

  // ⭐ 근무명 색상 생성 - 2026-08-19부터 "근무명 색상 변경" 기능 복원과 함께
  // 온보딩 전용 파스텔 팔레트 계산(패턴 등장 순서 기반)을 버리고, 실제 화면
  // (calendar_tab.dart)이 쓰는 것과 동일한 effectiveShiftColors()로 통일함 - 그래야
  // 온보딩 직후 위젯/전체근무표(shiftColors 캐시를 읽는 쪽)가 실제 달력 탭과 같은
  // 색을 보여줌(온보딩 시점엔 아직 사용자가 색을 하나도 지정 안 했으니
  // customColors는 없음 - 그래서 결과는 곧 kDefaultCalendarThemeId 디폴트 그대로).
  // 순서는 shiftTypes(=_allShiftTypes, 아래서 그대로 넘김) 기준 - calendar_tab.dart도
  // 항상 이 순서로 계산하므로 이렇게 맞춰야 이후 색이 안 어긋남.
  Map<String, int> _generateShiftColors() {
    final theme =
        context.availableCalendarTheme(ref.read(calendarThemeProvider));
    return effectiveShiftColors(_allShiftTypes, theme, null)
        .map((name, color) => MapEntry(name, color.toARGB32()));
  }

  Future<void> _saveAlarmTemplates() async {
    for (var entry in _shiftAlarms.entries) {
      final shift = entry.key;
      final alarms = entry.value;

      for (var alarm in alarms) {
        await DatabaseService.instance.insertAlarmTemplate(
          shiftType: shift,
          time: _formatTime(alarm.time),
          alarmTypeId: alarm.alarmTypeId, // 사용자가 선택한 타입
          dayOffset: alarm.dayOffset,
        );
      }
    }

    print('✅ 알람 템플릿 저장 완료');
  }

  // onboarding_screen.dart의 _saveAndFinish() 수정

// ⭐ 2026-09-15 (전체 코드 점검 Q-01) - "시작하기" 연타 방지. 예전엔 가드가 없어 두 번 누르면
// 저장이 두 번 돌아 스케줄 행·알람 템플릿·알람이 중복으로 들어갈 수 있었음(saveSchedule은
// id 없는 스케줄을 insert, insertAlarmTemplate은 append). 성공하면 화면이 교체되므로 되돌리지
// 않고, 실패했을 때만 다시 누를 수 있게 풀어줌.
  bool _finishing = false;

  Future<void> _saveAndFinish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await _saveAndFinishOnce();
    } catch (e) {
      debugPrint('❌ 온보딩 저장 실패: $e');
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppUiSnackBar(content: Text(context.l10n.onboardingSaveFailed)),
        );
      }
    }
  }

  Future<void> _saveAndFinishOnce() async {
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

    // Commit deletion before Native cancelIfGone; keep the new templates.
    // Continue cancelling other IDs if an individual OS cancellation fails.
    try {
      final removedIds = await DatabaseService.instance.deleteAllAlarms();
      for (final id in removedIds) {
        try {
          await AlarmService().cancelAlarm(id);
        } catch (e) {
          print('⚠️ 개별 알람 취소 실패 (ID: $id): $e');
        }
      }
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

    // 분류값(규칙적/불규칙)만 보낸다 - 근무표 내용은 보내지 않음
    AppAnalytics.track(AnalyticsEvent.onboardingComplete,
        params: {'schedule_type': _isRegular! ? 'regular' : 'irregular'});

    // ⭐ 온보딩 완료 후 무조건 달력탭으로 이동
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) =>
              const MainScreen(initialIndex: kCalendarTabIndex), // 달력탭
        ),
      );
    }
  }

  // onboarding_screen.dart에서 수정

  Future<void> _generate10DaysAlarms(ShiftSchedule schedule) async {
    print('🔄 10일치 알람 생성 시작...');

    final today = DateTime.now();
    final result = await regenerateFixedAlarmsForDates(
      db: await DatabaseService.instance.database,
      schedule: schedule,
      dates: {
        for (var i = 0; i < kAlarmRefreshWindowDays; i++)
          DateTime(today.year, today.month, today.day + i),
      },
      nowOverride: today,
    );
    // Share the same transaction and consumed-slot policy as regeneration.
    for (final id in result.cancelIds) {
      await AlarmService().cancelAlarm(id);
    }
    for (final alarm in result.scheduled) {
      await AlarmService().scheduleAlarm(
        id: alarm.id,
        dateTime: alarm.dateTime,
        label: alarm.label,
        soundType: 'loud',
      );
    }
    print('✅ ${result.scheduled.length}개 알람 생성 완료');
  }
}

// 알람 시간 설정 다이얼로그

String _shiftNameIssueMessage(
    BuildContext context, ShiftNameIssue issue, String name) {
  switch (issue) {
    case ShiftNameIssue.empty:
      return context.l10n.onboardingEnterShiftName;
    case ShiftNameIssue.tooLong:
      return context.l10n.onboardingCharLimitError(shiftNameLengthLimit(name));
    case ShiftNameIssue.comma:
      return context.l10n.shiftNameCommaNotAllowed;
    case ShiftNameIssue.reserved:
      return context.l10n.shiftNameReserved(name);
    case ShiftNameIssue.duplicate:
      return context.l10n.onboardingDuplicateShiftName;
  }
}
