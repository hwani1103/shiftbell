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
  testWidgets('SDK pending for a minute leaves app usable and disposed slot never loads late', (tester) async {
    final sdk = Completer<void>();
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final ump = MethodChannel('plugins.flutter.io/google_mobile_ads/ump', StandardMethodCodec(UserMessagingCodec()));
    messenger.setMockMethodCallHandler(ump, (call) async {
      if (call.method == 'ConsentInformation#requestConsentInfoUpdate') {
        throw PlatformException(code: '1', message: 'offline');
      }
      if (call.method == 'ConsentInformation#canRequestAds') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(instanceManager.channel, (call) async {
      calls.add(call);
      if (call.method == 'AdSize#getAnchoredAdaptiveBannerAdSize') return 56;
      if (call.method == 'MobileAds#initialize') {
        await sdk.future;
        return InitializationStatus({});
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(ump, null);
      messenger.setMockMethodCallHandler(instanceManager.channel, null);
    });
    var taps = 0;
    final warmUp = AdService.warmUp();
    await tester.runAsync(AdService.prepareLayout);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: TextButton(onPressed: () => taps++, child: const Text('calendar')),
      bottomNavigationBar: const BannerAdSlot(),
    )));
    await tester.pump(const Duration(minutes: 1));
    await tester.tap(find.text('calendar'));
    expect(taps, 1);
    expect(AdService.isInitialized, isFalse);
    expect(calls.where((c) => c.method == 'loadBannerAd'), isEmpty);
    expect(calls.where((c) => c.method == 'MobileAds#initialize'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    sdk.complete();
    await tester.runAsync(() => warmUp);
    await tester.pump();
    expect(AdService.isInitialized, isTrue);
    expect(calls.where((c) => c.method == 'loadBannerAd'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
