// lib/services/ad_service.dart
//
// ⭐ 2026-08-24 추가 - AdMob 초기화와 "배너가 차지할 정확한 높이" 계산을 담당.
//
// 왜 높이를 미리 계산해서 캐시하나:
//
// 요즘 권장되는 배너는 옛날 320×50 고정 배너가 아니라 **앵커드 적응형 배너**로,
// 높이가 화면 폭에 따라 달라짐(대략 50~90dp). 그런데 이 높이는 "어떤 광고가
// 서빙되느냐"가 아니라 **"어떤 크기를 요청했느냐"** 로 결정됨 - 즉 광고를 한 번도
// 로드하지 않아도 SDK에 물어보면 미리 알 수 있고, 나중에 실제 광고가 뜰 때도 정확히
// 그 높이를 차지함. 그래서 지금 광고를 안 띄우더라도 이 값만큼 자리를 비워두면
// 나중에 실제 광고를 켤 때 레이아웃이 전혀 안 움직임.
//
// 왜 앱 시작 시점에 미리 계산하나:
//
// 이 계산은 플랫폼 채널을 타는 비동기 호출이라, 화면을 그리는 중에 하면 "높이를
// 모르는 첫 프레임 → 높이를 아는 다음 프레임"으로 한 번 튐. 그 튐 자체가 여기서
// 막으려는 현상이므로, 앱이 첫 화면을 그리기 전에 미리 구해서 캐시해둠.
//
// 이 앱은 세로 모드 전용(AndroidManifest에서 MainActivity가 portrait 고정)이라
// 화면 폭이 실행 중에 바뀌지 않고, 따라서 이 값도 한 번 구하면 계속 유효함.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ad_config.dart';

class AdService {
  AdService._();

  static double? _bannerHeight;
  static AdSize? _bannerAdSize;
  static bool _initialized = false;

  /// 배너가 차지할 높이(dp). [warmUp]이 끝나기 전이거나 계산에 실패했으면
  /// [kBannerAdFallbackHeight]를 돌려줌 - null을 절대 반환하지 않으므로 호출부에서
  /// "높이를 모르는 상태"를 따로 처리할 필요가 없음(=레이아웃이 비는 순간이 없음).
  static double get bannerHeight => _bannerHeight ?? kBannerAdFallbackHeight;

  /// 실제 배너를 만들 때 쓸 AdSize. [warmUp] 실패 시 null이면 배너를 만들지 않고
  /// 자리만 확보함(높이는 위 [bannerHeight]로 이미 확보되어 있음).
  static AdSize? get bannerAdSize => _bannerAdSize;

  static bool get isInitialized => _initialized;

  /// 앱 시작 시 한 번 호출. SDK를 초기화하고 배너 높이를 미리 계산해 캐시함.
  ///
  /// ⭐ 실패해도 절대 예외를 밖으로 던지지 않음. 광고는 이 앱의 부가 기능이고,
  /// 알람이 핵심이므로 - 광고 초기화가 실패했다고 앱 시작이 막히면 훨씬 나쁨.
  /// (DatabaseHelper.onDiskVersion()의 fail-open 판단과 같은 이유)
  static Future<void> warmUp() async {
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('⚠️ AdMob 초기화 실패 - 광고 없이 계속 진행: $e');
      // 초기화가 실패해도 높이 계산은 시도해봄(실패하면 fallback으로 감).
    }

    try {
      // MediaQuery는 아직 위젯 트리가 없어서 못 씀 - 플랫폼에서 직접 논리 픽셀 폭을
      // 구함. 세로 고정이라 이 값은 실행 중에 바뀌지 않음.
      final view = ui.PlatformDispatcher.instance.implicitView;
      if (view == null) {
        debugPrint('⚠️ 화면 정보를 못 읽음 - 배너 높이 fallback 사용');
        return;
      }
      final widthDp = (view.physicalSize.width / view.devicePixelRatio).truncate();
      if (widthDp <= 0) {
        debugPrint('⚠️ 화면 폭이 0 이하 - 배너 높이 fallback 사용');
        return;
      }

      // ⭐ 2026-08-25 - google_mobile_ads 9.x로 복귀하면서 처음엔 비-deprecated
      // 대체 API(getLargeAnchoredAdaptiveBannerAdSizeWithOrientation)로 바꿨는데,
      // "Large"는 이름 그대로 실제로 더 큰(최대 화면 높이의 15%까지) 배너 슬롯을
      // 요청하는 별도 API였음 - 네이티브 채널 메서드명 자체가
      // "AdSize#getLargeAnchoredAdaptiveBannerAdSize"로 예전과 다름. 그 결과 확보되는
      // 자리(bannerHeight)만 커지고 실제 로드되는 테스트 배너 크리에이티브는 그대로라,
      // 광고 위아래로 빈 여백이 생기고 그만큼 달력 영역이 줄어드는 회귀가 생겼음
      // (사용자 확인). deprecated 표시는 있지만 네이티브 채널 메서드명이 예전
      // "AdSize#getAnchoredAdaptiveBannerAdSize"와 완전히 동일해서(패키지 소스로
      // 직접 확인) 예전과 정확히 같은(더 작은) 크기를 계산함 - 지금 이 앱엔 이 크기가
      // 맞으므로 의도적으로 deprecated API를 계속 씀. 세로 고정 앱이라 orientation은
      // 항상 portrait으로 고정해서 넘김.
      // ignore: deprecated_member_use
      final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
        Orientation.portrait,
        widthDp,
      );

      if (size == null) {
        debugPrint('⚠️ 적응형 배너 크기 계산 실패 - fallback($kBannerAdFallbackHeight) 사용');
        return;
      }

      _bannerAdSize = size;
      _bannerHeight = size.height.toDouble();
      debugPrint('✅ 배너 높이 확정: ${size.width}×${size.height} (화면 폭 ${widthDp}dp 기준)');
    } catch (e) {
      debugPrint('⚠️ 배너 높이 계산 실패 - fallback($kBannerAdFallbackHeight) 사용: $e');
    }
  }
}
