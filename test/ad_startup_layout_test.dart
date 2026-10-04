import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';
import 'package:shiftbell/services/ad_service.dart';
import 'package:shiftbell/widgets/banner_ad_slot.dart';

void main() {
  testWidgets(
      'delayed consent never blocks geometry; late initialization loads current slot',
      (tester) async {
    final consent = Completer<void>();
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final ump = MethodChannel('plugins.flutter.io/google_mobile_ads/ump',
        StandardMethodCodec(UserMessagingCodec()));
    messenger.setMockMethodCallHandler(ump, (call) async {
      if (call.method == 'ConsentInformation#requestConsentInfoUpdate') {
        await consent.future;
        throw PlatformException(
            code: '1', message: 'simulated network failure');
      }
      if (call.method == 'ConsentInformation#canRequestAds') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(instanceManager.channel, (call) async {
      calls.add(call);
      if (call.method == 'AdSize#getAnchoredAdaptiveBannerAdSize') {
        return (call.arguments['width'] as int) > 500 ? 90 : 56;
      }
      if (call.method == 'MobileAds#initialize')
        return InitializationStatus({});
      return null;
    });
    tester.view.physicalSize = const Size(752, 835);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final warmUp = AdService.warmUp();
    expect(identical(warmUp, AdService.warmUp()), isTrue);
    await tester.runAsync(AdService.prepareLayout);
    expect(AdService.bannerHeight, 90);
    expect(AdService.isInitialized, isFalse);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Text('달력 사용 가능'), bottomNavigationBar: BannerAdSlot())));
    await tester.pump(const Duration(seconds: 12));
    expect(find.text('달력 사용 가능'), findsOneWidget);
    expect(calls.where((c) => c.method == 'loadBannerAd'), isEmpty);
    tester.view.physicalSize = const Size(360, 840);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    consent.complete();
    await tester.runAsync(() => warmUp);
    await tester.pump();
    final requests = calls.where((c) => c.method == 'loadBannerAd').toList();
    expect(requests, hasLength(1),
        reason: 'Obsolete unfolded request must not load');
    expect((requests.single.arguments['size'] as AdSize).width, 360);
    expect(tester.getSize(find.byType(BannerAdSlot)).height, 56);
    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(ump, null);
    messenger.setMockMethodCallHandler(instanceManager.channel, null);
  });
}
