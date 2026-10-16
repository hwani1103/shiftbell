import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_ui_theme_preview_provider.dart';
import '../providers/app_ui_system_bars_provider.dart';
import '../theme/app_ui_system_bars.dart';
import '../theme/app_ui_theme.dart';
import '../theme/app_ui_time_palettes.dart';

/// Runtime app colors for migrated regions. Calendar designs and splash remain independent.
class AppUiThemeScope extends ConsumerStatefulWidget {
  const AppUiThemeScope(
      {super.key,
      required this.builder,
      this.enabled = true,
      this.preserveTextGeometry = false,
      this.paletteTransform,
      this.inactiveSystemUiStyle});
  final WidgetBuilder builder;
  final bool enabled;
  final bool preserveTextGeometry;
  final AppUiPalette Function(AppUiPalette)? paletteTransform;
  final SystemUiOverlayStyle? inactiveSystemUiStyle;
  @override
  ConsumerState<AppUiThemeScope> createState() => _AppUiThemeScopeState();
}

class _AppUiThemeScopeState extends ConsumerState<AppUiThemeScope>
    with WidgetsBindingObserver {
  late AppUiTimeTheme _period;
  late final Timer _timer;
  bool _contentPresented = false;
  late bool _lastEnabled;
  @override
  void initState() {
    super.initState();
    _lastEnabled = widget.enabled;
    _period = AppUiTimeTheme.forLocalTime(ref.read(appUiThemeClockProvider)());
    WidgetsBinding.instance.addObserver(this);
    _timer =
        Timer.periodic(AppUiTimeTheme.clockCheckInterval, (_) => _checkTime());
  }

  void _checkTime() {
    final next =
        AppUiTimeTheme.forLocalTime(ref.read(appUiThemeClockProvider)());
    if (mounted && next != _period) setState(() => _period = next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkTime();
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(appUiThemePreviewProvider);
    final supportsDarkNavigationIcons =
        ref.watch(appUiDarkNavigationIconsProvider).valueOrNull ?? false;
    // Do not show a temporary day palette before a saved night selection is read.
    if (selected.isLoading && widget.enabled && !_contentPresented) {
      return ColoredBox(color: AppUiPalette.blue.background);
    }
    _contentPresented = true;
    // Legacy and migrated text styles have different inheritance contracts.
    // Switch the boundary directly; animate only within the common palette.
    final modeChanged = _lastEnabled != widget.enabled;
    _lastEnabled = widget.enabled;
    final choice = selected.valueOrNull;
    final source = choice?.palette ??
        ref.watch(appUiThemePaletteOverrideProvider) ??
        _period.palette;
    final palette = widget.paletteTransform?.call(source) ?? source;
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: widget.enabled
            ? AppUiSystemBars.forPalette(palette,
                supportsDarkNavigationIcons: supportsDarkNavigationIcons)
            : AppUiSystemBars.withBlackNavigation(
                widget.inactiveSystemUiStyle ?? SystemUiOverlayStyle.dark),
        child: AnimatedTheme(
            data: widget.enabled
                ? AppUiTheme.withPalette(Theme.of(context), palette,
                    preserveTextGeometry: widget.preserveTextGeometry)
                : Theme.of(context),
            duration: modeChanged
                ? Duration.zero
                : AppUiMotion.transitionDuration(context),
            child: Builder(builder: widget.builder)));
  }
}

/// Modal routes keep the same saved selection and live clock as their source.
Future<T?> showAppUiDialog<T>(
    {required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => UncontrolledProviderScope(
          container: container, child: AppUiThemeScope(builder: builder)));
}

/// The calendar's own ColorScheme must not leak into app-owned editing sheets.
Future<T?> showAppUiBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool useSafeArea = false,
  bool useRootNavigator = false,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    shape: shape ??
        const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppUiMetrics.cardRadius))),
    builder: (_) => UncontrolledProviderScope(
        container: container,
        child: AppUiThemeScope(
            builder: (context) => Material(
                color: backgroundColor ?? AppUiPalette.of(context).surface,
                shape: shape ??
                    const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppUiMetrics.cardRadius))),
                child: DefaultTextStyle.merge(
                    style: TextStyle(color: AppUiPalette.of(context).text),
                    child: Builder(builder: builder))))),
  );
}
