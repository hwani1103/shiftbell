import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/sync_path_tools.dart';

void main(List<String> args) {
  if (args.length != 4) {
    stderr.writeln('Usage: LEVELS.json SAFE_PLAN.json SEED OUTPUT.json');
    exitCode = 64;
    return;
  }
  try {
    final pack = const LevelParser().parsePack(
      File(args[0]).readAsStringSync(),
    );
    final plan = const LevelParser().parsePlan(
      File(args[1]).readAsStringSync(),
    );
    if (!pack.isValid || !plan.isValid)
      throw ArgumentError([...pack.issues, ...plan.issues]);
    final level = pack.value!.levels.singleWhere(
      (l) => l.identity == plan.value!.levelIdentity,
    );
    final candidate = const LevelGenerator().generate(
      level,
      plan.value!,
      seed: int.parse(args[2]),
    );
    File(args[3]).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(candidate.toJson())}\n',
    );
    stdout.writeln(candidate.verified ? 'VERIFIED' : 'UNKNOWN');
    if (!candidate.verified) exitCode = 2;
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}
