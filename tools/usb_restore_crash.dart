// Stop the backed-up dev process at a persisted restore boundary, without
// force-stop or rebooting the device. Never used by the application itself.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final config = jsonDecode(await File(args.single).readAsString()) as Map;
  const package = 'com.hwani1103.shiftbell.dev';
  final service = await vmServiceConnectUri(config['uri'] as String);
  final vm = await service.getVM();
  final isolate = vm.isolates!.firstWhere((i) => i.name == 'main');
  final details = await service.getIsolate(isolate.id!);
  final library = details.libraries!.firstWhere(
      (l) => l.uri!.endsWith('services/restore_coordinator.dart'));
  final events = StreamIterator(service.onDebugEvent.where(
      (e) => e.isolate?.id == isolate.id && e.kind == EventKind.kPauseBreakpoint));
  await service.streamListen(EventStreams.kDebug);
  final breakpoint = await service.addBreakpointWithScriptUri(
      isolate.id!, library.uri!, config['line'] as int);
  try {
    await service.evaluate(isolate.id!, library.id!, config['expression'] as String);
    while (await events.moveNext().timeout(const Duration(seconds: 60))) {
      final phase = await service.evaluateInFrame(isolate.id!, 0, 'job.phase.name') as InstanceRef;
      if (phase.valueAsString == config['phase']) {
        final adb = config['adb'] as String;
        final serial = config['serial'] as String;
        final pidResult = await Process.run(adb, ['-s', serial, 'shell', 'pidof', package]);
        final pid = (pidResult.stdout as String).trim();
        if (!RegExp(r'^\d+$').hasMatch(pid)) throw StateError('Ambiguous dev PID');
        final killed = await Process.run(adb,
            ['-s', serial, 'shell', 'run-as', package, 'kill', '-9', pid]);
        if (killed.exitCode != 0) throw StateError('Dev process kill failed');
        print(jsonEncode({'phase': phase.valueAsString, 'killedDevPid': pid, 'result': 'boundary reached; process killed'}));
        return;
      }
      await service.resume(isolate.id!);
    }
  } finally {
    try { await service.removeBreakpoint(isolate.id!, breakpoint.id!); } catch (_) {}
    await events.cancel();
    await service.dispose();
  }
}
