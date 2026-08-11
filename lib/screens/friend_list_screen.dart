// screens/friend_list_screen.dart
//
// ⭐ 친구 공유 (베타) 메인 화면 - "내 공유 코드 만들기"로 이동하는 버튼 +
// 친구 추가(이름+코드 붙여넣기) + 등록된 친구 목록(탭하면 그 친구 달력 보기).
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
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'SB1:...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                ),
                style: TextStyle(fontSize: 11.sp, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('취소')),
            ElevatedButton(
              onPressed: () async {
                final ok = await ref.read(friendProvider.notifier).addFriend(
                      displayName: nameController.text,
                      code: codeController.text,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '친구를 추가했어요' : '코드가 올바르지 않아요. 다시 확인해주세요')),
                  );
                }
              },
              child: Text('추가'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendProvider);

    return Scaffold(
      appBar: AppBar(title: Text('친구 공유 (베타)', style: TextStyle(fontSize: 18.sp))),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyShareCodeScreen())),
                    icon: Icon(Icons.qr_code, size: 18.sp),
                    label: Text('내 공유 코드 만들기', style: TextStyle(fontSize: 13.sp)),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12.h)),
                  ),
                ),
                SizedBox(width: 10.w),
                ElevatedButton.icon(
                  onPressed: () => _showAddFriendDialog(context, ref),
                  icon: Icon(Icons.person_add_alt, size: 18.sp),
                  label: Text('친구 추가', style: TextStyle(fontSize: 13.sp)),
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h)),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: 16.w),
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              '베타: 지금은 친구가 코드를 보내줄 때마다 "친구 추가"로 다시 붙여넣어야 최신 정보로 갱신돼요. 실시간 자동 동기화는 추후 지원 예정입니다.',
              style: TextStyle(fontSize: 11.sp, color: Theme.of(context).colorScheme.outline, height: 1.4),
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: friends.isEmpty
                ? Center(
                    child: Text('아직 추가한 친구가 없어요', style: TextStyle(fontSize: 14.sp, color: Theme.of(context).colorScheme.outline)),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 4.h),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(friend.name.isNotEmpty ? friend.name[0] : '?')),
                          title: Text(friend.name, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            friend.data.hasMemos ? '메모 공유됨' : '메모 비공개',
                            style: TextStyle(fontSize: 11.sp),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('친구 삭제'),
                                  content: Text('${friend.name}님을 목록에서 삭제할까요?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text('취소')),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: Text('삭제')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref.read(friendProvider.notifier).removeFriend(friend.id);
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => FriendCalendarView(friendName: friend.name, data: friend.data)),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
