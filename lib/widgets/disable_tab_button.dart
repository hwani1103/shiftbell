// lib/widgets/disable_tab_button.dart
//
// ⭐ 2026-09-13 추가(사용자 요청) - 일정관리/컨디션 탭 각자의 스크롤 콘텐츠
// 맨 아래(우측 정렬)에 두는 "OO 화면 사용하지 않기" 버튼 + 확인 다이얼로그.
// 두 탭이 완전히 같은 디자인/문구 톤을 쓰도록 공용 위젯으로 뺌 -
// tab_visibility_provider.dart의 provider를 직접 받아서 끈다.
// ⭐ 2026-09-13(2차) - 순수 텍스트 버튼에서 옅은 빨강 배경+테두리를 가진 실제
// "버튼" 모양으로 변경(요청: "텍스트만 있는 거에서 버튼까지 있는 걸로").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_extensions.dart';
import '../providers/tab_visibility_provider.dart';

/// 일정관리 탭의 Native/로컬 동기화 실패를 사용자에게 알리고 호출부의 후속 동작을 막는다.
Future<bool> setTabEnabledWithFeedback(
  BuildContext context,
  Future<void> Function() setEnabled,
) async {
  try {
    await setEnabled();
    return true;
  } on StateError {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.scheduleTabSyncFailed)),
      );
    }
    return false;
  }
}

/// [tabLabel] 예: "일정관리", "컨디션". 눌러서 확인하면 [provider]를 false로
/// 바꾸고, [onDisabled]로 부모(main.dart)에게 "지금 이 탭을 보고 있었다면
/// 안전한 탭으로 옮겨달라"고 알린다.
///
/// [extraNotice]: 탭별로 추가 안내가 필요할 때(예: 일정관리 탭 - "이 탭으로
/// 돌아가는 알림 진입 경로도 같이 닫아야 한다") 확인 다이얼로그 본문에 한 줄
/// 더 붙임. [onConfirmed]: `setEnabled(false)` 직후, [onDisabled] 호출 전에
/// 실행되는 탭별 부수효과(예: 예약된 일정 알림 일괄 취소) - 2026-09-13 추가,
/// 일정관리/컨디션 탭 숨김 시 각 탭의 "숨겨진 동안 들어오는 우회 경로"를
/// 같이 정리하기 위함(사용자 요청).
class DisableTabButton extends ConsumerWidget {
  final String tabLabel;
  final StateNotifierProvider<TabEnabledNotifier, bool> provider;
  final VoidCallback onDisabled;
  final String? extraNotice;
  final Future<void> Function()? onConfirmed;
  // ⭐ 2026-09-13 - 일정관리 탭만 본문과 좀 더 떨어진(더 아래) 위치에 두라는
  // 요청 - 컨디션 탭은 자리 그대로 유지, 폰트/색은 두 탭 다 아래에서 공통으로
  // 적용(위치만 탭별로 다름).
  final double topSpacing;

  const DisableTabButton({
    super.key,
    required this.tabLabel,
    required this.provider,
    required this.onDisabled,
    this.extraNotice,
    this.onConfirmed,
    this.topSpacing = 0,
  });

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$tabLabel 화면 사용하지 않기'),
        content: Text(
          '확인 버튼을 누르면 화면 하단의 목록에서 사라집니다.\n'
          '설정에서 다시 원복할 수 있습니다.'
          '${extraNotice != null ? '\n$extraNotice' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final changed = await setTabEnabledWithFeedback(
      context,
      () => ref.read(provider.notifier).setEnabled(false),
    );
    if (!changed) return;
    if (onConfirmed != null) await onConfirmed!();
    onDisabled();
  }

  // ⭐ 2026-09-13(2차) - "텍스트만 있는 것 → 버튼 디자인"으로 변경(요청). 이전에
  // "훨씬 연한 빨간색"으로 톤을 낮춰달라던 요청은 여전히 유효하다고 보고,
  // 채움색이 아니라 옅은 배경+테두리인 아웃라인 버튼 형태로 만듦 - 눈에 띄는
  // 진한 빨강 채움(AppSecondButton의 danger variant)은 이 버튼의 "위험하지만
  // 조용히 있어야 하는" 톤과 안 맞아서 재사용하지 않고, 이 위젯 전용으로
  // 옅은 빨강 배경(shade50) + 테두리(shade200) + 아이콘/텍스트(shade400)를 씀.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _confirm(context, ref),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_off_outlined,
                      size: 16, color: Colors.red.shade400),
                  const SizedBox(width: 6),
                  Text(
                    '$tabLabel 화면 사용하지 않기',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
