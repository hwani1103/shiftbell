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
        // ⭐ 2026-08-25 - 정적 그라데이션 대신 잠금화면/오버레이(WaveGradientView.kt)와
        // 동일한 "각도가 계속 회전하는" 파도 애니메이션을 Flutter 쪽에도 이식.
        // 네이티브는 커스텀 View.onDraw()에서 매 프레임 LinearGradient(Shader)를
        // 다시 그리는 방식이지만, Flutter는 AnimationController + Alignment 회전으로
        // 같은 효과를 냄(13초 주기, 대비를 높인 동일 팔레트 - kAppWaveGradientColors).
        // SizedBox.expand로 명시적으로 꽉 채움 - 스크롤 콘텐츠가 화면보다 짧을 때
        // 그 아래로 흰 배경(바깥 Scaffold 기본색)이 비쳐 보이던 문제 방지(광고
        // 슬롯처럼 보였다는 피드백의 원인).
        body: SizedBox.expand(
          child: _WaveGradientBackground(
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

    // ⭐ 2026-08-25 4차 수정 - (1) 링 색은 "임박" 여부와 무관하게 항상
    // kAppRingAccent 고정(전엔 임박 시 tertiary(주황)로 바뀌게 했는데, 이건
    // 목업에 없던 임의 추가였음 - 목업의 링은 항상 고정색). "남은 시간" 카드의
    // 아이콘/텍스트만 임박 시 강조색으로 바뀌는 건 실제 앱 원래 동작이라 유지.
    // (2) 흰 여백을 아래로 밀어내려던 문제(SizedBox.expand로 해결, build()
    // 상단 참고)로 확보된 공간에 맞춰 링/카드/버튼을 전체적으로 약 18% 키움.
    final isImminent = timeData['isImminent'] as bool;
    final onCardColor = isImminent ? colorScheme.tertiary : kAppChipBorder;
    const typeIds = [1, 2, 3];
    final typeIcons = [Icons.volume_up_rounded, Icons.vibration_rounded, Icons.notifications_off_rounded];
    final typeLabels = [context.l10n.alarmSoundVibration, context.l10n.alarmVibration, context.l10n.alarmSilent];

    return SafeArea(
      // ⭐ 2026-08-25 3차 수정 - ScrollConfiguration(overscroll:false)로 Material3
      // 스트레치 데코레이션은 없앴는데도 "여전히 아주 살짝 당겨진다"는 재보고를
      // 받음. 남은 원인: 콘텐츠 실제 높이가 뷰포트보다 미세하게(기기별로 몇 px)
      // 더 커서 physics 입장에선 "진짜 오버플로"라 ClampingScrollPhysics가 정상
      // 동작한 것 - 눈에 안 보일 만큼 작은 여분이라 사용자한텐 "굳이 안 내려가도
      // 되는데 내려가지는" 것처럼 느껴짐. _NoTinyOverflowScrollPhysics로 그
      // maxScrollExtent가 아주 작을 때(_tinyOverflowThreshold 미만)는 드래그 자체를
      // 씹어서 진짜 못 내려가게 하고, 그보다 큰 진짜 오버플로(작은 화면 기기 등)는
      // 그대로 정상 스크롤되게 함 - 안전장치는 유지.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: SingleChildScrollView(
        physics: const _NoTinyOverflowScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 28.h),
        child: Column(
          children: [
            Row(
              children: [
                Text(context.l10n.alarmUpNext, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: kAppChipBorder)),
              ],
            ),
            SizedBox(height: 24.h),

            // ⭐ "UI 테마" 탭에서 확정한 카운트다운 링. 알람 12시간 전부터
            // 채워지기 시작해서 알람 시각에 근접함(=임박 표시). 알람이 실제로
            // 울리기 전에는 절대 100%로 보이지 않도록 최대 96%까지만 채움
            // (_CountdownRing 참고 - 12시간짜리 창의 마지막 1분은 수학적으로도
            // 99.86%라 육안으로는 꽉 찬 것처럼 보였던 문제 수정). 화면을 보고
            // 있는 동안 15초 간격으로 계속 조금씩 움직이고, 탭을 나갔다
            // 들어와도 리셋되지 않음(progress는 항상 "지금 vs 알람 시각"의
            // 순수 계산값이라 위젯이 언제 새로 만들어졌는지와 무관).
            SizedBox(
              width: 238.w,
              height: 238.w,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _CountdownRing(
                    size: 238.w,
                    strokeWidth: 14.w,
                    alarmTime: alarm.date!,
                    color: kAppRingAccent,
                    trackColor: kAppChipBorder.withOpacity(0.15),
                  ),
                  Container(
                    width: 188.w,
                    height: 188.w,
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
                          padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 4.h),
                          decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(20.r)),
                          child: Text(dateLabel, style: TextStyle(fontSize: 12.sp, color: colorScheme.primary, fontWeight: FontWeight.w700)),
                        ),
                        SizedBox(height: 7.h),
                        Text(timeStr, style: TextStyle(fontSize: 33.sp, fontWeight: FontWeight.w800, color: colorScheme.primary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16.h),

            if (alarm.shiftType != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20.r)),
                child: Text(alarm.shiftType!, style: TextStyle(fontSize: 14.sp, color: kAppChipBorder, fontWeight: FontWeight.w600)),
              ),

            SizedBox(height: 28.h),

            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 남은 시간 카드
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20.r)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer_outlined, size: 21.sp, color: onCardColor),
                          SizedBox(height: 9.h),
                          Text(context.l10n.alarmUntil, style: TextStyle(fontSize: 11.sp, color: kAppChipBorder.withOpacity(0.6))),
                          SizedBox(height: 2.h),
                          Text(timeData['text'] as String, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800, color: onCardColor)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 14.w),
                  // 알람 타입 선택 카드
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20.r)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          final selected = alarm.alarmTypeId == typeIds[i];
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 4.h),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _onTypeSelected(alarm.id!, typeIds[i]),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26.w,
                                    height: 26.w,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: selected ? colorScheme.primary : Colors.transparent, shape: BoxShape.circle),
                                    child: Icon(typeIcons[i], size: 14.sp, color: selected ? Colors.white : kAppChipBorder.withOpacity(0.4)),
                                  ),
                                  SizedBox(width: 7.w),
                                  Expanded(
                                    child: Text(
                                      typeLabels[i],
                                      style: TextStyle(fontSize: 11.sp, color: kAppChipBorder.withOpacity(selected ? 0.9 : 0.5), fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
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

            SizedBox(height: 26.h),

            SizedBox(
              width: double.infinity,
              child: AppThirdButton(
                onPressed: widget.onShowAllAlarms,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_rounded, size: 18),
                    SizedBox(width: 7.w),
                    Text(context.l10n.alarmViewAllRegistered),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: AppSecondButton(
                variant: AppSecondButtonVariant.danger,
                onPressed: widget.onDismiss,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.alarm_off_rounded, size: 18),
                    SizedBox(width: 7.w),
                    Text(context.l10n.alarmTurnOffThis),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _onTypeSelected(int alarmId, int typeId) async {
    if (!mounted) return;
    await ref.read(alarmNotifierProvider.notifier).updateAlarmType(alarmId, typeId);
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
/// 15초마다 다시 그림. 링이 12시간에 걸쳐 채워지는 속도를 감안하면 15초
/// 간격도 눈으로는 완전히 매끄럽게 보이고, 화면이 켜져 있는 몇 시간 내내
/// 매 프레임(60fps)을 다시 그리는 것보다 배터리 부담이 훨씬 적음.
class _CountdownRing extends StatefulWidget {
  const _CountdownRing({required this.size, required this.strokeWidth, required this.alarmTime, required this.color, required this.trackColor});

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
    const window = Duration(hours: 12);
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
      painter: _RingPainter(progress: _progress, color: widget.color, trackColor: widget.trackColor, strokeWidth: widget.strokeWidth),
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

// ⭐ 2026-08-25 추가 - 잠금화면/오버레이(WaveGradientView.kt)와 같은 "각도가
// 계속 회전하는" 그라데이션 배경을 Flutter 쪽에 이식. 네이티브는 커스텀
// View.onDraw()에서 매 프레임 LinearGradient(Shader)를 다시 만드는 방식이지만,
// Flutter는 그런 저수준 API가 없으므로 AnimationController로 각도값만 계속
// 갱신하고 Container의 LinearGradient(begin/end Alignment)를 매 프레임 다시
// 계산해서 그림 - 시각적으로는 동일한 "천천히 회전하는 대각선 그라데이션" 효과.
// AnimatedBuilder의 child(=실제 알람 콘텐츠)는 애니메이션 값과 무관하므로 매
// 프레임 재사용됨(재빌드 안 됨) - 배경 그라데이션 Container만 매 프레임 다시 그림.
class _WaveGradientBackground extends StatefulWidget {
  final Widget child;
  const _WaveGradientBackground({required this.child});

  @override
  State<_WaveGradientBackground> createState() => _WaveGradientBackgroundState();
}

class _WaveGradientBackgroundState extends State<_WaveGradientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 네이티브(WaveGradientView.kt)와 동일한 13초 회전 주기.
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 13))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // 시작 방향은 기존 정적 배경과 동일한 topLeft→bottomRight(=45°)에서
        // 출발해서 한 바퀴(360°)씩 계속 회전.
        final angle = math.pi / 4 + 2 * math.pi * _controller.value;
        final dx = math.cos(angle);
        final dy = math.sin(angle);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-dx, -dy),
              end: Alignment(dx, dy),
              colors: kAppWaveGradientColors,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

// ⭐ 2026-08-25 추가 - "실제로는 몇 px 남는데 스크롤이 가능은 한" 미세 오버플로를
// 아예 못 내려가게 막는 커스텀 physics. ClampingScrollPhysics 자체는 정상
// 동작이지만(뷰포트보다 콘텐츠가 조금이라도 크면 스크롤을 허용하는 게 맞는
// 동작), 그 "조금"이 사용자 눈엔 안 보일 만큼 작을 때도 그대로 허용되다 보니
// "왜 굳이 내려가지?"로 느껴짐 - maxScrollExtent가 _tinyOverflowThreshold보다
// 작으면 드래그 자체를 무시해서 그 미세한 여분을 진짜 오버플로가 아닌 것처럼
// 처리함. 그보다 큰 진짜 오버플로(작은 화면 기기 등)는 평소처럼 정상 스크롤됨.
const double _tinyOverflowThreshold = 12.0;

class _NoTinyOverflowScrollPhysics extends ClampingScrollPhysics {
  const _NoTinyOverflowScrollPhysics({super.parent});

  @override
  _NoTinyOverflowScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _NoTinyOverflowScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (position.maxScrollExtent <= _tinyOverflowThreshold) return false;
    return super.shouldAcceptUserOffset(position);
  }
}
