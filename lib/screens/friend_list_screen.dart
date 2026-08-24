// screens/friend_list_screen.dart
//
// ⭐ 일정 공유 메인 화면(구 "친구 공유") - 메인 바텀 네비게이션 4번째 탭으로 승격됨
// (예전엔 설정 탭 안에 "친구 공유 (베타)"로 숨어있었음, lib/main.dart 참고).
// "내 근무표 공유하기"로 이동하는 버튼 + 친구 추가(이름+코드 붙여넣기) + 등록된 친구
// 목록(탭하면 그 친구 달력 보기). 친구공유 v1(Firestore) 전환으로 목록을 당겨서
// 새로고침하면 각 친구의 최신 스케줄을 다시 받아옴 - "베타" 문구/안내 배너는 그래서
// 삭제(예전엔 "친구 추가"를 매번 다시 눌러야 갱신됐음).
// ⭐ "구독"의 핵심은 친구 목록에 그냥 들어있는 게 아니라 "볼 때마다 최신"이어야 한다는
// 것 - 그래서 친구를 탭해서 달력을 열 때마다 로컬 캐시(data_json)를 바로 보여주는 대신
// Firestore에서 한 번 다시 fetch함(_openFriend). 오프라인 등으로 fetch가 실패해도
// 캐시가 있으면 그걸로라도 보여주고, 캐시도 없으면 에러 안내로 끝냄 - 절대 빈 화면으로
// 안 넘어감.
// ⭐ 버튼 두 개만 뜬금없이 있어서 사용성이 떨어진다는 피드백 - 각 버튼 아래 뭘 위한
// 버튼인지 짧은 설명을 붙임. 친구 카드도 원형 아바타/"최신 근무표 동기화됨" 서브타이틀을
// 없애고 "{이름}님의 교대 스케줄" 한 줄로 단순화함.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../providers/friend_provider.dart';
import 'my_share_code_screen.dart';
import 'friend_calendar_view.dart';
import '../l10n/l10n_extensions.dart';

class FriendListScreen extends ConsumerStatefulWidget {
  // ⭐ 2026-08-19 "달력탭으로 가는 스와이프는 항상 일방향" 규칙(next_alarm_tab.dart/
  // settings_tab.dart의 6번 기능 참고 - 달력탭 자체는 좌우 스와이프로 이전/다음달을
  // 넘기므로, 다른 탭에서 달력탭으로 "들어오는" 스와이프만 살려두고 반대 방향은 절대
  // 안 만듦)을 이 탭에도 적용. main.dart 탭 순서가 다음알람(0)/달력(1)/일정공유(2)/
  // 설정(3)이라 일정공유는 설정과 같은 쪽(달력보다 뒤)에 있으므로, 설정탭과 동일하게
  // 좌→우 스와이프 시 달력탭으로 이동.
  final VoidCallback? onSwipeToCalendar;
  const FriendListScreen({super.key, this.onSwipeToCalendar});

  @override
  ConsumerState<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends ConsumerState<FriendListScreen> {
  @override
  void initState() {
    super.initState();
    // ⭐ 상단 "새로고침" 버튼을 없애는 대신, 이 탭에 들어올 때마다(하단 네비게이션은
    // 탭을 전환할 때 이전 탭 위젯을 버리고 새로 만드는 구조라 - main.dart의
    // _tabs[_currentIndex] 참고 - 이 initState가 "탭 진입"마다 매번 실행됨) 조용히
    // 백그라운드에서 전체 새로고침을 시도함. force:false라 마지막 새로고침이
    // 2분 이내면 실제 네트워크 요청 없이 바로 리턴(friend_provider.dart 참고) -
    // 그래서 탭을 빠르게 왔다갔다 해도 Firestore를 반복 호출하지 않음. 로딩 스피너/
    // 토스트 없이 끝내고, 새 데이터가 오면 ref.watch가 알아서 목록을 다시 그림
    // (이미 보이는 캐시 위에 조용히 최신값으로 갈아끼우는 방식).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendProvider.notifier).refreshAll();
    });
  }

  void _showAddFriendDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.friendAdd, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${context.l10n.friendName} ${context.l10n.friendNameOptionalHint}', style: TextStyle(fontSize: 12.sp)),
              SizedBox(height: 6.h),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: context.l10n.friendNameHintExample,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                ),
              ),
              SizedBox(height: 14.h),
              Text(context.l10n.friendShareCodeFromFriend, style: TextStyle(fontSize: 12.sp)),
              SizedBox(height: 6.h),
              TextField(
                controller: codeController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'SB2:...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                ),
                style: TextStyle(fontSize: 11.sp, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
            ElevatedButton(
              onPressed: () async {
                final ok = await ref.read(friendProvider.notifier).addFriend(
                      displayName: nameController.text,
                      code: codeController.text,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? context.l10n.friendAddedToast : context.l10n.friendInvalidCodeOrDuplicate)),
                  );
                }
              },
              child: Text(context.l10n.commonAdd),
            ),
          ],
        );
      },
    );
  }

  // ⭐ 친구를 탭했을 때 - 캐시를 그대로 쓰지 않고 매번 Firestore에서 최신 스케줄을 다시
  // 받아옴("구독처럼" 볼 때마다 최신을 보장). 로딩 중엔 잠깐 스피너만 띄우고(별도 화면
  // 전환 없음), 끝나면 최신 데이터로 달력을 염 - 실패해도 캐시가 있으면 캐시로 열고,
  // 캐시도 없으면 안내만 하고 끝냄(빈 화면 방지).
  Future<void> _openFriend(BuildContext context, WidgetRef ref, FriendEntry friend) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    final refreshed = await ref.read(friendProvider.notifier).refreshFriend(friend.id, friend.ownerId);
    if (!context.mounted) return;
    Navigator.pop(context); // 로딩 다이얼로그 닫기

    final updatedList = ref.read(friendProvider).where((f) => f.id == friend.id);
    final latest = updatedList.isEmpty ? friend : updatedList.first;
    if (latest.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.friendLoadFailedCheckNetwork)),
      );
      return;
    }
    if (!refreshed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.friendShowingCachedSchedule)),
      );
    }
    if (!context.mounted) return;
    final displayName = latest.name.isEmpty ? context.l10n.friendDefaultDisplayName : latest.name;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FriendCalendarView(friendName: displayName, data: latest.data!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // ⭐ 6번 기능: 좌→우 스와이프로 달력탭 이동 (settings_tab.dart와 동일한 방향/임계값)
      onHorizontalDragEnd: (details) {
        if (widget.onSwipeToCalendar != null && details.primaryVelocity != null) {
          // 좌→우 스와이프 (velocity > 0)
          if (details.primaryVelocity! > 500) {
            widget.onSwipeToCalendar!();
          }
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.friendShareTitle, style: TextStyle(fontSize: 18.sp)),
        // ⭐ 상단 새로고침 버튼 삭제 - initState의 자동 새로고침 + 아래
        // RefreshIndicator(당겨서 새로고침)로 충분하고, 버튼이 있으면 사용자가
        // 습관적으로 눌러 불필요한 Firestore 읽기가 반복되기 쉬웠음.
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.w, 16.w, 4.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyShareCodeScreen())),
                  icon: Icon(Icons.qr_code, size: 18.sp),
                  label: Text(context.l10n.friendShareMyScheduleTitle, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12.h)),
                ),
                SizedBox(height: 6.h),
                Text(
                  context.l10n.friendShareChannelsExplainer,
                  style: TextStyle(fontSize: 12.5.sp, color: colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 16.h),
                ElevatedButton.icon(
                  onPressed: () => _showAddFriendDialog(context, ref),
                  icon: Icon(Icons.person_add_alt, size: 18.sp),
                  label: Text(context.l10n.friendAdd, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12.h)),
                ),
                SizedBox(height: 6.h),
                Text(
                  '${context.l10n.friendEnterShareCode}\n${context.l10n.friendCanCheckAnytime}',
                  style: TextStyle(fontSize: 12.5.sp, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          const Divider(height: 1),
          Expanded(
            child: friends.isEmpty
                ? Center(
                    child: Text(context.l10n.friendNoneAddedYet, style: TextStyle(fontSize: 14.sp, color: colorScheme.outline)),
                  )
                : RefreshIndicator(
                    // ⭐ 당겨서 새로고침은 사용자가 명시적으로 요청한 액션이라
                    // force:true로 스로틀 무시하고 항상 새로 받아옴.
                    onRefresh: () => ref.read(friendProvider.notifier).refreshAll(force: true),
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        final displayName = friend.name.isEmpty ? context.l10n.friendDefaultDisplayName : friend.name;
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4.h),
                          child: ListTile(
                            title: Text(
                              context.l10n.friendScheduleOf(displayName),
                              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: colorScheme.error),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(context.l10n.friendRemove),
                                    content: Text(context.l10n.friendRemoveConfirm(displayName)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
                                      TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.commonDelete)),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ref.read(friendProvider.notifier).removeFriend(friend.id);
                                }
                              },
                            ),
                            onTap: () => _openFriend(context, ref, friend),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}
