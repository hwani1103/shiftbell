import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/alarm.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../services/alarm_refresh_helper.dart';

// 알람 설정 (시간 + 타입)
class AlarmSetting {
  final TimeOfDay time;
  final int alarmTypeId;  // 1: 소리, 2: 진동, 3: 무음

  AlarmSetting({required this.time, this.alarmTypeId = 1});

  AlarmSetting copyWith({TimeOfDay? time, int? alarmTypeId}) {
    return AlarmSetting(
      time: time ?? this.time,
      alarmTypeId: alarmTypeId ?? this.alarmTypeId,
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {  // ⭐ 변경
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();  // ⭐ 변경
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {  // ⭐ 변경
  int _step = 0;
  bool? _isRegular;
  List<String> _pattern = [];
  int? _todayIndex;
  
  List<String> _baseShiftTypes = ['주간', '야간', '오전', '오후', '휴무'];
  List<String> _customShiftTypes = [];
  List<String> get _allShiftTypes => [..._baseShiftTypes, ..._customShiftTypes];
  Map<String, List<AlarmSetting>> _shiftAlarms = {};
  List<String> _selectedShifts = [];  // 불규칙용

  List<String> get _uniqueShifts {
    return _pattern.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(
          child: Text('교대근무 스케줄 생성'),
        ),
        leading: _step > 0
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => _step--);
                },
              )
            : SizedBox(width: 56.w),
      ),
      body: SafeArea(
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildSelectType();
      case 1:
        return _isRegular == true ? _buildShiftTypeCreation() : _buildShiftTypesInput();
      case 2:
        return _isRegular == true ? _buildPatternInput() : _buildSelectShiftsForAlarm();
      case 3:
        return _isRegular == true ? _buildTodayIndexInput() : _buildMainAlarmSetup();
      case 4:
        return _isRegular == true ? _buildMainAlarmSetup() : _buildComplete();
      case 5:
        return _buildComplete();
      default:
        return Container();
    }
  }

  Widget _buildSelectType() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '고정적으로 순환하는\n교대 근무인가요?',
            style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 48.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isRegular = true;
                  _step = 1;
                  _shiftAlarms.clear();  // ⭐ 초기화
                  _selectedShifts.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16.h),
              ),
              child: Text('예 - 규칙적', style: TextStyle(fontSize: 18.sp)),
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isRegular = false;
                  _step = 1;
                  _shiftAlarms.clear();  // ⭐ 초기화
                  _selectedShifts.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16.h),
              ),
              child: Text('아니요 - 불규칙', style: TextStyle(fontSize: 18.sp)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftTypeCreation() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무 형태를 확인하세요\n없다면 추가 가능합니다',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                ..._allShiftTypes.map((name) {
                  final isCustom = _customShiftTypes.contains(name);
                  if (isCustom) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ElevatedButton(
                          onPressed: () {},
                          child: Text(name),
                        ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: GestureDetector(
                            onTap: () => _deleteCustomShiftType(name),
                            child: Container(
                              width: 20.w,
                              height: 20.h,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                size: 14.sp,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return ElevatedButton(
                      onPressed: () {},
                      child: Text(name),
                    );
                  }
                }),
                
                OutlinedButton.icon(
                  onPressed: _customShiftTypes.length < 4 ? _showAddCustomDialog : null,
                  icon: Icon(Icons.add),
                  label: Text('추가'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 48.h),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _step = 2);
                },
                child: Text('다음'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftTypesInput() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무 형태를 확인하세요\n없다면 추가 가능합니다',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                ..._allShiftTypes.map((name) {
                  final isCustom = _customShiftTypes.contains(name);
                  if (isCustom) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ElevatedButton(
                          onPressed: () {},
                          child: Text(name),
                        ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: GestureDetector(
                            onTap: () => _deleteCustomShiftType(name),
                            child: Container(
                              width: 20.w,
                              height: 20.h,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                size: 14.sp,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return ElevatedButton(
                      onPressed: () {},
                      child: Text(name),
                    );
                  }
                }),
                
                OutlinedButton.icon(
                  onPressed: _customShiftTypes.length < 4 ? _showAddCustomDialog : null,
                  icon: Icon(Icons.add),
                  label: Text('추가'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 48.h),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _step = 2);
                },
                child: Text('다음'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ 불규칙: 실제 사용할 근무 선택
  Widget _buildSelectShiftsForAlarm() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '실제 근무 패턴에 해당하는\n근무를 모두 선택해주세요',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: _allShiftTypes.map((name) {
              final isSelected = _selectedShifts.contains(name);
              
              return ElevatedButton(
                onPressed: () {
                  setState(() {
                    if (isSelected) {
                      _selectedShifts.remove(name);
                    } else {
                      _selectedShifts.add(name);
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.blue.shade700 : null,
                  foregroundColor: isSelected ? Colors.white : null,
                  elevation: isSelected ? 2 : null,
                ),
                child: Text(name),
              );
            }).toList(),
          ),
          
          Spacer(),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedShifts.isEmpty ? null : () {
                setState(() => _step = 3);
              },
              child: Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternInput() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '버튼을 탭해서 패턴을 완성해주세요',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: _allShiftTypes.map((name) => ElevatedButton(
              onPressed: _pattern.length < 30 ? () => _addToPattern(name) : null,
              child: Text(name),
            )).toList(),
          ),
          
          SizedBox(height: 24.h),
          
          Text(
            '전체 교대 패턴 순서대로 입력 - 최대 30일 \n ex) 주주휴휴야야휴휴',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12.h),
          
          Expanded(
            child: _buildPatternGrid(isSelectable: false),
          ),
          
          SizedBox(height: 16.h),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _pattern.isEmpty ? null : () {
                setState(() => _step = 3);
              },
              child: Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternGrid({required bool isSelectable}) {
  if (_pattern.isEmpty) {
    return Center(
      child: Text(
        '패턴 없음',
        style: TextStyle(fontSize: 16.sp, color: Colors.grey),
      ),
    );
  }

  return GridView.builder(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 6,  // ⭐ 6열 고정
      crossAxisSpacing: 6.w,  // ⭐ 간격 살짝 줄임 (8.w → 6.w)
      mainAxisSpacing: 6.h,   // ⭐ 간격 살짝 줄임 (8.h → 6.h)
      childAspectRatio: 1.0, // ⭐ 거의 정사각형 (0.85 → 0.95)
    ),
    itemCount: _pattern.length,
    itemBuilder: (context, index) {
      final isSelected = isSelectable && _todayIndex == index;
      
      return InkWell(
        onTap: isSelectable
            ? () {
                setState(() => _todayIndex = index);
              }
            : () {
                _removeFromPattern(index);
              },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey,
              width: 2,
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
                      fontSize: 9.sp,  // ⭐ 번호도 살짝 축소 (10.sp → 9.sp)
                      color: isSelected ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
              
              Expanded(
                child: Center(
                  child: Text(
                    _pattern[index],
                    style: TextStyle(
                      fontSize: 11.sp,  // ⭐ 근무명 축소 (14.sp → 12.sp)
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,  // ⭐ 1줄 강제
                    overflow: TextOverflow.ellipsis,  // ⭐ 넘치면 ... 처리
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  void _deleteCustomShiftType(String name) {
    setState(() {
      _customShiftTypes.remove(name);
      _pattern.removeWhere((shift) => shift == name);
    });
  }

  void _showAddCustomDialog() {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('근무명 추가'),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLength: 4,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '근무명 (최대 4글자)',
              counterText: '',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('근무명을 입력해주세요')),
                );
                return;
              }
              if (text.length > 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('4글자 이하로 입력해주세요')),
                );
                return;
              }
              if (_allShiftTypes.contains(text)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('이미 존재하는 근무명입니다')),
                );
                return;
              }
              
              setState(() {
                _customShiftTypes.add(text);
              });
              Navigator.pop(context);
            },
            child: Text('추가'),
          ),
        ],
      ),
    );
  }

  void _addToPattern(String shift) {
    if (_pattern.length < 30) {
      setState(() => _pattern.add(shift));
    }
  }

  void _removeFromPattern(int index) {
    setState(() {
      _pattern.removeAt(index);
    });
  }

  Widget _buildMainAlarmSetup() {
  final shiftsToSetup = _isRegular == true ? _uniqueShifts : _selectedShifts;
  
  return Padding(
    padding: EdgeInsets.all(24.w),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '근무별 고정 알람을 설정하세요',
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
        ),
        Text(
          '각 근무당 최대 3개까지 설정 가능',
          style: TextStyle(fontSize: 14.sp, color: Colors.black),
        ),
        Text(
          '설정 탭에서도 설정 / 수정이 가능합니다',
          style: TextStyle(fontSize: 14.sp, color: Colors.black),
        ),
        SizedBox(height: 24.h),
        
        Expanded(
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(  // ⭐ 변경
              maxCrossAxisExtent: 120.w,  // ⭐ 변경
              crossAxisSpacing: 12.w,
              mainAxisSpacing: 12.h,
              childAspectRatio: 0.70,
            ),
            itemCount: shiftsToSetup.length,
            itemBuilder: (context, index) {
              final shift = shiftsToSetup[index];
              final alarms = _shiftAlarms[shift] ?? [];
              
              return _buildShiftAlarmCard(shift, alarms);
            },
          ),
        ),
        
        SizedBox(height: 16.h),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              setState(() => _step = _isRegular == true ? 5 : 4);
            },
            child: Text('다음'),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildShiftAlarmCard(String shift, List<AlarmSetting> alarms) {
    return InkWell(
      onTap: () => _showAlarmTimeDialog(shift),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: alarms.isEmpty ? Colors.red.shade300 : Colors.black,
            width: 2,
          ),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          children: [
            Text(
              shift,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 12.h),

            Expanded(
              child: Center(
                child: alarms.isEmpty
                    ? Text(
                        '탭하여 설정',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.grey,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: alarms.map((alarm) => Padding(
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getAlarmTypeEmoji(alarm.alarmTypeId),
                                style: TextStyle(fontSize: 12.sp),
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                _formatTime(alarm.time),
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getAlarmTypeEmoji(int alarmTypeId) {
    switch (alarmTypeId) {
      case 1: return '🔔';  // 소리
      case 2: return '📳';  // 진동
      case 3: return '🔇';  // 무음
      default: return '🔔';
    }
  }

  void _showAlarmTimeDialog(String shift) {
    showDialog(
      context: context,
      builder: (context) => _AlarmTimeDialog(
        shift: shift,
        initialAlarms: _shiftAlarms[shift] ?? [],
        onSave: (alarms) {
          setState(() {
            _shiftAlarms[shift] = alarms;
          });
        },
      ),
    );
  }

  Widget _buildTodayIndexInput() {
    final today = DateTime.now();
    final dateText = '${today.month}/${today.day}';
    
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘($dateText)은 어떤 근무인가요?',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          
          Expanded(
            child: _buildPatternGrid(isSelectable: true),
          ),
          
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _todayIndex == null ? null : () {
                setState(() => _step = 4);
              },
              child: Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplete() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 100.sp, color: Colors.green),
          SizedBox(height: 24.h),
          Text(
            '설정 완료!',
            style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 48.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveAndFinish,
              child: Text('시작하기'),
            ),
          ),
        ],
      ),
    );
  }

  // onboarding_screen.dart의 _generateShiftColors() 함수 수정
// onboarding_screen.dart의 _generateShiftColors() 함수 전체 교체

Map<String, int> _generateShiftColors() {
  final Map<String, int> colors = {};

  // 1. 휴무 계열 → 명확한 빨강 (파스텔 아님)
  for (var shift in _allShiftTypes) {
    if (shift.contains('휴')) {
      colors[shift] = 0xFFEF5350;  // ⭐ Red (진한 빨강)
    }
  }

  // 2. 나머지 근무 → 파스텔 팔레트에서 순서대로 할당
  final nonRestShifts = _allShiftTypes.where((s) => !s.contains('휴')).toList();

  for (int i = 0; i < nonRestShifts.length && i < 8; i++) {
    final shift = nonRestShifts[i];
    final color = ShiftSchedule.shiftPalette[i % 8];  // ⭐ 파스텔 팔레트 순환
    colors[shift] = color.value;  // Color → int 변환
  }

  return colors;
}

Future<void> _saveAlarmTemplates() async {
  for (var entry in _shiftAlarms.entries) {
    final shift = entry.key;
    final alarms = entry.value;

    for (var alarm in alarms) {
      await DatabaseService.instance.insertAlarmTemplate(
        shiftType: shift,
        time: _formatTime(alarm.time),
        alarmTypeId: alarm.alarmTypeId,  // 사용자가 선택한 타입
      );
    }
  }

  print('✅ 알람 템플릿 저장 완료');
}

 // onboarding_screen.dart의 _saveAndFinish() 수정

// onboarding_screen.dart - _saveAndFinish()
Future<void> _saveAndFinish() async {
  final shiftColors = _generateShiftColors();
  
  List<String> activeShifts;
  if (_isRegular!) {
    activeShifts = _pattern.toSet().toList();
  } else {
    activeShifts = _selectedShifts;
  }
  
  final schedule = ShiftSchedule(
    isRegular: _isRegular!,
    pattern: _isRegular! ? _pattern : null,
    todayIndex: _todayIndex,
    shiftTypes: _allShiftTypes,
    activeShiftTypes: activeShifts,
    startDate: DateTime.now(),
    shiftColors: shiftColors,
  );

  await ref.read(scheduleProvider.notifier).saveSchedule(schedule);
  await _saveAlarmTemplates();

  // ⭐ 기존 알람 전체 삭제 (Native + DB)
  try {
    final allAlarms = await DatabaseService.instance.getAllAlarms();
    for (final alarm in allAlarms) {
      if (alarm.id != null) {
        await AlarmService().cancelAlarm(alarm.id!);
      }
    }
    await DatabaseService.instance.deleteAllAlarms();
    print('🗑️ 온보딩: 기존 알람 전체 삭제 완료');
  } catch (e) {
    print('⚠️ 기존 알람 삭제 실패: $e');
  }

  // ⭐ 10일치 알람 생성 (1회만!)
  if (_isRegular!) {
    await _generate10DaysAlarms(schedule);
  }

  // 갱신 완료 표시
  await AlarmRefreshHelper.instance.markRefreshed();
  print('✅ 온보딩 완료 - 갱신 완료 표시');

  // AlarmNotifier 갱신
  if (mounted) {
    try {
      await ref.read(alarmNotifierProvider.notifier).refresh();
      print('✅ 온보딩 완료 - AlarmNotifier 갱신 완료');
    } catch (e) {
      print('❌ AlarmNotifier 갱신 실패: $e');
    }
  }

  if (mounted) {
    Navigator.of(context).pushReplacementNamed('/home');
  }
}

  // onboarding_screen.dart에서 수정

Future<void> _generate10DaysAlarms(ShiftSchedule schedule) async {
  print('🔄 10일치 알람 생성 시작...');

  final List<Alarm> alarms = [];
  final today = DateTime.now();

  for (var i = 0; i < 10; i++) {
    final date = today.add(Duration(days: i));
    final shiftType = schedule.getShiftForDate(date);

    if (shiftType == '미설정') continue;

    final alarmSettings = _shiftAlarms[shiftType] ?? [];

    for (var setting in alarmSettings) {
      final alarmTime = DateTime(
        date.year,
        date.month,
        date.day,
        setting.time.hour,
        setting.time.minute,
      );

      if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) continue;

      final alarm = Alarm(
        time: _formatTime(setting.time),
        date: alarmTime,
        type: 'fixed',
        alarmTypeId: setting.alarmTypeId,  // 사용자가 선택한 타입
        shiftType: shiftType,
      );

      alarms.add(alarm);
    }
  }
  
  if (alarms.isNotEmpty) {
    // DB 저장
    await DatabaseService.instance.insertAlarmsInBatch(alarms);
    
    // ⭐ 변경: 저장된 알람 다시 읽어서 DB ID로 Native 등록
    final savedAlarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in savedAlarms) {
      if (alarm.date != null && alarm.date!.isAfter(DateTime.now())) {
        await AlarmService().scheduleAlarm(
          id: alarm.id!,  // ⭐ DB ID 사용
          dateTime: alarm.date!,
          label: alarm.shiftType ?? '알람',
          soundType: 'loud',
        );
      }
    }
    
    // ⭐ 삭제: refresh() 불필요
    // if (mounted) {
    //   ref.read(alarmNotifierProvider.notifier).refresh();
    // }
  }
  
  print('✅ ${alarms.length}개 알람 생성 완료');
}
}

// 알람 시간 설정 다이얼로그
class _AlarmTimeDialog extends StatefulWidget {
  final String shift;
  final List<AlarmSetting> initialAlarms;
  final Function(List<AlarmSetting>) onSave;

  const _AlarmTimeDialog({
    required this.shift,
    required this.initialAlarms,
    required this.onSave,
  });

  @override
  State<_AlarmTimeDialog> createState() => _AlarmTimeDialogState();
}

class _AlarmTimeDialogState extends State<_AlarmTimeDialog> {
  late List<AlarmSetting> _alarms;

  @override
  void initState() {
    super.initState();
    _alarms = List.from(widget.initialAlarms);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.shift} 고정 알람'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '고정 알람 3개까지 등록 가능',
              style: TextStyle(fontSize: 13.sp, color: Colors.grey),
            ),
            SizedBox(height: 16.h),

            ..._alarms.asMap().entries.map((entry) {
              final alarm = entry.value;
              return Container(
                margin: EdgeInsets.only(bottom: 12.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 시간 + 삭제 버튼
                    Row(
                      children: [
                        // ⭐ 시간 영역 탭하면 시간 수정
                        InkWell(
                          onTap: () => _editAlarmTime(entry.key),
                          borderRadius: BorderRadius.circular(8.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.alarm, size: 20.sp, color: Colors.blue),
                                SizedBox(width: 8.w),
                                Text(
                                  '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red, size: 20.sp),
                          onPressed: () {
                            setState(() {
                              _alarms.removeAt(entry.key);
                            });
                          },
                          constraints: BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    // 알람 타입 선택 버튼들
                    Row(
                      children: [
                        _buildTypeButton(entry.key, 1, '🔔', '소리'),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 2, '📳', '진동'),
                        SizedBox(width: 8.w),
                        _buildTypeButton(entry.key, 3, '🔇', '무음'),
                      ],
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 8.h),

            if (_alarms.length < 3)
              OutlinedButton.icon(
                onPressed: _addAlarm,
                icon: Icon(Icons.add),
                label: Text('알람 추가'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 44.h),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('취소'),
        ),
        TextButton(
          onPressed: _alarms.isEmpty
              ? null
              : () {
                  _alarms.sort((a, b) {
                    final aMinutes = a.time.hour * 60 + a.time.minute;
                    final bMinutes = b.time.hour * 60 + b.time.minute;
                    return aMinutes.compareTo(bMinutes);
                  });

                  widget.onSave(_alarms);
                  Navigator.pop(context);
                },
          child: Text('저장'),
        ),
      ],
    );
  }

  // 알람 타입 선택 버튼
  Widget _buildTypeButton(int index, int typeId, String emoji, String label) {
    final isSelected = _alarms[index].alarmTypeId == typeId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _alarms[index] = _alarms[index].copyWith(alarmTypeId: typeId);
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected ? Colors.orange.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: TextStyle(fontSize: 16.sp)),
              SizedBox(height: 2.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: isSelected ? Colors.orange.shade800 : Colors.grey.shade600,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ 알람 시간 수정
  Future<void> _editAlarmTime(int index) async {
    final currentAlarm = _alarms[index];
    await showDialog(
      context: context,
      builder: (context) => _SamsungStyleTimePicker(
        initialTime: currentAlarm.time,
        onTimeSelected: (time) {
          setState(() {
            _alarms[index] = currentAlarm.copyWith(time: time);
          });
        },
      ),
    );
  }

  Future<void> _addAlarm() async {
    await showDialog(
      context: context,
      builder: (context) => _SamsungStyleTimePicker(
        onTimeSelected: (time) {
          setState(() {
            // 기본값: 소리 (alarmTypeId = 1)
            _alarms.add(AlarmSetting(time: time, alarmTypeId: 1));
          });
        },
      ),
    );
  }
}

class _SamsungStyleTimePicker extends StatefulWidget {
  final Function(TimeOfDay) onTimeSelected;
  final TimeOfDay? initialTime;  // ⭐ 초기 시간 (수정 시 사용)

  const _SamsungStyleTimePicker({
    required this.onTimeSelected,
    this.initialTime,
  });

  @override
  State<_SamsungStyleTimePicker> createState() => _SamsungStyleTimePickerState();
}

class _SamsungStyleTimePickerState extends State<_SamsungStyleTimePicker> {
  bool _isAM = true;
  int _hour = 9;
  int _minute = 0;

  @override
  void initState() {
    super.initState();
    // ⭐ 초기 시간이 있으면 설정
    if (widget.initialTime != null) {
      final t = widget.initialTime!;
      _minute = t.minute;
      if (t.hour == 0) {
        _isAM = true;
        _hour = 12;
      } else if (t.hour < 12) {
        _isAM = true;
        _hour = t.hour;
      } else if (t.hour == 12) {
        _isAM = false;
        _hour = 12;
      } else {
        _isAM = false;
        _hour = t.hour - 12;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '시간 선택',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = true;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isAM ? Colors.blue : Colors.grey.shade300,
                            width: _isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            '오전',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 8.h),
                    
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = false;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: !_isAM ? Colors.blue : Colors.grey.shade300,
                            width: !_isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            '오후',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(width: 16.w),

                // ⭐ 시간 NumberPicker 수정
                _TappableNumberPicker(
                  value: _hour,
                  minValue: 1,
                  maxValue: 12,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      if (_hour == 11 && value == 12) {
                        _isAM = !_isAM;
                      } else if (_hour == 12 && value == 11) {
                        _isAM = !_isAM;
                      }
                      _hour = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                
                Text(':', style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold)),

                // ⭐ 분 NumberPicker 수정
                _TappableNumberPicker(
                  value: _minute,
                  minValue: 0,
                  maxValue: 59,
                  zeroPad: true,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      _minute = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 24.h),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('취소'),
                ),
                SizedBox(width: 8.w),
                ElevatedButton(
                  onPressed: () {
                    int hour24;
                    if (_isAM) {
                      hour24 = _hour == 12 ? 0 : _hour;
                    } else {
                      hour24 = _hour == 12 ? 12 : _hour + 12;
                    }

                    widget.onTimeSelected(TimeOfDay(hour: hour24, minute: _minute));
                    Navigator.pop(context);
                  },
                  child: Text('확인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ⭐ 탭 가능한 NumberPicker Wrapper (스와이프 + 탭 지원)
class _TappableNumberPicker extends StatelessWidget {
  final int value;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;
  final bool infiniteLoop;
  final bool zeroPad;
  final double itemHeight;
  final double itemWidth;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final BoxDecoration? decoration;

  const _TappableNumberPicker({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
    this.infiniteLoop = false,
    this.zeroPad = false,
    this.itemHeight = 50.0,
    this.itemWidth = 60.0,
    this.textStyle,
    this.selectedTextStyle,
    this.decoration,
  });

  void _handleTapUp() {
    // ⭐ 위쪽 탭: 값 감소 (한 칸만)
    // infiniteLoop에서 경계값이면 탭 무시 (60칸 점프 방지)
    if (infiniteLoop && value == minValue) {
      return;
    }

    int newValue = value - 1;
    if (newValue < minValue) {
      newValue = minValue;  // infiniteLoop여도 탭으로는 순환 안 함
    }
    if (newValue != value) {
      onChanged(newValue);
    }
  }

  void _handleTapDown() {
    // ⭐ 아래쪽 탭: 값 증가 (한 칸만)
    // infiniteLoop에서 경계값이면 탭 무시 (60칸 점프 방지)
    if (infiniteLoop && value == maxValue) {
      return;
    }

    int newValue = value + 1;
    if (newValue > maxValue) {
      newValue = maxValue;  // infiniteLoop여도 탭으로는 순환 안 함
    }
    if (newValue != value) {
      onChanged(newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemHeight * 3,
      width: itemWidth,
      child: Stack(
        children: [
          // ⭐ 기존 NumberPicker (부드러운 스크롤)
          NumberPicker(
            value: value,
            minValue: minValue,
            maxValue: maxValue,
            zeroPad: zeroPad,
            infiniteLoop: infiniteLoop,
            haptics: true,
            itemHeight: itemHeight,
            itemWidth: itemWidth,
            axis: Axis.vertical,
            textStyle: textStyle,
            selectedTextStyle: selectedTextStyle,
            onChanged: onChanged,
            decoration: decoration,
          ),

          // ⭐ 위쪽 탭 영역 (한 칸 위로)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: itemHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleTapUp,
              child: Container(color: Colors.transparent),
            ),
          ),

          // ⭐ 아래쪽 탭 영역 (한 칸 아래로)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: itemHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleTapDown,
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }
}