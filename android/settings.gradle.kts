pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    // ⭐ 2026-08-25 - 2.1.0 → 2.3.0으로 올림 (google_mobile_ads 최신판 9.x가 끌고
    // 오는 네이티브 play-services-ads가 이 버전의 metadata를 요구함). 자세한
    // 배경/절차는 코틀린_버전업_계획.md 참고.
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
    // ⭐ 2026-09-12 - Firebase Analytics 1단계(project_admin_analytics_plan
    // 메모리 참고). google-services.json을 읽어서 네이티브 Analytics SDK에
    // google_app_id를 심어줌 - 이게 없으면 SDK가 조용히 "Missing google_app_id"로
    // 자기 자신을 비활성화함(firebase_core만으로는 Auth/Firestore는 되지만
    // Analytics는 예외).
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
