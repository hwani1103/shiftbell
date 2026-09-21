// lib/screens/condition_tab.dart
//
// ⭐ 수면·회복 탭(구 "컨디션" 탭). 하단 탭·앱바 이름만 바뀌었고 클래스·provider·저장 키(condition_tab_enabled)는
// 호환을 위해 그대로 둔다.
//
// ⭐ 2026-09-15 (출시 적합성 재검토 후속, 사용자 결정) - 범위를 줄여 핵심만 남김.
//  - 남긴 것: "오늘의 컨디션"(교대 일정 + 실제 수면 기록을 연결해 지금 시각 기준 확인된 사실·추천 행동·판단 범위),
//    자동 기록 확인 카드, 최근 수면 기록 미니 달력(빠른 입력·수정)
//  - 뺀 것: 컨디션 점수(0~100, 임의 가중치·데이터 없음과 상태 나쁨 혼동), 범용 건강 Tip(개인화 안 됨),
//    날짜 시드 문구 조합(today_forecast_engine.dart)
//  - 근무시간을 아직 안 넣었어도 수면 기록은 남길 수 있게 함(예전엔 안내 문구와 Tip만 보였음)
//
// ⭐ 1차 버전이라 l10n 키를 새로 안 만들고 한국어 문자열을 직접 씀(영어 로케일에서는 이 탭 자체가 안 보임 - main.dart
// _showConditionTab). 이 화면은 사용자를 겁주지 않는 방향 - 점수·진단 없이 "무엇이 확인됐고, 무엇을 하면 되는지".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/shift_schedule.dart';
import '../models/sleep_record.dart';
import '../providers/condition_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/sleep_condition_provider.dart';
import '../providers/sleep_record_provider.dart';
import '../providers/tab_visibility_provider.dart';
import '../services/condition/condition_rule_engine.dart';
import '../services/condition/evidence_database.dart';
import '../services/condition/recovery_briefing_engine.dart';
import '../services/condition/shift_time_category.dart';
import '../services/condition/sleep_by_category_stats.dart';
import '../services/condition/sleep_day_slots.dart';
import '../theme/app_colors.dart';
import '../utils/sleep_format_util.dart';
import '../widgets/disable_tab_button.dart';
import '../widgets/onboarding_info_popups.dart';
import '../widgets/sleep_edit_dialog.dart';
import 'sleep_calendar_full_screen.dart';
import 'work_hours_settings_screen.dart';

/// 하단 탭·앱바·"사용하지 않기" 버튼에 쓰는 탭 이름
const String kSleepRecoveryTabLabel = '수면·회복';

/// 탭 위쪽에 한 번에 보여줄 자동 기록 확인 카드 수
const int _kMaxPendingCards = 3;

class ConditionTab extends ConsumerWidget {
  // ⭐ 2026-09-13 - "OO 화면 사용하지 않기" 버튼은 이 탭 스크롤 콘텐츠 맨 아래(main.dart에서 콜백을 내려받음).
  final VoidCallback onDisabled;
  final Future<void> Function() onConfirmed;

  const ConditionTab(
      {super.key, required this.onDisabled, required this.onConfirmed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(kSleepRecoveryTabLabel),
        centerTitle: true,
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('불러오지 못했습니다: $e')),
        data: (schedule) {
          if (schedule == null) {
            return const _NoScheduleNotice();
          }
          return _ConditionBody(
              schedule: schedule,
              onDisabled: onDisabled,
              onConfirmed: onConfirmed);
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
  final VoidCallback onDisabled;
  final Future<void> Function() onConfirmed;
  const _ConditionBody(
      {required this.schedule,
      required this.onDisabled,
      required this.onConfirmed});

  @override
  ConsumerState<_ConditionBody> createState() => _ConditionBodyState();
}

class _ConditionBodyState extends ConsumerState<_ConditionBody>
    with WidgetsBindingObserver {
  // ⭐ 2026-09-11 - 최초 진입 사용법 안내. build()가 여러 번 불려도 중복 예약하지 않도록 가드.
  bool _tutorialChecked = false;

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

  // ⭐ 2026-09-01 후속4 - 위젯·자동 감지가 DB에 직접 쓴 수면 기록은 push 구독이 없어서, 앱 복귀 때 다시 읽는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(sleepRecordProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_tutorialChecked) {
      _tutorialChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowConditionTabTutorial(context);
      });
    }

    final setupNeeded = ref.watch(conditionSetupNeededProvider);
    final pending = ref.watch(pendingSleepRecordsProvider);

    return ListView(
      // ⭐ 2026-09-13(3차) - 아래 여백은 일정관리 탭과 같은 12.h(사용하지 않기 버튼과 광고 영역 사이 거리)
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12.h),
      children: [
        // ⭐ 2026-09-15 - 확인을 미룬 자동 기록이 쌓이면 탭 위쪽이 카드로 뒤덮였음(재검토 #3). 최신 3건만 보이고
        // 나머지는 개수만 알림 - 앞의 카드를 처리하면 다음 것이 올라온다(자동 확정은 여전히 하지 않음).
        if (pending.isNotEmpty) ...[
          // ⭐ P2 #7(2026-09-18, 사용자 요청) - 대기 카드가 2건 이상이면 화면에 보이는
          // 만큼(최대 _kMaxPendingCards개)을 한 번에 "맞아요" 처리하는 버튼. 되돌릴 필요가
          // 있으면 확인 뒤 "최근 수면 기록"에서 개별 수정·삭제하면 됨(별도 되돌리기 없음).
          if (pending.length >= 2)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => ref
                    .read(sleepRecordProvider.notifier)
                    .confirmAllPending(
                        pending.take(_kMaxPendingCards).toList()),
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('보이는 기록 모두 확인'),
              ),
            ),
          for (final r in pending.take(_kMaxPendingCards))
            _PendingSleepConfirmationCard(record: r),
          if (pending.length > _kMaxPendingCards)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                '확인을 기다리는 자동 기록이 ${pending.length - _kMaxPendingCards}건 더 있어요. 위 카드를 처리하면 이어서 보여드려요.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 16),
        ],
        // 근무시간이 하나도 없으면 오늘의 컨디션 대신 설정 안내 - 수면 기록(아래 미니 달력)은 그래도 남길 수 있음
        // ⭐ 2026-09-21(사용자 지적) - 그동안 이 상태에서는 자동 수면 감지가 계속 돌아가 기록이 쌓이는데도
        // 화면에는 설정 안내만 떠서 그 기록에 대해 한마디도 안 했음. 근무 일정 없이도 말할 수 있는 것
        // (어제 수면·최근 7일 평균)만 추려서 위에 먼저 보여준다.
        if (setupNeeded) ...[
          const _SleepOnlySummaryCard(),
          const _SetupNeededCard(),
        ] else
          const _TodayConditionCard(),
        const SizedBox(height: 16),
        const _SleepCategoryAveragesCard(),
        const SizedBox(height: 16),
        const _SleepMiniCalendarCard(),
        // ⭐ 2026-09-13 - 스크롤 맨 아래에 "사용하지 않기" 버튼
        const SizedBox(height: 28),
        DisableTabButton(
          tabLabel: kSleepRecoveryTabLabel,
          provider: conditionTabEnabledProvider,
          onConfirmed: widget.onConfirmed,
          onDisabled: widget.onDisabled,
        ),
      ],
    );
  }
}

// ── 근무시간 미입력 안내 ────────────────────────────────────────────────

class _SetupNeededCard extends StatelessWidget {
  const _SetupNeededCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '오늘의 컨디션을 보려면 근무시간이 필요해요',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '쓰고 있는 근무 중 하나 이상의 출퇴근 시각을 입력하면, 근무 사이 회복시간과 퇴근 후 실제 수면을 바탕으로 '
              '몇 시까지 잠자리에 들지·카페인을 언제 끊을지 같은 오늘 챙길 일을 알려드려요.\n'
              '수면 기록은 지금도 아래 "최근 수면 기록"에서 남길 수 있어요.',
              style: TextStyle(
                  fontSize: 13.5, height: 1.45, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const WorkHoursSettingsScreen()),
                ),
                icon: const Icon(Icons.schedule, size: 18),
                label: const Text('근무시간 입력하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 오늘의 컨디션 (확인된 사실 / 추천 행동 / 판단 범위) ─────────────────────

class _TodayConditionCard extends ConsumerStatefulWidget {
  const _TodayConditionCard();

  @override
  ConsumerState<_TodayConditionCard> createState() =>
      _TodayConditionCardState();
}

class _TodayConditionCardState extends ConsumerState<_TodayConditionCard> {
  bool _showEvidence = false;

  @override
  Widget build(BuildContext context) {
    final briefing = ref.watch(recoveryBriefingProvider);
    if (briefing == null) return const SizedBox.shrink();
    final evidenceIds = briefing.evidenceIds;
    // ⭐ 2026-09-18 - "이 근무 패턴 자체가 구조적으로 EU/IOM 기준을 넘는지"는
    // 스케줄이 안 바뀌면 매일 같은 값이라, 매번 반복되는 캐션(facts 리스트)이
    // 아니라 카드 상단에 조용한 배경 정보 한 줄로만 보여준다(사용자 지적 참고).
    final loadProfile = ref.watch(scheduleLoadProfileProvider);

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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '오늘의 컨디션',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kAppMainAccent),
                  ),
                ),
                _LevelChip(level: briefing.level),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              briefing.situation,
              style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
            if (loadProfile != null) ...[
              const SizedBox(height: 4),
              Text(
                loadProfile.note,
                style: const TextStyle(
                    fontSize: 11.5, height: 1.3, color: Colors.black45),
              ),
            ],
            const SizedBox(height: 14),
            const _SectionLabel('최근 근무·수면'),
            const SizedBox(height: 6),
            if (briefing.facts.isEmpty)
              const Text('아직 살펴볼 내용이 없어요.',
                  style: TextStyle(fontSize: 13, color: Colors.black54))
            else
              for (final fact in briefing.facts) _FactRow(fact: fact),
            const SizedBox(height: 12),
            const _SectionLabel('추천 행동'),
            const SizedBox(height: 6),
            if (briefing.actions.isEmpty)
              const Text(
                '지금 따로 챙길 행동은 없어요. 평소 수면 리듬을 유지하세요.',
                style: TextStyle(
                    fontSize: 13.5, height: 1.4, color: Colors.black87),
              )
            else
              for (var i = 0; i < briefing.actions.length; i++)
                _ActionRow(index: i + 1, action: briefing.actions[i]),
            if (briefing.limitations.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LimitationBox(lines: briefing.limitations),
            ],
            const SizedBox(height: 8),
            const _GeneralGuidanceNote(),
            if (evidenceIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => _showEvidence = !_showEvidence),
                icon: Icon(
                    _showEvidence ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                label: Text(_showEvidence ? '근거 접기' : '근거 보기',
                    style: const TextStyle(fontSize: 12.5)),
              ),
              if (_showEvidence)
                for (final id in evidenceIds) _EvidenceLine(id: id),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final ConditionLevel level;
  const _LevelChip({required this.level});

  @override
  Widget build(BuildContext context) {
    // 3단계 판정은 근무 일정 기반(ConditionRuleEngine) - 수면 기록 유무로 바뀌지 않는다
    final (String label, Color color) = switch (level) {
      ConditionLevel.normal => ('근무 부담 보통', const Color(0xFF2E7D32)),
      ConditionLevel.attention => ('주의가 필요한 날', const Color(0xFFB26A00)),
      ConditionLevel.highLoad => ('회복 부담이 큰 날', const Color(0xFFC62828)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Colors.black54));
  }
}

class _FactRow extends StatelessWidget {
  final BriefingFact fact;
  const _FactRow({required this.fact});

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (fact.tone) {
      BriefingTone.caution =>
        const Icon(Icons.error_outline, size: 16, color: Color(0xFFE08A00)),
      BriefingTone.good => const Icon(Icons.check_circle_outline,
          size: 16, color: Color(0xFF2E7D32)),
      BriefingTone.neutral => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Icon(Icons.circle, size: 6, color: Colors.black38),
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 19, child: Center(child: icon)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(fact.text,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final int index;
  final BriefingAction action;
  const _ActionRow({required this.index, required this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: kAppMainAccent, shape: BoxShape.circle),
            child: Text('$index',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(action.text,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

/// ⭐ 2026-09-21(사용자 요청) - 문장마다 "근거 수준은 낮음"·"~로 보고돼요" 같은 단서를
/// 달아 딱딱해지는 대신, 카드 전체에 해당하는 한 줄만 맨 아래에 조용히 둔다.
class _GeneralGuidanceNote extends StatelessWidget {
  const _GeneralGuidanceNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '수면·교대근무 연구를 참고한 일반적인 안내예요(의학적 진단이 아니에요).',
      style: TextStyle(fontSize: 11, height: 1.3, color: Colors.black38),
    );
  }
}

/// ⭐ 2026-09-21(사용자 지적, 항목 3) - 근무시간을 아직 안 넣은 상태 전용. 근무 일정이
/// 없어도 계산되는 수면 사실(어제 수면·최근 7일 평균)만 추려서 보여준다 - 자동 감지는
/// 그 상태에서도 계속 돌아가므로 "기록은 쌓이는데 앱은 아무 말도 안 한다"가 되지 않게 함.
class _SleepOnlySummaryCard extends ConsumerWidget {
  const _SleepOnlySummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefing = ref.watch(recoveryBriefingProvider);
    if (briefing == null) return const SizedBox.shrink();
    final facts = briefing.facts
        .where((f) =>
            f.topic == BriefingTopic.sleepAmount ||
            f.topic == BriefingTopic.sleepAverage)
        .toList();
    if (facts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('최근 수면'),
              const SizedBox(height: 6),
              for (final fact in facts) _FactRow(fact: fact),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitationBox extends StatelessWidget {
  final List<String> lines;
  const _LimitationBox({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: Colors.black54),
              SizedBox(width: 4),
              Text('판단 범위',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('· $line',
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, color: Colors.black54)),
            ),
        ],
      ),
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  final String id;
  const _EvidenceLine({required this.id});

  @override
  Widget build(BuildContext context) {
    Evidence? evidence;
    for (final e in kEvidenceDatabase) {
      if (e.id == id) {
        evidence = e;
        break;
      }
    }
    if (evidence == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '${evidence.topic} — ${evidence.source}',
        style: const TextStyle(
            fontSize: 11.5, height: 1.35, color: Colors.black54),
      ),
    );
  }
}

// ── 자동 감지 확인 카드 ────────────────────────────────────────────────

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
    final durationText = end != null
        ? fmtSleepDuration(end.difference(record.start), record.source)
        : '진행 중';

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
                Expanded(
                  child: Text(
                    '이때 주무셨나요?',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              // ⭐ 2026-09-01 - end==null(진행 중)은 거의 안 보여야 정상 - 앱을 여는 즉시(checkNow) Native가 후보를 닫음.
              end != null
                  ? '${fmtDateTime(record.start)} ~ ${fmtDateTime(end)}, 약 $durationText 동안 폰을 쓰지 않아 수면으로 추정했어요.'
                  : '${fmtDateTime(record.start)}부터 수면 중인 것으로 추정됩니다.\n(잠시 후 기상 시각이 추정되면 다시 표시돼요)',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 4),
            // ⭐ 2026-09-15 - 확인을 미루면 분석에 빠진다는 걸 알려서(재검토 #3) 확인 동선으로 유도. 거부는 학습에 반영됨.
            const Text(
              '확인한 기록만 오늘의 컨디션에 반영돼요. 수면이 아니었다면 "기록하지 않기"를 눌러주세요(다음부터 덜 잡혀요).',
              style: TextStyle(
                  fontSize: 11.5, height: 1.35, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(sleepRecordProvider.notifier)
                      .discardPending(record),
                  child: const Text('기록하지 않기'),
                ),
                OutlinedButton(
                  onPressed: () => _edit(context, ref),
                  child: const Text('수정'),
                ),
                ElevatedButton(
                  onPressed: () => ref
                      .read(sleepRecordProvider.notifier)
                      .confirmPending(record),
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
// ⭐ 2026-09-01 재설계 - 하루를 가로 스크롤 카드 한 칸으로(날짜+요일 / 근무명 / 주 수면 / 낮잠 2칸). 칸을 탭하면
// 그 자리에서 기록을 만들거나 고친다(sleep_day_slots.dart - "슬롯"은 표시 개념이고 DB 컬럼은 없음). 오늘까지만 그리고,
// 더 옛날 기록은 "전체보기"(sleep_calendar_full_screen.dart). 근무시간이 없어도(analyzer null) 그대로 동작한다.

class _SleepMiniCalendarCard extends ConsumerStatefulWidget {
  const _SleepMiniCalendarCard();

  @override
  ConsumerState<_SleepMiniCalendarCard> createState() =>
      _SleepMiniCalendarCardState();
}

// ⭐ 2026-09-01 후속7(2차) - 탭에 들어올 때마다 가로 목록이 오른쪽으로 순간이동하던 문제: jumpTo 대신
// reverse:true + 날짜 최신순(오늘이 index 0)으로 넘겨 처음부터 오늘이 오른쪽 끝에 보이게 함.
class _SleepMiniCalendarCardState
    extends ConsumerState<_SleepMiniCalendarCard> {
  @override
  Widget build(BuildContext context) {
    final days = ref.watch(recentSleepDaySlotsProvider);
    final analyzer = ref.watch(conditionAnalyzerProvider);
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
                  child: Text('최근 수면 기록',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SleepCalendarFullScreen()),
                  ),
                  icon: const Icon(Icons.calendar_month, size: 17),
                  label: const Text('전체보기'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              '칸을 눌러 수면을 기록·수정할 수 있어요. 옆으로 밀면 지난 날짜가 보여요 →',
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
                  final shiftName =
                      analyzer?.instanceForDate(day.date).shiftName;
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

// ── 근무 종류별 평균 수면 (P2 #6, 2026-09-18) ─────────────────────────────
//
// ⭐ 사용자 요청 - "야간 후 평균 4시간 40분, 주간 후 6시간 50분"처럼 근무표와 실제
// 수면 기록을 둘 다 가진 이 앱만 만들 수 있는 통계. 표본 부족한 카테고리는 아예 안
// 보임(sleep_by_category_stats.dart). 점수·등급화 없이 담백하게 숫자만 보여주고,
// 권장 최소(7시간, EVIDENCE-011) 미만인 카테고리만 옅은 경고 아이콘을 붙인다 -
// 새로운 판정을 만드는 게 아니라 이미 있는 기준(recommendedSleepMinMinutes)을
// 재사용하는 것뿐이라 원칙 위반이 아니다.

class _SleepCategoryAveragesCard extends ConsumerWidget {
  const _SleepCategoryAveragesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(sleepCategoryStatsProvider);
    final averages = stats.averages;
    final pendingCategories = stats.categories
        .where((category) =>
            stats.samplesFor(category) < kMinSampleDaysForCategoryAverage)
        .toList();

    // ⭐ 막대 공통 스케일 - 권장선(7시간)이 항상 같은 위치에 오도록 고정 하한을 두고,
    // 그보다 오래 자는 카테고리가 있으면 거기에 맞춰 늘린다(막대가 넘치지 않도록).
    final maxTotal = averages.isEmpty
        ? _kSleepBarBaseScaleMinutes
        : averages.map((a) => a.averageMinutes).reduce((a, b) => a > b ? a : b);
    final scale = maxTotal > _kSleepBarBaseScaleMinutes
        ? maxTotal
        : _kSleepBarBaseScaleMinutes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.insights_rounded, size: 20, color: kAppMainAccent),
                SizedBox(width: 7),
                Expanded(
                  child: Text('내 근무별 수면 패턴',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '최근 30일 중 수면 기록이 있는 날을 근무 유형별로 비교해요.',
              style: TextStyle(
                  fontSize: 11.5, height: 1.35, color: Colors.black45),
            ),
            if (averages.isNotEmpty) ...[
              const SizedBox(height: 10),
              const _SleepCategoryLegend(),
              const SizedBox(height: 12),
              for (final a in averages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child:
                      _SleepCategoryAverageRow(average: a, scaleMinutes: scale),
                ),
            ] else ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kAppMainAccent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '아직 평균을 만드는 중이에요. 같은 근무 유형의 수면이 3일 쌓이면 주 수면과 낮잠을 나눠 보여드려요.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: Colors.black87),
                ),
              ),
            ],
            if (pendingCategories.isNotEmpty) ...[
              if (averages.isNotEmpty) const Divider(height: 12),
              const SizedBox(height: 8),
              const Text(
                '평균 준비 중 · 유형별 3일 필요',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final category in pendingCategories)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        '${_sleepCategoryRowLabel(category)} ${stats.samplesFor(category)}/$kMinSampleDaysForCategoryAverage일',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 2),
            const Text(
              '하루는 주 수면 1건과 낮잠 최대 2건만 합산해요. 빠진 기록이 있으면 평균이 낮게 보일 수 있어요.',
              style: TextStyle(
                  fontSize: 10.5, height: 1.35, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}

/// ⭐ 2026-09-21(사용자 요청) - 막대 공통 스케일의 하한(10시간). 권장선(7시간)이
/// 항상 막대의 70% 지점에 오도록 해서 카테고리끼리 눈으로 바로 비교되게 한다.
const int _kSleepBarBaseScaleMinutes = 10 * 60;

const Color _kMainSleepBarColor = kAppMainAccent;
final Color _kNapBarColor = kAppMainAccent.withOpacity(0.32);

String _sleepCategoryRowLabel(ShiftTimeCategory c) =>
    c == ShiftTimeCategory.off ? '휴무일' : '${c.label} 근무일';

class _SleepCategoryLegend extends StatelessWidget {
  const _SleepCategoryLegend();

  @override
  Widget build(BuildContext context) {
    // ⭐ 글꼴 배율을 키운 기기에서 한 줄에 안 들어갈 수 있어 Wrap으로 감쌈(항목별로는
    // 색칩과 라벨이 떨어지면 안 되므로 각 쌍을 Row로 묶어서 넣는다).
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        _item(_swatch(_kMainSleepBarColor), '주 수면'),
        _item(_swatch(_kNapBarColor), '낮잠'),
        _item(
            Container(width: 1.5, height: 10, color: Colors.black38), '권장 7시간'),
      ],
    );
  }

  Widget _item(Widget mark, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      );

  Widget _swatch(Color color) => Container(
        width: 10,
        height: 10,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );
}

/// 한 카테고리 = 라벨/총합 한 줄 + 누적 막대 + 주수면·낮잠 분해 한 줄.
class _SleepCategoryAverageRow extends StatelessWidget {
  final SleepCategoryAverage average;
  final int scaleMinutes;
  const _SleepCategoryAverageRow(
      {required this.average, required this.scaleMinutes});

  @override
  Widget build(BuildContext context) {
    final total = average.averageMinutes;
    final low = total < ConditionRuleEngine.recommendedSleepMinMinutes;
    final hasNap = average.averageNapMinutes > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _sleepCategoryRowLabel(average.category),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
            ),
            Text(
              fmtDuration(Duration(minutes: total)),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: low ? const Color(0xFFB26A00) : Colors.black87,
              ),
            ),
            const SizedBox(width: 6),
            Text('(${average.sampleDays}일)',
                style: const TextStyle(fontSize: 10.5, color: Colors.black38)),
          ],
        ),
        const SizedBox(height: 5),
        _SleepStackedBar(
          mainMinutes: average.averageMainMinutes,
          napMinutes: average.averageNapMinutes,
          scaleMinutes: scaleMinutes,
          markerMinutes: ConditionRuleEngine.recommendedSleepMinMinutes,
        ),
        const SizedBox(height: 4),
        Text(
          // ⭐ 낮잠이 0이면 줄 자체를 짧게 - "낮잠 0분"이 주간·휴무마다 반복되면 노이즈만 됨.
          hasNap
              ? '주 수면 ${fmtDuration(Duration(minutes: average.averageMainMinutes))}'
                  ' · 낮잠 ${fmtDuration(Duration(minutes: average.averageNapMinutes))}'
              : '주 수면 ${fmtDuration(Duration(minutes: average.averageMainMinutes))}',
          style: const TextStyle(fontSize: 11.5, color: Colors.black54),
        ),
      ],
    );
  }
}

class _SleepStackedBar extends StatelessWidget {
  final int mainMinutes;
  final int napMinutes;
  final int scaleMinutes;
  final int markerMinutes;
  const _SleepStackedBar({
    required this.mainMinutes,
    required this.napMinutes,
    required this.scaleMinutes,
    required this.markerMinutes,
  });

  @override
  Widget build(BuildContext context) {
    const height = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        double px(int minutes) =>
            scaleMinutes <= 0 ? 0 : (minutes / scaleMinutes * w).clamp(0.0, w);
        final mainW = px(mainMinutes);
        final napW = px(napMinutes).clamp(0.0, (w - mainW).clamp(0.0, w));
        final markerX = px(markerMinutes);

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(height / 2),
                child: Row(
                  children: [
                    Container(
                        width: mainW,
                        height: height,
                        color: _kMainSleepBarColor),
                    Container(
                        width: napW, height: height, color: _kNapBarColor),
                  ],
                ),
              ),
              Positioned(
                left: (markerX - 0.75).clamp(0.0, w),
                child: Container(
                    width: 1.5, height: height, color: Colors.black38),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SleepDayTile extends ConsumerWidget {
  final SleepDaySlots day;
  final String? shiftName;
  const _SleepDayTile({required this.day, required this.shiftName});

  bool get _isToday {
    final now = DateTime.now();
    return day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;
  }

  Future<void> _handleTap(
      BuildContext context, WidgetRef ref, SleepSlotCategory category) {
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
        color:
            _isToday ? kAppMainAccent.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: _isToday
                ? kAppMainAccent.withOpacity(0.35)
                : Colors.grey.shade200),
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
            style: const TextStyle(
                fontSize: 11,
                color: Colors.black87,
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(height: 8),
          for (final category in SleepSlotCategory.values) ...[
            Expanded(
              child: _SleepSlotCell(
                cardDate: day.date,
                category: category,
                record: day.forCategory(category),
                onTap: () => _handleTap(context, ref, category),
              ),
            ),
            if (category != SleepSlotCategory.values.last)
              const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

class _SleepSlotCell extends StatelessWidget {
  final DateTime cardDate;
  final SleepSlotCategory category;
  final SleepRecord? record;
  final VoidCallback onTap;
  const _SleepSlotCell({
    required this.cardDate,
    required this.category,
    required this.record,
    required this.onTap,
  });

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
              style: const TextStyle(
                  fontSize: 9.5,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (r == null)
              const Text('+ 기록',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500))
            else ...[
              Builder(builder: (context) {
                // ⭐ 2026-09-13 - 야간 근무 회복수면처럼 실제 취침일이 카드 날짜와 다르면 시각 앞에 "M/D "를 붙임.
                final timeText = r.end != null
                    ? '${fmtTimeOnly(r.start)}-${fmtTimeOnly(r.end!)}'
                    : '${fmtTimeOnly(r.start)}~ 진행중';
                final startsOnDifferentDate = !_isSameDate(r.start, cardDate);
                final displayText = startsOnDifferentDate
                    ? '${r.start.month}/${r.start.day} $timeText'
                    : timeText;
                return Text(
                  displayText,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              }),
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
