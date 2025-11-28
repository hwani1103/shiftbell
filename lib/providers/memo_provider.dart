// providers/memo_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/date_memo.dart';
import '../services/database_service.dart';

// ⭐ 메모 상태 관리 Provider
class MemoNotifier extends StateNotifier<Map<String, List<DateMemo>>> {
  MemoNotifier() : super({});

  final _db = DatabaseService.instance;

  // ⭐ 특정 날짜의 메모 로드
  Future<void> loadMemosForDate(String date) async {
    final memos = await _db.getMemosForDate(date);
    state = {...state, date: memos};
  }

  // ⭐ 기간의 메모들 로드 (달력 표시용)
  Future<void> loadMemosForDateRange(DateTime startDate, DateTime endDate) async {
    final memos = await _db.getMemosForDateRange(startDate, endDate);
    state = {...state, ...memos};
  }

  // ⭐ 메모 생성
  Future<bool> createMemo(String date, String memoText) async {
    if (memoText.trim().isEmpty) {
      print('⚠️ 메모 내용이 비어있습니다.');
      return false;
    }

    final id = await _db.createMemo(date, memoText.trim());
    if (id == null) {
      return false;  // 최대 3개 초과
    }

    // 상태 갱신
    await loadMemosForDate(date);
    return true;
  }

  // ⭐ 메모 수정
  Future<void> updateMemo(int id, String date, String memoText) async {
    if (memoText.trim().isEmpty) {
      print('⚠️ 메모 내용이 비어있습니다.');
      return;
    }

    await _db.updateMemo(id, memoText.trim());
    // 상태 갱신
    await loadMemosForDate(date);
  }

  // ⭐ 메모 삭제
  Future<void> deleteMemo(int id, String date) async {
    await _db.deleteMemo(id);
    // 상태 갱신
    await loadMemosForDate(date);
  }

  // ⭐ 메모 순서 변경
  Future<void> reorderMemos(String date, List<int> memoIds) async {
    await _db.reorderMemos(date, memoIds);
    // 상태 갱신
    await loadMemosForDate(date);
  }

  // ⭐ 특정 날짜의 메모 가져오기 (캐시)
  List<DateMemo> getMemosForDate(String date) {
    return state[date] ?? [];
  }

  // ⭐ 전체 상태 초기화
  void clear() {
    state = {};
  }
}

// ⭐ Provider 인스턴스
final memoProvider = StateNotifierProvider<MemoNotifier, Map<String, List<DateMemo>>>(
  (ref) => MemoNotifier(),
);
