class AlarmType {
  final int id;
  final String name;  // 내부 식별용 (UI에서는 이모지만 표시)
  final String emoji;
  final String soundFile;  // 'loud', 'vibrate', 'silent'
  final double volume;  // 0.0 ~ 1.0 (소리 볼륨)
  final int vibrationStrength;  // 0=없음, 1=약, 2=중, 3=강
  final bool isPreset;
  final int duration;  // 분 단위

  AlarmType({
    required this.id,
    required this.name,
    required this.emoji,
    required this.soundFile,
    required this.volume,
    this.vibrationStrength = 2,  // 기본값: 중
    required this.isPreset,
    this.duration = 5,
  });

  // DB → 객체
  factory AlarmType.fromMap(Map<String, dynamic> map) {
    return AlarmType(
      id: map['id'],
      name: map['name'],
      emoji: map['emoji'],
      soundFile: map['sound_file'],
      volume: map['volume'],
      vibrationStrength: map['vibration_strength'] ?? 2,
      isPreset: map['is_preset'] == 1,
      duration: map['duration'] ?? 10,
    );
  }

  // 객체 → DB
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'sound_file': soundFile,
      'volume': volume,
      'vibration_strength': vibrationStrength,
      'is_preset': isPreset ? 1 : 0,
      'duration': duration,
    };
  }

  // 타입 판별 (default, alarmbell 또는 기존 loud/soft도 소리 타입)
  bool get isSound => soundFile == 'default' || soundFile.startsWith('alarmbell') || soundFile == 'loud' || soundFile == 'soft';
  bool get isVibrate => soundFile == 'vibrate';
  bool get isSilent => soundFile == 'silent';

  // 진동 세기 텍스트
  String get vibrationText {
    switch (vibrationStrength) {
      case 1: return '약하게';
      case 3: return '강하게';
      default: return '없음';
    }
  }

  // 기본 3개 프리셋
  static final List<AlarmType> presets = [
    AlarmType(
      id: 1,
      name: 'sound',
      emoji: '🔔',
      soundFile: 'default',  // 시스템 기본 알람음
      volume: 0.7,  // 70%
      vibrationStrength: 3,  // 강하게
      isPreset: true,
      duration: 3,  // 3분
    ),
    AlarmType(
      id: 2,
      name: 'vibrate',
      emoji: '📳',
      soundFile: 'vibrate',
      volume: 0.0,
      vibrationStrength: 3,  // 강하게
      isPreset: true,
      duration: 3,  // 3분
    ),
    AlarmType(
      id: 3,
      name: 'silent',
      emoji: '🔇',
      soundFile: 'silent',
      volume: 0.0,
      vibrationStrength: 0,  // 없음
      isPreset: true,
      duration: 3,  // 3분
    ),
  ];
}
