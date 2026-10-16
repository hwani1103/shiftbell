import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/calendar_date_grid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('moving table border preserves the former stationary outline pixels',
      () async {
    for (final horizontal in [false, true]) {
      for (final count in [2, 4, 5, 6]) {
        Future<List<int>> render(bool table) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(Colors.white, BlendMode.src);
          const side = BorderSide(color: Color(0x80000000), width: 2);
          if (table) {
            CalendarDateGridBorder(
                    side: side,
                    lastRowColumns: count,
                    horizontalRows: horizontal)
                .paint(canvas, const Rect.fromLTWH(7, 9, 140, 140),
                    rows: const [20, 40, 60, 80, 100, 120],
                    columns: const [20, 40, 60, 80, 100, 120]);
          } else {
            canvas.translate(7, 9);
            CalendarDateGrid(
                    side: side,
                    headerHeight: 20,
                    rowHeight: 20,
                    lastRowColumns: count,
                    horizontalRows: horizontal)
                .paint(canvas, const Size(140, 140));
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(160, 160);
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          final result = List<int>.of(bytes);
          image.dispose();
          picture.dispose();
          return result;
        }

        expect(await render(true), await render(false));
      }
    }
  });
  for (final count in [2, 4, 5, 6]) {
    test('date outline closes $count final cells without boxing actions',
        () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      CalendarDateGrid(
              side: const BorderSide(color: Color(0x80000000), width: 2),
              headerHeight: 20,
              rowHeight: 20,
              lastRowColumns: count,
              horizontalRows: false)
          .paint(canvas, const Size(140, 140));
      final picture = recorder.endRecording();
      final image = await picture.toImage(140, 140);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int red(int x, int y) => bytes.getUint8((y * 140 + x) * 4);
      expect(red(count * 20, 130), lessThan(255),
          reason: 'Last date has its right edge');
      expect(red(count * 20 - 10, 139), inInclusiveRange(126, 128));
      expect(red(count * 20 + 10, 120), lessThan(255),
          reason: 'Fifth row closes above actions');
      expect(red(count * 20 + 10, 139), 255,
          reason: 'No table edge below actions');
      expect(red(count * 20 + 10, 130), 255,
          reason: 'Actions remain outside table');
      expect(red(10, 40), 255,
          reason: 'Minimal design has no added row dividers');
      expect(red(20, 139), red(10, 139),
          reason: 'No doubled alpha at intersections');
      image.dispose();
      picture.dispose();
    });
  }
}
