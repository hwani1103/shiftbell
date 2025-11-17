class AlarmType {
  final int id;
  final String name;
  final String emoji;
  final String soundFile;
  final double volume;
  final bool isPreset;

  AlarmType({
    required this.id,
    required this.name,
    required this.emoji,
    required this.soundFile,
    required this.volume,
    required this.isPreset,
  });

  // DB → 객체
  factory AlarmType.fromMap(Map<String, dynamic> map) {
    return AlarmType(
      id: map['id'],
      name: map['name'],
      emoji: map['emoji'],
      soundFile: map['sound_file'],
      volume: map['volume'],
      isPreset: map['is_preset'] == 1,
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
      'is_preset': isPreset ? 1 : 0,
    };
  }

  // 기본 3개
  static final List<AlarmType> presets = [
    AlarmType(
      id: 1,
      name: '소리',
      emoji: '🔊',
      soundFile: 'loud',
      volume: 1.0,
      isPreset: true,
    ),
    AlarmType(
      id: 2,
      name: '진동',
      emoji: '📳',
      soundFile: 'vibrate',
      volume: 0.0,
      isPreset: true,
    ),
    AlarmType(
      id: 3,
      name: '무음',
      emoji: '🔕',
      soundFile: 'silent',
      volume: 0.0,
      isPreset: true,
    ),
  ];
}