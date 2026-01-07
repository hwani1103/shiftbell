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
    final groupedMemos = _groupMemosByYearAndDate();
    final sortedYears = groupedMemos.keys.toList()..sort((a, b) => b.compareTo(a)); // 최근 연도 우선

    return Scaffold(
      appBar: AppBar(
        title: Text('메모 모아보기', style: TextStyle(fontSize: 18.sp)),
        elevation: 1,
      ),
      body: Column(
        children: [
          // 검색창
          Container(
            padding: EdgeInsets.all(16.w),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '메모 검색...',
                hintStyle: TextStyle(fontSize: 14.sp, color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
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
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: Colors.indigo.shade400, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
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
                        Icon(Icons.note_outlined, size: 64.sp, color: Colors.grey.shade300),
                        SizedBox(height: 16.h),
                        Text(
                          _searchQuery.isNotEmpty ? '검색 결과가 없습니다' : '메모가 없습니다',
                          style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: 16.h),
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
                              color: Colors.indigo.shade50,
                              border: Border(
                                left: BorderSide(color: Colors.indigo.shade400, width: 4),
                              ),
                            ),
                            child: Text(
                              '($year)',
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade700,
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
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      SizedBox(width: 8.w),
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: Colors.grey.shade300,
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
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8.r),
                                      border: Border.all(color: Colors.grey.shade200),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.03),
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      memo.memoText,
                                      style: TextStyle(
                                        fontSize: 14.sp,
                                        color: Colors.black87,
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
