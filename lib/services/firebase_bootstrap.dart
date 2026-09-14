// lib/services/firebase_bootstrap.dart
//
// ⭐ Firebase 초기화를 한 곳에서 가드. firebase_options.dart가 아직 플레이스홀더 값이면
// (Firebase 콘솔 프로젝트를 아직 안 만든 상태) initializeApp이 실패하는데, 이 경우 예외를
// 조용히 삼키고 firebaseReady=false로 남겨서 앱의 나머지 기능(알람 등)은 평소대로 동작하게
// 함 - 친구공유의 Firestore 기능만 "동기화 실패"로 조용히 no-op됨 (friend_sync_service.dart
// 참고). main.dart/web_main.dart 둘 다 runApp() 전에 이걸 호출함.
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show appFlavor;
import '../firebase_options.dart';

bool firebaseReady = false;

// ⭐ 2026-09-12 - "교대시계 관리자" 1단계(project_admin_analytics_plan 메모리 참고).
// 커스텀 이벤트 없이 자동 수집 이벤트(session_start/first_open/screen_view 등)만으로
// DAU/MAU를 보는 게 목표라 Dart 쪽에서 할 일은 사실 거의 없음(네이티브 SDK가 앱
// 시작과 동시에 자동 수집을 시작함) - 그래도 플러그인 MethodChannel이 확실히
// 붙도록 인스턴스를 한 번 만들어두고, 수집이 꺼져있을 가능성(예: 이전에 opt-out
// 설정이 있었던 경우) 없이 항상 켜져 있게 명시적으로 보장함.
FirebaseAnalytics? analytics;

Future<void> initFirebase() async {
  // ⭐ 2026-08-14: Firebase Hosting(실 네트워크 지연) 환경에서만 재현된 레이스 컨디션 -
  // Firebase.initializeApp()이 웹 플랫폼 채널(FirebaseCoreHostApi)이 아직 등록되기 전에
  // 호출되면 "channel-error"로 실패함. localhost(지연 거의 0)에서는 항상 성공하고 실 배포
  // 도메인(실 네트워크 왕복 지연)에서만 실패하는 걸로 재현 확인함 - 엔진 부트스트랩의
  // registerPlugins/runApp 순서 보장이 느린 네트워크에서 깨지는 것으로 추정(정확한 상위
  // 원인은 FlutterFire/엔진 쪽이라 우리 코드로 못 고침). 짧은 재시도로 우회.
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      // ⭐ 2026-09-14 (출시전 감사 #29, D8) - dev flavor는 google-services.json에 등록된 dev 앱 ID로 초기화하고
      // Analytics 수집을 끔 → 테스트 설치가 운영 앱의 DAU/MAU·이벤트 통계에 섞이지 않음.
      // Firebase 프로젝트 자체는 prod와 같음(분리하려면 Console 작업이 필요해 이번 출시 범위 밖) - dev 친구공유 테스트는
      // 같은 Firestore에 문서를 씀.
      final isDevFlavor = !kIsWeb && appFlavor == 'dev';
      await Firebase.initializeApp(
        options: isDevFlavor ? DefaultFirebaseOptions.androidDev : DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
      analytics = FirebaseAnalytics.instance;
      await analytics!.setAnalyticsCollectionEnabled(!isDevFlavor);
      print('✅ Firebase 초기화 완료 (시도 $attempt번째)');
      return;
    } catch (e) {
      if (attempt == 3) {
        firebaseReady = false;
        print('⚠️ Firebase 초기화 실패 - 친구공유(Firestore) 기능만 비활성화됨: $e');
        return;
      }
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }
  }
}
