// lib/widgets/sleep_edit_dialog.dart
//
// ⭐ 실제 수면 기록(취침/기상 시각) 입력·수정 공용 UI. 원래 condition_tab.dart
// 안에 있던 `_showEditSleepDialog`를 여러 화면(미니 달력 카드, 전체보기 화면)에서
// 재사용할 수 있게 공용 위젯 파일로 뺐다 - UI만 다루고 DB는 전혀 모른다(호출부가
// 결과를 받아서 저장/삭제를 결정하거나, [handleSleepSlotTap]을 통해 바로 처리).
//
// ⭐ 2026-09-01 - AlertDialog + ListTile 2개짜리 옛날 UI가 "후지다"는 피드백으로
// 바텀시트 + 취침/기상 시각 카드 2개 나란히 보여주는 형태로 다시 그림(디자인만
// 변경 - 반환 타입/호출 계약은 그대로).
//
// ⚠️ 근무시간과 겹치는지 여부는 전혀 검사하지 않는다(수면기록_자동추정_설계.md
// 2장 - validation 없음 원칙).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sleep_record.dart';
import '../providers/sleep_record_provider.dart';
import '../services/condition/sleep_day_slots.dart';
import '../theme/app_colors.dart';
import '../utils/sleep_format_util.dart';
import 'app_second_button.dart';

sealed class SleepSlotEditResult {}

class SleepSlotSaved extends SleepSlotEditResult {
  final DateTime start;
  final DateTime end;
  SleepSlotSaved(this.start, this.end);
}

class SleepSlotDeleted extends SleepSlotEditResult {}

/// 취침/기상 시각을 입력받는 바텀시트.
/// - [initialStart]/[initialEnd]가 이미 있는 기록을 뜻하면 [showDeleteButton]을
///   true로 넘겨 "삭제" 버튼을 같이 보여줄 수 있다.
/// - 저장하면 [SleepSlotSaved], 삭제를 누르면 [SleepSlotDeleted], 취소/닫기는 null.
Future<SleepSlotEditResult?> showSleepSlotEditDialog(
  BuildContext context, {
  required DateTime initialStart,
  required DateTime initialEnd,
  bool showDeleteButton = false,
  String title = '수면 시각 입력',
}) async {
  var start = initialStart;
  var end = initialEnd;

  Future<DateTime?> pick(BuildContext sheetContext, DateTime initial) async {
    final date = await showDatePicker(
      context: sheetContext,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return null;
    if (!sheetContext.mounted) return null;
    final time = await showTimePicker(context: sheetContext, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  return showModalBottomSheet<SleepSlotEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setState) {
          // ⭐ 2026-09-01 후속7 - "미래 시각은 입력할 수 없어야 한다"는 요청
          // (예: 지금 낮 12시인데 오늘 밤 22시~다음날 06시를 미리 저장하는 건
          // 말이 안 됨 - 아직 안 일어난 일이므로). end.isAfter(start) 검증에
          // "취침/기상 둘 다 지금 시각을 넘지 않아야 한다"는 조건을 추가.
          final now = DateTime.now();
          final isFuture = start.isAfter(now) || end.isAfter(now);
          final valid = end.isAfter(start) && !isFuture;
          final String message;
          if (!end.isAfter(start)) {
            message = '기상 시각이 취침보다 빨라요';
          } else if (isFuture) {
            message = '아직 지나지 않은 시각은 기록할 수 없어요';
          } else {
            message = '${fmtDuration(end.difference(start))} 수면';
          }
          // ⭐ 2026-09-01 후속5 - "SafeArea가 없다"는 피드백으로 SafeArea(top: false,
          // 바텀시트라 위쪽은 필요 없음) 추가 - 제스처 내비게이션 바 등 하단 시스템
          // 영역과 버튼이 겹치지 않게 함. 키보드 인셋(viewInsets.bottom)은 SafeArea
          // 안쪽에서 별도로 더해줌(키보드가 열렸을 때 SafeArea의 정적 bottom 패딩과는
          // 별개로 그만큼 더 밀어올려야 하므로).
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _TimeCard(
                          icon: '🌙',
                          label: '취침',
                          time: start,
                          onTap: () async {
                            final picked = await pick(sheetContext, start);
                            if (picked != null) setState(() => start = picked);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward, color: Colors.black26, size: 18),
                      ),
                      Expanded(
                        child: _TimeCard(
                          icon: '☀️',
                          label: '기상',
                          time: end,
                          onTap: () async {
                            final picked = await pick(sheetContext, end);
                            if (picked != null) setState(() => end = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: valid ? kAppMainAccent : Colors.red.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  // ⭐ 2026-09-01 후속5 - TextButton/ElevatedButton 임의 조합 대신
                  // 앱 전역 공용 버튼(AppSecondButton - 고정 알람 편집 다이얼로그 등에서
                  // 이미 쓰는 "취소/저장/삭제" 전용 위젯)으로 통일해서 앱 컨셉과
                  // 색/모양이 어긋나지 않게 함. 후속 피드백으로 compact(패딩
                  // 10/6, 폰트 12)가 "너무 작다"는 지적 - 기본 프리셋(24/14,
                  // 15)보다는 작지만 compact보다 눈에 띄게 큰 중간 크기로 override.
                  Row(
                    children: [
                      if (showDeleteButton) ...[
                        AppSecondButton(
                          variant: AppSecondButtonVariant.danger,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          fontSize: 14,
                          onPressed: () => Navigator.of(sheetContext).pop(SleepSlotDeleted()),
                          child: const Text('삭제'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Spacer(),
                      AppSecondButton(
                        variant: AppSecondButtonVariant.neutral,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        fontSize: 14,
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('취소'),
                      ),
                      const SizedBox(width: 8),
                      AppSecondButton(
                        variant: AppSecondButtonVariant.success,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        fontSize: 14,
                        onPressed: valid ? () => Navigator.of(sheetContext).pop(SleepSlotSaved(start, end)) : null,
                        child: const Text('저장'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _TimeCard extends StatelessWidget {
  final String icon;
  final String label;
  final DateTime time;
  final VoidCallback onTap;
  const _TimeCard({required this.icon, required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 4),
            Text(fmtDateTime(time), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// ⭐ 2026-09-01 - 미니 달력 카드/전체보기가 공유하는 "칸 한 개를 탭했을 때" 동작.
/// [record]가 있으면 수정(+삭제) 시트, 없으면 [defaultSleepSlotTimes] 기본값으로
/// 새 시트를 띄우고 결과를 그대로 Provider에 반영한다 - 호출부는 이 함수 하나만
/// 부르면 됨(같은 로직을 화면마다 복붙하지 않기 위함).
Future<void> handleSleepSlotTap(
  BuildContext context,
  WidgetRef ref, {
  required DateTime date,
  required SleepSlotCategory category,
  required SleepRecord? record,
}) async {
  if (record != null) {
    final result = await showSleepSlotEditDialog(
      context,
      initialStart: record.start,
      initialEnd: record.end ?? DateTime.now(),
      showDeleteButton: true,
      title: '${category.label} 수정',
    );
    if (result is SleepSlotDeleted) {
      if (record.id != null) await ref.read(sleepRecordProvider.notifier).deleteRecord(record.id!);
    } else if (result is SleepSlotSaved) {
      await ref.read(sleepRecordProvider.notifier).updateTimes(record, start: result.start, end: result.end);
    }
    return;
  }

  final defaults = defaultSleepSlotTimes(date, category);
  final result = await showSleepSlotEditDialog(
    context,
    initialStart: defaults.start,
    initialEnd: defaults.end,
    title: '${category.label} 기록',
  );
  if (result is SleepSlotSaved) {
    await ref.read(sleepRecordProvider.notifier).addManual(start: result.start, end: result.end);
  }
}
