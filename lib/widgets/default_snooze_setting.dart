import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../services/snooze_settings_service.dart';

class DefaultSnoozeSetting extends StatefulWidget {
  const DefaultSnoozeSetting({super.key});
  @override
  State<DefaultSnoozeSetting> createState() => _DefaultSnoozeSettingState();
}

class _DefaultSnoozeSettingState extends State<DefaultSnoozeSetting> {
  int? _minutes;
  bool _busy = true;
  bool _failed = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _busy = true; _failed = false; });
    try {
      final minutes = await SnoozeSettingsService.read();
      if (mounted) setState(() => _minutes = minutes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _save(int minutes) async {
    setState(() { _busy = true; _failed = false; });
    try {
      final saved = await SnoozeSettingsService.save(minutes);
      if (mounted) setState(() => _minutes = saved);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.l10n.defaultSnoozeTitle, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(context.l10n.defaultSnoozeDescription),
      Wrap(spacing: 8, children: [for (final value in SnoozeSettingsService.choices)
        ChoiceChip(key: ValueKey('default-snooze-$value'),
          label: Text(context.l10n.defaultSnoozeMinutes(value)),
          selected: _minutes == value,
          onSelected: _busy || _minutes == null ? null : (_) => _save(value))]),
      if (_busy) const LinearProgressIndicator(),
      if (_failed) Row(children: [
        Expanded(child: Text(context.l10n.defaultSnoozeError, semanticsLabel: context.l10n.defaultSnoozeError)),
        TextButton(onPressed: _busy ? null : _load, child: Text(context.l10n.defaultSnoozeRetry)),
      ]),
    ]),
  );
}
