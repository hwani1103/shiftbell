import '../widgets/app_ui_feedback.dart';
import '../widgets/app_ui_components.dart';
import '../theme/app_ui_theme.dart';
import '../widgets/app_ui_theme_scope.dart';
import '../widgets/permission_warning_banner.dart';
import '../utils/alarm_clock_label.dart';
import 'package:intl/intl.dart';
import '../widgets/adaptive_layout.dart';
import '../constants/layout_limits.dart';
// lib/screens/next_alarm_tab.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/alarm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alarm_provider.dart';
import '../l10n/l10n_extensions.dart';
import '../utils/weekday_util.dart';
import '../constants/platform_channel.dart';
import '../utils/alarm_dismiss_gate.dart';

class NextAlarmTab extends StatelessWidget {
  const NextAlarmTab({super.key});

  @override
  Widget build(BuildContext context) => AppUiThemeScope(
      preserveTextGeometry: true, builder: (_) => const _NextAlarmContent());
}

// Keep the palette boundary inside this tab so other tabs retain their colors.
class _NextAlarmContent extends ConsumerStatefulWidget {
  const _NextAlarmContent();

  @override
  ConsumerState<_NextAlarmContent> createState() => _NextAlarmTabState();
}

class _NextAlarmTabState extends ConsumerState<_NextAlarmContent> {
  final _dismissGate = AlarmDismissGate();
  static const platform = kAlarmChannel;

  Future<void> _dismissAlarm(int id, DateTime? date) async {
    await _dismissGate.run(() async {
      // Keep the captured ID through the entire action. A rapid second tap on
      // the same spot must not act on the card that replaces this one.
      final deletion =
          await ref.read(alarmNotifierProvider.notifier).deleteAlarm(id, date);

      try {
        await platform.invokeMethod('cancelNotification');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }

      try {
        await platform.invokeMethod('triggerGuardCheck');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
      }

      if (mounted) {
        final p = AppUiPalette.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          AppUiSnackBar(
            backgroundColor: p.text,
            content: Text(
                deletion.reservationFailed
                    ? context.l10n.alarmRefreshUnconfirmed
                    : context.l10n.alarmCanceledToast,
                style: TextStyle(color: p.surface)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nextAlarmAsync = ref.watch(nextAlarmProvider);

    // ⭐ 2026-08-28 - 좌우 스와이프로 달력탭 이동하는 기능 제거(안 써서).
    return Scaffold(
      // A solid shared backdrop keeps loading and content on the same surface.
      backgroundColor: AppUiPalette.of(context).background,
      body: SizedBox.expand(
        child: ColoredBox(
          color: AppUiPalette.of(context).background,
          child: SafeArea(
            child: Column(
              children: [
                const PermissionWarningBanner(),
                Expanded(
                  child: nextAlarmAsync.when(
                    loading: () => const SizedBox.shrink(), // ⭐ 로딩 인디케이터 제거
                    error: (error, stack) => _buildEmptyState(),
                    data: (nextAlarm) {
                      if (nextAlarm == null) {
                        return _buildEmptyState();
                      }
                      return _AlarmDisplayWidget(
                        alarm: nextAlarm,
                        onDismiss: () =>
                            _dismissAlarm(nextAlarm.id!, nextAlarm.date),
                        onShowAllAlarms: () => _showAllAlarmsSheet(context),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final p = AppUiPalette.of(context);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120.w,
                height: 120.w,
                decoration: BoxDecoration(
                  color: p.soft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.alarm_off_rounded,
                  size: 60.sp,
                  color: p.secondaryText,
                ),
              ),
              SizedBox(height: 24.h),
              Text(
                context.l10n.alarmNoneUpcoming,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w500,
                  color: p.secondaryText,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                context.l10n.alarmEmptyStateHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: p.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 전체 알람 목록 바텀시트.
  // 원래 _AlarmDisplayWidgetState(다음 알람 카드)에 있었는데, 그 위젯은 refresh()가
  // state를 loading으로 바꾸는 순간 NextAlarmTab이 SizedBox로 잠깐 바꿔치기해서
  // 통째로 dispose됨 - 그런데 이 시트는 별개의 오버레이라 그대로 열려있다 보니, 죽은
  // State의 context를 계속 쓰다가 "Null check operator used on a null value"
  // (Theme.of(context) 내부)로 터졌음. 이 탭 자체(_NextAlarmTabState)는 알람
  // 데이터가 바뀌어도 항상 같은 자리에서 계속 살아있는 안정적인 State라 여기로 옮김.
  void _showAllAlarmsSheet(BuildContext context) {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) {
        // ⭐ 여기서 refresh - 안전한 context에서 호출
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(alarmNotifierProvider.notifier).refresh();
        });

        return AppUiThemeScope(
            builder: (context) => DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  minChildSize: 0.4,
                  maxChildSize: 0.85,
                  expand: false,
                  builder: (context, scrollController) {
                    return Consumer(
                      builder: (context, ref, child) {
                        final alarmsAsync = ref.watch(alarmNotifierProvider);
                        final p = AppUiPalette.of(context);

                        return Container(
                          key: const ValueKey('next-alarm-list-surface'),
                          decoration: BoxDecoration(
                            color: p.surface,
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20.r)),
                          ),
                          padding: EdgeInsets.symmetric(
                              horizontal: 20.w, vertical: 16.h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 핸들
                              Center(
                                child: Container(
                                  width: 40.w,
                                  height: 4.h,
                                  decoration: BoxDecoration(
                                    color: p.secondaryText,
                                    borderRadius: BorderRadius.circular(2.r),
                                  ),
                                ),
                              ),
                              SizedBox(height: 16.h),

                              // 제목
                              Text(
                                context.l10n.alarmRegistered,
                                style: TextStyle(
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.bold,
                                  color: p.text,
                                ),
                              ),
                              SizedBox(height: 16.h),

                              // 알람 목록
                              Expanded(
                                child: alarmsAsync.when(
                                  loading: () => Center(child: AppUiLoading()),
                                  error: (_, __) => Center(
                                      child: Text(
                                          context.l10n.statusErrorOccurred)),
                                  data: (alarms) {
                                    final now = DateTime.now();
                                    final futureAlarms = alarms
                                        .where((a) =>
                                            a.date != null &&
                                            a.date!.isAfter(now))
                                        .toList()
                                      ..sort(
                                          (a, b) => a.date!.compareTo(b.date!));

                                    if (futureAlarms.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.alarm_off_rounded,
                                              size: 48.sp,
                                              color: p.secondaryText,
                                            ),
                                            SizedBox(height: 12.h),
                                            Text(
                                              context.l10n.alarmNoneRegistered,
                                              style: TextStyle(
                                                fontSize: 15.sp,
                                                color: p.secondaryText,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return ListView.builder(
                                      controller: scrollController,
                                      itemCount: futureAlarms.length,
                                      itemBuilder: (itemContext, index) {
                                        final alarm = futureAlarms[index];
                                        // ⭐ 이 itemBuilder가 제공하는 자기 자신의 context를 씀
                                        // (바깥 State의 context가 아니라, 이 목록 항목 자체의
                                        // context - 항목이 화면에 남아있는 한 항상 유효함).
                                        return _buildAlarmListItem(
                                            itemContext, alarm, index == 0);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ));
      },
    );
  }

  // ⭐ 알람 목록 아이템 (context는 호출부의 itemBuilder가 준 것을 그대로 받아 씀)
  Widget _buildAlarmListItem(BuildContext context, Alarm alarm, bool isNext) {
    if (alarm.date == null) {
      return SizedBox.shrink();
    }

    final date = alarm.date!;
    final p = AppUiPalette.of(context);
    // ⭐ 영어 현지화 후속 수정: DateFormat.Md(locale)는 로케일에 따라 구분자가
    // 달라짐(예: ko → "8. 15.", en → "8/15") - 한국어 사용자에게 기존에 없던
    // 시각적 변화(점 구분자)가 새로 생기는 회귀였음. 순수 숫자 M/d 표기는 두
    // 언어 다 같은 순서(월/일)라 로케일 분기 없이 고정 "8/15" 형식으로 통일함
    // (work_hours_settings_provider.dart의 periodRangeShort와 동일한 판단).
    final dateStr = context.usesKoreanFeatures
        ? '${date.month}/${date.day} (${weekdayLabel(context, weekdayIndexOf(date))})'
        : DateFormat.MMMEd(Localizations.localeOf(context).toString())
            .format(date);
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: isNext ? p.soft : p.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isNext ? p.primary : p.border,
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // 날짜
          Container(
            width: 75.w,
            child: Text(
              [
                dateStr,
                if (alarm.type == 'snoozed') context.l10n.alarmSnoozedLabel,
                if (alarmClockLabel(context, date) case final String label)
                  label,
              ].join('\n'),
              style: TextStyle(
                fontSize: 13.sp,
                color: p.secondaryText,
              ),
            ),
          ),
          SizedBox(width: 8.w),

          // 시간
          Container(
            width: 60.w,
            child: Text(
              timeStr,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: isNext ? p.primary : p.text,
              ),
            ),
          ),
          SizedBox(width: 12.w),

          // 좁은 창과 큰 글자에서는 근무명/알람 종류를 두 줄로 배치한다.
          // 날짜와 시각의 고정 폭 뒤에 남은 공간만 사용해 목록 우측 넘침을 막는다.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8.w,
              runSpacing: 6.h,
              children: [
                // 근무 타입
                // ⭐ 2026-09-23 (1.0.24 B) - 커스텀 알람은 근무명이 없으므로 "커스텀 알람"으로 표시
                if (alarm.shiftType != null)
                  AppUiShiftChip(
                      name: alarm.shiftType!, size: AppChipSize.compact),

                // 알람 타입 표시 (소리/진동/무음)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: isNext ? p.primary : p.soft,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        alarm.alarmTypeId == 1
                            ? Icons.volume_up
                            : alarm.alarmTypeId == 2
                                ? Icons.vibration
                                : Icons.volume_off,
                        size: 14.sp,
                        color: isNext ? p.onPrimary : p.text,
                      ),
                      SizedBox(width: 5.w),
                      Flexible(
                          child: Text(
                        alarm.alarmTypeId == 1
                            ? context.l10n.alarmSoundShort
                            : alarm.alarmTypeId == 2
                                ? context.l10n.alarmVibration
                                : context.l10n.alarmSilent,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                          color: isNext ? p.onPrimary : p.text,
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmDisplayWidget extends ConsumerStatefulWidget {
  final Alarm alarm;
  final VoidCallback onDismiss;
  final VoidCallback onShowAllAlarms;

  const _AlarmDisplayWidget({
    required this.alarm,
    required this.onDismiss,
    required this.onShowAllAlarms,
  });

  @override
  ConsumerState<_AlarmDisplayWidget> createState() =>
      _AlarmDisplayWidgetState();
}

class _AlarmDisplayWidgetState extends ConsumerState<_AlarmDisplayWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
  }

  @override
  void didUpdateWidget(covariant _AlarmDisplayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ⭐ "다음 알람" 자체가 바뀌면(예: 지금 알람을 끄고 그다음 알람으로 넘어감)
    // 새 알람 기준으로 다시 스케줄 - 예전 알람 기준 간격이 새 알람엔 안 맞을 수 있음.
    if (oldWidget.alarm.date != widget.alarm.date) {
      _scheduleNextTick();
    }
  }

  // ⭐ 2026-08-25 추가 - "남은 시간" 텍스트를 고정 1분 간격 대신, 알람까지 남은
  // 시간에 맞춰 간격을 스스로 조절하는 "스마트" 재갱신으로 바꿈. 1일 넘게 남은
  // 알람을 분 단위로 다시 그릴 필요는 없고("1일 후" 표시는 몇 시간 동안 그대로임),
  // 반대로 임박했을 땐 더 촘촘하게 갱신되는 게 자연스러움 - Timer.periodic(고정
  // 간격) 대신 매번 다음 간격을 다시 계산해서 Timer(...)를 새로 거는 자기 재스케줄
  // 방식(self-rescheduling). setState()는 이 위젯 하나만 다시 그리므로(부모
  // NextAlarmTab이나 파도 배경까지 재구성되지 않음) 예전에 상위 탭 레벨 60초
  // 타이머가 매분 화면 전체를 다시 그리던 것과 달리 화면 깜빡임 걱정도 없음.
  void _scheduleNextTick() {
    _timer?.cancel();
    final alarmDate = widget.alarm.date;
    if (alarmDate == null) return;
    final remaining = alarmDate.difference(DateTime.now());
    _timer = Timer(_adaptiveTickInterval(remaining), () {
      if (mounted) {
        setState(() {});
        _scheduleNextTick();
      }
    });
  }

  static Duration _adaptiveTickInterval(Duration remaining) {
    // ⭐ 2026-08-25 재조정 - "1시간 미만이어도 30초 이내에는 바뀌어야지" 요청.
    // 순수 로컬 setState(DB/네트워크 재조회 전혀 없음, alarm.date는 이미 갖고
    // 있는 값)라 15초 간격 비용은 무시할 만한 수준 - "임박(2분 미만)"과
    // "1시간 미만" 구간을 합쳐서 둘 다 15초로 통일.
    if (remaining.isNegative || remaining.inHours < 1) {
      return const Duration(seconds: 15); // 분 단위 표시가 바뀔 수 있는 구간 - 촘촘하게
    } else if (remaining.inHours < 24) {
      return const Duration(minutes: 5); // 시간 단위 표시 - 5분이면 충분
    } else {
      return const Duration(minutes: 30); // "N일 후" - 아주 가끔만 갱신
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _getTimeUntilData(
      BuildContext context, DateTime alarmTime) {
    final now = DateTime.now();
    final diff = alarmTime.difference(now);

    if (diff.isNegative) {
      return {'text': context.l10n.alarmRingingSoon, 'isImminent': true};
    }

    final totalSeconds = diff.inSeconds;
    final totalMinutes = (totalSeconds / 60).ceil();

    if (totalMinutes <= 1) {
      return {'text': context.l10n.alarmRingingSoon, 'isImminent': true};
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    String text;
    // ⭐ 24시간 이상이면 일 단위로 표시
    if (hours >= 24) {
      final days = hours ~/ 24;
      final remainingHours = hours % 24;
      if (remainingHours > 0) {
        text = context.l10n.alarmRemainingDaysHours(days, remainingHours);
      } else {
        text = context.l10n.alarmRemainingDays(days);
      }
    } else if (hours > 0) {
      if (minutes > 0) {
        text = context.l10n.alarmRemainingHoursMinutes(hours, minutes);
      } else {
        text = context.l10n.alarmRemainingHours(hours);
      }
    } else {
      text = context.l10n.alarmRemainingMinutes(minutes);
    }

    return {
      'text': text,
      'isImminent': totalMinutes <= 30,
    };
  }

  String _getDateLabel(BuildContext context, DateTime alarmDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final alarmDay = DateTime(alarmDate.year, alarmDate.month, alarmDate.day);

    if (alarmDay == today) {
      return context.l10n.commonToday;
    } else if (alarmDay == tomorrow) {
      return context.l10n.commonTomorrow;
    } else {
      // ⭐ 위 _buildAlarmListItem과 동일한 이유로 고정 숫자 M/d 형식 사용.
      return context.usesKoreanFeatures
          ? '${alarmDate.month}/${alarmDate.day} (${weekdayLabel(context, weekdayIndexOf(alarmDate))})'
          : DateFormat.MMMEd(Localizations.localeOf(context).toString())
              .format(alarmDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final p = AppUiPalette.of(context);
    final timeStr = alarm.date != null
        ? '${alarm.date!.hour.toString().padLeft(2, '0')}:${alarm.date!.minute.toString().padLeft(2, '0')}'
        : alarm.time;

    // ⭐ CRITICAL FIX: null 체크 추가
    if (alarm.date == null) {
      return SizedBox.shrink();
    }

    final timeData = _getTimeUntilData(context, alarm.date!);
    final statusLabel = [
      if (alarm.type == 'snoozed') context.l10n.alarmSnoozedLabel,
      if (alarmClockLabel(context, alarm.date!) case final String label) label,
    ].join(' · ');
    final dateLabel = [
      _getDateLabel(context, alarm.date!),
      if (statusLabel.isNotEmpty) statusLabel
    ].join('\n');

    // Imminence uses the common selection emphasis; alarm behavior is unchanged.
    final isImminent = timeData['isImminent'] as bool;
    final onCardColor = isImminent ? p.selectionOutline : p.text;
    const typeIds = [1, 2, 3];
    final typeIcons = [
      Icons.volume_up_rounded,
      Icons.vibration_rounded,
      Icons.notifications_off_rounded
    ];
    final typeLabels = [
      context.l10n.alarmSoundVibration,
      context.l10n.alarmVibration,
      context.l10n.alarmSilent
    ];
    final layout = AppLayout.of(context);
    final ringSize = layout.isWide
        ? math.min(layout.isSquare ? 360.0 : 300.0,
            (layout.window.width - 80) * (layout.isSquare ? 0.5 : 4 / 9))
        : layout.isShortCover
            ? 190.w
            : 238.w;

    return SafeArea(
      // The ring yields height before controls. A bounded phone column needs no scrolling.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: LayoutBuilder(
            builder: (context, viewport) => AdaptiveHeroViewport(
                  padding: EdgeInsets.fromLTRB(
                      AppUiMetrics.pagePadding.w,
                      AppUiMetrics.gap.h,
                      AppUiMetrics.pagePadding.w,
                      AppUiMetrics.gap.h),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: layout.isWide
                            ? math.max(0, viewport.maxHeight - 60.h)
                            : 0),
                    child: AdaptiveHeroLayout(
                      distributeVerticalSpace: true,
                      flexibleIndex: 2,
                      splitIndex: (alarm.shiftType != null) ? 6 : 5,
                      children: [
                        Row(
                          children: [
                            Text(context.l10n.alarmUpNext,
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w700,
                                    color: p.secondaryText)),
                          ],
                        ),
                        SizedBox(height: AppUiMetrics.compactCardPadding.h),

                        // ⭐ "UI 테마" 탭에서 확정한 카운트다운 링. 알람 12시간 전부터
                        // 채워지기 시작해서 알람 시각에 근접함(=임박 표시). 알람이 실제로
                        // 울리기 전에는 절대 100%로 보이지 않도록 최대 96%까지만 채움
                        // (_CountdownRing 참고 - 12시간짜리 창의 마지막 1분은 수학적으로도
                        // 99.86%라 육안으로는 꽉 찬 것처럼 보였던 문제 수정). 화면을 보고
                        // 있는 동안 15초 간격으로 계속 조금씩 움직이고, 탭을 나갔다
                        // 들어와도 리셋되지 않음(progress는 항상 "지금 vs 알람 시각"의
                        // 순수 계산값이라 위젯이 언제 새로 만들어졌는지와 무관).
                        SizedBox(
                            width: ringSize,
                            height: ringSize,
                            child: FittedBox(
                                child: SizedBox(
                              width: 238.w,
                              height: 238.w,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  _CountdownRing(
                                    size: 238.w,
                                    strokeWidth: 14.w,
                                    alarmTime: alarm.date!,
                                    color: p.primary,
                                    trackColor: p.border,
                                  ),
                                  Container(
                                    width: 188.w,
                                    height: 188.w,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: p.surface,
                                      border: Border.all(color: p.border),
                                    ),
                                    child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 11.w,
                                                  vertical: 4.h),
                                              decoration: BoxDecoration(
                                                  color: p.soft,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20.r)),
                                              child: Text(dateLabel,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontSize: 12.sp,
                                                      color: p.primary,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                            SizedBox(height: 7.h),
                                            Text(timeStr,
                                                style: TextStyle(
                                                    fontSize: 33.sp,
                                                    fontWeight: FontWeight.w800,
                                                    color: p.primary)),
                                          ],
                                        )),
                                  ),
                                ],
                              ),
                            ))),

                        SizedBox(height: 16.h),

                        if (alarm.shiftType != null)
                          AppUiShiftChip(name: alarm.shiftType!),

                        SizedBox(height: AppUiMetrics.gap.h),

                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 남은 시간 카드
                              Expanded(
                                child: Container(
                                  padding: EdgeInsets.all(16.w),
                                  decoration: BoxDecoration(
                                      color: p.surface,
                                      border: Border.all(color: p.border),
                                      borderRadius:
                                          BorderRadius.circular(20.r)),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.timer_outlined,
                                          size: 21.sp, color: onCardColor),
                                      SizedBox(height: 9.h),
                                      Text(context.l10n.alarmUntil,
                                          style: TextStyle(
                                              fontSize: 11.sp,
                                              color: p.secondaryText)),
                                      SizedBox(height: 2.h),
                                      Wrap(
                                        spacing: 4.w,
                                        children: (timeData['text'] as String)
                                            .split(' ')
                                            .map((part) => Text(part,
                                                style: TextStyle(
                                                    fontSize: 15.sp,
                                                    fontWeight: FontWeight.w800,
                                                    color: onCardColor)))
                                            .toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: 14.w),
                              // 알람 타입 선택 카드
                              Expanded(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12.w, vertical: 14.h),
                                  decoration: BoxDecoration(
                                      color: p.surface,
                                      border: Border.all(color: p.border),
                                      borderRadius:
                                          BorderRadius.circular(20.r)),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(3, (i) {
                                      final selected =
                                          alarm.alarmTypeId == typeIds[i];
                                      return Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 4.h),
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _onTypeSelected(
                                              alarm.id!, typeIds[i]),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 26.w,
                                                height: 26.w,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                    color: selected
                                                        ? p.primary
                                                        : Colors.transparent,
                                                    shape: BoxShape.circle),
                                                child: Icon(typeIcons[i],
                                                    size: 14.sp,
                                                    color: selected
                                                        ? p.onPrimary
                                                        : p.secondaryText),
                                              ),
                                              SizedBox(width: 7.w),
                                              Expanded(
                                                child: Text(
                                                  typeLabels[i],
                                                  style: TextStyle(
                                                      fontSize: 11.sp,
                                                      color: selected
                                                          ? p.text
                                                          : p.secondaryText,
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w400),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: AppUiMetrics.gap.h),

                        SizedBox(
                          width: double.infinity,
                          child: AppUiButton(
                            emphasized: true,
                            action: AppUiAction.secondary,
                            onPressed: widget.onShowAllAlarms,
                            icon: Icons.list_rounded,
                            label: context.l10n.alarmViewAllRegistered,
                          ),
                        ),
                        SizedBox(height: AppUiMetrics.dialogActionGap.h),
                        SizedBox(
                          width: double.infinity,
                          child: AppUiButton(
                            emphasized: true,
                            action: AppUiAction.danger,
                            onPressed: widget.onDismiss,
                            icon: Icons.alarm_off_rounded,
                            label: context.l10n.alarmTurnOffThis,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
      ),
    );
  }

  Future<void> _onTypeSelected(int alarmId, int typeId) async {
    if (!mounted) return;
    await ref
        .read(alarmNotifierProvider.notifier)
        .updateAlarmType(alarmId, typeId);
    if (!mounted) return;
  }

  // ⭐ 2026-08-25 - 옛 3버튼 큰 카드 디자인은 "UI 테마" 탭에서 확정한 컴팩트
  // 원형 아이콘 리스트(알람 타입 카드 안에 인라인)로 교체되며 삭제함
  // (build() 참고).
}

/// ⭐ 카운트다운 링 - 알람 시각 12시간 전을 0%, 알람 시각을 정확히 100%로 놓고
/// 진행률을 "지금 시각 vs 알람 시각" 둘만으로 순수 계산함(위젯이 언제
/// mount됐는지와 전혀 무관). 그래서:
///   - 다음 알람 탭을 나갔다 다시 들어와도 절대 0%로 리셋되지 않음(진행률
///     계산이 마운트 시점에 기대지 않으므로).
///   - 알람이 실제로 울리기 전(now < alarmTime)에는 remaining이 항상 양수라
///     progress가 수학적으로 절대 1.0에 도달하지 않음 - 1.0은 딱 그 순간에만.
/// 화면을 보고 있는 동안 "자연히 계속 조금씩" 움직이는 것처럼 보이게 하려고
/// 15초마다 다시 그림. 링이 24시간에 걸쳐 채워지는 속도를 감안하면 15초
/// 간격도 눈으로는 완전히 매끄럽게 보이고, 화면이 켜져 있는 몇 시간 내내
/// 매 프레임(60fps)을 다시 그리는 것보다 배터리 부담이 훨씬 적음.
class _CountdownRing extends StatefulWidget {
  const _CountdownRing(
      {required this.size,
      required this.strokeWidth,
      required this.alarmTime,
      required this.color,
      required this.trackColor});

  final double size;
  final double strokeWidth;
  final DateTime alarmTime;
  final Color color;
  final Color trackColor;

  @override
  State<_CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<_CountdownRing> {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  // ⭐ 2026-08-25 - "알람이 울지도 않았는데 링이 꽉 차 보인다"는 피드백으로
  // 확인한 결과: 수학적으로는 알람 시각 전엔 항상 progress<1.0이 맞았지만(예:
  // 1분 전엔 99.86%), 12시간짜리 창 기준 0.14%는 두꺼운 링 선 두께보다도
  // 작아서 육안으로는 이미 다 찬 것처럼 보였음. 그래서 알람이 실제로 울리기
  // 전(remaining>0)에는 최대 96%까지만 채우도록 상한을 둠 - 남은 4%가 실제
  // 화면에서 또렷하게 보이는 틈으로 남아서, "아직 안 울렸다"는 게 눈으로도
  // 확실히 구분됨. 100%는 remaining<=0(=알람이 실제로 울린 순간)에만 나옴.
  static const double _maxProgressBeforeRinging = 0.96;

  double get _progress {
    // ⭐ 2026-09-01 - "24시간부터 링이 움직이게" 요청으로 12h → 24h. 비율
    // 계산식(raw = 1 - remaining/window) 자체는 그대로라 창 길이만 늘어난
    // 만큼 자동으로 더 천천히 채워짐(다른 값 손볼 필요 없음).
    const window = Duration(hours: 24);
    final remaining = widget.alarmTime.difference(DateTime.now());
    if (remaining.isNegative) return 1.0;
    if (remaining >= window) return 0.0;
    final raw = 1.0 - (remaining.inSeconds / window.inSeconds);
    return raw.clamp(0.0, _maxProgressBeforeRinging);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.size, widget.size),
      painter: _RingPainter(
          progress: _progress,
          color: widget.color,
          trackColor: widget.trackColor,
          strokeWidth: widget.strokeWidth),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(
      {required this.progress,
      required this.color,
      required this.trackColor,
      required this.strokeWidth});

  final double progress; // 0..1
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * progress;
    // -pi/2 = 12시 방향에서 시작, 시계 방향으로 sweep만큼 채움.
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, sweep, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
