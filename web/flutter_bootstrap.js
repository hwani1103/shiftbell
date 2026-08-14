// web/flutter_bootstrap.js
//
// ⭐ 기본 자동생성 flutter_bootstrap.js는 `_flutter.loader.load({serviceWorkerSettings:
// {serviceWorkerVersion}})`만 호출하는데, 그렇게 하면 서비스워커가 실제로 등록되지
// 않는 걸 실기기+Chrome devtools로 직접 확인함(navigator.serviceWorker.getRegistrations()
// 계속 빈 배열, flutter_service_worker.js 네트워크 요청 자체가 안 일어남 - 수동으로
// register()는 정상 동작 확인했으니 브라우저 문제는 아님). Flutter 공식 문서가 권장하는
// "커스텀 onEntrypointLoaded + initializeEngine(config)" 명시적 패턴으로 바꿔서
// serviceWorkerSettings가 확실히 전달되게 함.
// {{flutter_service_worker_version}}은 flutter build가 실제 값으로 치환해주는 템플릿
// 토큰(이미 따옴표+주석까지 포함된 형태로 치환되므로 추가로 따옴표 감싸면 안 됨).
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      serviceWorkerSettings: {
        serviceWorkerVersion: {{flutter_service_worker_version}},
        serviceWorkerUrl: "flutter_service_worker.js?v=" + {{flutter_service_worker_version}},
      },
    });
    await appRunner.runApp();
  },
});
