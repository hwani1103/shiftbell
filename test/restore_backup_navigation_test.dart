import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/backup_payload.dart';
import 'package:shiftbell/screens/restore_backup_screen.dart';

void main() {
  final payload = BackupPayload(
      schemaVersion: 2,
      exportedAt: DateTime(2026, 10, 1),
      appVersionName: 'test',
      appVersionCode: 1,
      tables: const {},
      preferences: const {});
  Widget app(Widget home) => ScreenUtilInit(
      designSize: const Size(360, 780),
      builder: (_, __) => MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home));
  for (final hardware in [false, true]) {
    testWidgets(
        'startup back leaves app without choosing restore/skip hardware=$hardware',
        (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(app(RestoreBackupScreen(payload: payload)));
      await tester.pumpAndSettle();
      if (hardware) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byType(BackButtonIcon));
      }
      await tester.pumpAndSettle();
      expect(calls.where((method) => method == 'SystemNavigator.pop'),
          hasLength(1));
      expect(find.byType(RestoreBackupScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'pushed recovery returns to existing screen and preserves its state',
      (tester) async {
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                child: const Text('existing draft'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        RestoreBackupScreen(payload: payload))))))));
    await tester.tap(find.text('existing draft'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RestoreBackupScreen), findsNothing);
    expect(find.text('existing draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('explicit cancellation callback receives system back',
      (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(app(
        RestoreBackupScreen(payload: payload, onCancel: () => cancelled++)));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cancelled, 1);
  });
}
