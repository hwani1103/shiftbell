// screens/my_share_code_screen.dart
//
// ⭐ "내 공유 코드 만들기" - 내 근무 패턴(+근무변경)과, 선택 시 메모까지 담아
// 코드 하나로 압축해서 보여줌. 친구가 이 텍스트를 카카오톡 등으로 받아서
// "친구 추가" 화면에 붙여넣으면 내 스케줄이 그 친구 앱에 그대로 들어감.
// ⭐ 절대 포함 안 되는 것: OT, 근로시간(shiftDurations) 설정, 알람 설정 전부.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../models/friend_schedule.dart';
import '../providers/schedule_provider.dart';
import '../services/database_service.dart';
import '../services/friend_share_service.dart';

// ⭐ 트랙1(웹) 배포 도메인 - 아직 실제로 호스팅한 적이 없어서 임시값임.
// web/ 폴더(flutter build web -t lib/web_main.dart 결과물)를 Firebase
// Hosting/Netlify/GitHub Pages 등에 올린 뒤, 실제 배정된 도메인으로 이 한
// 줄만 바꾸면 아래 "웹에서 보기 링크"가 바로 진짜로 동작함.
const String kWebViewBaseUrl = 'https://shiftbell-share.example.com';

class MyShareCodeScreen extends ConsumerStatefulWidget {
  const MyShareCodeScreen({super.key});

  @override
  ConsumerState<MyShareCodeScreen> createState() => _MyShareCodeScreenState();
}

class _MyShareCodeScreenState extends ConsumerState<MyShareCodeScreen> {
  final _nameController = TextEditingController();
  bool _includeMemos = false;
  String? _generatedCode;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _loadSavedName();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('friend_share_my_name');
    if (saved != null && mounted) {
      setState(() => _nameController.text = saved);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('친구에게 보일 내 이름을 입력해주세요')),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('friend_share_my_name', name);

      final schedule = ref.read(scheduleProvider).value;
      if (schedule == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('아직 근무 스케줄이 설정되지 않았어요')),
          );
        }
        return;
      }

      Map<String, List<String>>? memos;
      if (_includeMemos) {
        // ⭐ 근래 메모 위주로 공유 (과거 30일 ~ 미래 120일) - 무제한으로 다
        // 긁으면 코드가 너무 길어져서 붙여넣기가 번거로워짐.
        final now = DateTime.now();
        final memoMap = await DatabaseService.instance.getMemosForDateRange(
          now.subtract(const Duration(days: 30)),
          now.add(const Duration(days: 120)),
        );
        memos = memoMap.map((date, list) => MapEntry(date, list.map((m) => m.memoText).toList()));
      }

      final data = FriendScheduleData(
        ownerName: name,
        isRegular: schedule.isRegular,
        pattern: schedule.pattern,
        todayIndex: schedule.todayIndex,
        startDate: schedule.startDate,
        shiftColors: schedule.shiftColors ?? {},
        assignedDates: schedule.assignedDates ?? {},
        memos: memos,
        exportedAt: DateTime.now(),
      );

      final code = FriendShareService.encode(data);
      if (mounted) setState(() => _generatedCode = code);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _copyCode() {
    if (_generatedCode == null) return;
    Clipboard.setData(ClipboardData(text: _generatedCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('복사했어요! 카카오톡 등으로 친구에게 붙여넣기 해주세요')),
    );
  }

  // ⭐ 앱 미설치자(트랙1)용 - 코드를 URL 쿼리로 실은 웹 링크. 클릭만 하면
  // 앱 설치 없이 바로 내 근무표를 볼 수 있음(FriendCalendarView 그대로 재사용).
  String get _webViewLink => '$kWebViewBaseUrl/#/?code=$_generatedCode';

  // ⭐ OS 공유 시트(카카오톡/문자/기타 앱 선택)로 바로 넘김 - 코드 자체(앱
  // 사용자용, 트랙2)와 웹 링크(비사용자용, 트랙1)를 한 메시지에 같이 담아서,
  // 받는 사람이 앱이 있든 없든 알아서 원하는 방식으로 쓸 수 있게 함.
  void _shareCode() {
    if (_generatedCode == null) return;
    final name = _nameController.text.trim();
    Share.share(
      '$name님의 근무표를 공유해요! 🗓️\n\n'
      '▶ 앱 없이 바로 보기: $_webViewLink\n\n'
      '▶ 교대시계 앱 사용 중이면 "친구 추가"에 아래 코드를 붙여넣어주세요:\n$_generatedCode',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('내 공유 코드 만들기', style: TextStyle(fontSize: 18.sp))),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('친구에게 보일 이름', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '예: 김철수',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              ),
              style: TextStyle(fontSize: 14.sp),
            ),
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.note_alt_outlined, size: 20.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text('메모도 같이 공유하기', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    value: _includeMemos,
                    onChanged: (v) => setState(() => _includeMemos = v),
                  ),
                ],
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              '근무 패턴과 근무변경 내역은 항상 공유됩니다. OT · 근로시간 설정 · 알람 설정은 절대 공유되지 않습니다.',
              style: TextStyle(fontSize: 11.sp, color: Theme.of(context).colorScheme.outline),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _generating ? null : _generate,
                style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                child: _generating
                    ? SizedBox(width: 18.w, height: 18.w, child: const CircularProgressIndicator(strokeWidth: 2))
                    : Text('공유 코드 생성', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_generatedCode != null) ...[
              SizedBox(height: 20.h),
              Text('생성된 코드', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 8.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8.r),
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: SelectableText(_generatedCode!, style: TextStyle(fontSize: 11.sp, fontFamily: 'monospace')),
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyCode,
                      icon: Icon(Icons.copy, size: 18.sp),
                      label: Text('코드 복사', style: TextStyle(fontSize: 13.sp)),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12.h)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _shareCode,
                      icon: Icon(Icons.share, size: 18.sp),
                      label: Text('공유하기', style: TextStyle(fontSize: 13.sp)),
                      style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12.h)),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Text('앱 없는 친구용 웹 링크', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 4.h),
              Text(
                '⚠️ 아직 실제 배포 전이라 지금은 예시 링크예요. web 폴더를 호스팅에 올린 뒤 실제 도메인으로 바뀌면 바로 동작합니다 (아래 최종 안내 참고).',
                style: TextStyle(fontSize: 10.5.sp, color: Colors.orange.shade800),
              ),
              SizedBox(height: 8.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8.r),
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: SelectableText(_webViewLink, style: TextStyle(fontSize: 11.sp)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
