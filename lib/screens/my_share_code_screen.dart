// screens/my_share_code_screen.dart
//
// ⭐ "내 근무표 공유하기" - 친구공유 v1(Firestore). 예전엔 코드를 누를 때마다 그 순간의
// 스냅샷을 새로 인코딩했는데, 이제 코드/링크는 Firestore 문서 ID를 가리키는 "영구 주소"라
// 한 번만 발급하면 됨 - 이후 근무가 바뀌어도(근무변경 등) 코드는 그대로고, 그 코드를 열어본
// 친구가 매번 최신 상태를 자동으로 받아봄. 그래서 화면도 "생성 버튼"이 아니라 "공유 시작 →
// 공유 중" 상태 전환으로 단순화함.
// ⭐ 절대 포함 안 되는 것: 메모, OT, 근로시간(shiftDurations) 설정, 알람 설정 전부.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';
import '../services/friend_share_service.dart';
import '../services/friend_sync_service.dart';
import '../services/firebase_bootstrap.dart';
import '../providers/schedule_provider.dart';
import '../l10n/l10n_extensions.dart';

// ⭐ 트랙1(웹) 배포 도메인 - Firebase Hosting(shiftbell-29f31)에 실제 배포 완료
// (2026-08-14, `firebase deploy --only hosting`). build/web을 다시 배포하려면
// `flutter build web -t lib/web_main.dart` 후 같은 명령을 다시 실행하면 됨.
const String kWebViewBaseUrl = 'https://shiftbell-29f31.web.app';

class MyShareCodeScreen extends ConsumerStatefulWidget {
  const MyShareCodeScreen({super.key});

  @override
  ConsumerState<MyShareCodeScreen> createState() => _MyShareCodeScreenState();
}

class _MyShareCodeScreenState extends ConsumerState<MyShareCodeScreen> {
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  bool _loading = true;
  bool _working = false;
  bool _sharingEnabled = false;
  String? _ownerId;
  String? _savedName; // ⭐ Firestore에 마지막으로 반영된 이름 - 이름 변경 감지용

  @override
  void initState() {
    super.initState();
    _load();
    // ⭐ 이름 입력란에서 포커스가 빠질 때(다른 곳 탭/키보드 닫기) 바뀐 이름을
    // 자동 저장 - 이미 공유 중이면 별도 "저장" 버튼 없이도 바로 반영됨.
    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus) _maybeSaveName();
    });
  }

  Future<void> _load() async {
    final enabled = await FriendSyncService.instance.isSharingEnabled();
    final savedName = await FriendSyncService.instance.savedMyName();
    final ownerId = enabled ? await FriendSyncService.instance.getOrCreateOwnerId() : null;
    if (!mounted) return;
    setState(() {
      _sharingEnabled = enabled;
      _ownerId = ownerId;
      _savedName = savedName;
      _nameController.text = savedName ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  // ⭐ 이미 공유 중인 상태에서 이름만 바꿨을 때 - 코드/링크는 그대로 두고 표시 이름만
  // Firestore에 반영. 공유 시작 전이면 그냥 다음 "공유 시작하기"에 쓰일 값이라 저장할
  // 필요 없음(그때 _startSharing이 알아서 씀).
  Future<void> _maybeSaveName() async {
    if (!_sharingEnabled) return;
    final name = _nameController.text.trim();
    if (name.isEmpty || name == _savedName) return;
    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) return;
    final ok = await FriendSyncService.instance.updateMyName(newName: name, schedule: schedule);
    if (!mounted) return;
    if (ok) {
      setState(() => _savedName = name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.friendDisplayNameUpdated)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.friendDisplayNameUpdateFailed)),
      );
    }
  }

  Future<void> _startSharing() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.friendEnterDisplayNameError)),
      );
      return;
    }
    if (!firebaseReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.friendServerNotReady)),
      );
      return;
    }

    final schedule = ref.read(scheduleProvider).value;
    if (schedule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.friendScheduleNotSet)),
      );
      return;
    }

    setState(() => _working = true);
    try {
      final ownerId = await FriendSyncService.instance.startSharing(schedule: schedule, ownerName: name);
      if (!mounted) return;
      if (ownerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.friendStartSharingFailed)),
        );
        return;
      }
      setState(() {
        _sharingEnabled = true;
        _ownerId = ownerId;
        _savedName = name;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stopSharing() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.friendStopSharing),
        content: Text(
          '${context.l10n.friendStopSharingConfirm}\n\n${context.l10n.friendRestartSharingHint}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.friendStopSharingAction)),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _working = true);
    try {
      await FriendSyncService.instance.stopSharing();
      if (!mounted) return;
      setState(() {
        _sharingEnabled = false;
        _ownerId = null;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _code => FriendShareService.encodeOwnerId(_ownerId!);
  String get _webViewLink => '$kWebViewBaseUrl/#/?code=$_code';

  void _shareCode() {
    final name = _nameController.text.trim();
    Share.share(context.l10n.friendShareMessage(name, _webViewLink, _code));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.friendShareMyScheduleTitle, style: TextStyle(fontSize: 18.sp))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⭐ 별도 라벨 없이 "친구에게 보일 이름을 적어주세요"를 필드
                  // placeholder(hintText) 자체로 씀 - 비어있을 때만 보이고, 실제
                  // 값(공유 중이면 저장된 이름)이 있으면 그 값이 표시됨.
                  // 예전엔 공유 시작 후 이 필드가 비활성화돼서 이름을 못 바꿨음 -
                  // 이제 언제든 편집 가능하고, 포커스를 빠져나가면(_maybeSaveName)
                  // 공유 중일 땐 바로 Firestore에도 반영됨.
                  TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    decoration: InputDecoration(
                      hintText: context.l10n.friendEnterDisplayName,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    ),
                    style: TextStyle(fontSize: 14.sp),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _maybeSaveName(),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    '${context.l10n.friendShareIncludesSchedule}\n${context.l10n.friendShareExcludesExtras}',
                    style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant),
                  ),
                  SizedBox(height: 24.h),
                  if (!_sharingEnabled)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _working ? null : _startSharing,
                        style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                        child: _working
                            ? SizedBox(width: 18.w, height: 18.w, child: const CircularProgressIndicator(strokeWidth: 2))
                            : Text(context.l10n.friendStartSharing, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold)),
                      ),
                    )
                  else if (_ownerId == null)
                    // ⭐ 공유는 켜져 있는데 이번 로드에서 익명 로그인이 실패한 경우
                    // (오프라인 등) - _ownerId!를 그대로 쓰면 크래시라 별도 안내로 방어.
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.sync_problem, size: 18.sp, color: Theme.of(context).colorScheme.onErrorContainer),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              context.l10n.friendConnectionFailed,
                              style: TextStyle(fontSize: 12.5.sp, color: Theme.of(context).colorScheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Text(context.l10n.friendMyShareCode, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    SizedBox(height: 8.h),
                    _CopyBox(text: _code, monospace: true, onCopy: () => _copy(_code, context.l10n.friendCodeCopied)),
                    SizedBox(height: 6.h),
                    Text(
                      context.l10n.friendShareCodeInstructions,
                      style: TextStyle(fontSize: 11.5.sp, color: colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: 16.h),
                    Text(context.l10n.friendShareWithoutApp, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    SizedBox(height: 8.h),
                    _CopyBox(text: _webViewLink, onCopy: () => _copy(_webViewLink, context.l10n.friendLinkCopied)),
                    SizedBox(height: 6.h),
                    Text(
                      '${context.l10n.friendShareLinkHint}\n${context.l10n.friendInstallShortcutHint}',
                      style: TextStyle(fontSize: 11.5.sp, color: colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: 20.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _shareCode,
                        icon: Icon(Icons.share, size: 18.sp),
                        label: Text(context.l10n.commonShare, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                      ),
                    ),
                    // ⭐ "공유 중지"를 공유하기 버튼과 더 떨어뜨리고(실수 클릭 방지),
                    // 텍스트 링크가 아니라 빨간 배경의 진짜 버튼으로(공유하기와 같은
                    // border radius) - "너무 밋밋해서 눈에 안 띈다"는 피드백.
                    SizedBox(height: 20.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _working ? null : _stopSharing,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.onErrorContainer,
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                          elevation: 0,
                        ),
                        child: Text(context.l10n.friendStopSharing, style: TextStyle(fontSize: 12.5.sp, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CopyBox extends StatelessWidget {
  final String text;
  final bool monospace;
  final VoidCallback onCopy;
  const _CopyBox({required this.text, required this.onCopy, this.monospace = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8.r),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: SelectableText(
              text,
              style: TextStyle(fontSize: 11.5.sp, fontFamily: monospace ? 'monospace' : null),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        IconButton(onPressed: onCopy, icon: Icon(Icons.copy, size: 18.sp)),
      ],
    );
  }
}
