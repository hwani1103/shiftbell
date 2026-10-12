import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/permission_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'notification_request_attempted': true});
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') {
        return {
          'notification': 'denied',
          'overlay': 'denied',
          'exactAlarm': 'granted',
          'fullScreen': 'granted',
          'alarmChannel': 'granted',
          'sdk': 37,
        };
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  for (final width in [320.0, 360.0, 662.0, 752.0, 806.0, 932.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final lang in ['ko', 'en', 'de', 'pt', 'hi']) {
        testWidgets('$lang $width x$scale settings label fits visibly',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(MaterialApp(
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const Scaffold(
                body: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: PermissionPanel(actionRequiredOnly: true))),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final kind in ['notification', 'overlay']) {
            final button = find.byKey(ValueKey('permission-$kind'));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final text =
                find.descendant(of: button, matching: find.byType(Text));
            final paragraph = tester.renderObject<RenderParagraph>(text);
            final painter = TextPainter(
                text: paragraph.text,
                textDirection: paragraph.textDirection,
                textScaler: paragraph.textScaler)
              ..layout(maxWidth: paragraph.size.width);
            expect(
                painter.height, lessThanOrEqualTo(paragraph.size.height + .01),
                reason:
                    '$lang complete label must remain visible at large text sizes');
            expect(paragraph.didExceedMaxLines, isFalse);
            final metrics = paragraph.getBoxesForSelection(TextSelection(
                baseOffset: 0,
                extentOffset: paragraph.text.toPlainText().length));
            if (scale == 1) {
              expect(metrics.map((box) => box.top).toSet().length, 1,
                  reason:
                      'normal-size settings word must not split across lines');
            }
            final rect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(24));
            expect(rect.right, lessThanOrEqualTo(width - 24));
            painter.dispose();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
