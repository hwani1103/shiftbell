import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/l10n_extensions.dart';
import 'app_second_button.dart';

/// Shared by calendar cells and the memo list on every device size.
Future<void> showMemoDetailSheet({
  required BuildContext context,
  required String dateLabel,
  required String text,
  required Future<void> Function(String) onSave,
  required Future<void> Function() onDelete,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (_) => _MemoDetailSheet(
          dateLabel: dateLabel, text: text, onSave: onSave, onDelete: onDelete),
    );

class _MemoDetailSheet extends StatefulWidget {
  const _MemoDetailSheet(
      {required this.dateLabel,
      required this.text,
      required this.onSave,
      required this.onDelete});
  final String dateLabel;
  final String text;
  final Future<void> Function(String) onSave;
  final Future<void> Function() onDelete;

  @override
  State<_MemoDetailSheet> createState() => _MemoDetailSheetState();
}

class _MemoDetailSheetState extends State<_MemoDetailSheet> {
  late final _controller = TextEditingController(text: widget.text);
  bool _editing = false;
  bool _edited = false;
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    FocusScope.of(context).unfocus();
    var completed = false;
    try {
      await action();
      completed = true;
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted && !completed) setState(() => _working = false);
    }
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.statusEnterMemoContent)));
      return;
    }
    _perform(() => widget.onSave(text));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 36.w,
                      height: 4.h,
                      margin: EdgeInsets.only(bottom: 16.h),
                      decoration: BoxDecoration(
                          color: colors.outline,
                          borderRadius: BorderRadius.circular(2.r)))),
              Row(children: [
                Icon(Icons.event_note_rounded,
                    size: 18.sp, color: colors.primary),
                SizedBox(width: 6.w),
                Expanded(
                    child: Text(widget.dateLabel,
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: colors.primary))),
              ]),
              SizedBox(height: 12.h),
              if (_editing)
                TextField(
                  key: const ValueKey('memo-detail-editor'),
                  controller: _controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 5,
                  // Editing is an interaction flag, not a comparison with the
                  // original text. Undoing back to the original still enables Save.
                  onChanged: (_) {
                    if (!_edited) setState(() => _edited = true);
                  },
                  decoration: InputDecoration(
                    hintText: context.l10n.calendarMemoContent,
                    contentPadding: EdgeInsets.all(12.w),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: colors.outline)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide:
                            BorderSide(color: colors.primary, width: 2)),
                  ),
                  style: TextStyle(fontSize: 14.sp),
                )
              else
                InkWell(
                  key: const ValueKey('memo-detail-content'),
                  borderRadius: BorderRadius.circular(10.r),
                  onTap: () => setState(() => _editing = true),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(10.r)),
                    child: Text(widget.text,
                        style: TextStyle(
                            fontSize: 14.sp,
                            color: colors.onSurface,
                            height: 1.5)),
                  ),
                ),
              SizedBox(height: 16.h),
              Row(children: [
                Expanded(
                    child: AppSecondButton(
                  key: const ValueKey('memo-detail-delete'),
                  variant: AppSecondButtonVariant.danger,
                  onPressed: () => _perform(widget.onDelete),
                  child: Text(context.l10n.commonDelete),
                )),
                SizedBox(width: 10.w),
                Expanded(
                    child: AppSecondButton(
                  key: const ValueKey('memo-detail-save'),
                  variant: _editing
                      ? AppSecondButtonVariant.success
                      : AppSecondButtonVariant.primary,
                  onPressed: _edited && !_working ? _save : null,
                  child: Text(_editing
                      ? context.l10n.commonSave
                      : context.l10n.commonEdit),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
