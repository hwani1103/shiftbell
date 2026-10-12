// UMP chooses the applicable published message; app language is not jurisdiction.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConsentService {
  AdConsentService._();

  static Future<void>? _gatherFuture;
  static Future<void>? _privacyFuture;
  static final _privacyRequired = ValueNotifier<bool>(false);
  static final _adRevision = ValueNotifier<int>(0);
  static int _privacyQuery = 0;

  static ValueListenable<bool> get privacyOptionsRequired => _privacyRequired;
  // Choices can change while canRequestAds remains true. Replace prior ads too.
  static ValueListenable<int> get adRequestRevision => _adRevision;

  /// One update per app process; concurrent callers share the same work.
  /// AdService invokes this outside the first-screen startup gate.
  static Future<void> gatherConsent() => _gatherFuture ??= _gatherConsent();

  static Future<void> _gatherConsent() async {
    try {
      final debugSettings = debugSettingsFor(
        enabled: kDebugMode && appFlavor == 'dev',
        geography: const String.fromEnvironment('UMP_DEBUG_GEOGRAPHY',
            defaultValue: 'disabled'),
        testDeviceIds: const String.fromEnvironment('UMP_TEST_DEVICE_IDS'),
      );
      // Explicit temporary test builds only. Normal builds preserve choices.
      if (debugSettings != null &&
          const bool.fromEnvironment('UMP_RESET_CONSENT')) {
        await ConsentInformation.instance.reset();
      }
      final update = Completer<bool>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(consentDebugSettings: debugSettings),
        () => update.complete(true),
        (error) {
          debugPrint('Consent information update failed: ${error.message}');
          update.complete(false);
        },
      );
      if (await update.future) {
        await isPrivacyOptionsRequired();
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('Consent form error: ${error.message}');
        });
      }
    } catch (error) {
      debugPrint('Consent gathering failed: $error');
    } finally {
      await isPrivacyOptionsRequired();
      _adRevision.value++;
    }
  }

  /// Query UMP even after errors. Its prior valid choices may still allow ads.
  /// This is not a statement that personalized advertising was accepted.
  static Future<bool> canRequestAds() =>
      ConsentInformation.instance.canRequestAds().catchError((_) => false);

  static Future<bool> isPrivacyOptionsRequired() async {
    final query = ++_privacyQuery;
    try {
      final status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      if (query == _privacyQuery &&
          status != PrivacyOptionsRequirementStatus.unknown) {
        _privacyRequired.value =
            status == PrivacyOptionsRequirementStatus.required;
      }
    } catch (_) {
      // A transient SDK error must not remove a previously required entry.
    }
    return _privacyRequired.value;
  }

  /// Repeated taps share the form already being presented.
  static Future<void> showPrivacyOptionsForm() =>
      _privacyFuture ??= _showPrivacyOptionsForm();

  static Future<void> _showPrivacyOptionsForm() async {
    try {
      // Avoid opening a second form during initial consent.
      await _gatherFuture;
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) debugPrint('Privacy options error: ${error.message}');
      });
    } catch (error) {
      debugPrint('Privacy options failed: $error');
    } finally {
      await isPrivacyOptionsRequired();
      _adRevision.value++;
      _privacyFuture = null;
    }
  }

  /// Opt-in test geography requires UMP hashed test-device IDs.
  /// The production call site hard-gates this with dev flavor AND kDebugMode.
  @visibleForTesting
  static ConsentDebugSettings? debugSettingsFor({
    required bool enabled,
    required String geography,
    required String testDeviceIds,
  }) {
    if (!enabled) return null;
    final ids = testDeviceIds.split(',').map((id) => id.trim())
        .where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return null;
    final region = switch (geography) {
      'eea' => DebugGeography.debugGeographyEea,
      'regulated_us' => DebugGeography.debugGeographyRegulatedUsState,
      'other' => DebugGeography.debugGeographyOther,
      _ => null,
    };
    return region == null ? null : ConsentDebugSettings(
      debugGeography: region, testIdentifiers: ids,
    );
  }
}
