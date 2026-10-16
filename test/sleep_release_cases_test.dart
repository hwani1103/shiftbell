import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tools/sleep_release_cases.dart';

void main() {
  test('explicit sleep attribution and average policy ledger', () {
    final result = runSleepReleaseCases();
    File('artifacts/sleep_global_2026_10_14/host_attribution_ledger.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    expect(result['errors'], isEmpty);
  });
}
