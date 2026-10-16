import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

/// One small, offline poster shown only when the application is launched.
final class GameLaunchSplash extends StatefulWidget {
  static const asset = 'assets/art/sync_paths_splash.webp';
  static const displayDuration = Duration(milliseconds: 1400);
  final Widget child;
  const GameLaunchSplash({super.key, required this.child});

  @override
  State<GameLaunchSplash> createState() => _GameLaunchSplashState();
}

final class _GameLaunchSplashState extends State<GameLaunchSplash> {
  Timer? _timer;
  bool _loading = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading) {
      _loading = true;
      _prepare();
    }
  }

  Future<void> _prepare() async {
    await precacheImage(
      const AssetImage(GameLaunchSplash.asset),
      context,
      onError: (_, _) {},
    );
    if (!mounted) return;
    _timer = Timer(GameLaunchSplash.displayDuration, () {
      if (mounted) setState(() => _finished = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: const GameStrings().appTitle,
      theme: GameSkin.light.theme(),
      home: Scaffold(
        key: const ValueKey('launch-splash'),
        body: SafeArea(
          child: Center(
            child: Image.asset(
              GameLaunchSplash.asset,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              semanticLabel: const GameStrings().appTitle,
              errorBuilder: (_, _, _) => Text(
                const GameStrings().appTitle,
                style: GameSkin.light.style(GameTextRole.title),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
