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
// - 오래 걸리면(slowThreshold) 진행 중 표시.
// - ⭐ 2026-09-14 (R0-02 교차 리뷰) 실패도 성공도 하지 않고 멈추면(stallThreshold, DB 잠금·
//   플랫폼 호출 정지 등) "다시 시도" 버튼을 보여줌. 예전엔 진행 중 표시만 무기한 이어졌음.
//   진행 중인 옛 시도는 취소할 수 없으므로(Dart Future) 그대로 두고 새 시도를 시작하며,
//   옛 시도의 결과는 무시함. DB 열기는 DatabaseService가 진행 중인 같은 Future를 공유하므로
//   다시 시도해도 마이그레이션이 겹쳐 돌지 않음(contracts §5: 필수 단계는 여러 번 불려도 안전).
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
    this.stallThreshold = const Duration(seconds: 45),
  });

  /// 앱 시작에 반드시 필요한 초기화. 실패하면 예외를 던져야 함.
  final Future<T> Function() initialize;

  /// 초기화 성공 후 실제 앱.
  final Widget Function(T result) builder;

  /// 이 시간이 지나도 안 끝나면 "준비 중" 안내를 보여줌 (측정값이 아니라 빈 화면을
  /// 오래 두지 않기 위한 표시 기준).
  final Duration slowThreshold;

  /// 이 시간이 지나도 안 끝나면 멈춘 것으로 보고 "다시 시도"를 열어줌 (측정값이 아니라
  /// 사용자가 무기한 기다리지 않게 하는 상한 정책값). slowThreshold보다 길어야 함.
  final Duration stallThreshold;

  @override
  State<StartupGate<T>> createState() => _StartupGateState<T>();
}

enum StartupPhase { running, slow, stalled, failed, done }

class _StartupGateState<T> extends State<StartupGate<T>> {
  StartupPhase _phase = StartupPhase.running;
  late T _result;
  Object? _error;
  Timer? _slowTimer;
  Timer? _stallTimer;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _slowTimer?.cancel();
    _stallTimer?.cancel();
  }

  void _run() {
    final attempt = ++_attempt;
    _cancelTimers();
    _slowTimer = Timer(widget.slowThreshold, () {
      if (mounted && attempt == _attempt && _phase == StartupPhase.running) {
        setState(() => _phase = StartupPhase.slow);
      }
    });
    _stallTimer = Timer(widget.stallThreshold, () {
      if (mounted &&
          attempt == _attempt &&
          (_phase == StartupPhase.running || _phase == StartupPhase.slow)) {
        debugPrint('⚠️ 앱 시작 초기화가 ${widget.stallThreshold.inSeconds}초 넘게 끝나지 않음 - 다시 시도 허용');
        setState(() => _phase = StartupPhase.stalled);
      }
    });

    Future<T>.sync(widget.initialize).then(
      (result) {
        if (!mounted || attempt != _attempt) return;
        _cancelTimers();
        setState(() {
          _result = result;
          _phase = StartupPhase.done;
        });
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('❌ 앱 시작 초기화 실패: $error\n$stack');
        if (!mounted || attempt != _attempt) return;
        _cancelTimers();
        setState(() {
          _error = error;
          _phase = StartupPhase.failed;
        });
      },
    );
  }

  void _retry() {
    // 실패했거나 멈춘 경우에만 다시 시작 - 정상 진행 중에는 겹쳐 실행하지 않음.
    if (_phase != StartupPhase.failed && _phase != StartupPhase.stalled) return;
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
              StartupPhase.stalled => SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_bottom, size: 48, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      Text(context.l10n.startupStalledMessage, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: onRetry,
                        child: Text(context.l10n.startupRetry),
                      ),
                    ],
                  ),
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
