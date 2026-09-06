import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/memo_provider.dart';
import '../models/date_memo.dart';
import '../l10n/l10n_extensions.dart';
import '../utils/weekday_util.dart';
import '../widgets/app_second_button.dart';

// ⭐ 2026-09-03 - "화면이 후지다"는 피드백으로 전면 재구성(레이아웃만 - 검색
// 기능/Provider 계약은 그대로 유지). 기존엔 연도 헤더 하나에 그 해 전체 날짜가
// 쭉 나열되는 단조로운 구성이라 스캔하기 불편했음. 이번엔:
//   - 연도 대신 "월" 단위로 묶어서(현실적으로 스크롤 한 화면에 들어오는 단위) 더
//     잘게 나눔
//   - 날짜 줄에 요일 칩을 붙여서 훑어보기 쉽게 함
//   - 메모 카드에 왼쪽 포인트 바 + 그림자를 줘서 리스트가 아니라 "카드 뭉치"처럼
//     보이게 함
//   - 검색 중엔 일치하는 부분을 굵게 강조 표시(하이라이트)
//   - 검색창 아래 "총 N개"/"검색 결과 N개" 카운트를 보여줘서 지금 몇 개를 보고
//     있는지 항상 알 수 있게 함
//   - 카드를 탭하면 바텀시트로 보기/수정/삭제(sleep_edit_dialog.dart와 같은
//     톤 - 이 앱에서 이미 "낡은 AlertDialog 대신"으로 자리잡은 패턴)
class MemoListView extends ConsumerStatefulWidget {
  const MemoListView({super.key});

  @override
  ConsumerState<MemoListView> createState() => _MemoListViewState();
}

class _MemoListViewState extends ConsumerState<MemoListView> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllMemos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllMemos() async {
    final farPast = DateTime(2020, 1, 1);
    final farFuture = DateTime(2030, 12, 31);
    await ref.read(memoProvider.notifier).loadMemosForDateRange(farPast, farFuture);
  }

  /// 월(YYYY-MM) -> 날짜(YYYY-MM-DD) -> 메모 목록으로 그룹핑. 검색어가 있으면
  /// 여기서 같이 필터링(기존 로직 그대로, 그룹 단위만 연도->월로 세분화).
  Map<String, Map<String, List<DateMemo>>> _groupMemos(Map<String, List<DateMemo>> all) {
    final grouped = <String, Map<String, List<DateMemo>>>{};
    all.forEach((dateStr, memos) {
      for (final memo in memos) {
        if (_searchQuery.isNotEmpty &&
            !memo.memoText.toLowerCase().contains(_searchQuery.toLowerCase())) {
          continue;
        }
        final monthKey = dateStr.substring(0, 7); // 'YYYY-MM'
        grouped.putIfAbsent(monthKey, () => {});
        grouped[monthKey]!.putIfAbsent(dateStr, () => []);
        grouped[monthKey]![dateStr]!.add(memo);
      }
    });
    return grouped;
  }

  String _monthLabel(BuildContext context, String monthKey) {
    final year = int.parse(monthKey.substring(0, 4));
    final month = int.parse(monthKey.substring(5, 7));
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    if (isKorean) return '$year년 $month월';
    return DateFormat.yMMMM('en').format(DateTime(year, month));
  }

  String _dateLabel(BuildContext context, DateTime date) {
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final weekday = weekdayLabel(context, weekdayIndexOf(date));
    if (isKorean) return '${date.month}월 ${date.day}일 ($weekday)';
    return '${DateFormat.MMMd('en').format(date)} ($weekday)';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allMemos = ref.watch(memoProvider);
    final totalCount = allMemos.values.fold<int>(0, (sum, list) => sum + list.length);
    final grouped = _groupMemos(allMemos);
    final matchedCount = grouped.values.fold<int>(
      0,
      (sum, dateGroups) => sum + dateGroups.values.fold<int>(0, (s, memos) => s + memos.length),
    );
    final sortedMonths = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        title: Text(context.l10n.calendarMemoAll, style: TextStyle(fontSize: 18.sp)),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchHeader(context, colorScheme, totalCount, matchedCount),
          Expanded(
            child: grouped.isEmpty
                ? _buildEmptyState(context, colorScheme)
                : ListView.builder(
                    padding: EdgeInsets.only(
                      top: 4.h,
                      bottom: MediaQuery.of(context).padding.bottom + 16.h,
                    ),
                    itemCount: sortedMonths.length,
                    itemBuilder: (context, monthIndex) {
                      final monthKey = sortedMonths[monthIndex];
                      final dateGroups = grouped[monthKey]!;
                      final sortedDates = dateGroups.keys.toList()..sort((a, b) => b.compareTo(a));
                      final monthCount = dateGroups.values.fold<int>(0, (s, m) => s + m.length);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMonthHeader(context, colorScheme, monthKey, monthCount),
                          ...sortedDates.map((dateStr) {
                            final date = DateTime.parse(dateStr);
                            final memos = dateGroups[dateStr]!;
                            return _buildDateSection(context, colorScheme, date, dateStr, memos);
                          }),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ⭐ 검색창 + "총 N개"/"검색 결과 N개" 카운트. 흰 카드로 살짝 띄워서
  // colorScheme.surface(연보라) 배경 위에서 존재감이 드러나게 함.
  Widget _buildSearchHeader(BuildContext context, ColorScheme colorScheme, int totalCount, int matchedCount) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '${context.l10n.calendarMemoSearch}...',
              hintStyle: TextStyle(fontSize: 14.sp, color: colorScheme.outline),
              prefixIcon: Icon(Icons.search_rounded, color: colorScheme.primary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, size: 20.sp, color: colorScheme.onSurfaceVariant),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style: TextStyle(fontSize: 14.sp),
          ),
          Padding(
            padding: EdgeInsets.only(left: 16.w, right: 12.w, bottom: 8.h),
            child: Text(
              _searchQuery.isEmpty
                  ? context.l10n.calendarMemoTotalCount(totalCount)
                  : context.l10n.calendarMemoSearchResultCount(matchedCount),
              style: TextStyle(fontSize: 12.sp, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88.w,
            height: 88.w,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.note_alt_outlined,
              size: 40.sp,
              color: colorScheme.primary.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            _searchQuery.isNotEmpty ? context.l10n.calendarSearchNoResults : context.l10n.calendarMemoNone,
            style: TextStyle(fontSize: 15.sp, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthHeader(BuildContext context, ColorScheme colorScheme, String monthKey, int count) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 12.h, bottom: 4.h),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      color: colorScheme.surface,
      child: Row(
        children: [
          Text(
            _monthLabel(context, monthKey),
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800, color: colorScheme.primary),
          ),
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700, color: colorScheme.primary),
            ),
          ),
          Expanded(child: Container()),
        ],
      ),
    );
  }

  Widget _buildDateSection(
    BuildContext context,
    ColorScheme colorScheme,
    DateTime date,
    String dateStr,
    List<DateMemo> memos,
  ) {
    final isSunday = date.weekday == DateTime.sunday;
    final isSaturday = date.weekday == DateTime.saturday;
    final weekdayColor = isSunday
        ? const Color(0xFFE0574B)
        : isSaturday
            ? const Color(0xFF3E7BD6)
            : colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30.w,
                height: 30.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: weekdayColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: weekdayColor),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                _dateLabel(context, date),
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          ...memos.map((memo) => _buildMemoCard(context, colorScheme, date, dateStr, memo)),
        ],
      ),
    );
  }

  Widget _buildMemoCard(
    BuildContext context,
    ColorScheme colorScheme,
    DateTime date,
    String dateStr,
    DateMemo memo,
  ) {
    return Padding(
      padding: EdgeInsets.only(left: 38.w, bottom: 8.h),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: () => _showMemoActionSheet(context, date, dateStr, memo),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4.w,
                  constraints: BoxConstraints(minHeight: 44.h),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(12.r)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    child: _highlightedText(
                      memo.memoText,
                      _searchQuery,
                      TextStyle(fontSize: 14.sp, color: colorScheme.onSurface, height: 1.4),
                      colorScheme.primary,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(right: 8.w, top: 10.h),
                  child: Icon(Icons.chevron_right_rounded, size: 18.sp, color: colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 검색어와 일치하는 부분을 굵게 + 강조색으로 표시.
  Widget _highlightedText(String text, String query, TextStyle baseStyle, Color highlightColor) {
    if (query.isEmpty) return Text(text, style: baseStyle);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(fontWeight: FontWeight.w800, color: highlightColor, backgroundColor: highlightColor.withOpacity(0.12)),
      ));
      start = idx + query.length;
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }

  // ⭐ 메모 상세/수정/삭제 - sleep_edit_dialog.dart와 같은 톤(바텀시트 + SafeArea +
  // AppSecondButton)으로 통일. calendar_tab.dart의 옛 AlertDialog 팝업(_showMemoDetailPopup)과
  // 기능은 동일(보기/수정/삭제)하되 이 화면 전용으로 새로 구성 - 다른 파일의
  // private 다이얼로그라 직접 재사용은 못 함.
  void _showMemoActionSheet(BuildContext context, DateTime date, String dateStr, DateMemo memo) {
    final editController = TextEditingController(text: memo.memoText);
    bool isEditing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = Theme.of(sheetContext).colorScheme;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36.w,
                          height: 4.h,
                          margin: EdgeInsets.only(bottom: 16.h),
                          decoration: BoxDecoration(
                            color: colorScheme.outline,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.event_note_rounded, size: 18.sp, color: colorScheme.primary),
                          SizedBox(width: 6.w),
                          Text(
                            _dateLabel(sheetContext, date),
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: colorScheme.primary),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      if (isEditing)
                        TextField(
                          controller: editController,
                          autofocus: true,
                          maxLines: 5,
                          minLines: 2,
                          decoration: InputDecoration(
                            hintText: sheetContext.l10n.calendarMemoContent,
                            contentPadding: EdgeInsets.all(12.w),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10.r),
                              borderSide: BorderSide(color: colorScheme.outline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10.r),
                              borderSide: BorderSide(color: colorScheme.primary, width: 2),
                            ),
                          ),
                          style: TextStyle(fontSize: 14.sp),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(14.w),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Text(
                            memo.memoText,
                            style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurface, height: 1.5),
                          ),
                        ),
                      SizedBox(height: 16.h),
                      Row(
                        children: [
                          if (isEditing) ...[
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.neutral,
                                onPressed: () {
                                  setSheetState(() {
                                    isEditing = false;
                                    editController.text = memo.memoText;
                                  });
                                },
                                child: Text(sheetContext.l10n.commonCancel),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.success,
                                onPressed: () async {
                                  if (editController.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                                      SnackBar(content: Text(sheetContext.l10n.statusEnterMemoContent)),
                                    );
                                    return;
                                  }
                                  FocusScope.of(sheetContext).unfocus();
                                  await ref.read(memoProvider.notifier).updateMemo(
                                        memo.id!,
                                        dateStr,
                                        editController.text.trim(),
                                      );
                                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                                },
                                child: Text(sheetContext.l10n.commonSave),
                              ),
                            ),
                          ] else ...[
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.danger,
                                onPressed: () async {
                                  await ref.read(memoProvider.notifier).deleteMemo(memo.id!, dateStr);
                                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                                },
                                child: Text(sheetContext.l10n.commonDelete),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: AppSecondButton(
                                variant: AppSecondButtonVariant.primary,
                                onPressed: () {
                                  setSheetState(() => isEditing = true);
                                },
                                child: Text(sheetContext.l10n.commonEdit),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => editController.dispose());
  }
}
