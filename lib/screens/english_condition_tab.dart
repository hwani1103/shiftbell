import '../widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sleep_record.dart';
import '../providers/sleep_record_provider.dart';
import '../providers/condition_provider.dart';
import '../providers/sleep_condition_provider.dart';
import '../providers/tab_visibility_provider.dart';
import '../services/condition/english_recovery_summary.dart';
import '../services/condition/english_sleep_copy.dart';
import '../widgets/disable_tab_button.dart';

/// English sleep screen. It shows recorded facts only; Korean recovery advice is
/// deliberately kept out until its evidence and wording have been localized.
class EnglishConditionTab extends ConsumerWidget {
  const EnglishConditionTab(
      {super.key, required this.onDisabled, required this.onConfirmed});

  final VoidCallback onDisabled;
  final Future<void> Function() onConfirmed;

  static String _time(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(value);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date · $time';
  }

  static void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<DateTime?> _pickDateTime(
      BuildContext context, DateTime initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _addSleep(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final start =
        await _pickDateTime(context, now.subtract(const Duration(hours: 8)));
    if (start == null || !context.mounted) return;
    final end = await _pickDateTime(context, now);
    if (end == null || !context.mounted) return;
    if (!end.isAfter(start.add(const Duration(minutes: 1))) ||
        end.isAfter(DateTime.now())) {
      _notice(context,
          'The end time must be at least 2 minutes after the start and cannot be in the future.');
      return;
    }
    try {
      final notifier = ref.read(sleepRecordProvider.notifier);
      if (await notifier.findOverlap(start, end) != null) {
        if (context.mounted)
          _notice(context, 'These times overlap an existing sleep record.');
        return;
      }
      await notifier.addManual(start: start, end: end);
    } catch (_) {
      if (context.mounted) _notice(context, 'Could not save the sleep record.');
    }
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, SleepRecord record) async {
    if (record.end == null) return;
    try {
      final conflict =
          await ref.read(sleepRecordProvider.notifier).confirmPending(record);
      if (conflict != null && context.mounted)
        _notice(context, 'This estimate overlaps an existing sleep record.');
    } catch (_) {
      if (context.mounted) _notice(context, 'Could not confirm this estimate.');
    }
  }

  Future<void> _editPending(
      BuildContext context, WidgetRef ref, SleepRecord record) async {
    if (record.end == null) return;
    final start = await _pickDateTime(context, record.start);
    if (start == null || !context.mounted) return;
    final end = await _pickDateTime(context, record.end!);
    if (end == null || !context.mounted) return;
    if (!end.isAfter(start.add(const Duration(minutes: 1))) ||
        end.isAfter(DateTime.now())) {
      _notice(context,
          'The end time must be at least 2 minutes after the start and cannot be in the future.');
      return;
    }
    try {
      final conflict = await ref
          .read(sleepRecordProvider.notifier)
          .confirmPending(record, overrideStart: start, overrideEnd: end);
      if (conflict != null && context.mounted)
        _notice(context, 'These times overlap an existing sleep record.');
    } catch (_) {
      if (context.mounted) _notice(context, 'Could not confirm this estimate.');
    }
  }

  Future<void> _discard(
      BuildContext context, WidgetRef ref, SleepRecord record) async {
    if (record.id == null) return;
    try {
      await ref.read(sleepRecordProvider.notifier).deleteRecord(record.id!);
    } catch (_) {
      if (context.mounted) _notice(context, 'Could not discard this estimate.');
    }
  }

  Future<void> _editConfirmed(
      BuildContext context, WidgetRef ref, SleepRecord record) async {
    if (record.end == null) return;
    final start = await _pickDateTime(context, record.start);
    if (start == null || !context.mounted) return;
    final end = await _pickDateTime(context, record.end!);
    if (end == null || !context.mounted) return;
    if (!end.isAfter(start.add(const Duration(minutes: 1))) ||
        end.isAfter(DateTime.now())) {
      _notice(context,
          'The end time must be at least 2 minutes after the start and cannot be in the future.');
      return;
    }
    try {
      final notifier = ref.read(sleepRecordProvider.notifier);
      if (await notifier.findOverlap(start, end, excludeId: record.id) !=
          null) {
        if (context.mounted)
          _notice(context, 'These times overlap another sleep record.');
        return;
      }
      await notifier.updateTimes(record, start: start, end: end);
    } catch (_) {
      if (context.mounted)
        _notice(context, 'Could not update the sleep record.');
    }
  }

  Future<void> _deleteConfirmed(
      BuildContext context, WidgetRef ref, SleepRecord record) async {
    if (record.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this sleep record?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(sleepRecordProvider.notifier).deleteRecord(record.id!);
    } catch (_) {
      if (context.mounted)
        _notice(context, 'Could not delete the sleep record.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(sleepRecordProvider);
    final analyzer = ref.watch(conditionAnalyzerProvider);
    final nowForGuidance = ref.watch(briefingClockProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep & Recovery'), centerTitle: true),
      body: records.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
            onPressed: () => ref.read(sleepRecordProvider.notifier).refresh(),
            child:
                const Text('Could not load your sleep records. Tap to retry.'),
          ),
        ),
        data: (all) {
          final pending = all
              .where((r) => r.status == SleepStatus.pendingConfirmation)
              .toList()
            ..sort((a, b) => b.start.compareTo(a.start));
          final confirmed = all
              .where((r) => r.status == SleepStatus.confirmed)
              .toList()
            ..sort((a, b) => b.start.compareTo(a.start));
          final now = DateTime.now();
          final weekStart = now.subtract(const Duration(days: 7));
          final recentStart = now.subtract(const Duration(days: 60));
          final recent = confirmed
              .where((r) => r.end != null && r.end!.isAfter(recentStart))
              .toList();
          final weekRecords = confirmed
              .where((r) => r.end != null && r.end!.isAfter(weekStart))
              .toList();
          final weekMinutes = weekRecords.fold<int>(0, (sum, r) {
            final start = r.start.isBefore(weekStart) ? weekStart : r.start;
            return sum + r.end!.difference(start).inMinutes;
          });
          final recovery = analyzer == null
              ? null
              : buildEnglishRecoverySummary(
                  analyzer: analyzer, records: all, now: nowForGuidance);
          return RefreshIndicator(
            onRefresh: () => ref.read(sleepRecordProvider.notifier).refresh(),
            child: AdaptiveSectionList(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Your sleep',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                    'Review detected sleep before it becomes a confirmed record. Your sleep data is stored on this device.'),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sleep in the past 7 days',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(EnglishSleepCopy.weekTotal(
                            Duration(minutes: weekMinutes),
                            weekRecords.length)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shifts and recovery',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (recovery?.currentShiftEnd != null)
                          Text(
                              'Current shift ends: ${_time(context, recovery!.currentShiftEnd!)}'),
                        if (recovery?.currentShiftEnd != null)
                          const Text(
                              'You can review your recovery after this shift ends.'),
                        if (recovery?.nextShiftStart != null)
                          Text(
                              'Next shift starts: ${_time(context, recovery!.nextShiftStart!)}'),
                        if (recovery?.lastShiftEnd != null)
                          Text(
                              'Last shift ended: ${_time(context, recovery!.lastShiftEnd!)}'),
                        if (recovery?.betweenShifts != null)
                          Text(
                              'Time between shifts: ${EnglishSleepCopy.duration(recovery!.betweenShifts!)}'),
                        if (recovery?.recordedSleepAfterLastShift != null)
                          Text(EnglishSleepCopy.sinceLastShift(
                              recovery!.recordedSleepAfterLastShift!)),
                        for (final line in EnglishSleepCopy.guidance(
                            recovery, nowForGuidance))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(line),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                            'These times and records come from this device. This guidance does not assess your health.',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _addSleep(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add sleep record'),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Sleep estimates to review (${pending.length})',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (pending.length > 10)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'Showing the 10 most recent estimates. Review one to see the next.'),
                    ),
                  for (final record in pending.take(10))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${_time(context, record.start)} → ${record.end == null ? 'In progress' : _time(context, record.end!)}'),
                              if (record.end != null)
                                Text(EnglishSleepCopy.duration(
                                    record.end!.difference(record.start))),
                              Wrap(spacing: 8, children: [
                                TextButton(
                                  onPressed: record.end == null
                                      ? null
                                      : () => _confirm(context, ref, record),
                                  child: const Text('Confirm'),
                                ),
                                TextButton(
                                  onPressed: record.end == null
                                      ? null
                                      : () =>
                                          _editPending(context, ref, record),
                                  child: const Text('Edit, then confirm'),
                                ),
                                TextButton(
                                  onPressed: record.id == null
                                      ? null
                                      : () => _discard(context, ref, record),
                                  child: const Text('Discard'),
                                ),
                              ]),
                            ]),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Text('Confirmed sleep · past 60 days',
                    style: Theme.of(context).textTheme.titleLarge),
                if (recent.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          'No confirmed sleep recorded in the past 60 days.')),
                for (final record in recent)
                  Card(
                    child: ListTile(
                      title: Text(_time(context, record.start)),
                      subtitle: Text(record.end == null
                          ? 'In progress'
                          : 'Ended ${_time(context, record.end!)} · ${EnglishSleepCopy.duration(record.end!.difference(record.start))}'),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Record actions',
                        onSelected: (action) => action == 'edit'
                            ? _editConfirmed(context, ref, record)
                            : _deleteConfirmed(context, ref, record),
                        itemBuilder: (_) => [
                          if (record.end != null)
                            const PopupMenuItem(
                                value: 'edit', child: Text('Edit times')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                DisableTabButton(
                  tabLabel: 'Sleep & Recovery',
                  provider: conditionTabEnabledProvider,
                  onConfirmed: onConfirmed,
                  onDisabled: onDisabled,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
