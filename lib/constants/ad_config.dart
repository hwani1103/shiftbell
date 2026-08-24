// lib/constants/ad_config.dart
//
// ⭐ 2026-08-24 추가 - AdMob 배너 광고 설정을 한 곳에 모음.
//
// 아직 실제 광고를 붙이는 단계가 아님. 이 시점에 미리 넣어두는 이유는 "나중에 광고를
// 넣었을 때 세로 길이가 바뀌어서 달력 레이아웃이 깨지는 것"을 막기 위함 - 지금부터
// 광고가 차지할 정확한 높이를 확보해두고, 그 아래에서 UI 작업을 하면 나중에 실제
// 광고를 켜도 레이아웃이 1px도 안 움직임.
//
// ⚠️ 실제 배포 전 반드시 할 것 (아래 두 상수 + 매니페스트 1곳, 총 3군데):
//   1) kBannerAdUnitId → 본인 AdMob 광고 단위 ID
//   2) kAdSlotDebugTint → false (광고 영역 색 표시 끄기)
//   3) android/app/src/main/AndroidManifest.xml의
//      com.google.android.gms.ads.APPLICATION_ID meta-data → 본인 앱 ID
//
// ⚠️ 개발 중에 본인의 실제 광고 ID를 쓰면 절대 안 됨. 자기 광고에 노출/클릭이 쌓이면
// 무효 트래픽으로 판정되어 AdMob 계정이 정지될 수 있음. 출시 직전에만 교체할 것.

import 'package:flutter/material.dart';

/// 구글이 공개한 **테스트 전용** 배너 광고 단위 ID (Android).
/// 계정 없이 누구나 쓸 수 있고, 실제 광고와 똑같은 크기의 테스트 배너가 표시됨.
/// https://developers.google.com/admob/android/test-ads
const String kBannerAdUnitIdTest = 'ca-app-pub-3940256099942544/6300978111';

/// 구글이 공개한 **테스트 전용** 앱 ID. AndroidManifest의
/// `com.google.android.gms.ads.APPLICATION_ID` meta-data에 들어가 있음.
/// (이 meta-data가 없으면 AdMob SDK가 앱 시작 시점에 의도적으로 크래시시킴)
const String kAdMobAppIdTest = 'ca-app-pub-3940256099942544~3347511713';

/// 실제로 사용할 배너 광고 단위 ID. **출시 전 본인 ID로 교체할 것.**
const String kBannerAdUnitId = kBannerAdUnitIdTest;

/// 광고 영역을 눈에 보이게 색으로 표시할지 여부.
///
/// UI 디자인 작업 중엔 true로 두면 "광고가 실제로 차지할 영역"이 색과 테두리로
/// 보여서 달력 크기를 그 영역에 맞춰 잡기 편함. **출시 전 false로 바꿀 것.**
///
/// ⭐ 중요: 이 값을 켜고 끄는 것은 **높이에 전혀 영향을 주지 않음.** 색과 테두리는
/// 확보된 높이 "안에" 그려지므로, true든 false든 레이아웃은 완전히 동일함.
const bool kAdSlotDebugTint = true;

/// 적응형 배너 높이 계산에 실패했을 때 쓸 대체 높이(dp).
///
/// 표준 고정 배너(320×50)의 높이. 적응형 배너 높이는 보통 이보다 크거나 같으므로,
/// 계산 실패 시에도 최소한 이만큼은 확보해서 레이아웃이 무너지지 않게 함.
/// (계산이 실패하는 건 SDK 초기화 전이나 플랫폼 채널 오류 같은 드문 경우뿐)
const double kBannerAdFallbackHeight = 50.0;

/// 광고 영역 배경색 (kAdSlotDebugTint가 true일 때만 보임).
/// 달력 색상과 헷갈리지 않도록 채도가 낮은 회보라 계열을 씀.
const Color kAdSlotDebugFill = Color(0x332962FF);

/// 광고 영역 테두리색 (kAdSlotDebugTint가 true일 때만 보임).
const Color kAdSlotDebugBorder = Color(0x882962FF);
