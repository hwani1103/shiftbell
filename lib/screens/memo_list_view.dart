import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/memo_provider.dart';
import '../models/date_memo.dart';

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
    // 모든 메모 로드
    _loadAllMemos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllMemos() async {
    // 전체 메모 로드 (날짜 범위를 넓게)
    final farPast = DateTime(2020, 1, 1);
    final farFuture = DateTime(2030, 12, 31);
    await ref.read(memoProvider.notifier).loadMemosForDateRange(farPast, farFuture);
  }

  // 메모를 연도/날짜별로 그룹핑
  Map<int, Map<String, List<DateMemo>>> _groupMemosByYearAndDate() {
    final allMemos = ref.watch(memoProvider);
    final Map<int, Map<String, List<DateMemo>>> grouped = {};

    // 모든 메모를 날짜별로 수집
    allMemos.forEach((dateStr, memos) {
      for (var memo in memos) {
        // 검색 필터링
        if (_searchQuery.isNotEmpty &&
            !memo.memoText.toLowerCase().contains(_searchQuery.toLowerCase())) {
          continue;
        }

        final date = DateTime.parse(dateStr);
        final year = date.year;

        if (!grouped.containsKey(year)) {
          grouped[year] = {};
        }
        if (!grouped[year]!.containsKey(dateStr)) {
          grouped[year]![dateStr] = [];
        }
        grouped[year]![dateStr]!.add(memo);
      }
    });

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final groupedMemos = _groupMemosByYearAndDate();
    final sortedYears = groupedMemos.keys.toList()..sort((a, b) => b.compareTo(a)); // 최근 연도 우선

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        title: Text('메모 모아보기', style: TextStyle(fontSize: 18.sp)),
        elevation: 1,
      ),
      body: Column(
        children: [
          // 검색창
          Container(
            padding: EdgeInsets.all(16.w),
            color: colorScheme.surface,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '메모 검색...',
                hintStyle: TextStyle(fontSize: 14.sp, color: colorScheme.outline),
                prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 20.sp),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                filled: true,
                fillColor: colorScheme.surfaceVariant,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              style: TextStyle(fontSize: 14.sp),
            ),
          ),

          // 메모 리스트
          Expanded(
            child: groupedMemos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_outlined, size: 64.sp, color: colorScheme.outline),
                        SizedBox(height: 16.h),
                        Text(
                          _searchQuery.isNotEmpty ? '검색 결과가 없습니다' : '메모가 없습니다',
                          style: TextStyle(fontSize: 16.sp, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    // ⭐ 하단 네비게이션 바 영역 고려한 패딩
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 16.h,
                    ),
                    itemCount: sortedYears.length,
                    itemBuilder: (context, yearIndex) {
                      final year = sortedYears[yearIndex];
                      final dateGroups = groupedMemos[year]!;
                      final sortedDates = dateGroups.keys.toList()
                        ..sort((a, b) => b.compareTo(a)); // 최근 날짜 우선

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 연도 헤더
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                            margin: EdgeInsets.only(top: yearIndex == 0 ? 8.h : 24.h, bottom: 8.h),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              border: Border(
                                left: BorderSide(color: colorScheme.primary, width: 4),
                              ),
                            ),
                            child: Text(
                              '($year)',
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),

                          // 날짜별 메모
                          ...sortedDates.map((dateStr) {
                            final date = DateTime.parse(dateStr);
                            final memos = dateGroups[dateStr]!;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 날짜 구분선
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${date.month}/${date.day}',
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      SizedBox(width: 8.w),
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // 메모 목록
                                ...memos.map((memo) {
                                  return Container(
                                    margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                                    padding: EdgeInsets.all(12.w),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(8.r),
                                      border: Border.all(color: colorScheme.outline),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.shadow.withOpacity(0.03),
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      memo.memoText,
                                      style: TextStyle(
                                        fontSize: 14.sp,
                                        color: colorScheme.onSurface,
                                        height: 1.4,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            );
                          }).toList(),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
