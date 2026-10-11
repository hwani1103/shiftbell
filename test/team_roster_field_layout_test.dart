import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/screens/all_teams_setup_screen.dart';
import 'package:shiftbell/services/database_service.dart';
import 'team_schedule_edit_flow_test.dart' as fixture;

void main() {
  late Directory temp;
  setUpAll(() async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('roster_field_');
    await databaseFactory.setDatabasesPath(temp.path);
    DatabaseService.debugIsAndroidOverride = false;
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    await temp.delete(recursive: true);
  });
  for (final width in [320.0, 480.0, 806.0, 1000.0]) {
    testWidgets('roster editor has room to paint existing names at $width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await fixture.mount(tester, AllTeamsSetupScreen(
        pattern: fixture.pattern, myTodayIndex: 1,
        existingTeamNames: const ['A', 'B', 'C', 'D']), width: width);
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      for (final name in ['A', 'B', 'C', 'D']) {
        final field = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == name);
        final state = tester.state<EditableTextState>(field);
        final widget = state.widget;
        final painter = TextPainter(text: TextSpan(text: name, style: widget.style),
          textDirection: TextDirection.ltr, textScaler: widget.textScaler ?? TextScaler.noScaling)..layout();
        expect(state.renderEditable.size.width, greaterThanOrEqualTo(painter.width), reason: name);
        painter.dispose();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
