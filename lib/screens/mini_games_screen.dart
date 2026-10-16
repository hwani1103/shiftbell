import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import '../l10n/l10n_extensions.dart';
import '../services/sync_paths_host.dart';
import '../widgets/app_ui_theme_scope.dart';
import '../widgets/settings_appearance.dart';
import '../theme/app_ui_theme.dart';

class MiniGamesScreen extends StatelessWidget {
  const MiniGamesScreen({super.key});
  @override
  Widget build(BuildContext context) => AppUiThemeScope(
      builder: (context) => SettingsAppearance(
          builder: (context) => Scaffold(
                appBar:
                    AppBar(title: Text(context.l10n.settingsMiniGamesTitle)),
                body: Padding(
                  padding: const EdgeInsets.all(AppUiMetrics.pagePadding),
                  child: SettingsGroup(children: [
                    ListTile(
                      key: const ValueKey('mini-game-sync-paths'),
                      leading: const Text('1'),
                      title: const Text('Sync Paths'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const SyncPathsScreen())),
                    )
                  ]),
                ),
              )));
}

/// A game route inside the existing application Navigator, never another app.
class SyncPathsScreen extends StatefulWidget {
  const SyncPathsScreen({super.key});
  @override
  State<SyncPathsScreen> createState() => _SyncPathsScreenState();
}

class _SyncPathsScreenState extends State<SyncPathsScreen> {
  final _audio = SyncPathsAudio();
  GameSessionController? _session;
  late final BoardVisuals _visuals =
      BoardVisuals(unit: RollingBallVisual(), tile: BlockTileVisual());
  bool _failed = false, _exiting = false;
  Timer? _poster;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final parsed = const LevelParser().parsePack(
          await rootBundle.loadString('assets/sync_paths/levels.json'));
      if (!parsed.isValid) throw StateError('Invalid campaign');
      if (!mounted) return;
      final session = GameSessionController(
          parsed.value!, SyncPathsProgressStore(),
          playbackRate: 1.5,
          unlockAllForTesting: false,
          onSound: _audio.play,
          onSilence: _audio.stop);
      _session = session;
      await session.initialize();
      if (!mounted) return;
      unawaited(_audio.initialize());
      _poster = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _poster = null);
      });
      setState(() {});
    } catch (error) {
      debugPrint('Sync Paths could not initialize: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    _audio.stop();
    await _session?.flush();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _poster?.cancel();
    _session?.dispose();
    _audio.dispose();
    // The game widget owns visuals once displayed; poster/error exits own them here.
    if (_session == null || _poster != null || _failed) _visuals.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (_failed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sync Paths')),
        body: Center(child: Text(context.l10n.statusErrorOccurred)),
      );
    }
    if (s == null || !s.ready || _poster != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sync Paths')),
        body: SafeArea(
            child: Center(
                child: Image.asset(
          'assets/sync_paths/splash.webp',
          fit: BoxFit.contain,
          semanticLabel: 'Sync Paths',
        ))),
      );
    }
    return SyncPathGameApp(
      session: s,
      embedded: true,
      allowTesting: false,
      showIntro: true,
      strings: GameStrings(korean: context.usesKoreanFeatures),
      visuals: _visuals,
      onExit: _exit,
    );
  }
}
