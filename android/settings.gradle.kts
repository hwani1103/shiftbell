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
    // ⭐ 2.3.0으로 올려서 google_mobile_ads 최신판(9.x)을 써보려다 보류함 -
    // 자세한 내용/재개 계획은 코틀린_버전업_계획.md 참고. UI 작업 끝난 뒤 진행할 것.
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
