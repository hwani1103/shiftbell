import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'package:sync_path_ui/src/campaign_visuals.dart';
import 'gates_campaign_test.dart' show current;
import 'finale_ui_test.dart' show capture;

void main() {
  setUpAll(() async {
    for (final (name, path) in [
      ('packages/sync_path_ui/GameSans', 'assets/fonts/GameSansSubset.ttf'),
      (
        'MaterialIcons',
        'C:/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      await (FontLoader(name)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
  });

  testWidgets(
    'First hub starts at LV1 below LV100, no launch controls or help; game uses compact level colors and 3:7 controls',
    (t) async {
      t.view.physicalSize = const Size(320, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final s = GameSessionController(current(), MemoryProgressStore());
      await s.initialize();
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: SyncPathGameApp(
            session: s,
            visuals: BoardVisuals(
              unit: RollingBallVisual(),
              tile: BlockTileVisual(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Sync Paths'), findsOneWidget);
      expect(find.byKey(const ValueKey('start')), findsNothing);
      expect(find.byKey(const ValueKey('continue')), findsNothing);
      expect(find.text(const GameStrings().tagline), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      final first = find.byKey(const ValueKey('level-0'));
      final last = find.byKey(const ValueKey('level-99'));
      expect(first.hitTestable(), findsOneWidget);
      expect(t.getRect(last).top, lessThan(t.getRect(first).top));
      await capture(t, key, 'hub-lv1-bottom');
      await t.tap(first);
      await t.pumpAndSettle();
      expect(s.selectedUnitId, 'A');
      final undo = find.byKey(const ValueKey('undo'));
      final go = find.byKey(const ValueKey('execute'));
      expect(t.widget(undo), isA<OutlinedButton>());
      expect(t.getSize(undo).height, greaterThanOrEqualTo(48));
      expect(t.getSize(undo).width / t.getSize(go).width, closeTo(3 / 7, .01));
      expect(
        find.descendant(of: undo, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.text('출발'), findsOneWidget);
      expect(
        (t
                    .widget<Container>(
                      find.byKey(const ValueKey('level-badge')),
                    )
                    .decoration
                as BoxDecoration)
            .color,
        CampaignColors.card(1),
      );
      await capture(t, key, 'game-lv1-controls');
      await t.tap(find.byKey(const ValueKey('unit-A')));
      await t.pumpAndSettle();
      expect(s.selectedUnitId, isNull);
      await t.tap(find.byKey(const ValueKey('unit-B')));
      await t.pumpAndSettle();
      expect(s.selectedUnitId, 'B');
      s.leave();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('test-lock')));
      await t.ensureVisible(last);
      await t.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      await capture(t, key, 'hub-lv100-top');
      await t.tap(last);
      await t.pumpAndSettle();
      expect(find.text('LV 100'), findsOneWidget);
      expect(
        (t
                    .widget<Container>(
                      find.byKey(const ValueKey('level-badge')),
                    )
                    .decoration
                as BoxDecoration)
            .color,
        CampaignColors.card(100),
      );
      expect(go.hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await capture(t, key, 'game-lv100-badge');
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
}
