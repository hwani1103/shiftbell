// lib/services/condition/sleep_overlap.dart
//
// ⭐ 2026-09-22 (출시 전 품질점검 B-2) - 수면 기록끼리 겹칠 때의 두 가지 규칙을 한 곳에 모은 순수 함수.
//
// 1. 합계는 "구간 합집합"으로 센다([mergedSleepMinutesBetween]). 예전 "지난 24시간 수면"은 기록 길이를 단순히
//    더해서, 두 기록이 겹치면 겹친 시간을 두 번 셌다(브리핑이 "충분히 잤다"로 잘못 말할 수 있었음). 이미 저장된
//    겹친 기록이나 Native 경로(위젯·자동 감지)에서 생긴 겹침이 있어도 합계가 틀리지 않게 계산 쪽에서 막는다.
// 2. 사용자가 직접 넣거나 확정할 때는 겹침을 막는다([findOverlappingSleep]). 비교 대상은 확정된 기록(진행 중
//    포함)뿐 - 확인 대기(PENDING) 자동 후보는 사용자가 아직 못 봤을 수 있어서, 그것 때문에 직접 입력이 막히면
//    이유를 알 수 없기 때문이다(겹치는 자동 후보는 확정하려 할 때 막힌다).
//
// ⚠️ 저장 계층(DB)에서 "주 수면 1 + 낮잠 2"를 강제하지 않는다. 주 수면/낮잠은 원래 조회할 때 계산하는 값이고
// (sleep_day_slots.dart), 저장 시점에 강제하면 위젯·자동 감지가 만든 실제 기록을 조용히 버리게 된다.

import '../../models/sleep_record.dart';

/// [from]~[until] 창 안에서 [records]가 덮는 시간(분)을 겹침 없이 센다. 끝나지 않은 기록은 무시한다
/// (호출부가 확정·종료된 기록만 넘기는 것이 원칙).
int mergedSleepMinutesBetween(Iterable<SleepRecord> records, DateTime from, DateTime until) {
  if (!until.isAfter(from)) return 0;
  final spans = <({DateTime s, DateTime e})>[];
  for (final r in records) {
    final end = r.end;
    if (end == null) continue;
    final s = r.start.isAfter(from) ? r.start : from;
    final e = end.isBefore(until) ? end : until;
    if (e.isAfter(s)) spans.add((s: s, e: e));
  }
  if (spans.isEmpty) return 0;
  spans.sort((a, b) => a.s.compareTo(b.s));

  var total = 0;
  var curStart = spans.first.s;
  var curEnd = spans.first.e;
  for (final span in spans.skip(1)) {
    if (span.s.isAfter(curEnd)) {
      total += curEnd.difference(curStart).inMinutes;
      curStart = span.s;
      curEnd = span.e;
    } else if (span.e.isAfter(curEnd)) {
      curEnd = span.e;
    }
  }
  total += curEnd.difference(curStart).inMinutes;
  return total;
}

/// [start]~[end]와 겹치는 확정 수면 기록 하나(가장 이른 것)를 돌려준다. 없으면 null.
/// - [excludeId]: 수정·확정 중인 자기 자신은 뺀다.
/// - 확정됐지만 아직 안 끝난(위젯으로 "수면"만 누른) 기록은 [now]까지 이어지는 것으로 본다.
/// - 끝과 시작이 정확히 맞닿는 것(06:00에 끝나고 06:00에 시작)은 겹침이 아니다.
SleepRecord? findOverlappingSleep(
  Iterable<SleepRecord> records,
  DateTime start,
  DateTime end, {
  int? excludeId,
  DateTime? now,
}) {
  final nowValue = now ?? DateTime.now();
  SleepRecord? found;
  for (final r in records) {
    if (r.status != SleepStatus.confirmed) continue;
    if (excludeId != null && r.id == excludeId) continue;
    final rEnd = r.end ?? (nowValue.isAfter(r.start) ? nowValue : r.start);
    if (r.start.isBefore(end) && rEnd.isAfter(start)) {
      if (found == null || r.start.isBefore(found.start)) found = r;
    }
  }
  return found;
}
