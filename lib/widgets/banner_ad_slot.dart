// lib/widgets/banner_ad_slot.dart
//
// ⭐ 2026-08-24 추가 - 배너 광고가 들어갈 자리.
//
// 이 위젯의 계약(이 두 가지는 앞으로도 반드시 지켜야 함):
//
// 1) **항상 정확히 같은 높이를 차지한다.** 광고 로드 성공/실패/로딩중/미표시와 무관하게
//    AdService.bannerHeight 그대로. 광고가 없다고 높이가 0이 되면 달력이 위아래로
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

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ad_config.dart';
import '../services/ad_service.dart';

class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final size = AdService.bannerAdSize;

    // 높이 계산에 실패했거나 SDK 초기화가 안 됐으면 광고를 만들지 않음.
    // 자리(높이)는 아래 build에서 fallback 높이로 이미 확보되므로 레이아웃엔 영향 없음.
    if (size == null || !AdService.isInitialized) {
      debugPrint('⏭️ 배너 광고 생략(크기 미확정 또는 SDK 미초기화) - 자리만 확보함');
      return;
    }

    final ad = BannerAd(
      size: size,
      adUnitId: kBannerAdUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('⚠️ 배너 광고 로드 실패(자리는 그대로 유지됨): $error');
          ad.dispose();
          if (!mounted) return;
          setState(() => _isLoaded = false);
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = AdService.bannerHeight;

    return SizedBox(
      // ⭐ 이 높이가 이 위젯의 전부. 아래 내용물이 무엇이든 이 값은 안 변함.
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
          if (_isLoaded && _bannerAd != null)
            Center(
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
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
  }
}
