import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 전체 교대조 근무표 작성 다이얼로그
class AllTeamsSetupDialog extends StatefulWidget {
  final List<String> pattern;
  final VoidCallback? onComplete;  // ⭐ 완료 시 콜백

  const AllTeamsSetupDialog({
    super.key,
    required this.pattern,
    this.onComplete,
  });

  @override
  State<AllTeamsSetupDialog> createState() => _AllTeamsSetupDialogState();
}

class _AllTeamsSetupDialogState extends State<AllTeamsSetupDialog> {
  final PageController _pageController = PageController();
  final TextEditingController _teamInputController = TextEditingController();
  int _currentPage = 0;

  // 사용자 입력 데이터
  List<String> _teamNames = []; // 예: ['A', 'B', 'C', 'D']
  String? _myTeam; // 예: 'C'
  Map<String, int> _teamIndices = {}; // 예: {'A': 1, 'B': 3, 'C': 5, 'D': 7} (오늘의 패턴 인덱스 1~8)

  @override
  void initState() {
    super.initState();
    _teamInputController.addListener(_onTeamInputChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _teamInputController.dispose();
    super.dispose();
  }

  void _onTeamInputChanged() {
    final text = _teamInputController.text.toUpperCase(); // 대문자 변환

    // 먼저 controller의 텍스트를 대문자로 업데이트 (커서 위치 유지)
    if (_teamInputController.text != text) {
      final selection = _teamInputController.selection;
      _teamInputController.value = _teamInputController.value.copyWith(
        text: text,
        selection: selection,
      );
    }

    setState(() {
      final teams = text
          .split(RegExp(r'\s+')) // 공백으로 분리
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e.length == 1)
          .toList();

      // 중복 제거
      _teamNames = teams.toSet().toList();
    });
  }

  void _nextPage() {
    // 키보드 닫기
    FocusScope.of(context).unfocus();

    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    // 키보드 닫기
    FocusScope.of(context).unfocus();

    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      child: Container(
        height: screenHeight * 0.9, // 화면 높이의 90%
        padding: EdgeInsets.all(24.w),
        child: Column(
          children: [
            // 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '전체 교대조 근무표 작성',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            SizedBox(height: 16.h),

            // 진행 상태 표시
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return Row(
                  children: [
                    Container(
                      width: 30.w,
                      height: 30.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index <= _currentPage
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: index <= _currentPage
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                    ),
                    if (index < 2)
                      Container(
                        width: 60.w,
                        height: 2.h,
                        color: index < _currentPage
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                  ],
                );
              }),
            ),

            SizedBox(height: 24.h),

            // 페이지 내용
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildStep1_PatternConfirm(),
                  _buildStep2_TeamNamesInput(),
                  _buildStep3_OffsetInput(),
                ],
              ),
            ),

            SizedBox(height: 16.h),

            // 하단 버튼
            Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousPage,
                      child: Text('이전'),
                    ),
                  ),
                if (_currentPage > 0) SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canProceed() ? (_currentPage < 2 ? _nextPage : _complete) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                    ),
                    child: Text(
                      _currentPage < 2 ? '다음' : '완료',
                      style: TextStyle(color: colorScheme.onPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_currentPage) {
      case 0:
        return true; // 패턴 확인만 하면 됨
      case 1:
        return _teamNames.length >= 2; // 최소 2개 조
      case 2:
        return _teamIndices.length == _teamNames.length &&
               _teamIndices.values.every((idx) => idx >= 1 && idx <= widget.pattern.length);
      default:
        return false;
    }
  }

  // 패턴 표시 (스케줄 변경과 동일한 스타일)
  Widget _buildPatternCards(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6.w,
      runSpacing: 6.h,
      children: widget.pattern.asMap().entries.map((entry) {
        final index = entry.key;
        final shift = entry.value;

        return Container(
          width: 50.w,
          height: 50.w,
          decoration: BoxDecoration(
            // ⭐ 스케줄 변경과 동일: surfaceVariant 배경
            color: colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: colorScheme.outline,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 4.w, top: 2.h),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 9.sp,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    shift,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 1단계: 교대 패턴 확인
  Widget _buildStep1_PatternConfirm() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1단계: 교대 패턴 확인',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          '현재 설정된 교대 패턴을 확인해주세요.',
          style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: 24.h),
        // ⭐ 교대 패턴 (심플하게)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '교대 패턴 (총 ${widget.pattern.length}일 주기)',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 12.h),
            Container(
              height: 150.h,
              child: SingleChildScrollView(
                child: _buildPatternCards(context),
              ),
            ),
          ],
        ),
        SizedBox(height: 24.h),
        // ⭐ 안내 문구 (스케줄 변경과 동일한 amber 톤)
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade900.withOpacity(0.2) : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade700 : Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade400 : Colors.amber.shade700, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  '이 패턴을 기준으로 전체 조의 근무표를 작성합니다.',
                  style: TextStyle(fontSize: 12.sp, color: Colors.amber.shade800),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2단계: 전체 조 구성 입력
  Widget _buildStep2_TeamNamesInput() {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '2단계: 전체 조 구성',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '전체 교대조를 입력해주세요.\n(한 글자만, 띄어쓰기로 구분)',
            style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: 24.h),
          TextField(
            controller: _teamInputController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '조 이름 (예: A B C D)',
              hintText: null,  // ⭐ 활성화 시 placeholder 안 보이게
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          if (_teamNames.isNotEmpty)
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '입력된 조 (${_teamNames.length}개)',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    children: _teamNames.map((team) {
                      return Chip(
                        label: Text(
                          '$team조',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: colorScheme.surface,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          SizedBox(height: 16.h),
          // ⭐ 안내 문구 (스케줄 변경과 동일한 amber 톤)
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade900.withOpacity(0.2) : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade700 : Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade400 : Colors.amber.shade700, size: 20.sp),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    '한 글자만 입력 가능합니다. (예: A, 가, 1)\n최소 2개 조 이상 입력해주세요.',
                    style: TextStyle(fontSize: 12.sp, color: Colors.amber.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3단계: 각 조 근무 선택
  Widget _buildStep3_OffsetInput() {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3단계: 오늘 각 조의 근무 설정',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '오늘 각 조가 교대근무 패턴의 어떤 근무인지 선택해주세요.',
            style: TextStyle(fontSize: 14.sp, color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: 16.h),

          // 각 조별 근무 선택
          ..._teamNames.map((team) {
            final selectedIndex = _teamIndices[team];
            final colorScheme = Theme.of(context).colorScheme;
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: colorScheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$team조 - 오늘의 근무 선택',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: List.generate(widget.pattern.length, (i) {
                        final index = i + 1;
                        final shiftName = widget.pattern[i];
                        final isSelected = selectedIndex == index;
                        final isUsedByOther = _teamIndices.entries
                            .any((entry) => entry.key != team && entry.value == index);

                        return GestureDetector(
                          onTap: isUsedByOther ? null : () {
                            setState(() {
                              _teamIndices[team] = index;
                            });
                          },
                          child: Container(
                            width: 50.w,
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
                            decoration: BoxDecoration(
                              color: isUsedByOther
                                  ? colorScheme.outline.withOpacity(0.3)
                                  : (isSelected ? colorScheme.primary : colorScheme.surface),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: isUsedByOther
                                    ? colorScheme.outline
                                    : (isSelected ? colorScheme.primary : colorScheme.outline),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$index',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? colorScheme.onPrimary : colorScheme.error,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  shiftName,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Future<void> _complete() async {
    // SharedPreferences에 전체 근무표 데이터 저장
    final prefs = await SharedPreferences.getInstance();

    // JSON 형태로 저장
    await prefs.setStringList('all_teams_names', _teamNames);
    await prefs.setString('all_teams_my_team', _myTeam ?? '');

    // 인덱스를 JSON 문자열로 저장
    final indicesJson = _teamIndices.map((key, value) => MapEntry(key, value.toString()));
    await prefs.setString('all_teams_indices', jsonEncode(indicesJson));

    print('✅ 전체 교대조 근무표 저장 완료:');
    print('  - 조 목록: $_teamNames');
    print('  - 본인 조: $_myTeam');
    print('  - 인덱스: $_teamIndices');

    if (!mounted) return;

    Navigator.pop(context, true);  // ⭐ true 반환하여 완료됨을 알림

    // ⭐ 콜백 호출
    widget.onComplete?.call();

    // 성공 메시지
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('전체 교대조 근무표가 설정되었습니다!'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
