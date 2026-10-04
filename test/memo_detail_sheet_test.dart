import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/app_second_button.dart';
import 'package:shiftbell/widgets/memo_detail_sheet.dart';

void main() {
  Future<void> open(WidgetTester tester,
      {String language = 'ko',
      required Future<void> Function(String) save,
      required Future<void> Function() delete}) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(360, 780),
      builder: (_, __) => MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showMemoDetailSheet(
                          context: context,
                          dateLabel: 'October 4',
                          text: 'original memo',
                          onSave: save,
                          onDelete: delete),
                      child: const Text('open'),
                    ))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  final content = find.byKey(const ValueKey('memo-detail-content'));
  final editor = find.byKey(const ValueKey('memo-detail-editor'));
  final save = find.byKey(const ValueKey('memo-detail-save'));
  final delete = find.byKey(const ValueKey('memo-detail-delete'));
  bool enabled(WidgetTester t, Finder f) =>
      t.widget<AppSecondButton>(f).onPressed != null;

  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language tap content opens keyboard; change then undo still enables Save',
        (t) async {
      final saved = <String>[];
      await open(t, language: language, save: (v) async {
        saved.add(v);
      }, delete: () async {});
      expect(enabled(t, delete), isTrue);
      expect(enabled(t, save), isFalse);
      expect(editor, findsNothing);
      await t.tap(content);
      await t.pumpAndSettle();
      expect(editor, findsOneWidget);
      expect(t.testTextInput.isVisible, isTrue);
      expect(enabled(t, save), isFalse);
      expect(enabled(t, delete), isTrue);
      await t.enterText(editor, 'changed');
      await t.pump();
      expect(enabled(t, save), isTrue);
      await t.enterText(editor, 'original memo');
      await t.pump();
      expect(enabled(t, save), isTrue);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(saved, ['original memo']);
      expect(editor, findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  for (final edit in [false, true]) {
    testWidgets('Delete remains usable, editing=$edit', (t) async {
      var deletes = 0;
      await open(t, save: (_) async {
        fail('must not save on deletion');
      }, delete: () async {
        deletes++;
      });
      if (edit) {
        await t.tap(content);
        await t.pumpAndSettle();
        await t.enterText(editor, 'changed');
        await t.pump();
      }
      expect(enabled(t, delete), isTrue);
      await t.tap(delete);
      await t.pumpAndSettle();
      expect(deletes, 1);
      expect(save, findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('empty edit enables Save but validation preserves the memo',
      (t) async {
    var saves = 0;
    await open(t, save: (_) async {
      saves++;
    }, delete: () async {});
    await t.tap(content);
    await t.pumpAndSettle();
    await t.enterText(editor, '   ');
    await t.pump();
    expect(enabled(t, save), isTrue);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(saves, 0);
    expect(editor, findsOneWidget);
    expect(enabled(t, delete), isTrue);
    await t.tap(delete);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
