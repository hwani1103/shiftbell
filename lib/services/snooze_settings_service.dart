import '../constants/platform_channel.dart';

class SnoozeSettingsService {
  static const backupKey = 'default_snooze_minutes';
  static const choices = [5, 10, 15];

  static Future<int> read() async {
    final value = await kAlarmChannel.invokeMethod<int>('getDefaultSnoozeMinutes');
    if (!choices.contains(value)) throw StateError('Invalid snooze default response');
    return value!;
  }

  static Future<int> save(int minutes) async {
    if (!choices.contains(minutes)) throw ArgumentError.value(minutes);
    final saved = await kAlarmChannel.invokeMethod<int>(
      'setDefaultSnoozeMinutes', {'minutes': minutes});
    if (saved != minutes) throw StateError('Snooze default was not saved');
    return saved!;
  }
}
