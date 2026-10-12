import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.ffuf.in_app_update/methods');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late GlobalKey<NavigatorState> nav;
  var checks = 0;
  var available = 2;
  var version = 42;
  var fail = false;
  Completer<void>? gate;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nav = GlobalKey<NavigatorState>();
    checks = 0;
    available = 2;
    version = 42;
    fail = false;
    gate = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expectSync(call.method, 'checkForUpdate');
      checks++;
      await gate?.future;
      if (fail) throw PlatformException(code: 'PLAY_UNAVAILABLE');
      return {'updateAvailability': available, 'availableVersionCode': version,
        'immediateAllowed': false, 'flexibleAllowed': false,
        'installStatus': 0, 'packageName': 'com.hwani1103.shiftbell', 'updatePriority': 0};
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(360, 800),
      builder: (_, __) => MaterialApp(navigatorKey: nav,
        locale: const Locale('ko'), supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate], home: const Scaffold(body: Text('calendar'))),
    ));
    await tester.pumpAndSettle();
  }
  Future<void> expire() async => (await SharedPreferences.getInstance()).remove('play_update_last_checked_at');
  testWidgets('Play unavailable update records cooldown without showing a dialog', (tester) async {
    available = 1;
    await mount(tester);
    await UpdateService.checkForUpdate(nav.currentContext!);
    await UpdateService.checkForUpdate(nav.currentContext!);
    expect(checks, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('failed Play query permits retry and concurrent calls use one query', (tester) async {
    await mount(tester);
    fail = true;
    await UpdateService.checkForUpdate(nav.currentContext!);
    expect((await SharedPreferences.getInstance()).getInt('play_update_last_checked_at'), isNull);
    fail = false;
    available = 1;
    gate = Completer<void>();
    final first = UpdateService.checkForUpdate(nav.currentContext!);
    await tester.pump();
    await UpdateService.checkForUpdate(nav.currentContext!);
    expect(checks, 2);
    expect(find.text('calendar'), findsOneWidget);
    gate!.complete();
    await first;
  });
  testWidgets('later suppresses same version but a newer version is shown; dismiss remains unseen', (tester) async {
    await mount(tester);
    final first = UpdateService.checkForUpdate(nav.currentContext!);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.ensureVisible(find.byType(OutlinedButton));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await first;
    expect((await SharedPreferences.getInstance()).getInt('notified_update_version'), 42);
    await expire();
    await UpdateService.checkForUpdate(nav.currentContext!);
    expect(find.byType(AlertDialog), findsNothing);
    version = 43;
    await expire();
    final next = UpdateService.checkForUpdate(nav.currentContext!);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    await next;
    expect((await SharedPreferences.getInstance()).getInt('notified_update_version'), 42);
  });
  testWidgets('late Play response after disposing context does not open a dialog', (tester) async {
    await mount(tester);
    gate = Completer<void>();
    final pending = UpdateService.checkForUpdate(nav.currentContext!);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate!.complete();
    await pending;
    expect(tester.takeException(), isNull);
    expect((await SharedPreferences.getInstance()).getInt('notified_update_version'), isNull);
  });
}
