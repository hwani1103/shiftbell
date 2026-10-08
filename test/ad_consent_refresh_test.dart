import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';
import 'package:shiftbell/services/ad_consent_service.dart';
import 'package:shiftbell/widgets/banner_ad_slot.dart';

void main() {
  testWidgets('privacy choices dispose the old banner and recheck a fixed-size slot',
      (tester) async {
    final calls = <MethodCall>[];
    var allowed = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final ump = MethodChannel('plugins.flutter.io/google_mobile_ads/ump',
        StandardMethodCodec(UserMessagingCodec()));
    messenger.setMockMethodCallHandler(ump, (call) async {
      if (call.method == 'ConsentInformation#canRequestAds') return allowed;
      if (call.method ==
          'ConsentInformation#getPrivacyOptionsRequirementStatus') {
        return 1;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(instanceManager.channel, (call) async {
      calls.add(call);
      if (call.method == 'AdSize#getAnchoredAdaptiveBannerAdSize') return 56;
      if (call.method == 'MobileAds#initialize') return InitializationStatus({});
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(ump, null);
      messenger.setMockMethodCallHandler(instanceManager.channel, null);
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('calendar'), bottomNavigationBar: BannerAdSlot()),
    ));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
    final height = tester.getSize(find.byType(BannerAdSlot)).height;

    allowed = false;
    await AdConsentService.showPrivacyOptionsForm();
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'disposeAd'), hasLength(1),
        reason: 'The ad requested under the previous choices must be removed');
    expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
    expect(tester.getSize(find.byType(BannerAdSlot)).height, height);

    allowed = true;
    await AdConsentService.showPrivacyOptionsForm();
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(2));
    expect(calls.where((c) => c.method == 'MobileAds#initialize'), hasLength(1));
    // Changed choices can still permit ads; the old request must be replaced.
    await AdConsentService.showPrivacyOptionsForm();
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(3));
    expect(calls.where((c) => c.method == 'disposeAd'), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
