// lib/constants/ad_config.dart
//
// ⭐ 2026-08-24 추가 - AdMob 배너 광고 설정을 한 곳에 모음. 광고가 차지할 높이를 미리 확보해
// 실제 광고를 켜도 레이아웃이 움직이지 않게 함.
//
// ⭐ 2026-09-14 (출시전 감사 G5 #6, D2) - dev/prod·debug/release를 코드가 구분하도록 바꿈. 손으로 3군데를 바꾸던 방식은
// 테스트 ID·파란 틴트가 운영 빌드에 그대로 나가는 사고(L01)를 만들었음.
//  - 광고 단위 ID: **prod flavor + release 빌드**에서만 실제 ID를 쓰고, 그 값은 소스에 적지 않고 빌드 명령으로 주입:
//      flutter build appbundle --release --flavor prod --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXX/YYYY
//    주입하지 않은 prod release는 광고 요청 자체를 하지 않음(자리만 유지) - 테스트 ID가 운영에 나가지 않게.
//    dev flavor와 모든 debug/profile 빌드는 항상 구글 공개 테스트 ID.
//  - AdMob 앱 ID(Manifest meta-data): android/app/build.gradle.kts의 manifestPlaceholders["admobAppId"].
//    prod는 Gradle 속성 ADMOB_APP_ID(예: ~/.gradle/gradle.properties 또는 -PADMOB_APP_ID=...)로 주입, 없으면 테스트 앱 ID.
//    dev는 항상 테스트 앱 ID.
//  - 광고 영역 틴트: debug 빌드에서만 표시.
//
// ⚠️ 개발 중에 본인의 실제 광고 ID를 쓰면 절대 안 됨(무효 트래픽으로 AdMob 계정 정지 위험). 실제 ID 주입은 D2대로
// 최종 배포 빌드 직전에만.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;

/// 구글이 공개한 **테스트 전용** 배너 광고 단위 ID (Android).
/// https://developers.google.com/admob/android/test-ads
const String kBannerAdUnitIdTest = 'ca-app-pub-3940256099942544/6300978111';

/// 구글이 공개한 **테스트 전용** 앱 ID. Gradle manifestPlaceholders 기본값과 같은 값.
/// (APPLICATION_ID meta-data가 없으면 AdMob SDK가 앱 시작 시점에 의도적으로 크래시시킴)
const String kAdMobAppIdTest = 'ca-app-pub-3940256099942544~3347511713';

/// 운영 배너 광고 단위 ID - 빌드 시 `--dart-define=ADMOB_BANNER_ID=...`로만 주입(소스에 실제 ID를 두지 않음).
const String _kBannerAdUnitIdRelease = String.fromEnvironment('ADMOB_BANNER_ID');

/// 지금 빌드가 실제 광고를 써야 하는 운영 빌드인지(prod flavor + release).
bool get isProductionAdBuild => kReleaseMode && appFlavor == 'prod';

/// 실제로 사용할 배너 광고 단위 ID. 빈 문자열이면 광고를 요청하지 않음(운영 빌드인데 실제 ID가 주입되지 않은 경우).
String get kBannerAdUnitId => isProductionAdBuild ? _kBannerAdUnitIdRelease : kBannerAdUnitIdTest;

/// 광고 영역을 눈에 보이게 색으로 표시할지 여부 - debug 빌드에서만.
///
/// ⭐ 이 값을 켜고 끄는 것은 **높이에 전혀 영향을 주지 않음.** 색과 테두리는 확보된 높이 "안에" 그려짐.
const bool kAdSlotDebugTint = kDebugMode;

/// 적응형 배너 높이 계산에 실패했을 때 쓸 대체 높이(dp) - 표준 고정 배너(320×50)의 높이.
const double kBannerAdFallbackHeight = 50.0;

/// 광고 영역 배경색 (kAdSlotDebugTint가 true일 때만 보임).
const Color kAdSlotDebugFill = Color(0x332962FF);

/// 광고 영역 테두리색 (kAdSlotDebugTint가 true일 때만 보임).
const Color kAdSlotDebugBorder = Color(0x882962FF);
