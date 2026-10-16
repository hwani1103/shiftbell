import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';

String boundedRead(String path) {
  final file = File(path);
  if (file.lengthSync() > LevelParser.maxJsonBytes) {
    throw FormatException('inputTooLarge: $path');
  }
  return file.readAsStringSync();
}

/// Core-only independent host: no app services, network, platform plugins or
/// certificate/solver dependency. Output goes only to the explicit output file.
void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run bin/simulate.dart LEVELS.json PLAN.json TRACE.json',
    );
    exitCode = 64;
    return;
  }
  try {
    const parser = LevelParser();
    final pack = parser.parsePack(boundedRead(arguments[0]));
    final plan = parser.parsePlan(boundedRead(arguments[1]));
    final inputIssues = [...pack.issues, ...plan.issues];
    SimulationResult result;
    if (inputIssues.isNotEmpty) {
      result = InvalidPlan(inputIssues);
    } else {
      final matches = pack.value!.levels
          .where(
            (level) =>
                level.identity.levelId == plan.value!.levelIdentity.levelId,
          )
          .toList();
      result = matches.length != 1
          ? InvalidPlan([
              const ValidationIssue(
                IssueCode.staleLevelIdentity,
                'levelIdentity',
              ),
            ])
          : const SimulationEngine().simulate(matches.single, plan.value!);
    }
    final Map<String, Object> output;
    if (result is InvalidPlan) {
      output = {
        'outcome': 'invalidPlan',
        'issues': result.issues.map((i) => i.toJson()).toList(),
      };
      exitCode = 2;
    } else {
      final trace = result as SimulationTrace;
      output = trace.toJson();
    }
    File(arguments[2]).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(output)}\n',
    );
    stdout.writeln(output['outcome']);
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
