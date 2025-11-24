import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/database_service.dart';
import 'onboarding_screen.dart';
import '../services/alarm_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../models/alarm_type.dart';
import 'package:audioplayers/audioplayers.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {

  Future<void> _resetSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('스케줄 초기화'),
        content: Text('교대 스케줄과 알람을 모두 초기화할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('초기화', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final alarms = await DatabaseService.instance.getAllAlarms();
      for (var alarm in alarms) {
        if (alarm.id != null) {
          await AlarmService().cancelAlarm(alarm.id!);
        }
      }

      await ref.read(scheduleProvider.notifier).resetSchedule();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => OnboardingScreen()),
        );
      }
    }
  }

  Future<void> _showAlarmListDialog() async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    // ⭐ Null 체크 추가: date가 null인 알람은 맨 뒤로
    alarms.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return a.date!.compareTo(b.date!);
    });

    final now = DateTime.now();
    final futureAlarms = alarms.where((a) => a.date != null && a.date!.isAfter(now)).toList();
    final pastAlarms = alarms.where((a) => a.date != null && a.date!.isBefore(now)).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.alarm, color: Colors.blue),
            SizedBox(width: 8.w),
            Text('등록된 알람'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: 500.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCountItem('미래', futureAlarms.length, Colors.green),
                    _buildCountItem('과거', pastAlarms.length, Colors.grey),
                    _buildCountItem('전체', alarms.length, Colors.blue),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              if (alarms.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.h),
                    child: Text('등록된 알람이 없습니다', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: alarms.length,
                    itemBuilder: (context, index) {
                      final alarm = alarms[index];
                      final isPast = alarm.date!.isBefore(now);
                      final isToday = alarm.date!.year == now.year &&
                                     alarm.date!.month == now.month &&
                                     alarm.date!.day == now.day;

                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 2.h),
                        child: Text(
                          '${_formatDate(alarm.date!)} ${alarm.shiftType ?? "알람"}${isToday ? " (오늘)" : ""}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontFamily: 'monospace',
                            color: isPast ? Colors.grey : (isToday ? Colors.orange : Colors.black),
                            decoration: isPast ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAlarmHistoryDialog() async {
    final history = await DatabaseService.instance.getAlarmHistory(limit: 100);

    // 한 달 이상 지난 이력 삭제
    final oneMonthAgo = DateTime.now().subtract(Duration(days: 30));
    await DatabaseService.instance.deleteOldHistory(oneMonthAgo);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.history, color: Colors.purple),
            SizedBox(width: 8.w),
            Text('알람 이력'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: 500.h),
          child: history.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(32.h),
                  child: Text('알람 이력이 없습니다', style: TextStyle(color: Colors.grey)),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: history.map((item) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Text(
                        '${_formatHistoryLine(item)}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontFamily: 'monospace',
                          color: _getTypeColor(item.dismissType),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('이력 삭제'),
                  content: Text('모든 알람 이력을 삭제할까요?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('취소')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('삭제', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await DatabaseService.instance.clearAlarmHistory();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ 알람 이력 삭제 완료')),
                );
              }
            },
            child: Text('전체 삭제', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildCountItem(String label, int count, Color color) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11.sp)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatHistoryLine(dynamic item) {
    final date = item.scheduledDate;
    final time = item.scheduledTime;
    final type = _getTypeText(item.dismissType);
    final shift = item.shiftType ?? '';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $time $shift $type';
  }

  String _getTypeText(String type) {
    switch (type) {
      case 'swiped': return 'check';
      case 'snoozed': return 'snooze';
      case 'timeout': return 'timeout';
      case 'ringing': return 'ringing';
      default: return type;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'swiped': return Colors.green;
      case 'snoozed': return Colors.orange;
      case 'timeout': return Colors.red;
      case 'ringing': return Colors.blue;
      default: return Colors.grey;
    }
  }

  Future<void> _showAlarmTypeDialog() async {
    final alarmTypes = await DatabaseService.instance.getAllAlarmTypes();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AlarmTypeSettingsSheet(
        alarmTypes: alarmTypes,
        onUpdate: () {
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Spacer(),
            Padding(
              padding: EdgeInsets.only(right: 16.w),
              child: Text('설정'),
            ),
          ],
        ),
      ),
      body: scheduleAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('에러 발생: $error')),
        data: (schedule) {
          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              // 현재 스케줄 정보
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.indigo.shade200, width: 1.5),
                ),
                child: Column(
                  children: [
                    // 헤더
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(10.r),
                          topRight: Radius.circular(10.r),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month, color: Colors.indigo, size: 20.sp),
                          SizedBox(width: 8.w),
                          Text(
                            '교대 스케줄',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                          Spacer(),
                          // 스케줄 설정 버튼
                          InkWell(
                            onTap: () {
                              // TODO: 스케줄 설정 화면으로 이동
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('스케줄 설정 (준비 중)')),
                              );
                            },
                            borderRadius: BorderRadius.circular(8.r),
                            child: Padding(
                              padding: EdgeInsets.all(4.w),
                              child: Icon(Icons.settings, color: Colors.indigo.shade400, size: 20.sp),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 내용
                    Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (schedule == null)
                            Text('설정 안 됨', style: TextStyle(color: Colors.grey))
                          else if (schedule.isRegular && schedule.pattern != null)
                            _buildPatternRow(schedule.pattern!)
                          else
                            _buildShiftTypesRow((schedule.activeShiftTypes ?? schedule.shiftTypes)),
                        ],
                      ),
                    ),
                    // 초기화 버튼
                    Divider(height: 1, color: Colors.indigo.shade100),
                    InkWell(
                      onTap: _resetSchedule,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(10.r),
                        bottomRight: Radius.circular(10.r),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh, color: Colors.red.shade400, size: 16.sp),
                            SizedBox(width: 6.w),
                            Text(
                              '스케줄 초기화',
                              style: TextStyle(
                                color: Colors.red.shade400,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16.h),

              // 알람음 관리
              ListTile(
                leading: Icon(Icons.notifications_active, color: Colors.orange),
                title: Text('알람음 관리'),
                subtitle: Text('소리, 진동, 무음 설정'),
                trailing: Icon(Icons.chevron_right),
                onTap: _showAlarmTypeDialog,
              ),

              // 등록된 알람
              ListTile(
                leading: Icon(Icons.alarm, color: Colors.blue),
                title: Text('등록된 알람'),
                subtitle: Text('현재 등록된 알람 목록'),
                onTap: _showAlarmListDialog,
              ),

              // 모든 알람 삭제
              ListTile(
                leading: Icon(Icons.delete_sweep, color: Colors.red),
                title: Text('모든 알람 삭제'),
                subtitle: Text('DB + Native 알람 전부 삭제'),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('모든 알람 삭제'),
                      content: Text('정말로 모든 알람을 삭제할까요?\n(스케줄은 유지됩니다)'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('취소'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('삭제', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await ref.read(alarmNotifierProvider.notifier).deleteAllAlarms();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ 모든 알람 삭제 완료')),
                      );
                    }
                  }
                },
              ),

              Divider(),

              // 알람 이력
              ListTile(
                leading: Icon(Icons.history, color: Colors.purple),
                title: Text('알람 이력'),
                subtitle: Text('지난 알람 기록 (30일)'),
                onTap: _showAlarmHistoryDialog,
              ),
            ],
          );
        },
      ),
    );
  }

  // 교대 패턴 표시 (규칙적)
  Widget _buildPatternRow(List<String> pattern) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '교대 패턴',
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 4.w,
          runSpacing: 6.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (int i = 0; i < pattern.length; i++) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Text(
                  pattern[i],
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
              if (i < pattern.length - 1)
                Icon(Icons.arrow_forward, size: 14.sp, color: Colors.grey.shade400),
            ],
          ],
        ),
      ],
    );
  }

  // 근무명 표시 (불규칙)
  Widget _buildShiftTypesRow(List<String> shiftTypes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '근무명',
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 6.w,
          runSpacing: 6.h,
          children: shiftTypes.map((type) => Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(6.r),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Text(
              type,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade700,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
}

// 알람 타입 설정 BottomSheet
class _AlarmTypeSettingsSheet extends StatefulWidget {
  final List<AlarmType> alarmTypes;
  final VoidCallback onUpdate;

  const _AlarmTypeSettingsSheet({
    required this.alarmTypes,
    required this.onUpdate,
  });

  @override
  State<_AlarmTypeSettingsSheet> createState() => _AlarmTypeSettingsSheetState();
}

class _AlarmTypeSettingsSheetState extends State<_AlarmTypeSettingsSheet> {
  late List<AlarmType> _types;

  // 오디오 플레이어
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  // 진동용 MethodChannel
  static const platform = MethodChannel('com.example.shiftbell/alarm');

  @override
  void initState() {
    super.initState();
    _types = List.from(widget.alarmTypes);

    // DB에 타입이 없으면 프리셋으로 초기화
    if (_types.isEmpty) {
      _initPresets();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initPresets() async {
    for (var preset in AlarmType.presets) {
      await DatabaseService.instance.insertAlarmType(preset);
    }
    final types = await DatabaseService.instance.getAllAlarmTypes();
    setState(() {
      _types = types;
    });
  }

  Future<void> _updateType(AlarmType type) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'alarm_types',
      type.toMap(),
      where: 'id = ?',
      whereArgs: [type.id],
    );

    final types = await DatabaseService.instance.getAllAlarmTypes();
    setState(() {
      _types = types;
    });
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Text(
                '알람음 설정',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          SizedBox(height: 16.h),

          // 타입 목록
          ..._types.map((type) => _buildTypeCard(type)).toList(),

          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  Widget _buildTypeCard(AlarmType type) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타입 헤더 (이모지 + 이름)
          Row(
            children: [
              Text(type.emoji, style: TextStyle(fontSize: 28.sp)),
              SizedBox(width: 12.w),
              Text(
                type.isSound ? '소리' : type.isVibrate ? '진동' : '무음',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (type.isSound)
                Text(
                  ' (진동 포함)',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                ),
            ],
          ),
          SizedBox(height: 12.h),

          // 소리 타입: 음악 선택 + 음량 슬라이더
          if (type.isSound) ...[
            _buildSoundSelectRow(type),
            SizedBox(height: 12.h),
            _buildSliderRow(
              label: '음량',
              value: type.volume,
              onChanged: (v) => _updateType(AlarmType(
                id: type.id,
                name: type.name,
                emoji: type.emoji,
                soundFile: type.soundFile,
                volume: v,
                vibrationStrength: type.vibrationStrength,
                isPreset: type.isPreset,
                duration: type.duration,
              )),
              suffix: '${(type.volume * 100).round()}%',
            ),
            SizedBox(height: 8.h),
          ],

          // 진동 타입: 진동 세기
          if (type.isVibrate) ...[
            _buildVibrationRow(type),
            SizedBox(height: 8.h),
          ],

          // 모든 타입: 지속 시간
          _buildDurationRow(type),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required String suffix,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 50.w,
          child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 45.w,
          child: Text(suffix, style: TextStyle(fontSize: 13.sp)),
        ),
      ],
    );
  }

  // 알람 사운드 목록 (파일명과 표시명)
  static const List<Map<String, String>> _soundOptions = [
    {'id': 'alarmbell1', 'name': '알람벨 1', 'file': 'alarmbell1.mp3'},
    {'id': 'alarmbell2', 'name': '알람벨 2', 'file': 'alarmbell2.mp3'},
  ];

  String _selectedSoundId = 'alarmbell1';

  // 소리 미리듣기 재생 (중지 버튼 누를 때까지 반복)
  Future<void> _playSound(String soundId, double volume) async {
    await _audioPlayer.stop();

    final sound = _soundOptions.firstWhere(
      (s) => s['id'] == soundId,
      orElse: () => _soundOptions.first,
    );

    try {
      await _audioPlayer.setVolume(volume);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);  // 반복 재생
      await _audioPlayer.play(AssetSource('sounds/${sound['file']}'));
      setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('소리 재생 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('알람음 파일을 찾을 수 없습니다')),
        );
      }
    }
  }

  // 소리 정지
  void _stopSound() {
    _audioPlayer.stop();
    setState(() => _isPlaying = false);
  }

  // 진동 테스트 (약 1초)
  Future<void> _testVibration(int strength) async {
    try {
      await platform.invokeMethod('testVibration', {'strength': strength});
    } catch (e) {
      debugPrint('진동 테스트 실패: $e');
    }
  }

  Widget _buildSoundSelectRow(AlarmType type) {
    return Row(
      children: [
        SizedBox(
          width: 50.w,
          child: Text('알람음', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Row(
            children: [
              // 알람음 선택 드롭다운
              Expanded(
                child: GestureDetector(
                  onTap: () => _showSoundPicker(type),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.music_note, size: 18.sp, color: Colors.orange),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            _getSoundName(_selectedSoundId),
                            style: TextStyle(fontSize: 13.sp),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              // 재생/정지 버튼
              GestureDetector(
                onTap: () {
                  if (_isPlaying) {
                    _stopSound();
                  } else {
                    _playSound(_selectedSoundId, type.volume);
                  }
                },
                child: Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: _isPlaying ? Colors.red.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: _isPlaying ? Colors.red : Colors.blue,
                    ),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.stop : Icons.play_arrow,
                    color: _isPlaying ? Colors.red : Colors.blue,
                    size: 20.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getSoundName(String soundId) {
    return _soundOptions.firstWhere(
      (s) => s['id'] == soundId,
      orElse: () => {'name': '알람벨 1'},
    )['name']!;
  }

  void _showSoundPicker(AlarmType type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,  // 스크롤 가능하게
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,  // 화면의 50% 높이
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Row(
                    children: [
                      Text(
                        '알람음 선택',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                // 스크롤 가능한 목록
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _soundOptions.length,
                    itemBuilder: (context, index) {
                      final sound = _soundOptions[index];
                      final isSelected = _selectedSoundId == sound['id'];
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                          color: isSelected ? Colors.orange : Colors.grey,
                        ),
                        title: Text(
                          sound['name']!,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.orange.shade800 : Colors.black,
                          ),
                        ),
                        onTap: () {
                          setState(() => _selectedSoundId = sound['id']!);
                          setModalState(() {});
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVibrationRow(AlarmType type) {
    return Row(
      children: [
        SizedBox(
          width: 50.w,
          child: Text('세기', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Row(
            children: [
              _buildVibrationButton(type, 1, '약하게'),
              SizedBox(width: 8.w),
              _buildVibrationButton(type, 3, '강하게'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVibrationButton(AlarmType type, int strength, String label) {
    final isSelected = type.vibrationStrength == strength;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _updateType(AlarmType(
            id: type.id,
            name: type.name,
            emoji: type.emoji,
            soundFile: type.soundFile,
            volume: type.volume,
            vibrationStrength: strength,
            isPreset: type.isPreset,
            duration: type.duration,
          ));
          // 진동 미리보기 (1초)
          _testVibration(strength);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected ? Colors.orange.shade100 : Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.orange.shade800 : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDurationRow(AlarmType type) {
    return Row(
      children: [
        SizedBox(
          width: 50.w,
          child: Text('시간', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Row(
            children: [
              _buildDurationButton(type, 1),
              SizedBox(width: 8.w),
              _buildDurationButton(type, 3),
              SizedBox(width: 8.w),
              _buildDurationButton(type, 5),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDurationButton(AlarmType type, int minutes) {
    final isSelected = type.duration == minutes;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateType(AlarmType(
          id: type.id,
          name: type.name,
          emoji: type.emoji,
          soundFile: type.soundFile,
          volume: type.volume,
          vibrationStrength: type.vibrationStrength,
          isPreset: type.isPreset,
          duration: minutes,
        )),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade100 : Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '${minutes}분',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue.shade800 : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
