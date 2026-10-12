// Invokes explicit expressions in the attached dev VM for device service tests.
// UI-path checks still require real screen actions; this is not their substitute.
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final config = jsonDecode(await File(args.single).readAsString()) as Map;
  final service = await vmServiceConnectUri(config['uri'] as String);
  try {
    final vm = await service.getVM();
    final ref = vm.isolates!.firstWhere((i) => i.name == 'main');
    final isolate = await service.getIsolate(ref.id!);
    if (config['list'] == true) {
      print(jsonEncode(isolate.libraries!.map((l) => l.uri).toList()));
      return;
    }
    final library = isolate.libraries!.firstWhere(
        (l) => l.uri!.endsWith(config['library'] as String));
    final result = await service.evaluate(ref.id!, library.id!,
        config['expression'] as String);
    if (result is! InstanceRef) {
      print(jsonEncode(result.toJson()));
      exitCode = 1;
      return;
    }
    if (config['await'] == true && result.kind != InstanceKind.kString) {
      InstanceRef pendingResult = result;
      final deadline = DateTime.now().add(
          Duration(seconds: config['timeoutSeconds'] as int? ?? 90));
      while (DateTime.now().isBefore(deadline)) {
        final object = await service.getObject(ref.id!, pendingResult.id!) as Instance;
        final fields = object.fields ?? [];
        final states = fields.where((f) => f.decl?.name == '_state');
        final state = states.isEmpty ? null : states.first.value as InstanceRef;
        // Dart's state 4 is a chained Future, not a completed result.
        // Follow it before reading the eventual string/error.
        if (state != null && (int.parse(state.valueAsString!) & 30) == 4) {
          pendingResult = fields.firstWhere(
              (f) => f.decl?.name == '_resultOrListeners').value as InstanceRef;
          continue;
        }
        if (state != null && (int.parse(state.valueAsString!) & 24) != 0) {
          final value = fields.firstWhere(
              (f) => f.decl?.name == '_resultOrListeners').value as InstanceRef;
          final full = await service.getObject(ref.id!, value.id!) as Instance;
          print(jsonEncode(full.toJson()));
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      throw StateError('Remote Future timeout; operation may still be running');
    }
    print(jsonEncode((await service.getObject(ref.id!, result.id!)).toJson()));
  } finally {
    await service.dispose();
  }
}
