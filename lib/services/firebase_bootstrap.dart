// lib/services/firebase_bootstrap.dart
//
// ⭐ Firebase 초기화를 한 곳에서 가드. firebase_options.dart가 아직 플레이스홀더 값이면
// (Firebase 콘솔 프로젝트를 아직 안 만든 상태) initializeApp이 실패하는데, 이 경우 예외를
// 조용히 삼키고 firebaseReady=false로 남겨서 앱의 나머지 기능(알람 등)은 평소대로 동작하게
// 함 - 친구공유의 Firestore 기능만 "동기화 실패"로 조용히 no-op됨 (friend_sync_service.dart
// 참고). main.dart/web_main.dart 둘 다 runApp() 전에 이걸 호출함.
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

bool firebaseReady = false;

Future<void> initFirebase() async {
  // ⭐ 2026-08-14: Firebase Hosting(실 네트워크 지연) 환경에서만 재현된 레이스 컨디션 -
  // Firebase.initializeApp()이 웹 플랫폼 채널(FirebaseCoreHostApi)이 아직 등록되기 전에
  // 호출되면 "channel-error"로 실패함. localhost(지연 거의 0)에서는 항상 성공하고 실 배포
  // 도메인(실 네트워크 왕복 지연)에서만 실패하는 걸로 재현 확인함 - 엔진 부트스트랩의
  // registerPlugins/runApp 순서 보장이 느린 네트워크에서 깨지는 것으로 추정(정확한 상위
  // 원인은 FlutterFire/엔진 쪽이라 우리 코드로 못 고침). 짧은 재시도로 우회.
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      firebaseReady = true;
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
