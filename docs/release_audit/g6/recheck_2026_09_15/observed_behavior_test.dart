// Diagnostic probes: PASS means the documented unsafe behavior was observed,
// not that the product meets its release requirements. No production edits.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/services/app_restart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  test('AUD-02: a new ring after the last check does not prevent restart', () async {
    var ringing = false;
    var checks = 0;
    var restartedWhileRinging = false;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'isAlarmRingingLive') {
        checks++;
        Future<void>.delayed(const Duration(milliseconds: 100), () { ringing = true; });
        return false;
      }
      if (call.method == 'restartApp') {
        restartedWhileRinging = ringing;
        return true;
      }
      return null;
    });
    await restartAppWhenNoAlarmRinging();
    expect(checks, 1);
    expect(restartedWhileRinging, isTrue);
  });

  test('AUD-02: unknown ring state is treated as safe to restart', () async {
    var restarted = false;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'isAlarmRingingLive') {
        throw PlatformException(code: 'INJECTED_CHANNEL_FAILURE');
      }
      if (call.method == 'restartApp') { restarted = true; return true; }
      return null;
    });
    await restartAppWhenNoAlarmRinging();
    expect(restarted, isTrue);
  });

  testWidgets('AUD-01: barrierDismissible false alone permits system back', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      pageContext = context;
      return const Scaffold(body: Text('calendar'));
    })));
    // Same dialog configuration as CalendarTab._bulkAssignShift. This checks
    // framework route behavior; it does not claim an end-to-end CalendarTab run.
    showDialog<void>(
      context: pageContext,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(Navigator.of(pageContext).canPop(), isFalse);
  });
}
