// lib/providers/health_tip_provider.dart
//
// ⭐ 2026-09-01 후속11 - "교대근무 건강 & 수면 관리 Tip" 데이터 준비.
// Firestore `health_tips` 컬렉션(문서마다 icon/title/content 3필드)을 읽되,
// friend_share의 app_config와 동일한 "읽기 전용 원격 설정" 패턴 - Firebase
// 미설정/오프라인/컬렉션이 비어있으면 health_tips_catalog.dart 로컬 15개로
// 조용히 대체함(사용자가 나중에 Firebase 콘솔에서 문서를 추가하면 앱이 별도
// 배포 없이 자동으로 반영). "오늘의 컨디션"(today_forecast_engine.dart)과는
// 완전히 무관 - 그쪽 provider를 전혀 안 읽음.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/health_tip.dart';
import '../services/condition/health_tips_catalog.dart';
import '../services/firebase_bootstrap.dart';

const String _kHealthTipsCollection = 'health_tips';

final healthTipsListProvider = FutureProvider<List<HealthTip>>((ref) async {
  if (!firebaseReady) return kHealthTipsCatalog;
  try {
    final snapshot = await FirebaseFirestore.instance.collection(_kHealthTipsCollection).get();
    if (snapshot.docs.isEmpty) return kHealthTipsCatalog;
    return snapshot.docs.map((d) => HealthTip.fromMap(d.data())).toList();
  } catch (_) {
    // ⭐ 친구공유와 동일한 방어 - 네트워크 실패 등으로 못 읽으면 로컬 목록으로
    // 조용히 대체(사용자가 팁을 아예 못 보는 것보단 로컬 기본값이 나음).
    return kHealthTipsCatalog;
  }
});

/// 매일 하나씩 순서대로 돌아가며 보여줌(사용자 요청 - "골고루 로테이션",
/// 해시 기반 의사난수가 아니라 단순 나머지 연산이라 모든 팁이 빠짐없이
/// 균등하게 돌아감). 리스트 길이가 바뀌어도(Firestore에 팁 추가) 다음날부터
/// 자연스럽게 새 길이 기준으로 순환됨.
final todayHealthTipProvider = Provider<HealthTip?>((ref) {
  final tipsAsync = ref.watch(healthTipsListProvider);
  final tips = tipsAsync.value;
  if (tips == null || tips.isEmpty) return null;
  final dayNumber = DateTime.now().difference(DateTime(2020, 1, 1)).inDays;
  return tips[dayNumber % tips.length];
});
