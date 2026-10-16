import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/src/certificate_verifier.dart';

void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run bin/verify_pilot.dart LEVELS.json CERTIFICATES.json OUTPUT.json',
    );
    exitCode = 64;
    return;
  }
  try {
    final parsed = const LevelParser().parsePack(
      File(arguments[0]).readAsStringSync(),
    );
    if (!parsed.isValid) throw StateError(parsed.issues.join(', '));
    final certificates =
        jsonDecode(File(arguments[1]).readAsStringSync())
            as Map<String, dynamic>;
    final report = verifyCertificates(parsed.value!, certificates);
    File(arguments[2]).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln(
      'PASS: ${report['spatialCombinations']} combinations / ${report['safeSolutions']} solutions across ${parsed.value!.levels.length} levels',
    );
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  }
}
