import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'session.dart';
import 'skin.dart';
import 'visuals.dart';
import 'presentation.dart';
import 'gate_visual.dart';
import 'portal_visual.dart';
import 'waypoint_visual.dart';

final class GameBoard extends StatefulWidget {
  final GameSessionController session;
  final GameSkin skin;
  final GameStrings strings;
  final BoardVisuals visuals;
  final Duration visualTime;
  final bool reducedMotion;
  final Duration reactionTime;
  const GameBoard({
    super.key,
    required this.session,
    required this.skin,
    required this.strings,
    this.visuals = const BoardVisuals(),
    this.visualTime = Duration.zero,
    this.reducedMotion = false,
    this.reactionTime = Duration.zero,
  });
  @override
  State<GameBoard> createState() => _GameBoardState();
}

final class _GameBoardState extends State<GameBoard> {
  final _gates = GateVisual();
  final _portals = PortalVisual();
  @override
  void dispose() {
    _gates.dispose();
    _portals.dispose();
    super.dispose();
  }

  Cell? _downCell;
  Offset? _downPosition;
  int? _pointer;
  bool _moved = false;
  Cell? _cell(Offset p, double pitch) {
    if (p.dx < 0 || p.dy < 0) return null;
    final c = Cell((p.dx / pitch).floor(), (p.dy / pitch).floor());
    return widget.session.level.map.contains(c) ? c : null;
  }

  void _activate(Cell cell) {
    final session = widget.session;
    if (!session.editable) return;
    if (session.selectedUnitId == null) {
      final unit = session.level.units
          .where((u) => u.start == cell)
          .firstOrNull;
      if (unit != null) session.selectUnit(unit.id);
    } else {
      session.append(cell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session, level = session.level;
    final skin = widget.skin, strings = widget.strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth,
          level.map.width * GameMetrics.minCellForBoard(level.map.width),
        );
        final pitch = width / level.map.width;
        final height = pitch * level.map.height;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: height,
            child: Listener(
              onPointerDown: (event) {
                if (_pointer != null) {
                  _moved = true;
                  return;
                }
                _pointer = event.pointer;
                _downPosition = event.localPosition;
                _downCell = _cell(event.localPosition, pitch);
                _moved = false;
              },
              onPointerMove: (event) {
                if (event.pointer == _pointer &&
                    _downPosition != null &&
                    (event.localPosition - _downPosition!).distance >
                        kTouchSlop)
                  _moved = true;
              },
              onPointerCancel: (event) {
                if (event.pointer == _pointer) {
                  _pointer = null;
                  _downCell = null;
                }
              },
              onPointerUp: (event) {
                if (event.pointer != _pointer) return;
                final end = _cell(event.localPosition, pitch);
                if (!_moved && end != null && end == _downCell) {
                  _activate(end);
                }
                _pointer = null;
                _downCell = null;
                _downPosition = null;
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GameBoardPainter(
                        session,
                        skin,
                        gates: _gates,
                        portals: _portals,
                        visuals: widget.visuals,
                        visualTime: widget.visualTime,
                        reducedMotion: widget.reducedMotion,
                        reactionTime: widget.reactionTime,
                      ),
                    ),
                  ),
                  for (var y = 0; y < level.map.height; y++)
                    for (var x = 0; x < level.map.width; x++)
                      Positioned(
                        left: x * pitch,
                        top: y * pitch,
                        width: pitch,
                        height: pitch,
                        child: Semantics(
                          key: ValueKey('cell-$x-$y'),
                          label:
                              '${strings.pick('행', 'row')} ${y + 1}, ${strings.pick('열', 'column')} ${x + 1}: ${gateCellLabel(level, Cell(x, y), strings)} ${portalCellLabel(level, Cell(x, y), strings)} ${level.map.isWalkable(Cell(x, y)) ? (Cell(x, y) == level.goal ? strings.goal : strings.pick('열린 칸', 'open cell')) : strings.wall}',
                          button: session.destinations.contains(Cell(x, y)),
                          onTap: session.destinations.contains(Cell(x, y))
                              ? () => _activate(Cell(x, y))
                              : null,
                          child: const Listener(
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox.expand(),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class GameBoardPainter extends CustomPainter {
  final GameSessionController session;
  final GameSkin skin;
  final GateVisual gates;
  final PortalVisual? portals;
  final BoardVisuals visuals;
  final Duration visualTime;
  final bool reducedMotion;
  final Duration reactionTime;
  GameBoardPainter(
    this.session,
    this.skin, {
    required this.gates,
    this.portals,
    this.visuals = const BoardVisuals(),
    this.visualTime = Duration.zero,
    this.reducedMotion = false,
    this.reactionTime = Duration.zero,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final level = session.level;
    final pitch = size.width / level.map.width;
    Offset center(double x, double y) =>
        Offset((x + 0.5) * pitch, (y + 0.5) * pitch);
    Offset tileCenter(Cell c) => center(c.x.toDouble(), c.y.toDouble());
    final legal = session.destinations.toSet();
    final selectedIndex = level.units.indexWhere(
      (u) => u.id == session.selectedUnitId,
    );
    final selectedColor = selectedIndex < 0
        ? skin.primary
        : skin.unitColors[selectedIndex % skin.unitColors.length];
    for (var y = 0; y < level.map.height; y++) {
      for (var x = 0; x < level.map.width; x++) {
        final cell = Cell(x, y);
        visuals.tile.paint(
          canvas,
          Rect.fromLTWH(x * pitch, y * pitch, pitch, pitch),
          TileVisualFrame(
            blocked: !level.map.isWalkable(cell),
            goal: cell == level.goal,
            legalDestination: legal.contains(cell),
            chapter: session.levelIndex ~/ 5,
            destinationColor: selectedColor,
          ),
          skin,
        );
      }
    }
    final routes = session.routes;
    final ordered = routes.toList()
      ..sort(
        (a, b) => a.unitId == session.selectedUnitId
            ? 1
            : b.unitId == session.selectedUnitId
            ? -1
            : a.unitId.compareTo(b.unitId),
      );
    for (final route in ordered) {
      final index = level.units.indexWhere((u) => u.id == route.unitId);
      final start = level.units[index].start;
      final path = Path()..moveTo(tileCenter(start).dx, tileCenter(start).dy);
      for (final end in route.endpoints) {
        path.lineTo(tileCenter(end).dx, tileCenter(end).dy);
        final portal = level.portalAt(end);
        if (portal != null) {
          final exit = tileCenter(portal.exit);
          path.moveTo(exit.dx, exit.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = skin.unitColors[index % skin.unitColors.length].withValues(
            alpha: session.editable
                ? (route.unitId == session.selectedUnitId ? 0.85 : 0.25)
                : 0.18,
          )
          ..strokeWidth =
              session.editable && route.unitId == session.selectedUnitId
              ? 3.2
              : 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      if (route.unitId == session.selectedUnitId) {
        for (final end in route.endpoints) {
          if (end != level.goal)
            canvas.drawCircle(
              tileCenter(end),
              3,
              Paint()..color = skin.unitColors[index % skin.unitColors.length],
            );
        }
      }
    }
    if (session.editable) {
      for (final route in routes) {
        if (route.endpoints.length == level.maxCommands &&
            !route.completes(level)) {
          canvas.drawCircle(
            tileCenter(level.afterEndpoint(route.endpoints.last)),
            pitch * .16,
            Paint()
              ..color = skin.collision
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
          final c = tileCenter(level.afterEndpoint(route.endpoints.last)),
              d = pitch * .06;
          final paint = Paint()
            ..color = skin.collision
            ..strokeWidth = 2;
          canvas.drawLine(c - Offset(d, d), c + Offset(d, d), paint);
          canvas.drawLine(c + Offset(-d, d), c + Offset(d, -d), paint);
        }
      }
    }
    gates.paint(
      canvas,
      level,
      session.trace?.gateTimeline,
      session.replay?.position ?? 0,
      pitch,
      skin,
    );
    portals?.paint(
      canvas,
      level,
      session.trace,
      session.replay?.position ?? 0,
      pitch,
      skin,
      reducedMotion,
    );
    final presentation = const MovementPresentation().frame(
      session,
      visualTime: visualTime,
      reducedMotion: reducedMotion,
      reactionTime: reactionTime,
    );
    for (final unit in presentation.units) {
      final c = center(unit.position.x, unit.position.y);
      if (!visuals.unit.animated &&
          session.selectedUnitId == unit.unitId &&
          session.mode == SessionMode.planning) {
        canvas.drawCircle(
          c,
          GameMetrics.markerRadius + 4,
          Paint()
            ..color = selectedColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
      visuals.unit.paint(canvas, c, pitch, unit, skin);
      // This point is the logical anchor, even if a character jumps or rotates.
      canvas.drawCircle(
        c,
        GameMetrics.coreRadius,
        Paint()..color = skin.onPrimary,
      );
    }
    if (session.mode == SessionMode.planning &&
        session.selectedUnitId != null) {
      final draftEnd = session.currentFor(session.selectedUnitId!);
      final start = level.units
          .singleWhere((u) => u.id == session.selectedUnitId)
          .start;
      if (draftEnd != start) {
        canvas.drawCircle(
          tileCenter(draftEnd),
          GameMetrics.markerRadius * 0.5,
          Paint()
            ..color = skin.selection
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    if (session.editable) paintWaypoints(canvas, routes, pitch, skin);
    for (final cue in presentation.cues) {
      visuals.unit.paintCue(
        canvas,
        center(cue.position.x.toDouble(), cue.position.y.toDouble()),
        pitch,
        cue,
        visualTime,
        reducedMotion,
        skin,
      );
    }
    final shown = <RationalPoint>{};
    for (final event in session.replay?.collisions ?? <CollisionEvent>[]) {
      if (!shown.add(event.position)) continue;
      final c = center(
        event.position.x.toDouble(),
        event.position.y.toDouble(),
      );
      canvas.drawCircle(
        c,
        GameMetrics.markerRadius + 6,
        Paint()
          ..color = skin.collision
          ..style = PaintingStyle.stroke
          ..strokeWidth = GameMetrics.routeWidth,
      );
      canvas.drawLine(
        c - const Offset(5, 5),
        c + const Offset(5, 5),
        Paint()
          ..color = skin.collision
          ..strokeWidth = GameMetrics.routeWidth,
      );
      canvas.drawLine(
        c + const Offset(-5, 5),
        c + const Offset(5, -5),
        Paint()
          ..color = skin.collision
          ..strokeWidth = GameMetrics.routeWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GameBoardPainter oldDelegate) => true;
}
