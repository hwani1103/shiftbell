// lib/screens/sleep_calendar_full_screen.dart
//
// ⭐ 2026-09-01 - "최근 수면 기록" 미니 달력 카드(condition_tab.dart)에서 가로
// 스크롤로는 한 번에 3일 정도만 보이는 한계를 보완하는 전체보기 화면. 이번달/
// 지난달/그 이전달을 좌우로 넘기며 한 달치 수면 기록을 전부 훑어볼 수 있다.
//
// ⭐ 리스트형/격자형 두 가지를 만들어 비교해본 뒤 **리스트형으로 확정**함
// (격자형/토글/바텀시트 전용 상세 화면은 삭제) - 격자 칸 하나에 날짜/근무명/
// 슬롯 3개를 다 욱여넣어야 해서 작은 화면/큰 글씨 설정에서 깨질 위험이 리스트형
// 보다 컸음.
//
// ⭐ 미니 달력 카드가 쓰는 sleepRecordProvider는 "오늘의 컨디션 예측"용으로
// 최근 60일만 불러오므로(sleep_record_provider.dart 참고), 이번달/지난달/
// 저저번달을 자유롭게 넘겨봐야 하는 이 화면은 기간 제한 없이 직접 DB를 다시
// 읽는다 - 편집(추가/수정/삭제)은 여전히 sleepRecordProvider의 notifier를 통해서
// 하므로(handleSleepSlotTap), 다른 화면(미니 달력 카드)의 상태도 같이 갱신된다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../models/sleep_record.dart';
import '../providers/condition_provider.dart';
import '../services/condition/sleep_day_slots.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../utils/sleep_format_util.dart';
import '../widgets/sleep_edit_dialog.dart';

class SleepCalendarFullScreen extends ConsumerStatefulWidget {
  const SleepCalendarFullScreen({super.key});

  @override
  ConsumerState<SleepCalendarFullScreen> createState() => _SleepCalendarFullScreenState();
}

class _SleepCalendarFullScreenState extends ConsumerState<SleepCalendarFullScreen> {
  late DateTime _month; // 보고 있는 달의 1일
  late Future<List<SleepRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _recordsFuture = DatabaseService.instance.getSleepRecords();
  }

  void _reload() => setState(() => _recordsFuture = DatabaseService.instance.getSleepRecords());

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _prevMonth() => setState(() => _month = DateTime(_month.year, _month.month - 1, 1));

  void _nextMonth() {
    if (_isCurrentMonth) return; // 미래 달로는 넘어갈 수 없음
    setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
  }

  @override
  Widget build(BuildContext context) {
    final analyzer = ref.watch(conditionAnalyzerProvider);
    final schedule = analyzer?.schedule;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('수면 기록 전체보기'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _MonthNavBar(month: _month, canGoNext: !_isCurrentMonth, onPrev: _prevMonth, onNext: _nextMonth),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<SleepRecord>>(
              future: _recordsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final now = DateTime.now();
                final lastOfMonth = DateTime(_month.year, _month.month + 1, 0);
                final rangeEnd = _isCurrentMonth ? DateTime(now.year, now.month, now.day) : lastOfMonth;
                final days = buildSleepDaySlots(records: snapshot.data!, from: _month, to: rangeEnd, analyzer: analyzer);

                if (days.isEmpty) {
                  return const Center(child: Text('이 달에는 표시할 날짜가 없어요.', style: TextStyle(color: Colors.black45)));
                }
                return _SleepMonthList(days: days, schedule: schedule, onChanged: _reload);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthNavBar extends StatelessWidget {
  final DateTime month;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MonthNavBar({required this.month, required this.canGoNext, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          SizedBox(
            width: 140,
            child: Text(
              '${month.year}년 ${month.month}월',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: Icon(Icons.chevron_right, color: canGoNext ? null : Colors.black26),
          ),
        ],
      ),
    );
  }
}

class _SleepMonthList extends StatefulWidget {
  final List<SleepDaySlots> days;
  final ShiftSchedule? schedule; // 근무명 표시 전용
  final VoidCallback onChanged;
  const _SleepMonthList({required this.days, required this.schedule, required this.onChanged});

  @override
  State<_SleepMonthList> createState() => _SleepMonthListState();
}

class _SleepMonthListState extends State<_SleepMonthList> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      // 이번달을 열었을 때 오늘(맨 아래)이 바로 보이게.
      final now = DateTime.now();
      final isCurrentMonth =
          widget.days.isNotEmpty && widget.days.last.date.month == now.month && widget.days.last.date.year == now.year;
      if (isCurrentMonth) _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ 2026-09-01 후속5 - "맨 아래 항목이 잘 안 보인다"는 피드백 - 이 리스트가
    // Scaffold body에 그대로 얹혀서 하단 시스템 제스처 영역을 안 피했었음.
    // MediaQuery.padding.bottom(제스처 내비게이션 바 등 하단 안전영역)을 기존
    // 여백(16)에 더해서, 스크롤을 끝까지 내려도 마지막 항목이 그 영역 위에서
    // 온전히 보이게 함.
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return ListView.separated(
      controller: _controller,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomSafe),
      itemCount: widget.days.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final day = widget.days[i];
        final shiftName = widget.schedule?.getShiftForDate(day.date) ?? '—';
        return _SleepDayListRow(day: day, shiftName: shiftName, onChanged: widget.onChanged);
      },
    );
  }
}

class _SleepDayListRow extends ConsumerWidget {
  final SleepDaySlots day;
  final String shiftName;
  final VoidCallback onChanged;
  const _SleepDayListRow({required this.day, required this.shiftName, required this.onChanged});

  bool get _isToday {
    final now = DateTime.now();
    return day.date.year == now.year && day.date.month == now.month && day.date.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isToday ? kAppMainAccent.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isToday ? kAppMainAccent.withOpacity(0.35) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ⭐ 2026-09-01 후속5 - "8/1 (토)만 진하다"는 피드백으로 날짜를 더
              // 눈에 띄게(14→16sp) 키움 - 나머지 텍스트 크기는 그대로 유지.
              Text(fmtDateWeekday(day.date), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shiftName,
                  // ⭐ 2026-09-01 후속5 - 근무명(야간/휴무/주간 등)이 너무 흐리다는
                  // 피드백으로 black54 → black87 + 약간의 굵기로 진하게 함.
                  style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final category in SleepSlotCategory.values) ...[
                if (category != SleepSlotCategory.values.first) const SizedBox(width: 8),
                Expanded(
                  child: _SlotChip(
                    category: category,
                    record: day.forCategory(category),
                    onTap: () async {
                      await handleSleepSlotTap(
                        context,
                        ref,
                        date: day.date,
                        category: category,
                        record: day.forCategory(category),
                      );
                      onChanged();
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final SleepSlotCategory category;
  final SleepRecord? record;
  final VoidCallback onTap;
  const _SlotChip({required this.category, required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = record;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⭐ 2026-09-01 후속5 - "주 수면/낮잠/+기록"이 다 너무 흐리다는 피드백으로
            // 라벨(black38→black87)/빈 칸 placeholder(black38→black54) 모두 진하게.
            Text(
              category.label,
              style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (r == null)
              const Text('+ 기록', style: TextStyle(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w500))
            else ...[
              Text(
                r.end != null ? '${fmtTimeOnly(r.start)} - ${fmtTimeOnly(r.end!)}' : '${fmtTimeOnly(r.start)}~ 진행 중',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (r.durationMinutes != null)
                Text(
                  '(${fmtSleepDuration(Duration(minutes: r.durationMinutes!), r.source)})',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
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
