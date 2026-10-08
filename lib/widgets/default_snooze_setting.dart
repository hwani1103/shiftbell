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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
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
    setState(() {
      _busy = true;
      _failed = false;
    });
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            colors.primary.withValues(alpha: .045), colors.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: .18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.more_time_rounded, size: 22, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(context.l10n.defaultSnoozeTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        Text(context.l10n.defaultSnoozeDescription,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final value in SnoozeSettingsService.choices)
            _buildChoice(context, value),
        ]),
        if (_busy && _minutes == null) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2)
        ],
        if (_failed) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: Text(context.l10n.defaultSnoozeError,
                    style: TextStyle(color: colors.error),
                    semanticsLabel: context.l10n.defaultSnoozeError)),
            TextButton(
                onPressed: _busy ? null : _load,
                child: Text(context.l10n.defaultSnoozeRetry)),
          ]),
        ],
      ]),
    );
  }

  // Match the duration cards without implicit selection or disabled animations.
  Widget _buildChoice(BuildContext context, int value) {
    final colors = Theme.of(context).colorScheme;
    final selected = _minutes == value;
    final enabled = !_busy && _minutes != null;
    return Semantics(
      key: ValueKey('default-snooze-$value'),
      button: true,
      selected: selected,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => _save(value) : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 76, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.primaryContainer : colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? colors.primary
                    : colors.onSurface.withValues(alpha: .18)),
          ),
          child: Text(context.l10n.defaultSnoozeMinutes(value),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      selected ? colors.onPrimaryContainer : colors.onSurface)),
        ),
      ),
    );
  }
}
