// screens/friend_calendar_view.dart
//
// ⭐ 친구 달력 보기 - 실제 달력탭(calendar_tab.dart)과 최대한 같은 톤(근무명
// 알약 배지 + 가운데 숫자 + 하단 메모)으로 만들되, 데이터는 Provider가 아니라
// 친구의 FriendScheduleData 스냅샷에서만 읽음. 맨 위 배너로 "지금 내 달력이
// 아니라 친구 달력을 보고 있다"는 걸 항상 인식시킴. 읽기 전용 - 근무 변경/
// 메모 추가/OT 입력 등 편집 기능은 없음(애초에 공유 안 되는 정보이기도 함).
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/friend_schedule.dart';
import '../models/shift_schedule.dart';

class FriendCalendarView extends StatefulWidget {
  final String friendName;
  final FriendScheduleData data;
  // ⭐ 웹(트랙1)에서만 true로 넘어옴 - 링크 받은 사람이 앱 미설치자일 수 있어서
  // "앱 설치하고 실시간으로 보기" 유도 배너를 하단에 추가로 보여줌. 앱 안(트랙2,
  // 친구 목록에서 열 때)에서는 이미 앱을 쓰고 있으니 당연히 안 보여줌.
  final bool showInstallPrompt;
  final VoidCallback? onInstallTap;

  const FriendCalendarView({
    super.key,
    required this.friendName,
    required this.data,
    this.showInstallPrompt = false,
    this.onInstallTap,
  });

  @override
  State<FriendCalendarView> createState() => _FriendCalendarViewState();
}

class _FriendCalendarViewState extends State<FriendCalendarView> {
  late DateTime _viewedMonth;
  static const _weekdayKr = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewedMonth = DateTime(now.year, now.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() => _viewedMonth = DateTime(_viewedMonth.year, _viewedMonth.month + delta, 1));
  }

  List<DateTime> _gridDays() {
    final firstOfMonth = DateTime(_viewedMonth.year, _viewedMonth.month, 1);
    final daysFromSunday = firstOfMonth.weekday % 7; // 일=7 -> 0
    final gridStart = firstOfMonth.subtract(Duration(days: daysFromSunday));
    return List.generate(42, (i) => gridStart.add(Duration(days: i)));
  }

  Color _shiftColor(String shiftName) {
    final v = widget.data.shiftColors[shiftName];
    if (v == null) return Colors.grey.shade300;
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = _gridDays();
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text('${widget.friendName}님의 근무표', style: TextStyle(fontSize: 17.sp))),
      body: Column(
        children: [
          // ⭐ 항상 눈에 띄는 배너 - "내 달력이 아니다"를 계속 인식시킴
          Container(
            width: double.infinity,
            color: Colors.amber.shade100,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, size: 16.sp, color: Colors.brown.shade600),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    '${widget.friendName}님의 근무표를 보는 중입니다 (읽기 전용)',
                    style: TextStyle(fontSize: 12.sp, color: Colors.brown.shade700, fontWeight: FontWeight.w600),
                  ),
                ),
                if (!widget.data.hasMemos)
                  Text('메모 비공개', style: TextStyle(fontSize: 10.5.sp, color: Colors.brown.shade400)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
            child: Row(
              children: [
                IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_viewedMonth.year}년 ${_viewedMonth.month}월',
                      style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              children: List.generate(7, (i) => Expanded(
                child: Center(
                  child: Text(_weekdayKr[i], style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: i == 0 ? Colors.red.shade400 : colorScheme.onSurfaceVariant)),
                ),
              )),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: Column(
                children: List.generate(6, (row) => Expanded(
                  child: Row(children: List.generate(7, (col) {
                    final day = days[row * 7 + col];
                    final outside = day.month != _viewedMonth.month;
                    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                    final isSunday = day.weekday == DateTime.sunday;
                    final shiftName = widget.data.getShiftForDate(day);
                    final hasShift = shiftName.isNotEmpty && shiftName != '미설정';
                    final memos = widget.data.memosForDate(day);

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _showDaySheet(context, day, shiftName, memos),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          margin: EdgeInsets.all(1.5.w),
                          decoration: BoxDecoration(
                            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4), width: 0.6),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (hasShift)
                                Container(
                                  height: 15.h,
                                  margin: EdgeInsets.symmetric(horizontal: 2.w),
                                  decoration: BoxDecoration(color: _shiftColor(shiftName), borderRadius: BorderRadius.circular(3.r)),
                                  alignment: Alignment.center,
                                  child: Text(
                                    shiftName,
                                    style: TextStyle(fontSize: 8.sp, fontWeight: FontWeight.bold, color: ShiftSchedule.getTextColor(_shiftColor(shiftName))),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              else
                                SizedBox(height: 15.h),
                              SizedBox(height: 2.h),
                              Text(
                                '${day.day}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                                  color: outside
                                      ? colorScheme.outlineVariant
                                      : (isSunday ? Colors.red.shade400 : colorScheme.onSurface),
                                ),
                              ),
                              if (memos.isNotEmpty)
                                ...memos.take(3).map((m) => Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 1.w),
                                  child: Text(m, style: TextStyle(fontSize: 6.5.sp, color: colorScheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                )),
                            ],
                          ),
                        ),
                      ),
                    );
                  })),
                )),
              ),
            ),
          ),
          if (widget.showInstallPrompt) _buildInstallBanner(context),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  // ⭐ 웹→앱 설치 funnel의 2단계("더 편하게 보기" 유도). 3단계(딥링크로 설치 후
  // 자동으로 친구 데이터까지 들어오는 것)는 스토어/딥링크 실배포가 필요해서
  // 지금은 스토어로만 연결하고, 최종 정리 문서에 딥링크 설정 방법을 남겨둠.
  Widget _buildInstallBanner(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '앱을 설치하면 내 근무표도 등록하고, 친구와 실시간으로 비교할 수 있어요',
              style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          SizedBox(width: 10.w),
          ElevatedButton(
            onPressed: widget.onInstallTap,
            style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h)),
            child: Text('앱 설치', style: TextStyle(fontSize: 12.sp)),
          ),
        ],
      ),
    );
  }

  void _showDaySheet(BuildContext context, DateTime day, String shiftName, List<String> memos) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${day.month}월 ${day.day}일', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 10.h),
              Row(children: [
                Container(width: 12.w, height: 12.w, decoration: BoxDecoration(color: _shiftColor(shiftName), shape: BoxShape.circle)),
                SizedBox(width: 8.w),
                Text('근무: $shiftName', style: TextStyle(fontSize: 15.sp)),
              ]),
              if (memos.isNotEmpty) ...[
                SizedBox(height: 12.h),
                Text('메모', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline)),
                SizedBox(height: 4.h),
                ...memos.map((m) => Padding(
                  padding: EdgeInsets.only(bottom: 4.h),
                  child: Text('· $m', style: TextStyle(fontSize: 13.sp)),
                )),
              ],
            ],
          ),
        );
      },
    );
  }
}
