import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'gates_campaign_test.dart' show current;
import 'support.dart' show enter, fromJson;

const evidence = '../../docs/next_version_27이후/game_implementation_v11';
void main() {
  test(
    'One hundred stages preserve all seventy gameplay identities and maps',
    () {
      final old = jsonDecode(
        File('$evidence/previous_70_pilot_levels.json').readAsStringSync(),
      );
      final live = jsonDecode(
        File(
          '../../examples/sync_path_lab/assets/pilot_levels.json',
        ).readAsStringSync(),
      );
      expect(live['packId'], old['packId']);
      expect(live['revision'], old['revision']);
      expect((live['levels'] as List).take(70).toList(), old['levels']);
      final pack = current();
      expect(pack.levels.length, 100);
      for (final l in pack.levels.skip(70)) {
        expect(l.gates.length, lessThanOrEqualTo(2));
        expect(l.portals.length, lessThanOrEqualTo(2));
        expect(l.maxCommands, greaterThan(5));
        expect(l.map.width, l == pack.levels.last ? 8 : 7);
      }
      final copy =
          jsonDecode(
                File(
                  '../../examples/sync_path_lab/assets/pilot_copy.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final c in copy.values) {
        expect(
          (c as Map).keys.any((k) => k.toString().startsWith('title')),
          false,
        );
        for (final language in ['hintsKo', 'hintsEn']) {
          expect(RegExp(r'\b[A-D]:').hasMatch(c[language].join('\n')), false);
        }
      }
    },
  );
  test(
    'Every final-stage certified solution is editable, persisted and runs to success',
    () async {
      final pack = current();
      final design = jsonDecode(
        File('$evidence/finale_design.json').readAsStringSync(),
      );
      final proof = jsonDecode(
        File('$evidence/finale_verification.json').readAsStringSync(),
      );
      expect(proof['levels'].length, 30);
      for (var i = 70; i < 100; i++) {
        final store = MemoryProgressStore();
        final s = GameSessionController(
          pack,
          store,
          unlockAllForTesting: true,
          playbackRate: 1.5,
        );
        await s.initialize();
        s.openLevel(i);
        expect(s.selectedUnitId, 'A');
        enter(s, fromJson(design['levels'][i - 70]['witness']));
        expect(s.canExecute, true);
        await s.flush();
        final restored = GameSessionController(
          pack,
          store,
          unlockAllForTesting: true,
        );
        await restored.initialize();
        restored.openLevel(i);
        expect(restored.selectedUnitId, 'A');
        expect(restored.canExecute, true);
        expect(
          restored.routes.map((r) => r.toJson()).toList(),
          s.routes.map((r) => r.toJson()).toList(),
        );
        s.execute();
        expect(s.trace!.outcome, SimulationOutcome.success);
        s.advance(const Duration(hours: 1));
        expect(s.mode, SessionMode.successReview);
        expect(
          proof['levels'][i - 70]['minimumRequiredMaxCommands'],
          s.level.maxCommands,
        );
        expect(
          proof['levels'][i - 70]['minimumExtraDistance'],
          greaterThanOrEqualTo(
            i < 80
                ? 4
                : i < 90
                ? 6
                : 8,
          ),
        );
        s.dispose();
        restored.dispose();
      }
    },
  );
}
