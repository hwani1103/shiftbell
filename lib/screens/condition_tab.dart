// lib/screens/condition_tab.dart
//
// ⭐ 컨디션 매니저 Phase 4 - 화면. "일정관리" 탭 옆에 신설된 독립 탭
// (컨디션매니저_설계.md 7장). 기존 탭(달력/일정관리/설정) 코드는 전혀 건드리지
// 않았고, 이 파일 하나로 완결됨.
//
// ⭐ 1차 버전이라 l10n 키를 새로 안 만들고 한국어 문자열을 직접 씀(설계 문서
// 7장 참고, AlarmTestScreen 등 기존 실험적 화면과 같은 관례) - 정식으로
// 자리잡으면 그때 app_ko.arb/app_en.arb로 옮길 것.
//
// ⭐ 이 화면은 사용자를 겁주지 않는 방향으로 만든다(스펙 33장) - 한 화면에서
// 이해해야 할 건 "오늘 상태 / 왜 그런지 / 무엇을 하면 되는지" 딱 3가지이고,
// 나머지(이번 주 패턴, 적용된 근거)는 눌러서 펼쳐보는 구조로 뺐다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../models/sleep_record.dart';
import '../providers/condition_provider.dart';
import '../providers/health_tip_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/sleep_condition_provider.dart';
import '../providers/sleep_record_provider.dart';
import '../services/condition/condition_score.dart';
import '../services/condition/sleep_day_slots.dart';
import '../services/condition/today_forecast_engine.dart';
import '../theme/app_colors.dart';
import '../utils/sleep_format_util.dart';
import '../widgets/sleep_edit_dialog.dart';
import 'sleep_calendar_full_screen.dart';

class ConditionTab extends ConsumerWidget {
  const ConditionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('컨디션'),
        centerTitle: true,
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('불러오지 못했습니다: $e')),
        data: (schedule) {
          if (schedule == null) {
            return const _NoScheduleNotice();
          }
          return _ConditionBody(schedule: schedule);
        },
      ),
    );
  }
}

class _NoScheduleNotice extends StatelessWidget {
  const _NoScheduleNotice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '먼저 근무 스케줄을 설정해주세요.\n(달력 탭에서 설정할 수 있어요)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.black54),
        ),
      ),
    );
  }
}

class _ConditionBody extends ConsumerStatefulWidget {
  final ShiftSchedule schedule;
  const _ConditionBody({required this.schedule});

  @override
  ConsumerState<_ConditionBody> createState() => _ConditionBodyState();
}

class _ConditionBodyState extends ConsumerState<_ConditionBody> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ⭐ 2026-09-01 후속4 - "위젯/자동감지로 수면 기록을 남기고 앱으로 돌아왔을 때
  // 오늘의 컨디션 예측이 바로 안 바뀌는 것 같다"는 피드백. sleepRecordProvider는
  // 실시간 push 구독이 없고 "필요할 때 다시 읽는" 방식이라(sleep_record_provider.dart
  // 주석 참고), 앱이 백그라운드(위젯 조작)→포그라운드로 돌아올 때 다시 안 읽으면
  // 이 탭이 켜져 있던 동안 위젯/자동감지가 DB에 직접 써넣은 변경을 놓친다.
  // 이 화면(컨디션 탭)만의 관심사라 main.dart는 전혀 안 건드리고 여기서 자체
  // 해결함(완전 분리 원칙 유지).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(sleepRecordProvider.notifier).refresh();
    }
  }

  // ⭐ 2026-09-04 - "어제의 수면 시간을 입력하시겠어요?" 토스트(구
  // _maybeShowSleepNudge)를 사용자 요청으로 제거함 - 근무 종료 시각을 고려 안
  // 하고 "어제가 근무일이었으면" 무조건 띄우다 보니, 아직 근무 중이거나 방금
  // 끝난 시점에도 뜨는 어색한 케이스가 있었음(예: 19~07시 야간근무 중인
  // 05:20에 진입해도 "어제(그 근무 시작일) 기록 안 했냐"고 물어봄). 어차피
  // 바로 아래 "최근 수면 기록" 미니 달력에서 빈 칸을 탭하면 똑같이 기록할 수
  // 있어서 안내 자체가 불필요하다는 판단 - 대체 기능 없이 그냥 삭제.
  @override
  Widget build(BuildContext context) {
    final setupNeeded = ref.watch(conditionSetupNeededProvider);

    // ⭐ 2026-09-01 - 근무별 실제 근무시간(하나라도)이 설정 탭에서 입력되기
    // 전까지는 이 탭에 아무것도 안 보이게 함(사용자 요청) - 입력 UI 자체가
    // 이제 이 탭에 없으므로(설정 → 근무시간 및 OT 설정으로 이동) 여기서
    // "부분적으로라도 보여줄 것"이 없음.
    if (setupNeeded) {
      return const _SetupNeededNotice();
    }

    final pending = ref.watch(pendingSleepRecordsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (pending.isNotEmpty) ...[
          for (final r in pending) _PendingSleepConfirmationCard(record: r),
          const SizedBox(height: 16),
        ],
        // ⭐ 2026-09-01 - "오늘의 컨디션 예측" 킬러 기능. 맨 위 카드 하나 -
        // 기존 카드들(추천/이번 주 패턴/최근 수면/근거)은 전부 그 아래로.
        // today_forecast_engine.dart 참고.
        //
        // ⭐ 2026-09-01 후속4 - 기존 "오늘의 컨디션"(4-rule 판정 그대로 노출,
        // 예: "12시간 근무입니다. 관련 연구에서는...") 카드를 삭제함(사용자
        // 요청) - 위 예측 카드가 이제 실제 수면 데이터까지 종합해서 하고 싶은
        // 말을 다 하므로 중복이라고 판단. ConditionRuleEngine 자체(판정 로직)는
        // 그대로 살아있고 "오늘의 추천" 카드가 여전히 그 결과(RULE_SLEEP_WINDOW
        // 등)를 씀 - 화면에서 판정 레벨(NORMAL/ATTENTION/HIGH_LOAD)을 직접
        // 노출하는 카드만 없앤 것.
        // ⭐ 2026-09-01 후속13 - 사용자 요청으로 "이번 주 패턴"(_WeeklySummaryCard)/
        // "수면과 근무의 관계"(_SleepShiftRelationCard) 삭제. "왜 이런 조언을
        // 하나요?"(접이식, 근거)는 한 번 "근거 자료"(전체 Evidence 12개)로
        // 확장했다가, 사용자가 "도움말 쪽을 나중에 리팩토링할 때 넣겠다"고
        // 해서 이 탭에서 완전히 빼고 lib/widgets/evidence_library_section.dart
        // 로 분리해둠(그 파일 상단 주석 참고 - 지금은 어디에도 연결 안 돼
        // 있음). 최종 순서: 오늘의 컨디션 → 건강 Tip → 최근 수면기록.
        const _TodayForecastCard(),
        const SizedBox(height: 16),
        const _HealthTipCard(),
        const SizedBox(height: 16),
        const _SleepMiniCalendarCard(),
      ],
    );
  }
}

// ⭐ 2026-09-01 - "근무별 출퇴근 시각" 입력 UI를 이 탭에서 완전히 걷어내고
// 설정 → 근무시간 및 OT 설정(work_hours_settings_screen.dart)으로 옮김 -
// 그 화면의 "근무별 실제 근무시간" 입력이 이제 출퇴근 시각 자체를 받아서
// condition_shift_times도 같이 채움(하나의 입력으로 두 데이터를 얻음). 그래서
// 이 탭은 설정이 하나도 안 돼 있으면 그쪽으로 안내만 하고 아무것도 안 보여줌.
// ⭐ 2026-09-01 후속 - "안내 문구만 덜렁 뜨고 탭이 텅 비어 보인다"는 지적으로
// 개편. 맨 위에 안내 문구는 그대로 두되(근무시간을 설정해야 아래 카드들이
// 의미가 생기니까), 그 아래에 "오늘의 교대근무 건강 Tip"(_HealthTipCard)만
// 얹음 - 이 카드는 근무시간/수면 데이터와 완전히 무관하게 매일 하나씩 돌아가며
// 보여주는 범용 팁이라(health_tip_provider.dart 참고) 설정 전에도 그대로 잘
// 동작함. 나머지 카드(오늘의 컨디션 예측/최근 수면기록)는 근무시간이 있어야만
// 의미 있는 계산이라 여전히 설정 후에만 보임(아래 build()의 setupNeeded 분기).
class _SetupNeededNotice extends StatelessWidget {
  const _SetupNeededNotice();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '먼저 설정에서 근무별 실제 근무시간을 입력해주세요.\n'
            '설정 → 근무시간 및 OT 설정 탭에서 실제 근무시간을 입력해주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.black54),
          ),
        ),
        SizedBox(height: 16),
        _HealthTipCard(),
      ],
    );
  }
}

// ── 오늘의 컨디션 예측 (킬러 기능 - 맨 위 카드) ──────────────────────────
//
// ⭐ 2026-09-01 - today_forecast_engine.dart가 최근 최대 4주의 근무시간 추세 +
// 실제 수면 기록(있는 만큼만)을 종합해 고른 신호 1개(+짧은 보조 문장)를
// 그대로 보여준다. 아래 "오늘의 컨디션"(기존 4-rule 판정)과는 별개 - 이
// 카드는 판정 레벨을 바꾸지 않고 문구만 다듬는 표시 전용 레이어.

class _TodayForecastCard extends ConsumerWidget {
  const _TodayForecastCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(todayForecastProvider);
    if (forecast == null) return const SizedBox.shrink();
    // ⭐ 2026-09-01 후속10 - "오늘의 컨디션 점수"(사용자 명시 요청,
    // condition_score.dart 상단 주석 참고 - 기존 "숫자 점수 금지" 원칙을
    // 이 축에 한해 의도적으로 뒤집음). forecast가 null이 아니면 baseResult도
    // 항상 있으므로 score도 항상 계산됨(둘 다 같은 조건에서 null).
    final scoreResult = ref.watch(conditionScoreProvider);

    return Card(
      color: kAppMainAccent.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kAppMainAccent.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⭐ 2026-09-01 후속11 - 제목 줄 우측에 점수를 나란히 배치(사용자
            // 요청 - 아래 별도 줄이 아니라 "오늘의 컨디션" 바로 옆).
            Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                const Text(
                  '오늘의 컨디션',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kAppMainAccent),
                ),
                const Spacer(),
                if (scoreResult != null) _ConditionScoreInline(result: scoreResult),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              forecast.message,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              _coverageCaption(ref.watch(recentSleepCoverageProvider)),
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ 2026-09-01 후속18 - recentSleepCoverageProvider(sleep_condition_provider.dart)
  // 참고: 근무일/휴무일 구분 없이 "최근 30일 중 실제 수면 기록이 있는 날"만
  // 센다(사용자가 "근무일인지는 안 중요하다, 최근 30일이면 된다"고 명확히
  // 정정함) - forecast.trackedNightCount(근무일 전용, today_forecast_engine.dart의
  // 다른 계산에 여전히 쓰임)와는 이제 별개의 값.
  String _coverageCaption(RecentSleepCoverage coverage) {
    if (coverage.daysWithSleep == 0) {
      return '최근 근무 일정 기준으로 예측했어요.';
    }
    return '최근 ${coverage.trackedDays}일 중 수면 기록 ${coverage.daysWithSleep}일 반영';
  }
}

/// ⭐ 2026-09-01 후속11 - "오늘의 컨디션" 제목 줄 우측에 나란히 붙는 인라인
/// 점수 표시("컨디션 점수 : NN점" + 아이콘, 사용자 요청 레이아웃). 아이콘은
/// 8단계로 묶어서 보여주고(condition_score.dart의 kConditionScoreTiers),
/// 정확한 숫자는 항상 그대로 노출.
class _ConditionScoreInline extends StatelessWidget {
  final ConditionScoreResult result;
  const _ConditionScoreInline({required this.result});

  @override
  Widget build(BuildContext context) {
    final tier = conditionScoreTierFor(result.score);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tier.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 4),
        Text(
          '컨디션 점수 : ${result.score}점',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
      ],
    );
  }
}

// ── 오늘의 교대근무 건강 Tip ───────────────────────────────────────────────
//
// ⭐ 2026-09-01 후속11 - 기존 "오늘의 추천"(ConditionRuleEngine.tips, 오늘
// 근무 상황에 맞는 걸 전부 나열)을 대체함(사용자 요청). "오늘의 컨디션"
// 판정과는 완전히 무관한 범용 건강 상식 카드로 - 하루에 딱 1개만, 아이콘/
// 제목/내용 3개 필드만(번호 없음). health_tip_provider.dart가 Firestore
// `health_tips` 컬렉션(사용자가 콘솔에서 직접 추가 가능) 또는 로컬 15개
// 목록(health_tips_catalog.dart)에서 날짜 기반으로 하나씩 순환해서 고른다.
// ⭐ 후속13 - 제목을 "교대근무 건강 & 수면 관리 Tip" → "오늘의 교대근무 건강
// Tip"으로 정리(사용자가 대안을 제시하며 "적절하게 만들어봐" 요청) - "오늘의
// 컨디션" 카드와 같은 "오늘의 OO" 접두어로 통일감을 주고("오늘의 명언"류
// 관용구와 같은 뜻 - 매일 바뀌는 팁 하나라는 의미), "수면"은 15개 팁 중
// 일부 주제일 뿐이라 제목에서 빼고 "건강"으로 포괄, "관리"는 "Tip"과
// 의미가 겹쳐서 정리.
class _HealthTipCard extends ConsumerWidget {
  const _HealthTipCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tip = ref.watch(todayHealthTipProvider);
    if (tip == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('오늘의 교대근무 건강 Tip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tip.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(tip.content, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87)),
                    ],
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

// ⭐ 2026-09-01 후속13 - "이번 주 패턴" 카드(_WeeklySummaryCard, 근무 카테고리별
// 횟수/최대 연속일수/평균 근무시간) 삭제(사용자 요청) - currentWeekSummaryProvider
// 자체는 다른 곳에서 쓸 수도 있어 그대로 둠(condition_provider.dart 참고).

// ⭐ 2026-09-01 후속13 - "근거 자료" 섹션(Evidence Database 전체 12개, 접이식)을
// 이 탭에서 완전히 뺌(사용자 요청 - "도움말 쪽 리팩토링할 때 거기다 넣을 것") -
// lib/widgets/evidence_library_section.dart로 그대로 분리해둠(지금은 어디에도
// 연결 안 됨, 그 파일 상단 주석 참고).

// ⭐ 2026-09-01 - "근무별 평균 취침 시각" 섹션(1순위 자동감지 기준) 삭제 -
// 사용자 요청으로 자동 감지 기준을 근무 일정 기반 회복구간(2순위였던 것)
// 하나로 통일함. sleep_opportunity.dart/SleepScheduleResolver.kt도 동일하게
// 단순화(수면기록_자동추정_설계.md 참고, 관련 기록은 그 문서에 남김).

// ── 자동 감지 확인 카드 (스펙 12장) ────────────────────────────────────────

class _PendingSleepConfirmationCard extends ConsumerWidget {
  final SleepRecord record;
  const _PendingSleepConfirmationCard({required this.record});

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showSleepSlotEditDialog(
      context,
      initialStart: record.start,
      initialEnd: record.end ?? DateTime.now(),
      title: '수면 시각 수정',
    );
    if (result is! SleepSlotSaved) return;
    await ref.read(sleepRecordProvider.notifier).confirmPending(
          record,
          overrideStart: result.start,
          overrideEnd: result.end,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final end = record.end;
    final durationText = end != null ? fmtSleepDuration(end.difference(record.start), record.source) : '진행 중';

    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bedtime, color: Color(0xFFF9A825)),
                SizedBox(width: 8),
                Text('수면을 기록했어요', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              // ⭐ 2026-09-01 - end==null(진행 중) 문구는 이제 화면에 거의 안 보여야
              // 정상 - Kotlin 쪽에서 앱을 여는 즉시(checkNow) 진행 중 후보를 종료하고
              // 기상 시각을 추정해서 넘겨주기 때문(SleepDetectionReceiver.kt 참고).
              // 그래도 아주 짧은 순간(백그라운드 처리 중)엔 보일 수 있어 남겨둠.
              end != null
                  ? '${fmtDateTime(record.start)} ~ ${fmtDateTime(end)},\n약 $durationText 수면한 것으로 추정됩니다.'
                  : '${fmtDateTime(record.start)}부터 수면 중인 것으로 추정됩니다.\n(잠시 후 기상 시각이 추정되면 다시 표시돼요)',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => ref.read(sleepRecordProvider.notifier).discardPending(record),
                  child: const Text('기록하지 않기'),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => _edit(context, ref),
                  child: const Text('수정'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => ref.read(sleepRecordProvider.notifier).confirmPending(record),
                  child: const Text('맞아요'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 최근 수면 기록 (미니 달력 카드) ──────────────────────────────────────
//
// ⭐ 2026-09-01 재설계 - 기존 "최근 N개 리스트 + 상단 추가 버튼" 대신, 하루를
// 가로 스크롤 카드 한 칸으로 보여주는 미니 달력 형태로 바꿈(사용자 피드백:
// 리스트형은 "진행중 - 자동확정"만 계속 나열되고 확정/수정 동선이 없었음).
// 각 날짜 칸은 4줄 - 날짜+요일 / 근무명 / 슬롯①(취침) / 슬롯②(취침) - 이고
// 아래 두 슬롯은 탭하면 바로 그 자리에서 수면 기록을 만들거나 고칠 수 있다
// (sleep_day_slots.dart 참고 - "슬롯"은 순수 표시/편집 편의 개념이고 DB에는
// 그런 컬럼이 없다. 첫 기록이 슬롯①, 그날 두 번째 기록이 자동으로 슬롯②가
// 된다). 미래 날짜는 절대 렌더링하지 않음(오늘까지만) - 더 옛날 기록은
// "전체보기"(sleep_calendar_full_screen.dart)에서 월 단위로 훑어봄.

class _SleepMiniCalendarCard extends ConsumerStatefulWidget {
  const _SleepMiniCalendarCard();

  @override
  ConsumerState<_SleepMiniCalendarCard> createState() => _SleepMiniCalendarCardState();
}

// ⭐ 2026-09-01 후속7(2차) - "컨디션 탭에 들어가자마자 스크롤하면(또는 다른
// 탭 갔다 오면) 가로 카드들이 왼쪽에서 오른쪽으로 딱 붙는 애니메이션이 매번
// 다시 생긴다"는 재확인 피드백. AutomaticKeepAliveClientMixin으로는 "같은
// 세션 안에서 세로로 멀리 스크롤했다 돌아오는" 경우만 막았을 뿐, **탭을
// 나갔다 들어올 때마다 이 State 자체가 통째로 새로 만들어지는** 경우까지는
// 못 막았음(이 앱의 탭 전환 구조상 매번 새로 만들어짐 - 그때마다 초기값
// 0에서 시작했다가 postFrameCallback으로 maxScrollExtent로 jumpTo하니, 매번
// "화면이 나타나자마자 한 프레임 뒤에 순간이동"하는 게 눈에 띄는 애니메이션
// 처럼 보였음). 근본적으로 고침: **jumpTo 자체를 없앰** - `reverse: true` +
// 날짜를 최신순(오늘이 맨 앞)으로 뒤집어서 넘기면, "스크롤 안 한 초기 상태"
// 자체가 이미 "오늘이 오른쪽 끝에 보이는" 상태가 되어(Flutter의 reverse
// 리스트는 index 0을 시작 가장자리에 놓음) 어떤 프레임에도 위치를 바꿀 필요가
// 없어짐 - State가 몇 번을 새로 만들어져도 처음부터 항상 올바른 위치로 그려짐.
class _SleepMiniCalendarCardState extends ConsumerState<_SleepMiniCalendarCard> {
  @override
  Widget build(BuildContext context) {
    final days = ref.watch(recentSleepDaySlotsProvider);
    final analyzer = ref.watch(conditionAnalyzerProvider);
    // ⭐ reverse:true와 짝을 맞춰 오늘(마지막 요소)이 index 0이 되도록 뒤집음.
    final reversedDays = days.reversed.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('최근 수면 기록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SleepCalendarFullScreen()),
                  ),
                  icon: const Icon(Icons.calendar_month, size: 17),
                  label: const Text('전체보기'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '아래 칸을 눌러 취침 시각을 기록/수정할 수 있어요. 옆으로 밀어보세요 →',
              style: TextStyle(fontSize: 11.5, color: Colors.black45),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: reversedDays.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final day = reversedDays[i];
                  final shiftName = analyzer?.instanceForDate(day.date).shiftName;
                  return _SleepDayTile(day: day, shiftName: shiftName);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepDayTile extends ConsumerWidget {
  final SleepDaySlots day;
  final String? shiftName;
  const _SleepDayTile({required this.day, required this.shiftName});

  bool get _isToday {
    final now = DateTime.now();
    return day.date.year == now.year && day.date.month == now.month && day.date.day == now.day;
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref, SleepSlotCategory category) {
    return handleSleepSlotTap(
      context,
      ref,
      date: day.date,
      category: category,
      record: day.forCategory(category),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 128,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _isToday ? kAppMainAccent.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isToday ? kAppMainAccent.withOpacity(0.35) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fmtDateWeekday(day.date),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            shiftName ?? '—',
            style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(height: 8),
          for (final category in SleepSlotCategory.values) ...[
            Expanded(
              child: _SleepSlotCell(
                category: category,
                record: day.forCategory(category),
                onTap: () => _handleTap(context, ref, category),
              ),
            ),
            if (category != SleepSlotCategory.values.last) const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

class _SleepSlotCell extends StatelessWidget {
  final SleepSlotCategory category;
  final SleepRecord? record;
  final VoidCallback onTap;
  const _SleepSlotCell({required this.category, required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = record;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category.label,
              style: const TextStyle(fontSize: 9.5, color: Colors.black87, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (r == null)
              const Text('+ 기록', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500))
            else ...[
              Text(
                r.end != null ? '${fmtTimeOnly(r.start)}-${fmtTimeOnly(r.end!)}' : '${fmtTimeOnly(r.start)}~ 진행중',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (r.durationMinutes != null)
                Text(
                  '(${fmtSleepDuration(Duration(minutes: r.durationMinutes!), r.source)})',
                  style: const TextStyle(fontSize: 10, color: Colors.black45),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ⭐ 2026-09-01 후속13 - "수면과 근무의 관계" 카드(_SleepShiftRelationCard,
// 야간/주간·오후/휴무 후 평균 수면 비교) 삭제(사용자 요청).
// sleepShiftRelationSummaryProvider 자체는 그대로 둠(다른 곳에서 재사용 가능).

