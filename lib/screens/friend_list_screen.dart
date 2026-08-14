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

class FriendListScreen extends ConsumerWidget {
  const FriendListScreen({super.key});

  void _showAddFriendDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('친구 추가', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('친구 이름 (선택 - 비우면 코드에 담긴 이름 사용)', style: TextStyle(fontSize: 12.sp)),
              SizedBox(height: 6.h),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: '예: 박영희',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                ),
              ),
              SizedBox(height: 14.h),
              Text('친구가 보내준 공유 코드', style: TextStyle(fontSize: 12.sp)),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            ElevatedButton(
              onPressed: () async {
                final ok = await ref.read(friendProvider.notifier).addFriend(
                      displayName: nameController.text,
                      code: codeController.text,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '친구를 추가했어요' : '코드가 올바르지 않거나 이미 추가된 친구예요')),
                  );
                }
              },
              child: const Text('추가'),
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
        const SnackBar(content: Text('근무표를 불러올 수 없어요. 네트워크 연결을 확인해주세요')),
      );
      return;
    }
    if (!refreshed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최신 정보를 못 받아와서, 이전에 저장된 근무표를 보여드려요')),
      );
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FriendCalendarView(friendName: latest.name, data: latest.data!)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('일정 공유', style: TextStyle(fontSize: 18.sp)),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: friends.isEmpty ? null : () => ref.read(friendProvider.notifier).refreshAll(),
          ),
        ],
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
                  label: Text('내 일정 공유하기', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12.h)),
                ),
                SizedBox(height: 6.h),
                Text(
                  '웹 링크를 통해 앱 설치 없이 내 일정을 공유하고,\n앱을 설치한 사람끼리는 공유 코드로 일정을 공유합니다.',
                  style: TextStyle(fontSize: 12.5.sp, color: colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 16.h),
                ElevatedButton.icon(
                  onPressed: () => _showAddFriendDialog(context, ref),
                  icon: Icon(Icons.person_add_alt, size: 18.sp),
                  label: Text('친구 추가', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12.h)),
                ),
                SizedBox(height: 6.h),
                Text(
                  '친구가 보내준 공유 코드를 입력하세요\n언제든 친구의 일정을 확인할 수 있습니다.',
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
                    child: Text('아직 추가한 친구가 없어요', style: TextStyle(fontSize: 14.sp, color: colorScheme.outline)),
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.read(friendProvider.notifier).refreshAll(),
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4.h),
                          child: ListTile(
                            title: Text(
                              '${friend.name}님의 교대 스케줄',
                              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: colorScheme.error),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('친구 삭제'),
                                    content: Text('${friend.name}님을 목록에서 삭제할까요?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
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
    );
  }
}
