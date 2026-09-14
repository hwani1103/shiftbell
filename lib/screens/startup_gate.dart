// lib/screens/startup_gate.dart
//
// ⭐ 2026-09-14 (G0, 출시전_코드감사_검토결과_v4 V4 + #8) - 앱 시작 초기화 게이트.
// 예전 main()은 runApp() 전에 날짜 포맷/DB 열기/Firebase/광고 초기화를 try/catch 없이
// 차례로 await했음 → 하나라도 실패하거나 멈추면 runApp이 불리지 않아 런치 화면에서
// 그대로 멈추고 다시 시도할 방법이 없었음. #8 이후로는 DB 마이그레이션 실패(저장공간
// 부족 등)를 더 이상 삼키지 않으므로, 이 실패가 실제로 사용자에게 드러날 수 있어서
// 반드시 함께 필요함.
//
// - 필수 초기화가 실패하면 안내 + "다시 시도". 릴리스 빌드에서는 예외 원문을 보여주지 않음.
// - 오래 걸리면(slowThreshold) 진행 중 표시만 함. 진행 중인 초기화를 취소하거나 중복
//   실행하지 않음(DB 마이그레이션 트랜잭션 도중일 수 있고, Dart Future는 취소도 안 됨).
// - 성공하면 builder로 실제 앱을 그림.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_theme.dart';

class StartupGate<T> extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.initialize,
    required this.builder,
    this.slowThreshold = const Duration(seconds: 15),
  });

  /// 앱 시작에 반드시 필요한 초기화. 실패하면 예외를 던져야 함.
  final Future<T> Function() initialize;

  /// 초기화 성공 후 실제 앱.
  final Widget Function(T result) builder;

  /// 이 시간이 지나도 안 끝나면 "준비 중" 안내를 보여줌 (측정값이 아니라 빈 화면을
  /// 오래 두지 않기 위한 표시 기준).
  final Duration slowThreshold;

  @override
  State<StartupGate<T>> createState() => _StartupGateState<T>();
}

enum StartupPhase { running, slow, failed, done }

class _StartupGateState<T> extends State<StartupGate<T>> {
  StartupPhase _phase = StartupPhase.running;
  late T _result;
  Object? _error;
  Timer? _slowTimer;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  void _run() {
    final attempt = ++_attempt;
    _slowTimer?.cancel();
    _slowTimer = Timer(widget.slowThreshold, () {
      if (mounted && attempt == _attempt && _phase == StartupPhase.running) {
        setState(() => _phase = StartupPhase.slow);
      }
    });

    Future<T>.sync(widget.initialize).then(
      (result) {
        if (!mounted || attempt != _attempt) return;
        _slowTimer?.cancel();
        setState(() {
          _result = result;
          _phase = StartupPhase.done;
        });
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('❌ 앱 시작 초기화 실패: $error\n$stack');
        if (!mounted || attempt != _attempt) return;
        _slowTimer?.cancel();
        setState(() {
          _error = error;
          _phase = StartupPhase.failed;
        });
      },
    );
  }

  void _retry() {
    // 진행 중에는 다시 시작하지 않음 - 같은 초기화가 겹쳐 돌지 않게.
    if (_phase != StartupPhase.failed) return;
    setState(() {
      _error = null;
      _phase = StartupPhase.running;
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == StartupPhase.done) return widget.builder(_result);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: StartupStatusScreen(
        phase: _phase,
        errorDetail: kReleaseMode ? null : _error?.toString(),
        onRetry: _retry,
      ),
    );
  }
}

class StartupStatusScreen extends StatelessWidget {
  const StartupStatusScreen({
    super.key,
    required this.phase,
    required this.onRetry,
    this.errorDetail,
  });

  final StartupPhase phase;
  final VoidCallback onRetry;

  /// 디버그/프로필 빌드에서만 전달됨. 릴리스에서는 항상 null.
  final String? errorDetail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (phase) {
              // 런치 화면과 같은 빈 흰 화면 (짧게 끝나는 정상 시작에서 깜빡임 방지).
              StartupPhase.running || StartupPhase.done => const SizedBox.shrink(),
              StartupPhase.slow => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(context.l10n.startupSlowMessage, textAlign: TextAlign.center),
                  ],
                ),
              StartupPhase.failed => SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.startupFailedTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(context.l10n.startupFailedBody, textAlign: TextAlign.center),
                      if (errorDetail != null) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          errorDetail!,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: onRetry,
                        child: Text(context.l10n.startupRetry),
                      ),
                    ],
                  ),
                ),
            },
          ),
        ),
      ),
    );
  }
}
