// Run after: dart run flutter_launcher_icons -f flutter_launcher_icons_web.yaml
// Packaging existing app artwork only; keep the maskable background opaque and
// the clock/bell inside the central safe area of circular launcher masks.
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final background = img.decodePng(
      File('assets/icon/app_icon_background.png').readAsBytesSync())!;
  final foreground = img.decodePng(
      File('assets/icon/app_icon_foreground.png').readAsBytesSync())!;
  for (final size in [192, 512]) {
    final output = img.copyResize(background,
        width: size, height: size, interpolation: img.Interpolation.cubic);
    final edge = (size * .78).round();
    final layer = img.copyResize(foreground,
        width: edge, height: edge, interpolation: img.Interpolation.cubic);
    img.compositeImage(output, layer,
        dstX: (size - edge) ~/ 2, dstY: (size - edge) ~/ 2);
    File('web/icons/Icon-maskable-$size.png')
        .writeAsBytesSync(img.encodePng(output));
  }
  final manifest = File('web/manifest.json');
  final data = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
  for (final icon in data['icons'] as List) {
    icon['src'] = '${(icon['src'] as String).split('?').first}?v=20260930';
  }
  manifest.writeAsStringSync(
      '${const JsonEncoder.withIndent('    ').convert(data)}\n');
}
