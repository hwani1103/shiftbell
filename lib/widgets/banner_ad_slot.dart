// lib/widgets/banner_ad_slot.dart
//
// ⭐ 2026-08-24 추가 - 배너 광고가 들어갈 자리.
//
// 이 위젯의 계약(이 두 가지는 앞으로도 반드시 지켜야 함):
//
// 1) **같은 창 크기에서는 높이를 유지한다.** 광고 로드 성공/실패/로딩중/미표시와 무관하다.
//    접힘·펼침으로 슬롯 폭이 바뀔 때만 SDK의 새 크기를 반영한다. 광고가 없다고 높이가 0이 되면 달력이 위아래로
//    튀는데, 그걸 막는 게 이 위젯의 존재 이유임.
//
// 2) **한 번 만들어지면 탭을 옮겨도 파괴되지 않는다.** main.dart에서 이 위젯을
//    BottomNavigationBar 위(=탭 화면 바깥)에 두고 Visibility로 보이기/숨기기만
//    전환함. 달력 탭 안에 넣으면 안 됨 - main.dart의 body는 IndexedStack이 아니라
//    `_tabs[_currentIndex]` 하나만 트리에 올리는 구조라, 탭을 옮길 때마다 이 위젯이
//    dispose되고 돌아올 때마다 BannerAd와 안드로이드 플랫폼 뷰가 새로 생성됨
//    (= 탭 전환마다 버벅임 + 광고 재요청 폭주).
//
// 현재는 kAdSlotDebugTint가 true라 광고 영역이 색과 테두리로 보임. 이건 확보된 높이
// "안에" 그려지므로 켜고 꺼도 레이아웃은 완전히 동일함 - 즉 지금 이 색 영역을 기준으로
// 달력 크기를 잡아두면, 나중에 실제 광고를 켰을 때 그대로 맞음.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ad_config.dart';
import '../services/ad_consent_service.dart';
import '../services/ad_service.dart';

class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  double _height = AdService.bannerHeight;
  int _generation = 0;
  int? _width;
  Orientation? _orientation;
  Timer? _resizeTimer;

  @override
  void initState() {
    super.initState();
    AdConsentService.adRequestRevision.addListener(_onConsentChanged);
  }

  void _onConsentChanged() {
    if (!mounted) return;
    final generation = ++_generation;
    _resizeTimer?.cancel();
    final width = _width;
    final orientation = _orientation;
    if (width != null && orientation != null) {
      // Remove the old ad immediately and query UMP even at the same size.
      // _loadAd preserves the measured slot height and rejects stale requests.
      unawaited(_loadAd(width, orientation, generation));
    }
  }

  void _scheduleSize(int width, Orientation orientation) {
    if (_width == width && _orientation == orientation) return;
    _width = width;
    _orientation = orientation;
    final generation = ++_generation;
    _resizeTimer?.cancel();
    // Wait until fold animation settles; don't request an ad per animation frame.
    _resizeTimer = Timer(const Duration(milliseconds: 200),
        () => _loadAd(width, orientation, generation));
  }

  Future<void> _loadAd(int width, Orientation orientation, int generation) async {
    if (!mounted || generation != _generation) return;
    final old = _bannerAd;
    setState(() { _bannerAd = null; _isLoaded = false; });
    await old?.dispose();
    final size = await AdService.sizeForSlot(width, orientation);
    if (!mounted || generation != _generation) return;
    if (size != null) setState(() => _height = size.height.toDouble());

    // 높이 계산에 실패했거나 SDK 초기화가 안 됐으면 광고를 만들지 않음.
    // 자리(높이)는 아래 build에서 fallback 높이로 이미 확보되므로 레이아웃엔 영향 없음.
    // ⭐ 2026-09-14 (G5 #6) - 운영(prod release) 빌드인데 실제 광고 ID가 주입되지 않았으면 요청하지 않음(테스트 ID 운영 노출 방지)
    if (kBannerAdUnitId.isEmpty) {
      debugPrint('⏭️ 배너 광고 생략(운영 광고 ID 미설정) - 자리만 확보함');
      return;
    }
    // Wait here, outside the app startup gate. A late SDK/consent response must
    // still load the ad; fold/resize/dispose invalidates obsolete requests.
    await AdService.warmUp();
    if (!mounted || generation != _generation) return;
    if (size == null || !AdService.isInitialized) {
      debugPrint('⏭️ 배너 광고 생략(크기 미확정 또는 SDK 미초기화) - 자리만 확보함');
      return;
    }
    // ⭐ 2026-09-22 - EEA/영국/스위스 등 UMP 동의가 필요한 사용자에게 동의 전
    // 광고를 요청하지 않음(ad_consent_service.dart). 위 warmUp 완료 후에만
    // 동의 상태를 읽고 광고를 요청한다.
    // 한국 등 동의가 애초에 불필요한 지역은 이 값이 거의 즉시 true라 체감 지연 없음.
    final allowed = await AdConsentService.canRequestAds();
    if (!allowed) {
      debugPrint('⏭️ 배너 광고 생략(광고 동의 미확보) - 자리만 확보함');
      return;
    }
    if (!mounted || generation != _generation) return;

    final ad = BannerAd(
      size: size,
      adUnitId: kBannerAdUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted || generation != _generation) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('⚠️ 배너 광고 로드 실패(자리는 그대로 유지됨): $error');
          ad.dispose();
          if (!mounted || generation != _generation) return;
          setState(() { _bannerAd = null; _isLoaded = false; });
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    AdConsentService.adRequestRevision.removeListener(_onConsentChanged);
    ++_generation;
    _resizeTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
    final height = _height;
    final orientation = MediaQuery.orientationOf(context);
    _scheduleSize(constraints.maxWidth.floor(), orientation);
    return SizedBox(
      // 로드 상태로 높이를 바꾸지 않는다. 창 크기에 따른 측정값만 반영한다.
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1) 광고 영역 표시용 배경 (출시 전 kAdSlotDebugTint = false로 끄면 사라짐)
          if (kAdSlotDebugTint)
            ColoredBox(
              color: kAdSlotDebugFill,
              child: Center(
                child: Text(
                  '광고 영역 ${height.toStringAsFixed(0)}dp',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kAdSlotDebugBorder,
                  ),
                ),
              ),
            ),

          // 2) 실제 광고. 로드된 뒤에만 올림 - 로드 전/실패 시엔 위 배경만 보임.
          //    ⭐ 2026-09-15 (AUD-07) - 슬롯보다 넓은 광고는 잘린 채 보이지 않게 아예 표시하지 않음
          //    (실행 중 접기·멀티윈도우로 폭이 줄어든 경우 - 자리 높이는 그대로)
          if (_isLoaded && _bannerAd != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final ad = _bannerAd!;
                if (ad.size.width > constraints.maxWidth) return const SizedBox.shrink();
                return Center(
                  child: SizedBox(
                    width: ad.size.width.toDouble(),
                    height: ad.size.height.toDouble(),
                    child: AdWidget(ad: ad),
                  ),
                );
              },
            ),

          // 3) 영역 경계선. IgnorePointer + 위에 겹쳐 그리기라 높이에 영향 없음.
          if (kAdSlotDebugTint)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: kAdSlotDebugBorder, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
    });
  }
}
