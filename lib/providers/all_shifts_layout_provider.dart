import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AllShiftsLayout { overview, timeline }

class AllShiftsLayoutController extends AsyncNotifier<AllShiftsLayout> {
  static const preferenceKey = 'all_shifts_layout';
  Future<void> _writes = Future.value();

  @override
  Future<AllShiftsLayout> build() async {
    final value =
        (await SharedPreferences.getInstance()).getString(preferenceKey);
    return AllShiftsLayout.values.where((e) => e.name == value).firstOrNull ??
        AllShiftsLayout.overview;
  }

  Future<void> select(AllShiftsLayout value) {
    state = AsyncData(value);
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!await (await SharedPreferences.getInstance())
          .setString(preferenceKey, value.name)) {
        throw StateError('Timetable layout could not be saved');
      }
    });
    return _writes;
  }
}

final allShiftsLayoutProvider =
    AsyncNotifierProvider<AllShiftsLayoutController, AllShiftsLayout>(
        AllShiftsLayoutController.new);
