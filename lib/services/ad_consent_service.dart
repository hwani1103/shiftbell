// lib/services/ad_consent_service.dart
//
// ⭐ 2026-09-22 - Google UMP(User Messaging Platform) 동의 수집. EEA(유럽경제지역)·
// 영국·스위스 사용자에게 개인정보 보호법(GDPR 등)상 필수인 광고 동의 흐름을
// google_mobile_ads 패키지에 내장된 UMP API로 구현.
//
// ⚠️ 한국 등 그 외 지역 사용자에게는 이 서비스가 사실상 아무 일도 안 함 -
// requestConsentInfoUpdate가 Google 서버에 물어봐서 지역을 판정하고(IP 기반,
// 이 앱이 직접 국가를 검사하지 않음), EEA/영국/스위스가 아니면 즉시
// ConsentStatus.notRequired로 응답되어 폼 자체가 로드/표시되지 않는다. 즉
// "한국 배포판에 영향 없이"는 코드로 국가를 분기해서가 아니라 UMP 설계 자체가
// 그렇게 되어 있음(Google의 지역 판정을 그대로 신뢰).
//
// AdMob 콘솔의 "Privacy & messaging"에서 EEA/영국/스위스용 메시지를 만들어야
// 실제로 폼이 뜬다(이 코드만으로는 메시지 내용이 없어 아무 일도 안 일어남) -
// 콘솔 설정은 사용자가 직접 할 일.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConsentService {
  AdConsentService._();

  static bool _gathered = false;

  /// 앱 시작 시 한 번(AdService.warmUp) 호출. 광고를 요청하기 전에 반드시
  /// 먼저 끝나야 함(EEA/영국/스위스 사용자에게 동의 없이 광고를 요청하면 안 됨).
  ///
  /// ⭐ 실패/타임아웃이어도 예외를 던지지 않음 - 광고는 부가 기능이고, 실패하면
  /// canRequestAds()가 그동안 캐시된 상태(또는 false)를 그대로 돌려주므로
  /// BannerAdSlot이 "광고 없이 자리만" 표시하는 기존 fallback으로 자연히 이어짐.
  static Future<void> gatherConsent() async {
    if (_gathered) return;
    final completer = Completer<void>();

    void finish() {
      _gathered = true;
      if (!completer.isCompleted) completer.complete();
    }

    try {
      final params = ConsentRequestParameters(
        // ⭐ debug 빌드에서만 강제로 EEA인 것처럼 - 개발 중 동의 폼을 직접 눈으로
        // 확인하기 위함. release 빌드에는 이 설정 자체가 안 들어가므로 실사용자
        // 지역 판정에는 전혀 영향 없음. 실기기로 테스트하려면 UMP가 로그에
        // 찍어주는 이 기기의 testIdentifiers 해시값을 여기 추가할 것
        // (콘솔 로그 "Use new ConsentDebugSettings.Builder().addTestDeviceHashedId(...)" 참고).
        consentDebugSettings:
            kDebugMode ? ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea) : null,
      );

      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
              if (error != null) {
                debugPrint('⚠️ 광고 동의 폼 표시 실패: ${error.message}');
              }
            });
          } catch (e) {
            debugPrint('⚠️ 광고 동의 폼 로드 실패: $e');
          }
          finish();
        },
        (FormError error) {
          debugPrint('⚠️ 광고 동의 정보 갱신 실패: ${error.message}');
          finish();
        },
      );
    } catch (e) {
      debugPrint('⚠️ 광고 동의 수집 시작 실패: $e');
      finish();
    }

    return completer.future;
  }

  /// 지금 광고를 요청해도 되는지(UMP가 필요하다고 판단한 동의를 이미 받았거나,
  /// 애초에 이 사용자에게는 필요 없는 경우 true). 한국 사용자는 사실상 항상 true.
  static Future<bool> canRequestAds() {
    return ConsentInformation.instance.canRequestAds().catchError((_) => false);
  }

  /// 설정 화면에 "광고 개인정보 설정" 진입점을 보여줄지 - EEA/영국/스위스처럼
  /// 동의를 받은 사용자에게만 true(다시 보거나 철회할 수 있어야 하므로). 그 외
  /// 지역(한국 포함)은 항상 false라 그 진입점 자체가 안 보임.
  static Future<bool> isPrivacyOptionsRequired() async {
    try {
      final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// 설정 화면의 "광고 개인정보 설정" 버튼이 부르는 함수 - 이미 본 동의 폼을
  /// 다시 열어 선택을 바꾸거나 철회할 수 있게 함.
  static Future<void> showPrivacyOptionsForm() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) debugPrint('⚠️ 광고 개인정보 설정 폼 오류: ${error.message}');
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }
}
