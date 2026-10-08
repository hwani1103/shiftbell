import 'package:flutter/material.dart';
import '../constants/shift_name_limits.dart';
import '../models/shift_schedule.dart';
import '../l10n/l10n_extensions.dart';
import 'app_second_button.dart';
import 'app_button.dart';
import 'app_shift_chip.dart';
import 'shift_editor_dialog.dart';
import 'shift_name_text_field.dart';

class ShiftNameEdits {
  const ShiftNameEdits(this.renamed, this.deleted, this.added);
  final Map<String, String> renamed;
  final Set<String> deleted;
  final List<String> added;
}

class ShiftNamesDialog extends StatefulWidget {
  const ShiftNamesDialog({super.key, required this.names, required this.used});
  final List<String> names;
  final Set<String> used;
  @override
  State<ShiftNamesDialog> createState() => _ShiftNamesDialogState();
}

class _ShiftNamesDialogState extends State<ShiftNamesDialog> {
  late final _original = {
    for (final name in widget.names) name: TextEditingController(text: name)
  };
  final _added = <TextEditingController>[];
  final _deleted = <String>{};
  final _retired = <TextEditingController>[];
  String? _error;

  @override
  void dispose() {
    for (final c in [..._original.values, ..._added, ..._retired]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final names = [
      ..._original.entries
          .where((e) => !_deleted.contains(e.key))
          .map((e) => e.value.text.trim()),
      ..._added.map((c) => c.text.trim())
    ];
    for (final name in names) {
      final issue = validateShiftName(name) ??
          (names.where((s) => s == name).length > 1
              ? ShiftNameIssue.duplicate
              : null);
      if (issue != null) {
        final l = context.l10n;
        setState(() => _error = switch (issue) {
              ShiftNameIssue.empty => l.onboardingEnterShiftName,
              ShiftNameIssue.tooLong =>
                l.onboardingCharLimitError(shiftNameLengthLimit(name)),
              ShiftNameIssue.comma => l.shiftNameCommaNotAllowed,
              ShiftNameIssue.reserved => l.shiftNameReserved(name),
              ShiftNameIssue.duplicate => l.onboardingDuplicateShiftName,
            });
        return;
      }
    }
    Navigator.pop(
        context,
        ShiftNameEdits({
          for (final e in _original.entries)
            if (!_deleted.contains(e.key) && e.key != e.value.text.trim())
              e.key: e.value.text.trim()
        }, _deleted, _added.map((c) => c.text.trim()).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final count = _original.length - _deleted.length + _added.length;
    Widget row(TextEditingController c, String? old) {
      final locked = old != null && widget.used.contains(old);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (old != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppShiftChip(label: old, dense: true)),
          Row(children: [
            Expanded(
                child: ShiftNameTextField(
                    controller: c,
                    decoration: InputDecoration(
                        labelText: context.l10n.shiftName,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12))))),
            IconButton(
                tooltip: locked
                    ? context.l10n.shiftNameInUse
                    : context.l10n.commonDelete,
                icon: Icon(locked ? Icons.lock_outline : Icons.delete_outline),
                onPressed: locked || count <= 1
                    ? null
                    : () => setState(() {
                          if (old != null) {
                            _deleted.add(old);
                          } else {
                            _added.remove(c);
                            _retired.add(c);
                          }
                        })),
          ]),
          if (locked)
            Text(context.l10n.shiftNameInUse,
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
    }

    return ShiftEditorDialog(
        title: Text(context.l10n.settingsEditShiftNameTitle),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.settingsRenameShiftDesc),
              for (final e in _original.entries)
                if (!_deleted.contains(e.key)) row(e.value, e.key),
              for (final c in _added) row(c, null),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              AppSecondButton(
                  onPressed: count >= kMaxShiftTypes
                      ? null
                      : () => setState(() {
                            _added.add(TextEditingController());
                            _error = null;
                          }),
                  child: Text(
                      '${context.l10n.commonAdd} ($count/$kMaxShiftTypes)')),
            ]),
        actions: [
          AppSecondButton(
              variant: AppSecondButtonVariant.neutral,
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonCancel)),
          AppButton(onPressed: _save, child: Text(context.l10n.commonSave)),
        ]);
  }
}
