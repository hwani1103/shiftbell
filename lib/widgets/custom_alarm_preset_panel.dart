import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_extensions.dart';
import '../providers/custom_alarm_preset_provider.dart';
import 'custom_alarm_widgets.dart';

/// The year/month remains outside this panel, visible in both steps.
class CustomAlarmPresetPanel extends ConsumerWidget {
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onBack, onEdit, onDelete;
  final bool onDarkHeader;
  const CustomAlarmPresetPanel(
      {super.key,
      required this.selectedIndex,
      required this.onSelect,
      required this.onBack,
      required this.onEdit,
      required this.onDelete,
      this.onDarkHeader = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(customAlarmPresetsProvider);
    final scheme = Theme.of(context).colorScheme;
    final fg = onDarkHeader ? Colors.white : scheme.onSurface;
    final accent = onDarkHeader ? Colors.white : scheme.primary;
    final selectedFg = onDarkHeader ? Colors.black87 : scheme.onPrimary;
    Widget action(
            IconData icon, String tooltip, VoidCallback callback, String key) =>
        SizedBox(
            width: 32,
            height: 40,
            child: IconButton(
                key: ValueKey(key),
                padding: EdgeInsets.zero,
                iconSize: 19,
                tooltip: tooltip,
                onPressed: callback,
                icon: Icon(icon, color: fg)));
    Widget slot(int i) {
      final preset = presets[i];
      final selected = selectedIndex == i;
      return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
              color: selected ? accent : fg.withValues(alpha: 0.045),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: selected ? accent : fg.withValues(alpha: 0.25))),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  key: ValueKey('one-tap-slot-$i'),
                  onTap: () => onSelect(i),
                  child: SizedBox(
                      height: 36,
                      child: Center(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: preset.isEmpty
                                      ? Icon(Icons.add, size: 18, color: fg)
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                              if (selected)
                                                Icon(
                                                    customAlarmTypeIcon(
                                                        preset.alarmTypeId),
                                                    size: 12,
                                                    color: selected
                                                        ? selectedFg
                                                        : fg),
                                              if (selected)
                                                const SizedBox(width: 3),
                                              Text(preset.time!,
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: selected
                                                          ? selectedFg
                                                          : fg)),
                                            ]))))))));
    }

    final visible = [
      for (var i = 0; i < presets.length; i++)
        if (!presets[i].isEmpty) i
    ];
    final nextEmpty = presets.indexWhere((preset) => preset.isEmpty);
    if (nextEmpty >= 0) visible.add(nextEmpty);
    return MediaQuery.withNoTextScaling(
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      action(
          Icons.arrow_back_rounded,
          MaterialLocalizations.of(context).backButtonTooltip,
          onBack,
          'one-tap-back'),
      if (selectedIndex == null)
        for (final i in visible)
          Flexible(
              child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                          sizeFactor: animation,
                          axis: Axis.horizontal,
                          axisAlignment: 1,
                          child: child)),
                  child: KeyedSubtree(
                      key: ValueKey('slot-$i-${presets[i].time}'),
                      child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(
                              milliseconds:
                                  MediaQuery.disableAnimationsOf(context)
                                      ? 0
                                      : 280 + visible.indexOf(i) * 35),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: Transform.translate(
                                  offset: Offset((1 - value) * 36, 0),
                                  child: child)),
                          child: SizedBox(width: 60, child: slot(i))))))
      else ...[
        Expanded(child: slot(selectedIndex!)),
        action(Icons.edit_outlined, context.l10n.customAlarmEditTooltip, onEdit,
            'one-tap-edit'),
        action(Icons.delete_outline_rounded, context.l10n.commonDelete,
            onDelete, 'one-tap-delete'),
      ],
    ]));
  }
}
