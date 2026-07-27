// providers/overtime_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';

// ⭐ 날짜별 OT(추가근무) 누적 시간 상태 관리 (date 'YYYY-MM-DD' -> 분)
// date_memos와 동일한 패턴: 달이 바뀔 때 그 달 범위를 통째로 다시 불러와 캐시함
class OvertimeNotifier extends StateNotifier<Map<String, int>> {
  OvertimeNotifier() : super({});

  final _db = DatabaseService.instance;

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ⭐ 달력에 보이는 범위(이전/다음 달 일부 포함) 로드
  Future<void> loadForRange(DateTime startDate, DateTime endDate) async {
    final data = await _db.getOvertimeForRange(startDate, endDate);

    // ⭐ 범위 안의 날짜는 전부 최신 상태로 교체해야 함(0이 된 날짜는 DB에 row가
    // 없으므로 data에도 없는데, 캐시에 예전 값이 남아있으면 안 지워지는 문제 방지)
    final newState = Map<String, int>.from(state);
    for (var d = startDate; !d.isAfter(endDate); d = d.add(const Duration(days: 1))) {
      newState.remove(_dateKey(d));
    }
    newState.addAll(data);
    state = newState;
  }

  // ⭐ 30분 단위 증감. 성공 시 그 날짜의 새 누적 시간(분) 반환
  Future<int> adjust(String date, int deltaMinutes) async {
    final newTotal = await _db.adjustOvertime(date, deltaMinutes);
    final newState = Map<String, int>.from(state);
    if (newTotal > 0) {
      newState[date] = newTotal;
    } else {
      newState.remove(date);
    }
    state = newState;
    return newTotal;
  }

  // ⭐ 특정 날짜 OT (캐시)
  int getForDate(String date) => state[date] ?? 0;

  // ⭐ 특정 연/월의 누적 OT 합계 (분)
  int getMonthTotal(int year, int month) {
    final prefix = '$year-${month.toString().padLeft(2, '0')}-';
    var total = 0;
    for (final entry in state.entries) {
      if (entry.key.startsWith(prefix)) total += entry.value;
    }
    return total;
  }

  // ⭐ 특정 연/월의 날짜별 OT 목록 (날짜 오름차순)
  List<MapEntry<String, int>> getMonthEntries(int year, int month) {
    final prefix = '$year-${month.toString().padLeft(2, '0')}-';
    final entries = state.entries.where((e) => e.key.startsWith(prefix)).toList();
    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  void clear() {
    state = {};
  }
}

final overtimeProvider = StateNotifierProvider<OvertimeNotifier, Map<String, int>>(
  (ref) => OvertimeNotifier(),
);
