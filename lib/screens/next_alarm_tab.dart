// lib/screens/next_alarm_tab.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/alarm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alarm_provider.dart';
import '../l10n/l10n_extensions.dart';
import '../utils/weekday_util.dart';
import '../constants/platform_channel.dart';
import '../theme/app_colors.dart';
import '../widgets/app_second_button.dart';
import '../widgets/app_third_button.dart';


class NextAlarmTab extends ConsumerStatefulWidget {
  final VoidCallback? onSwipeToCalendar;  // ⭐ 6번 기능: 스와이프 callback

  const NextAlarmTab({super.key, this.onSwipeToCalendar});

  @override
  ConsumerState<NextAlarmTab> createState() => _NextAlarmTabState();
}

class _NextAlarmTabState extends ConsumerState<NextAlarmTab> {
  Timer? _countdownTimer;
  Timer? _syncTimer;
  static const platform = kAlarmChannel;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // ⭐ 오버레이/잠금화면에서 알람을 끄기/스누즈하면 Native가 브로드캐스트로
    // Flutter에 갱신 신호를 보내긴 하는데, 그 경로(브로드캐스트 → MethodChannel →
    // Provider)가 여러 단계를 거치다 보니 타이밍에 따라 이 탭이 바로 못 따라갈 수
    // 있음. 이 탭이 떠 있는 동안 짧은 주기로 직접 재조회해서, 브로드캐스트가
    // 어떤 이유로 늦거나 씹혀도 몇 초 안에 실제 알람 상태(꺼짐/스누즈)와 항상
    // 일치하게 만듦.
    _syncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) ref.read(alarmNotifierProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _dismissAlarm(int id, DateTime? date) async {
    try {
      await platform.invokeMethod('dismissOverlay', {'alarmId': id});
    } catch (e) {
      print('⚠️ Overlay 종료 신호 실패: $e');
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.alarmCanceledToast),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextAlarmAsync = ref.watch(nextAlarmProvider);

    return GestureDetector(
      // ⭐ 6번 기능: 우→좌 스와이프로 달력탭 이동
      onHorizontalDragEnd: (details) {
        if (widget.onSwipeToCalendar != null && details.primaryVelocity != null) {
          // 우→좌 스와이프 (velocity < 0)
          if (details.primaryVelocity! < -500) {
            widget.onSwipeToCalendar!();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // ⭐ 2026-08-25 - "UI 테마" 탭에서 확정한 "오로라 페일" 그라데이션을 이
        // 탭 배경 전체에 씀(아이콘/잠금화면/오버레이와 같은 톤).
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: kAppAlarmGradient),
          ),
          child: nextAlarmAsync.when(
            loading: () => const SizedBox.shrink(),  // ⭐ 로딩 인디케이터 제거
            error: (error, stack) => _buildEmptyState(),
            data: (nextAlarm) {
              if (nextAlarm == null) {
                return _buildEmptyState();
              }
              return _AlarmDisplayWidget(
                alarm: nextAlarm,
                onDismiss: () => _dismissAlarm(nextAlarm.id!, nextAlarm.date),
                onShowAllAlarms: () => _showAllAlarmsSheet(context),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120.w,
              height: 120.w,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.alarm_off_rounded,
                size: 60.sp,
                color: colorScheme.outline,
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              context.l10n.alarmNoneUpcoming,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              context.l10n.alarmEmptyStateHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) {
        // ⭐ 여기서 refresh - 안전한 context에서 호출
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(alarmNotifierProvider.notifier).refresh();
        });

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Consumer(
              builder: (context, ref, child) {
                final alarmsAsync = ref.watch(alarmNotifierProvider);
                final colorScheme = Theme.of(context).colorScheme;

                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 핸들
                      Center(
                        child: Container(
                          width: 40.w,
                          height: 4.h,
                          decoration: BoxDecoration(
                            color: colorScheme.outline,
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
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 16.h),

                      // 알람 목록
                      Expanded(
                        child: alarmsAsync.when(
                          loading: () => Center(child: CircularProgressIndicator()),
                          error: (_, __) => Center(child: Text(context.l10n.statusErrorOccurred)),
                          data: (alarms) {
                            final now = DateTime.now();
                            final futureAlarms = alarms
                                .where((a) => a.date != null && a.date!.isAfter(now))
                                .toList()
                              ..sort((a, b) => a.date!.compareTo(b.date!));

                            if (futureAlarms.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.alarm_off_rounded,
                                      size: 48.sp,
                                      color: colorScheme.outline,
                                    ),
                                    SizedBox(height: 12.h),
                                    Text(
                                      context.l10n.alarmNoneRegistered,
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        color: colorScheme.onSurfaceVariant,
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
                                return _buildAlarmListItem(itemContext, alarm, index == 0);
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
        );
      },
    );
  }

  // ⭐ 알람 목록 아이템 (context는 호출부의 itemBuilder가 준 것을 그대로 받아 씀)
  Widget _buildAlarmListItem(BuildContext context, Alarm alarm, bool isNext) {
    if (alarm.date == null) {
      return SizedBox.shrink();
    }

    final date = alarm.date!;
    final colorScheme = Theme.of(context).colorScheme;
    // ⭐ 영어 현지화 후속 수정: DateFormat.Md(locale)는 로케일에 따라 구분자가
    // 달라짐(예: ko → "8. 15.", en → "8/15") - 한국어 사용자에게 기존에 없던
    // 시각적 변화(점 구분자)가 새로 생기는 회귀였음. 순수 숫자 M/d 표기는 두
    // 언어 다 같은 순서(월/일)라 로케일 분기 없이 고정 "8/15" 형식으로 통일함
    // (work_hours_settings_provider.dart의 periodRangeShort와 동일한 판단).
    final dateStr = '${date.month}/${date.day} (${weekdayLabel(context, weekdayIndexOf(date))})';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: isNext ? colorScheme.primary.withOpacity(0.1) : colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isNext ? colorScheme.primary.withOpacity(0.3) : colorScheme.outline.withOpacity(0.3),
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // 날짜
          Container(
            width: 75.w,
            child: Text(
              dateStr,
              style: TextStyle(
                fontSize: 13.sp,
                color: colorScheme.onSurfaceVariant,
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
                color: isNext ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),
          SizedBox(width: 12.w),

          // 근무 타입
          if (alarm.shiftType != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: isNext ? colorScheme.primary.withOpacity(0.2) : colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                alarm.shiftType!,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: isNext ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          Spacer(),

          // 알람 타입 표시 (소리/진동/무음)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: isNext ? colorScheme.primary : colorScheme.outline,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  alarm.alarmTypeId == 1 ? Icons.volume_up :
                  alarm.alarmTypeId == 2 ? Icons.vibration :
                  Icons.volume_off,
                  size: 14.sp,
                  color: isNext ? colorScheme.surface : colorScheme.onSurface,
                ),
                SizedBox(width: 5.w),
                Text(
                  alarm.alarmTypeId == 1 ? context.l10n.alarmSoundShort :
                  alarm.alarmTypeId == 2 ? context.l10n.alarmVibration : context.l10n.alarmSilent,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                    color: isNext ? colorScheme.surface : colorScheme.onSurface,
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
  ConsumerState<_AlarmDisplayWidget> createState() => _AlarmDisplayWidgetState();
}

class _AlarmDisplayWidgetState extends ConsumerState<_AlarmDisplayWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _getTimeUntilData(BuildContext context, DateTime alarmTime) {
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

  /// 카운트다운 링 진행률(0..1). 알람 12시간 전까지는 0(빈 링) - 그 안으로
  /// 들어오면 서서히 채워지기 시작해서 알람 시각에 정확히 1(완전히 채워짐 =
  /// 임박)이 됨. 창(window)을 12시간으로 잡은 건 교대근무 알람이 보통 전날
  /// 저녁~당일 새벽 사이에 맞춰지는 걸 감안한 값 - 그보다 훨씬 먼 알람은 계속
  /// 빈 링으로 있다가, 반나절 안쪽부터 "다가오고 있다"는 느낌을 주기 시작함.
  double _ringProgress(DateTime alarmTime) {
    const window = Duration(hours: 12);
    final remaining = alarmTime.difference(DateTime.now());
    if (remaining.isNegative) return 1.0;
    if (remaining >= window) return 0.0;
    return 1.0 - (remaining.inSeconds / window.inSeconds);
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
      return '${alarmDate.month}/${alarmDate.day} (${weekdayLabel(context, weekdayIndexOf(alarmDate))})';
    }
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final colorScheme = Theme.of(context).colorScheme;
    final timeStr = alarm.date != null
        ? '${alarm.date!.hour.toString().padLeft(2, '0')}:${alarm.date!.minute.toString().padLeft(2, '0')}'
        : alarm.time;

    // ⭐ CRITICAL FIX: null 체크 추가
    if (alarm.date == null) {
      return SizedBox.shrink();
    }

    final timeData = _getTimeUntilData(context, alarm.date!);
    final dateLabel = _getDateLabel(context, alarm.date!);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
        child: Column(
          children: [
            SizedBox(height: 8.h),

            Text(
              context.l10n.alarmUpNext,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
            ),

            SizedBox(height: 18.h),

            // ⭐ 2026-08-25 - "UI 테마" 탭에서 확정한 카운트다운 링 디자인. 알람
            // 시각 12시간 전부터 링이 채워지기 시작해서, 알람 시각에 완전히
            // 채워짐(=임박 표시). 값이 바뀔 때마다 부드럽게 이어서 애니메이션됨
            // (_CountdownRing 참고).
            SizedBox(
              width: 202.w,
              height: 202.w,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _CountdownRing(
                    size: 202.w,
                    strokeWidth: 12.w,
                    progress: _ringProgress(alarm.date!),
                    color: kAppRingAccent,
                    trackColor: colorScheme.onSurface.withOpacity(0.12),
                  ),
                  Container(
                    width: 160.w,
                    height: 160.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 6))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(20.r)),
                          child: Text(dateLabel, style: TextStyle(fontSize: 11.sp, color: colorScheme.primary, fontWeight: FontWeight.w700)),
                        ),
                        SizedBox(height: 6.h),
                        Text(timeStr, style: TextStyle(fontSize: 30.sp, fontWeight: FontWeight.w800, color: colorScheme.primary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 14.h),

            // 근무 타입 뱃지
            if (alarm.shiftType != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Text(
                  alarm.shiftType!,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ),

            SizedBox(height: 18.h),

            // 남은 시간 카드
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(18.w),
              decoration: BoxDecoration(
                color: timeData['isImminent']
                    ? colorScheme.tertiary.withOpacity(0.1)
                    : colorScheme.surface,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: timeData['isImminent']
                      ? colorScheme.tertiary.withOpacity(0.3)
                      : colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46.w,
                    height: 46.w,
                    decoration: BoxDecoration(
                      color: timeData['isImminent']
                          ? colorScheme.tertiary.withOpacity(0.2)
                          : colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.timer_outlined,
                      size: 24.sp,
                      color: timeData['isImminent']
                          ? colorScheme.tertiary
                          : colorScheme.primary,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.alarmUntil,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          timeData['text'],
                          style: TextStyle(
                            fontSize: 19.sp,
                            fontWeight: FontWeight.bold,
                            color: timeData['isImminent']
                                ? colorScheme.tertiary
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 14.h),

            // 알람 타입 선택 카드
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(18.w),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.alarmType,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 14.h),
                  Row(
                    children: [
                      _buildTypeSelectButton(
                        typeId: 1,
                        icon: Icons.volume_up_rounded,
                        label: context.l10n.alarmSoundVibration,
                        isSelected: alarm.alarmTypeId == 1,
                        onTap: () => _onTypeSelected(alarm.id!, 1),
                      ),
                      SizedBox(width: 10.w),
                      _buildTypeSelectButton(
                        typeId: 2,
                        icon: Icons.vibration_rounded,
                        label: context.l10n.alarmVibration,
                        isSelected: alarm.alarmTypeId == 2,
                        onTap: () => _onTypeSelected(alarm.id!, 2),
                      ),
                      SizedBox(width: 10.w),
                      _buildTypeSelectButton(
                        typeId: 3,
                        icon: Icons.notifications_off_rounded,
                        label: context.l10n.alarmSilent,
                        isSelected: alarm.alarmTypeId == 3,
                        onTap: () => _onTypeSelected(alarm.id!, 3),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: 12.h),

            // ⭐ 전체 알람 보기 버튼 (알람 타입 카드 아래, 우측 정렬) - "UI 테마"
            // 탭에서 확정한 AppThirdButton 컨셉으로 교체.
            Align(
              alignment: Alignment.centerRight,
              child: AppThirdButton(
                compact: true,
                onPressed: widget.onShowAllAlarms,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_alt_rounded, size: 16),
                    SizedBox(width: 6.w),
                    Text(context.l10n.alarmViewAllRegistered),
                  ],
                ),
              ),
            ),

            Spacer(),

            // 알람 취소 버튼 - "UI 테마" 탭에서 확정한 AppSecondButton(danger)
            // 컨셉으로 교체.
            SizedBox(
              width: double.infinity,
              child: AppSecondButton(
                variant: AppSecondButtonVariant.danger,
                onPressed: widget.onDismiss,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.alarm_off_rounded, size: 18),
                    SizedBox(width: 8.w),
                    Text(context.l10n.alarmTurnOffThis),
                  ],
                ),
              ),
            ),

            SizedBox(height: 12.h),
          ],
        ),
      ),
    );
  }

  Future<void> _onTypeSelected(int alarmId, int typeId) async {
    if (!mounted) return;
    await ref.read(alarmNotifierProvider.notifier).updateAlarmType(alarmId, typeId);
    if (!mounted) return;
  }

  Widget _buildTypeSelectButton({
    required int typeId,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary.withOpacity(0.1) : colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24.sp,
                color: isSelected ? colorScheme.primary : colorScheme.outline,
              ),
              SizedBox(height: 6.h),
              // ⭐ 영어 UI 레이아웃 수정: "Sound + Vibration"이 이 좁은(3등분)
              // 버튼 폭에서 두 줄로 줄바꿈되면서 이 버튼이 포함된 Row 전체 높이가
              // 늘어나고, 그만큼 아래 Spacer()가 흡수할 공간이 줄어들어 맨 아래
              // "Turn Off This Alarm" 버튼이 하단 내비게이션 바에 거의 붙어보이는
              // 문제가 있었음. 처음엔 한 줄+말줄임표("Sound + V...")로 급하게
              // 막았는데, "소리+진동"이라는 의미(진동도 같이 울린다는 사실)가
              // 잘려서 사용자가 오해할 수 있다는 지적으로 재수정 - 대신 세 버튼
              // 라벨 자리를 전부 "2줄 높이"로 고정해서, 짧은 라벨("Vibration",
              // "Silent")은 가운데 정렬로 1줄만 차지하고 긴 라벨("Sound +
              // Vibration")은 잘리지 않고 2줄로 자연스럽게 줄바꿈되면서도, 세
              // 버튼 높이가 항상 똑같이 유지되어 Row 전체 높이가 안 흔들림.
              SizedBox(
                height: 30.h,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.sp,
                      height: 1.15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ⭐ 카운트다운 링. progress(0..1)가 바뀔 때마다 마지막 값에서 새 값으로
/// 부드럽게 이어서 애니메이션됨(TweenAnimationBuilder가 알아서 처리 - end만
/// 계속 갱신하면 매번 새 애니메이션을 만들지 않고 현재 값에서 이어 감).
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.size, required this.strokeWidth, required this.progress, required this.color, required this.trackColor});

  final double size;
  final double strokeWidth;
  final double progress;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return CustomPaint(
          size: Size(size, size),
          painter: _RingPainter(progress: value, color: color, trackColor: trackColor, strokeWidth: strokeWidth),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.trackColor, required this.strokeWidth});

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
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweep, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
}
