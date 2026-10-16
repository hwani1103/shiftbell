import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'session.dart';
import 'skin.dart';
import 'board.dart';
import 'visuals.dart';
import 'campaign_visuals.dart';
import 'unit_thumbnail.dart';

final class PuzzleCopy {
  final String titleKo, titleEn;
  final List<String> hintsKo, hintsEn;
  final String? chapterKo, chapterEn;
  const PuzzleCopy(
    this.titleKo,
    this.titleEn,
    this.hintsKo,
    this.hintsEn, {
    this.chapterKo,
    this.chapterEn,
  });
  String title(GameStrings s) => s.pick(titleKo, titleEn);
  String? chapter(GameStrings s) => s.korean ? chapterKo : chapterEn;
  List<String> hints(GameStrings s) => s.korean ? hintsKo : hintsEn;
}

final class SyncPathGameApp extends StatefulWidget {
  final GameSessionController session;
  final Map<String, PuzzleCopy> copy;
  final GameSkin skin;
  final GameStrings strings;
  final VoidCallback? onExit;
  final bool ownsSession;
  final bool showIntro;
  final bool embedded;
  final bool allowTesting;
  final BoardVisuals visuals;
  const SyncPathGameApp({
    super.key,
    required this.session,
    this.copy = const {},
    this.skin = GameSkin.light,
    this.strings = const GameStrings(),
    this.onExit,
    this.ownsSession = false,
    this.showIntro = false,
    this.embedded = false,
    this.allowTesting = true,
    this.visuals = const BoardVisuals(),
  });
  @override
  State<SyncPathGameApp> createState() => _SyncPathGameAppState();
}

final class _SyncPathGameAppState extends State<SyncPathGameApp>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration? _lastElapsed;
  Duration _visualTime = Duration.zero;
  Duration _reactionTime = Duration.zero;
  SessionMode? _lastMode;
  Object? _lastTrace;
  bool _foreground = true;
  bool _reduced = false;
  late BuildContext _pageContext;
  bool _helpOpen = false;
  Timer? _heartTimer;
  final _hubScroll = ScrollController();
  final _levelKeys = <int, GlobalKey>{};
  bool _hubLocated = false;
  GameSessionController get s => widget.session;
  GameSkin get skin => widget.skin;
  GameStrings get words => widget.strings;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    s.setForeground(_foreground);
    _ticker = createTicker((elapsed) {
      final delta = _lastElapsed == null
          ? Duration.zero
          : elapsed - _lastElapsed!;
      _lastElapsed = elapsed;
      _visualTime += delta;
      if (s.mode == SessionMode.replaying) {
        s.advance(delta);
      } else {
        if (s.mode == SessionMode.failureReview ||
            s.mode == SessionMode.successReview)
          _reactionTime += delta;
        _changed();
      }
    });
    s.addListener(_changed);
    _syncHeartTimer();
  }

  void _syncHeartTimer() {
    _heartTimer?.cancel();
    if (_foreground) {
      _heartTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (s.ready) s.tickHearts();
      });
    }
  }

  void _changed() {
    if (_lastMode != s.mode || _lastTrace != s.trace) {
      _reactionTime = Duration.zero;
      _lastMode = s.mode;
      _lastTrace = s.trace;
    }
    final decorate =
        widget.visuals.unit.animated &&
        (s.mode == SessionMode.planning ||
            ((s.mode == SessionMode.failureReview ||
                    s.mode == SessionMode.successReview) &&
                _reactionTime < const Duration(milliseconds: 1200)));
    final play =
        _foreground &&
        !_helpOpen &&
        !_reduced &&
        (s.mode == SessionMode.replaying || decorate);
    if (play && !_ticker.isActive) {
      _lastElapsed = null;
      _ticker.start();
    } else if (!play && _ticker.isActive) {
      _ticker.stop();
      _lastElapsed = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SyncPathGameApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visuals != widget.visuals) oldWidget.visuals.dispose();
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_changed);
      if (oldWidget.ownsSession) oldWidget.session.dispose();
      _ticker.stop();
      _lastElapsed = null;
      widget.session.addListener(_changed);
      _changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    s.setForeground(_foreground);
    _syncHeartTimer();
    if (!_foreground) s.pause();
    _changed();
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _heartTimer?.cancel();
    _hubScroll.dispose();
    widget.visuals.dispose();
    if (widget.ownsSession) s.dispose();
    super.dispose();
  }

  Widget text(String value, GameTextRole role, {Color? color}) =>
      Text(value, style: skin.style(role, color: color));
  Widget button(
    String key,
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
    IconData? icon,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: GameMetrics.smallGap),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return primary
        ? FilledButton(key: ValueKey(key), onPressed: onPressed, child: child)
        : OutlinedButton(
            key: ValueKey(key),
            onPressed: onPressed,
            child: child,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return Theme(data: skin.theme(), child: _page());
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: words.appTitle,
      theme: skin.theme(),
      home: _page(),
    );
  }

  Widget _page() => Builder(
    builder: (context) {
      _pageContext = context;
      if (widget.showIntro &&
          s.ready &&
          s.mode == SessionMode.planning &&
          !_helpOpen &&
          s.levelIndex == 0 &&
          !s.rulesSeen) {
        _helpOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showHelp(intro: true);
        });
      }
      _reduced = MediaQuery.disableAnimationsOf(context);
      if (_reduced && _ticker.isActive)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _changed();
        });
      if (_reduced && s.mode == SessionMode.replaying)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) s.pause();
        });
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(textScaler: TextScaler.noScaling),
        child: PopScope(
          canPop: s.mode == SessionMode.hub && widget.onExit == null,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              if (s.mode == SessionMode.hub) {
                widget.onExit?.call();
              } else {
                s.leave();
              }
            }
          },
          child: Scaffold(
            appBar: s.ready && s.mode == SessionMode.hub
                ? AppBar(
                    title: text(words.appTitle, GameTextRole.section),
                    leading: widget.onExit == null
                        ? null
                        : BackButton(onPressed: widget.onExit),
                    actions: [
                      if (widget.allowTesting)
                        IconButton(
                          key: const ValueKey('test-lock'),
                          tooltip: s.unlockAllForTesting
                              ? words.testMode
                              : words.normalMode,
                          onPressed: s.toggleTesting,
                          icon: Icon(
                            s.unlockAllForTesting
                                ? Icons.lock_open_rounded
                                : Icons.lock_outline_rounded,
                            color: s.unlockAllForTesting
                                ? CampaignColors.focus
                                : skin.secondary,
                          ),
                        ),
                    ],
                  )
                : null,
            body: SafeArea(
              child: s.ready
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        controller: s.mode == SessionMode.hub
                            ? _hubScroll
                            : null,
                        key: ValueKey(
                          s.mode == SessionMode.hub
                              ? 'hub-scroll'
                              : 'game-scroll-${s.levelIndex}',
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: s.mode == SessionMode.hub
                                  ? GameMetrics.maxWidth
                                  : (constraints.maxHeight -
                                            GameMetrics.gameChromeHeight)
                                        .clamp(
                                          s.level.map.width *
                                                  GameMetrics.minCellForBoard(
                                                    s.level.map.width,
                                                  ) +
                                              2 *
                                                  GameMetrics
                                                      .minBoardPagePadding,
                                          GameMetrics.maxWidth,
                                        ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: s.mode == SessionMode.hub
                                    ? GameMetrics.pagePadding
                                    : GameMetrics.smallGap,
                                horizontal: s.mode == SessionMode.hub
                                    ? GameMetrics.pagePadding
                                    : GameMetrics.boardPagePadding(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                        s.level.map.width,
                                      ),
                              ),
                              child: s.mode == SessionMode.hub
                                  ? _hub()
                                  : _game(),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      );
    },
  );

  Widget _notice() {
    final notice = s.notice;
    if (notice == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GameMetrics.smallGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: text(
              switch (notice) {
                SessionNotice.invalidDestination => words.invalid,
                SessionNotice.budgetUsed => words.budget,
                SessionNotice.saveFailed => words.saveError,
                SessionNotice.corruptSave => words.corruptSave,
              },
              GameTextRole.body,
              color: skin.collision,
            ),
          ),
          if (notice == SessionNotice.saveFailed)
            button('retry-save', words.retry, s.retrySave),
        ],
      ),
    );
  }

  Widget _hub() {
    if (!_hubLocated) {
      _hubLocated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _levelKeys[s.levelIndex]?.currentContext;
        if (mounted && s.mode == SessionMode.hub && target != null) {
          Scrollable.ensureVisible(target, alignment: s.hasPlayed ? .35 : 1);
        }
      });
    }
    final done = s.completedLevels.length == s.pack.levels.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (done) text(words.campaignComplete, GameTextRole.body),
        if (s.unlockAllForTesting)
          text(words.testMode, GameTextRole.supporting),
        _notice(),
        text(words.levels, GameTextRole.section),
        const SizedBox(height: GameMetrics.smallGap),
        for (var i = s.pack.levels.length - 1; i >= 0; i--) ...[
          Padding(
            key: _levelKeys.putIfAbsent(i, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: GameMetrics.smallGap),
            child: _levelCard(i),
          ),
        ],
      ],
    );
  }

  Widget _levelCard(int i) {
    final color = CampaignColors.card(i + 1),
        ink = CampaignColors.ink(CampaignColors.card(i + 1));
    final current = i == s.levelIndex;
    return Semantics(
      selected: current,
      child: OutlinedButton(
        key: ValueKey('level-$i'),
        onPressed: i <= s.unlockedIndex ? () => s.openLevel(i) : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 62),
          backgroundColor: color,
          disabledBackgroundColor: color,
          foregroundColor: ink,
          disabledForegroundColor: ink,
          side: BorderSide(
            color: current ? CampaignColors.focus : ink.withValues(alpha: .12),
            width: current ? 3.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              s.isCompleted(i)
                  ? Icons.check_circle_outline
                  : i <= s.unlockedIndex
                  ? Icons.play_arrow_rounded
                  : Icons.lock_outline,
              size: 20,
            ),
            const SizedBox(width: GameMetrics.gap),
            Expanded(child: Text('LV ${i + 1}')),
            if (current) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Future<void> _showHelp({bool intro = false}) async {
    _helpOpen = true;
    s.pause();
    _changed();
    var page = 0;
    final lastPage = intro ? 0 : 3;
    await showDialog<bool>(
      context: _pageContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          return AlertDialog(
            insetPadding: const EdgeInsets.all(GameMetrics.pagePadding),
            title: Row(
              children: [
                Expanded(
                  child: text(words.lessonTitles[page], GameTextRole.section),
                ),
                const SizedBox(width: GameMetrics.smallGap),
                text('${page + 1}/4', GameTextRole.section),
              ],
            ),
            content: SingleChildScrollView(
              key: ValueKey('help-page-$page'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    [
                      Icons.star_rounded,
                      Icons.route_rounded,
                      Icons.key_rounded,
                      Icons.blur_circular_rounded,
                    ][page],
                    size: GameMetrics.lessonIconSize,
                    color: page == 0 ? skin.goalStar : skin.primary,
                  ),
                  const SizedBox(height: GameMetrics.gap),
                  text(words.lessons[page], GameTextRole.body),
                ],
              ),
            ),
            actions: [
              if (!intro)
                TextButton(
                  key: const ValueKey('help-back'),
                  onPressed: page > 0 ? () => update(() => page--) : null,
                  child: Text(words.previous),
                ),
              FilledButton(
                key: const ValueKey('help-next'),
                onPressed: () {
                  if (page < lastPage) {
                    update(() => page++);
                  } else {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: Text(page < lastPage ? words.helpNext : words.helpDone),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (intro) s.markRulesSeen();
    _helpOpen = false;
    _changed();
  }

  void _menuAction(String value) {
    switch (value) {
      case 'sound':
        s.toggleSound();
      case 'restart':
        s.restart();
      case 'exit':
        s.leave();
      case 'edit':
        s.editFailure();
      case 'help':
        _showHelp();
    }
  }

  Widget _game() {
    _hubLocated = false;
    final selected = s.routes
        .where((r) => r.unitId == s.selectedUnitId)
        .firstOrNull;
    final exhausted =
        selected != null &&
        selected.endpoints.length == s.level.maxCommands &&
        !selected.completes(s.level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              key: const ValueKey('level-badge'),
              width: GameMetrics.levelBadgeWidth,
              height: GameMetrics.levelBadgeHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CampaignColors.card(s.levelIndex + 1),
                borderRadius: BorderRadius.circular(GameMetrics.cellRadius),
              ),
              child: text(
                'LV ${s.levelIndex + 1}',
                GameTextRole.section,
                color: CampaignColors.ink(
                  CampaignColors.card(s.levelIndex + 1),
                ),
              ),
            ),
            const Spacer(),
            Tooltip(
              message: s.unlimitedHearts ? words.testMode : words.heartsHelp,
              child: HeartMeter(
                hearts: s.hearts,
                unlimited: s.unlimitedHearts,
                reducedMotion: _reduced,
                skin: skin,
                words: words,
              ),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('game-menu'),
              tooltip: words.menu,
              onOpened: s.pause,
              onSelected: _menuAction,
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'sound',
                  checked: s.soundEnabled,
                  child: Text(words.pick('효과음', 'Sound effects')),
                ),
                PopupMenuItem(
                  value: 'restart',
                  key: const ValueKey('menu-restart'),
                  child: Text(words.restart),
                ),
                if (s.mode == SessionMode.failureReview)
                  PopupMenuItem(
                    value: 'edit',
                    key: const ValueKey('menu-edit'),
                    child: Text(words.edit),
                  ),
                PopupMenuItem(
                  value: 'help',
                  key: const ValueKey('menu-help'),
                  child: Text(words.help),
                ),
                PopupMenuItem(
                  value: 'exit',
                  key: const ValueKey('menu-exit'),
                  child: Text(words.exit),
                ),
              ],
            ),
          ],
        ),
        GameBoard(
          session: s,
          skin: skin,
          strings: words,
          visuals: widget.visuals,
          visualTime: _visualTime,
          reducedMotion: _reduced,
          reactionTime: _reactionTime,
        ),
        const SizedBox(height: GameMetrics.smallGap),
        Row(
          children: [
            for (var i = 0; i < s.level.units.length; i++) ...[
              if (i > 0) const SizedBox(width: GameMetrics.smallGap),
              Expanded(child: _unitCard(i)),
            ],
          ],
        ),
        const SizedBox(height: GameMetrics.smallGap),
        SizedBox(
          height: GameMetrics.playControlsHeight,
          child: AnimatedSwitcher(
            duration: _reduced ? Duration.zero : GameMetrics.transition,
            switchInCurve: Curves.easeOut,
            child: Align(
              key: ValueKey(s.mode),
              alignment: Alignment.topCenter,
              child: _controls(exhausted),
            ),
          ),
        ),
        _notice(),
      ],
    );
  }

  Widget _controls(bool exhausted) {
    if (s.mode == SessionMode.planning)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Tooltip(
                  message: words.undo,
                  child: OutlinedButton(
                    key: const ValueKey('undo'),
                    onPressed: s.canUndo ? s.undo : null,
                    child: Icon(Icons.undo_rounded, semanticLabel: words.undo),
                  ),
                ),
              ),
              const SizedBox(width: GameMetrics.smallGap),
              Expanded(
                flex: 7,
                child: button(
                  'execute',
                  words.execute,
                  s.canExecute
                      ? () => s.execute(reducedMotion: _reduced)
                      : null,
                  primary: true,
                  icon: Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
          if (s.editable && exhausted)
            Semantics(
              liveRegion: true,
              child: text(
                words.exhausted,
                GameTextRole.supporting,
                color: skin.collision,
              ),
            ),
          if (s.editable && s.selectedUnitId == null)
            text(words.chooseBall, GameTextRole.supporting),
          if (s.editable &&
              s.selectedUnitId != null &&
              s.currentFor(s.selectedUnitId!) == s.level.goal &&
              s.routes.any((r) => !r.completes(s.level)))
            text(words.chooseAnother, GameTextRole.supporting),
        ],
      );
    if (s.mode == SessionMode.failureReview ||
        s.mode == SessionMode.successReview) {
      final failed = s.mode == SessionMode.failureReview;
      final gate = s.trace!.gateTimeline.failures;
      final pairs = s.trace!.earliestCollisions;
      final message = !failed
          ? (s.levelIndex == s.pack.levels.length - 1
                ? words.finaleSuccess
                : words.success)
          : gate.isNotEmpty
          ? words.gateFailure(gate.first.unitId, gate.first.gateId)
          : pairs.isNotEmpty
          ? words.collisionUnits(pairs.first.unitIds.join(' · '))
          : words.failure;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: text(
              message,
              GameTextRole.supporting,
              color: failed ? skin.collision : skin.goal,
            ),
          ),
          const SizedBox(height: GameMetrics.smallGap),
          Row(
            children: [
              Expanded(child: button('exit', words.exit, s.leave)),
              const SizedBox(width: GameMetrics.smallGap),
              Expanded(
                child: !failed && s.levelIndex < s.pack.levels.length - 1
                    ? button(
                        'next',
                        words.next,
                        () => s.openLevel(s.levelIndex + 1),
                        primary: true,
                      )
                    : button(
                        'restart',
                        words.restart,
                        s.restart,
                        primary: true,
                      ),
              ),
            ],
          ),
        ],
      );
    }
    if (s.mode == SessionMode.paused)
      return button(
        'resume',
        _reduced ? words.nextScene : words.resume,
        _reduced ? s.nextScene : s.resume,
        primary: true,
      );
    return button('pause', words.pause, s.pause);
  }

  Widget _unitCard(int index) {
    final unit = s.level.units[index];
    final route = s.routes.singleWhere((r) => r.unitId == unit.id);
    final selected = s.editable && unit.id == s.selectedUnitId;
    final done = route.completes(s.level);
    final remaining = s.level.maxCommands - route.endpoints.length;
    final invalid = s.editable && remaining == 0 && !done;
    final color = !s.editable
        ? skin.disabledText
        : invalid
        ? skin.collision
        : skin.unitColors[index % skin.unitColors.length];
    return Semantics(
      selected: selected,
      label: words.unitRemaining(unit.id, remaining, done),
      child: OutlinedButton(
        key: ValueKey('unit-${unit.id}'),
        onPressed: s.editable ? () => s.toggleUnit(unit.id) : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: GameMetrics.unitChipPadding,
          ),
          side: BorderSide(
            color: invalid || selected ? color : skin.border,
            width: selected ? 2.5 : 1,
          ),
          backgroundColor: !s.editable
              ? skin.disabledSurface
              : selected || invalid
              ? color.withValues(alpha: .12)
              : skin.surface,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UnitThumbnail(
              visual: widget.visuals.unit,
              unitId: unit.id,
              paletteIndex: index,
              skin: skin,
            ),
            const SizedBox(width: GameMetrics.unitChipPadding),
            if (done)
              Icon(
                Icons.check_rounded,
                size: GameMetrics.unitChipIcon,
                color: color,
              )
            else
              text('$remaining', GameTextRole.unit, color: color),
          ],
        ),
      ),
    );
  }
}
