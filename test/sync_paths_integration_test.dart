import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/mini_games_screen.dart';
import 'package:shiftbell/services/sync_paths_host.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'Independent progress key round-trips without touching schedule preferences',
      () async {
    SharedPreferences.setMockInitialValues({'schedule_tab_enabled': true});
    final store = SyncPathsProgressStore();
    await store.write('progress');
    expect(await SyncPathsProgressStore().read(), 'progress');
    expect(
        (await SharedPreferences.getInstance()).getBool('schedule_tab_enabled'),
        true);
  });
  test('Host effects release on route disposal and ignore later plays',
      () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncPathsAudio.channel, (call) async {
      methods.add(call.method);
      return null;
    });
    final audio = SyncPathsAudio();
    await audio.initialize();
    audio.play(GameSound.start);
    audio.stop();
    audio.dispose();
    audio.play(GameSound.start);
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['initialize', 'play', 'stop', 'release']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncPathsAudio.channel, null);
  });
  testWidgets(
      'Menu opens integrated game, Lv1 teaches only page1, back returns to mini-games',
      (t) async {
    await t
        .runAsync(() => rootBundle.loadString('assets/sync_paths/levels.json'));
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncPathsAudio.channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncPathsAudio.channel, null));
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!),
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MiniGamesScreen(),
    )));
    await t.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mini-game-sync-paths')));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.byType(SyncPathGameApp), findsOneWidget,
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .join(' | '));
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const ValueKey('test-lock')), findsNothing);
    final app = t.widget<SyncPathGameApp>(find.byType(SyncPathGameApp));
    expect(app.session.unlimitedHearts, false);
    expect(app.session.unlockedIndex, 0);
    final level = find.byKey(const ValueKey('level-0'));
    await t.ensureVisible(level);
    await t.tap(level);
    await t.pumpAndSettle();
    expect(find.text('1/4'), findsOneWidget);
    expect(find.byKey(const ValueKey('help-back')), findsNothing);
    await t.tap(find.byKey(const ValueKey('help-next')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.session.rulesSeen, true);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(app.session.mode, SessionMode.hub);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(SyncPathGameApp), findsNothing);
    expect(find.byKey(const ValueKey('mini-game-sync-paths')), findsOneWidget);
    expect(calls, contains('release'));
    expect(await SyncPathsProgressStore().read(), contains('"rulesSeen":true'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  test('Only game assets and production entry are connected', () {
    final manifest = File('pubspec.yaml').readAsStringSync();
    expect(manifest, contains('assets/sync_paths/levels.json'));
    expect(manifest, isNot(contains('pilot_copy.json')));
    final host = File('lib/screens/mini_games_screen.dart').readAsStringSync();
    expect(host, isNot(contains('SystemNavigator.pop')));
    expect(File('lib/screens/settings_tab.dart').readAsStringSync(),
        contains("ValueKey('settings-mini-games')"));
  });
}
