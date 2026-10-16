import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/calendar_merged_summary_border.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('merged final row has no vertical stubs or darker bottom intersections',
      () async {
    const side = BorderSide(color: Color(0x80000000), width: 2);
    const border = CalendarMergedSummaryBorder(side: side);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    border.paint(canvas, const Rect.fromLTWH(0, 0, 140, 140),
        rows: const [20, 40, 60, 80, 100, 120],
        columns: const [20, 40, 60, 80, 100, 120]);
    final picture = recorder.endRecording();
    final image = await picture.toImage(140, 140);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    int red(int x, int y) => data!.getUint8((y * 140 + x) * 4);
    expect(red(20, 130), lessThan(255), reason: 'Sunday/Monday stay separate');
    expect(red(40, 130), lessThan(255),
        reason: 'Dates and summary keep their boundary');
    for (final x in [60, 80, 100, 120]) {
      expect(red(x, 110), lessThan(255),
          reason: 'Earlier rows retain their grid');
      expect(red(x, 130), 255,
          reason: 'The merged final row has no hidden vertical grid');
      expect(red(x, 139), red(50, 139),
          reason: 'Bottom border has no doubled alpha at old columns');
    }
    expect(red(50, 139), inInclusiveRange(126, 128));
    image.dispose();
    picture.dispose();
  });
}
