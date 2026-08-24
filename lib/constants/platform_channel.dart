// lib/constants/platform_channel.dart
//
// ⭐ 2026-08-20 추가 - Flutter↔Native(Kotlin) MethodChannel 이름을 한 곳에 모음.
// 예전엔 'com.hwani1103.shiftbell/alarm' 리터럴 문자열이 Dart 쪽 12개 파일에 각자
// 따로 적혀 있었음(Kotlin 쪽은 MainActivity.kt 한 곳뿐이라 그쪽은 원래 안전함) - 이렇게
// 흩어져 있으면 오타 하나, 혹은 나중에 채널 이름을 바꿔야 할 때 한 곳이라도 빠뜨리면
// MissingPluginException으로 조용히 실패하는 지점이 파일 개수만큼 생김. 이 세션에서
// DB 버전(DatabaseHelper.kt)처럼 "여러 곳에 손으로 맞춰야 하는 값"이 반복적으로 어긋나는
// 문제를 겪은 김에, 같은 위험이 있는 이 값도 하나로 합침.
import 'package:flutter/services.dart';

const String kAlarmChannelName = 'com.hwani1103.shiftbell/alarm';

/// 공용 MethodChannel 인스턴스. `const MethodChannel(kAlarmChannelName)`도 동일하게
/// 동작하지만(MethodChannel은 이름만으로 동일시되는 값 타입), 매번 새로 안 만들고
/// 이 상수 하나를 재사용하면 되므로 이쪽을 기본으로 씀.
const MethodChannel kAlarmChannel = MethodChannel(kAlarmChannelName);
