import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'package:shiftbell/theme/app_theme.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/app_ui_theme_scope.dart';

class _AdMountProbe extends StatefulWidget {
  const _AdMountProbe();
  @override
  State<_AdMountProbe> createState() => _AdMountProbeState();
}

class _AdMountProbeState extends State<_AdMountProbe> {
  static int mounts = 0;
  @override
  void initState() {
    super.initState();
    mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 64);
}

void main() {
  testWidgets('calendar sheet defaults use the app text color', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppUiThemePreviewController.preferenceKey: 'night',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: Builder(builder: (context) {
              return TextButton(
                  onPressed: () => showAppUiBottomSheet<void>(
                      context: context,
                      builder: (_) => const Text('sheet title',
                          style: TextStyle(fontSize: 24))),
                  child: const Text('open'));
            })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final rich = tester.widget<RichText>(find.descendant(
        of: find.text('sheet title'), matching: find.byType(RichText)));
    expect(rich.text.style!.color, AppUiTimeTheme.night.palette.text);
    Color sheetSurface() => tester
        .widget<Material>(find
            .ancestor(
                of: find.text('sheet title'), matching: find.byType(Material))
            .first)
        .color!;
    expect(sheetSurface(), AppUiTimeTheme.night.palette.surface);
    await container
        .read(appUiThemePreviewProvider.notifier)
        .select(AppUiTimeTheme.daytime);
    await tester.pumpAndSettle();
    expect(sheetSurface(), AppUiTimeTheme.daytime.palette.surface);
    final updated = tester.widget<RichText>(find.descendant(
        of: find.text('sheet title'), matching: find.byType(RichText)));
    expect(updated.text.style!.color, AppUiTimeTheme.daytime.palette.text);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'frame activation, exclusions and preference reload preserve ad mount',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AppUiThemePreviewController.preferenceKey: 'night',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _AdMountProbeState.mounts = 0;
    var enabled = false;
    late StateSetter setFrame;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: StatefulBuilder(builder: (_, setState) {
              setFrame = setState;
              return AppUiThemeScope(
                  enabled: enabled,
                  inactiveSystemUiStyle: SystemUiOverlayStyle.dark,
                  builder: (_) => const _AdMountProbe());
            }))));
    await tester.pumpAndSettle();
    for (final active in [true, false, true, false, true]) {
      setFrame(() => enabled = active);
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(_AdMountProbe)));
      expect(theme.extension<AppUiPalette>()?.background,
          active ? AppUiTimeTheme.night.palette.background : null);
      expect(_AdMountProbeState.mounts, 1);
    }
    container.invalidate(appUiThemePreviewProvider);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_AdMountProbeState.mounts, 1);
    await container
        .read(appUiThemePreviewProvider.notifier)
        .select(AppUiTimeTheme.daytime);
    await tester.pumpAndSettle();
    expect(_AdMountProbeState.mounts, 1);
    final style = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
        .value;
    expect(style.statusBarColor, AppUiTimeTheme.daytime.palette.background);
    expect(style.statusBarIconBrightness, Brightness.dark);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
