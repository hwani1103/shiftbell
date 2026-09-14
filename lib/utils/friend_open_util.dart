// lib/utils/friend_open_util.dart
//
// ⭐ 2026-09-05 - "친구 한 명을 탭했을 때 최신 스케줄을 다시 받아와서 그 친구
// 달력을 여는" 로직을 공용화함. 원래 friend_list_screen.dart 안에 private로만
// 있었는데, 메인 달력탭의 "친구 일정 바로가기" 버튼(calendar_tab.dart)도 똑같은
// 동작(로딩 스피너 → Firestore에서 최신 갱신 → 실패 시 캐시로 대체 안내 →
// FriendCalendarView로 이동)이 필요해져서 두 곳이 나눠 갖지 않고 여기 하나로
// 모음 - 동작이 어긋나는 사고를 피하기 위한 이 프로젝트의 기존 관례
// (alarm_generation_service.dart 등)와 동일한 이유.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_extensions.dart';
import '../providers/friend_provider.dart';
import '../screens/friend_calendar_view.dart';

/// 친구를 탭했을 때 - 캐시를 그대로 쓰지 않고 매번 Firestore에서 최신 스케줄을
/// 다시 받아옴("구독처럼" 볼 때마다 최신을 보장). 로딩 중엔 잠깐 스피너만
/// 띄우고(별도 화면 전환 없음), 끝나면 최신 데이터로 달력을 염 - 실패해도
/// 캐시가 있으면 캐시로 열고, 캐시도 없으면 안내만 하고 끝냄(빈 화면 방지).
Future<void> openFriendCalendar(BuildContext context, WidgetRef ref, FriendEntry friend) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );
  final refreshResult =
      await ref.read(friendProvider.notifier).refreshFriend(friend.id, friend.ownerId);
  if (!context.mounted) return;
  Navigator.pop(context); // 로딩 다이얼로그 닫기

  if (refreshResult == FriendRefreshResult.serverRemoved) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.friendLoadFailedDetailed)),
    );
    return;
  }

  final updatedList = ref.read(friendProvider).where((f) => f.id == friend.id);
  final latest = updatedList.isEmpty ? friend : updatedList.first;
  if (latest.data == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.friendLoadFailedCheckNetwork)),
    );
    return;
  }
  if (refreshResult != FriendRefreshResult.refreshed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.friendShowingCachedSchedule)),
    );
  }
  if (!context.mounted) return;
  final displayName = latest.name.isEmpty ? context.l10n.friendDefaultDisplayName : latest.name;
  // ⭐ 2026-09-11(사용자 요청) - 로딩은 이미 위 스피너 다이얼로그가 다 떠안고
  // 있으니(Firestore 갱신까지 끝난 뒤에야 여기 도달), 정작 이 화면 전환은
  // MaterialPageRoute 기본 애니메이션(Android는 확대+페이드로 서서히
  // 나타나는 ZoomPageTransitionsBuilder) 때문에 "다 그려진 화면이 반투명하게
  // 천천히 나타나는" 것처럼 보였음. 데이터는 이미 다 준비된 상태이니 전환
  // 애니메이션 없이 바로 나타나는 게 자연스럽다고 판단해 duration 0인
  // PageRouteBuilder로 바꿈(뒤로가기도 동일하게 즉시).
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => FriendCalendarView(friendName: displayName, data: latest.data!),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}
