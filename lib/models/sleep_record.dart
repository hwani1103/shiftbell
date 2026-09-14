// lib/models/sleep_record.dart
//
// ⭐ 실제 수면 기록/자동 추정("C번 요구사항", 수면기록_자동추정_설계.md 1장) 전용
// 데이터 모델. 근무 스케줄/알람 로직과 완전히 무관 - condition_* 코드에서만 쓰임.
//
// ⚠️ 근무시간과 겹치는 수면도 정상 데이터로 저장한다(설계 문서 2장) - 이 모델/DB
// 계층에는 그 어떤 겹침 validation도 없다. "근무 중 수면"인지 여부는 저장하지
// 않고 조회 시점에 sleep_shift_relation.dart가 매번 계산한다(근무 스케줄이 나중에
// 바뀌어도 분류가 자동으로 다시 맞게 계산되도록).

// ⭐ 2026-09-04 - widgetManual 추가. 예전엔 "위젯 🌙/☀️ 버튼으로 직접 기록"과
// "앱 다이얼로그에서 시각을 직접 입력/수정"이 둘 다 manual 하나로 묶여있었는데,
// 수면시간 표시를 10분 단위로 반올림할지(자동추정/위젯처럼 "시스템이 관측한"
// 시각) 아니면 그대로 분 단위까지 보여줄지(사용자가 다이얼로그에서 실제로 고른
// 시각)를 구분하려면 필요해서 분리함(fmtSleepDuration 참고). DB에는 새 컬럼 없이
// source 문자열 값만 하나 늘어난 것 - 마이그레이션 불필요.
// Kotlin(SleepWidgetActionReceiver.kt)의 위젯 버튼 흐름만 이 값을 쓰고, 앱
// 다이얼로그 경로(sleep_record_provider.dart)는 항상 기존처럼 manual로 씀.
enum SleepSource { manual, widgetManual, autoDetected }

enum SleepStatus { confirmed, pendingConfirmation }

enum SleepConfidence { low, medium, high }

/// 자동 감지 후보는 시작 후 이 시간이 지나면 LOW 신뢰도의 확인 대기 기록으로
/// 닫힌다. Native와 Dart가 같은 행 기반 기한을 사용하며 별도 prefs에는 저장하지 않는다.
const Duration maxAutoSleepCandidateDuration = Duration(hours: 9);

DateTime autoSleepCandidateDeadline(DateTime start) =>
    start.add(maxAutoSleepCandidateDuration);

DateTime cappedAutoSleepCandidateEnd(DateTime start, DateTime now) {
  final deadline = autoSleepCandidateDeadline(start);
  return now.isBefore(deadline) ? now : deadline;
}

bool isAutoSleepCandidateExpired(DateTime start, DateTime now) =>
    !now.isBefore(autoSleepCandidateDeadline(start));

/// Native 수면 writer와 같은 locale 독립 DB 형식. 화면 표시용 locale과 분리하고
/// 밀리초를 저장하지 않아 어느 경로에서 닫아도 같은 end_time 문자열이 된다.
String sleepDateTimeToDb(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)}T'
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String sleepSourceToDb(SleepSource s) {
  switch (s) {
    case SleepSource.autoDetected:
      return 'AUTO_DETECTED';
    case SleepSource.widgetManual:
      return 'WIDGET_MANUAL';
    case SleepSource.manual:
      return 'MANUAL';
  }
}

SleepSource sleepSourceFromDb(String s) {
  switch (s) {
    case 'AUTO_DETECTED':
      return SleepSource.autoDetected;
    case 'WIDGET_MANUAL':
      return SleepSource.widgetManual;
    default:
      return SleepSource.manual;
  }
}

String sleepStatusToDb(SleepStatus s) => s == SleepStatus.confirmed ? 'CONFIRMED' : 'PENDING_CONFIRMATION';

SleepStatus sleepStatusFromDb(String s) =>
    s == 'CONFIRMED' ? SleepStatus.confirmed : SleepStatus.pendingConfirmation;

String? sleepConfidenceToDb(SleepConfidence? c) {
  if (c == null) return null;
  switch (c) {
    case SleepConfidence.low:
      return 'LOW';
    case SleepConfidence.medium:
      return 'MEDIUM';
    case SleepConfidence.high:
      return 'HIGH';
  }
}

SleepConfidence? sleepConfidenceFromDb(String? c) {
  switch (c) {
    case 'LOW':
      return SleepConfidence.low;
    case 'MEDIUM':
      return SleepConfidence.medium;
    case 'HIGH':
      return SleepConfidence.high;
    default:
      return null;
  }
}

class SleepRecord {
  final int? id;
  final DateTime start;
  final DateTime? end; // null = 진행 중(수동 '수면 중' 또는 자동 감지 후보 진행 중)
  final SleepSource source;
  final SleepStatus status;
  final SleepConfidence? confidence; // autoDetected만 사용

  const SleepRecord({
    this.id,
    required this.start,
    this.end,
    required this.source,
    required this.status,
    this.confidence,
  });

  bool get isOngoing => end == null;

  /// 실제 수면시간(분). 진행 중이면 null.
  int? get durationMinutes => end?.difference(start).inMinutes;

  SleepRecord copyWith({
    int? id,
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
    SleepSource? source,
    SleepStatus? status,
    SleepConfidence? confidence,
  }) {
    return SleepRecord(
      id: id ?? this.id,
      start: start ?? this.start,
      end: clearEnd ? null : (end ?? this.end),
      source: source ?? this.source,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
    );
  }

  factory SleepRecord.fromMap(Map<String, dynamic> map) => SleepRecord(
        id: map['id'] as int?,
        start: DateTime.parse(map['start_time'] as String),
        end: map['end_time'] != null ? DateTime.parse(map['end_time'] as String) : null,
        source: sleepSourceFromDb(map['source'] as String),
        status: sleepStatusFromDb(map['status'] as String),
        confidence: sleepConfidenceFromDb(map['confidence'] as String?),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'start_time': sleepDateTimeToDb(start),
        'end_time': end == null ? null : sleepDateTimeToDb(end!),
        'source': sleepSourceToDb(source),
        'status': sleepStatusToDb(status),
        'confidence': sleepConfidenceToDb(confidence),
      };
}
