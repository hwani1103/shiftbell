// lib/models/health_tip.dart
//
// ⭐ 2026-09-01 후속11 - "교대근무 건강 & 수면 관리 Tip" 카드용 모델(사용자
// 요청 - 오늘의 컨디션 판정과는 무관한 범용 건강 상식). 필드는 딱 3개(아이콘/
// 제목/내용)만 - 번호 없음. Firestore `health_tips` 컬렉션에서 읽어오되,
// Firebase 미설정/오프라인이면 health_tips_catalog.dart의 로컬 목록으로
// 대체함(친구공유 app_config와 동일한 "읽기 전용 원격 설정" 패턴).

class HealthTip {
  final String icon; // 이모지 1개
  final String title; // 제목(예: "수면")
  final String content; // 본문 2~3줄

  const HealthTip({required this.icon, required this.title, required this.content});

  factory HealthTip.fromMap(Map<String, dynamic> map) => HealthTip(
        icon: (map['icon'] as String?) ?? '💡',
        title: (map['title'] as String?) ?? '',
        content: (map['content'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => {'icon': icon, 'title': title, 'content': content};
}
