import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';
import 'package:shiftbell/services/ad_consent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('debug geography requires explicit dev gate and registered test devices', () {
    for (final region in ['eea', 'regulated_us', 'other']) {
      expect(AdConsentService.debugSettingsFor(enabled: false,
          geography: region, testDeviceIds: 'hashed-id'), isNull);
      expect(AdConsentService.debugSettingsFor(enabled: true,
          geography: region, testDeviceIds: ' , '), isNull);
    }
    expect(AdConsentService.debugSettingsFor(enabled: true,
        geography: 'disabled', testDeviceIds: 'id'), isNull);
    final debug = AdConsentService.debugSettingsFor(enabled: true,
        geography: 'eea', testDeviceIds: ' A, B,A ');
    expect(debug!.testIdentifiers, ['A', 'B']);
    expect(debug.debugGeography, DebugGeography.debugGeographyEea);
  });

  test('late privacy requirement updates, errors preserve entry and concurrent forms share work', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channel = MethodChannel('plugins.flutter.io/google_mobile_ads/ump',
        StandardMethodCodec(UserMessagingCodec()));
    var required = false;
    var fail = false;
    var forms = 0;
    var notifications = 0;
    final formClosed = Completer<void>();
    void listener() => notifications++;
    AdConsentService.privacyOptionsRequired.addListener(listener);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ConsentInformation#getPrivacyOptionsRequirementStatus') {
        if (fail) throw PlatformException(code: 'unavailable');
        return required ? 1 : 0;
      }
      if (call.method == 'UserMessagingPlatform#showPrivacyOptionsForm') {
        forms++;
        await formClosed.future;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      AdConsentService.privacyOptionsRequired.removeListener(listener);
    });
    expect(await AdConsentService.isPrivacyOptionsRequired(), isFalse);
    required = true;
    expect(await AdConsentService.isPrivacyOptionsRequired(), isTrue);
    expect(notifications, 1);
    fail = true;
    expect(await AdConsentService.isPrivacyOptionsRequired(), isTrue);
    fail = false;
    final revision = AdConsentService.adRequestRevision.value;
    final one = AdConsentService.showPrivacyOptionsForm();
    final two = AdConsentService.showPrivacyOptionsForm();
    expect(identical(one, two), isTrue);
    formClosed.complete();
    await Future.wait([one, two]);
    expect(forms, 1);
    expect(AdConsentService.adRequestRevision.value, revision + 1);
    await AdConsentService.showPrivacyOptionsForm();
    expect(forms, 2);
  });
}
