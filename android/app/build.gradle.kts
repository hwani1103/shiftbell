import java.util.Properties
import java.io.InputStreamReader
import java.io.FileInputStream
import java.nio.charset.Charset

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// key.properties 로드 (BOM 제거)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    InputStreamReader(FileInputStream(keystorePropertiesFile), Charsets.UTF_8).use { reader ->
        keystoreProperties.load(reader)
    }
}

android {
    namespace = "com.hwani1103.shiftbell"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        
        // Desugaring 활성화 ⭐
        isCoreLibraryDesugaringEnabled = true
    }

    // ⭐ 2026-08-25 - Kotlin 2.3.0부터 옛 kotlinOptions DSL이 에러로 처리됨
    // ("Using 'jvmTarget: String' is an error. Please migrate to the
    // compilerOptions DSL") - 새 DSL로 마이그레이션 (코틀린_버전업_계획.md 참고).
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    defaultConfig {
        applicationId = "com.hwani1103.shiftbell"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 24
        versionName = "1.0.22"
    }

    // ⭐ 정식(prod) 앱과 테스트(dev) 앱을 같은 기기에 동시에 설치해둘 수 있게 분리함.
    // dev는 applicationId가 달라져서(.dev 접미사) 완전히 "다른 앱"으로 취급되므로
    // - 정식 앱(Play Store에서 설치된 것)을 절대 덮어쓰거나 건드리지 않고
    // - DB/SharedPreferences 등 데이터도 완전히 분리됨 (테스트가 정식 데이터를 오염시킬 걱정 없음)
    // - 서명(signingConfig)은 release 빌드 타입 기준으로 두 flavor가 동일하게 적용되므로
    //   prod로 빌드한 AAB는 지금까지와 완전히 동일하게 Play Store 기존 앱 업데이트로 인식됨.
    // 사용법: 테스트 설치는 `flutter install --release --flavor dev`,
    //        정식 배포 빌드는 `flutter build appbundle --release --flavor prod`.
    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            // applicationId 접미사 없음 - 지금 Play Store에 올라가 있는 앱과 동일
            resValue("string", "app_name", "교대시계")
        }
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "교대시계 (테스트)")
        }
    }

    // ⭐ 릴리즈 서명 설정
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Desugaring 라이브러리 ⭐
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // ConstraintLayout
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")

    // AppCompat
    implementation("androidx.appcompat:appcompat:1.6.1")

    // Material (선택)
    implementation("com.google.android.material:material:1.11.0")
}

// ⭐ 2026-08-20 추가 - Dart↔Kotlin "손으로 맞춰야 하는 상수" 빌드 타임 가드.
//
// 이 앱은 Flutter(Dart)와 Native(Kotlin)가 같은 SQLite 파일을 각자 열고, 같은 "10일치
// 미리 생성" 규칙을 각자 구현하는 구조라, 몇몇 숫자 상수는 두 언어 양쪽에 각각 하드코딩된
// 채로 사람이 손으로 동일하게 맞춰야 함. 이 세션에서만도 DB 버전 불일치
// (DatabaseHelper.kt의 DATABASE_VERSION ↔ database_service.dart의 version:)가 위젯/
// 잠금화면 알람 시각 표시/고정 알람 수정 반영까지 세 갈래로 조용히 망가뜨렸고, 이게 벌써
// 세 번째 재발이었음(v13/14, v15/16, 이번 v17/18) - "다음에 안 잊어버리기"로는 구조적으로
// 안 막힘. 그래서 이 값들을 실제로 비교해서, 안 맞으면 빌드 자체가 실패하게 만듦 - 사람이
// 기억하지 않아도 됨.
//
// 대상:
// 1) DB 스키마 버전 (DatabaseHelper.kt DATABASE_VERSION ↔ database_service.dart version:)
// 2) 알람 자동 갱신 윈도우 일수 (AlarmRefreshEngine.kt DAYS_AHEAD ↔
//    alarm_limits.dart kAlarmRefreshWindowDays) - 2026-07-29에 이미 한 번 어긋나서
//    10일치 윈도우가 이틀 뒤처진 채 멈췄던 전례가 있음(alarm-reliability-overhaul 메모리).
//
// 새로 추가해야 할 "Dart/Kotlin 양쪽에 각각 있는 숫자 상수" 쌍이 생기면 아래
// checkPair() 호출을 하나 더 추가하면 됨 - 정규식 하나씩만 맞으면 끝.
val checkDartKotlinSync = tasks.register("checkDartKotlinSync") {
    group = "verification"
    description = "Dart(Flutter)와 Kotlin(Native) 양쪽에 각각 하드코딩된 상수들이 서로 일치하는지 빌드 전에 확인합니다 (안 맞으면 빌드 실패)."

    doLast {
        // ⭐ android/(rootProject) 의 부모 = 저장소 루트 - 여기서부터 lib/ 이하 Dart 파일을 찾음.
        val repoRoot = rootProject.projectDir.parentFile

        fun checkPair(label: String, kotlinFile: File, kotlinRegex: Regex, dartFile: File, dartRegex: Regex, hint: String) {
            if (!kotlinFile.exists()) throw GradleException("[$label] Kotlin 파일을 찾을 수 없음: ${kotlinFile.path}")
            if (!dartFile.exists()) throw GradleException("[$label] Dart 파일을 찾을 수 없음: ${dartFile.path}")

            val kotlinValue = kotlinRegex.find(kotlinFile.readText())?.groupValues?.get(1)
                ?: throw GradleException("[$label] ${kotlinFile.path}에서 패턴(${kotlinRegex.pattern})에 맞는 값을 못 찾음 - 코드가 리팩토링되면서 정규식도 같이 업데이트해야 할 수 있음.")
            val dartValue = dartRegex.find(dartFile.readText())?.groupValues?.get(1)
                ?: throw GradleException("[$label] ${dartFile.path}에서 패턴(${dartRegex.pattern})에 맞는 값을 못 찾음 - 코드가 리팩토링되면서 정규식도 같이 업데이트해야 할 수 있음.")

            if (kotlinValue != dartValue) {
                throw GradleException(
                    "\n\n🚨 [$label] Kotlin과 Dart 값이 다릅니다! Kotlin=$kotlinValue, Dart=$dartValue\n" +
                    "  - Kotlin: ${kotlinFile.path}\n" +
                    "  - Dart:   ${dartFile.path}\n" +
                    "  → $hint\n"
                )
            }
            logger.lifecycle("✅ [Dart↔Kotlin 동기화] $label 일치 확인 (값=$kotlinValue)")
        }

        checkPair(
            label = "DB 스키마 버전",
            kotlinFile = file("src/main/kotlin/com/hwani1103/shiftbell/DatabaseHelper.kt"),
            kotlinRegex = Regex("""DATABASE_VERSION\s*=\s*(\d+)"""),
            dartFile = File(repoRoot, "lib/services/database_service.dart"),
            dartRegex = Regex("""version:\s*(\d+),"""),
            hint = "DatabaseHelper.kt의 DATABASE_VERSION을 database_service.dart의 version:과 같은 값으로 맞추세요."
        )

        checkPair(
            label = "알람 자동 갱신 윈도우(일수)",
            kotlinFile = file("src/main/kotlin/com/hwani1103/shiftbell/AlarmRefreshEngine.kt"),
            kotlinRegex = Regex("""DAYS_AHEAD\s*=\s*(\d+)"""),
            dartFile = File(repoRoot, "lib/constants/alarm_limits.dart"),
            dartRegex = Regex("""kAlarmRefreshWindowDays\s*=\s*(\d+);"""),
            hint = "AlarmRefreshEngine.kt의 DAYS_AHEAD를 alarm_limits.dart의 kAlarmRefreshWindowDays와 같은 값으로 맞추세요."
        )
    }
}

// ⭐ 모든 빌드 variant(assembleDevRelease, bundleProdRelease 등)의 preBuild 단계가 이
// 체크를 먼저 통과해야만 진행되도록 함 - 즉 두 상수가 어긋난 코드는 애초에 APK/AAB로
// 빌드조차 되지 않음(런타임에 조용히 알람/위젯이 멈추는 대신, 빌드 시점에 시끄럽게 실패).
// ⭐ 실제 태스크 이름은 "preBuild"/"preDevReleaseBuild"/"preProdReleaseBuild" 등
// pre+<변형>+Build 형태(끝이 "Build"이지 "PreBuild"가 아님) - `./gradlew :app:tasks --all`로
// 직접 확인함. endsWith("PreBuild")로 처음 짰다가 전부 매칭 실패했던 걸
// `--dry-run`으로 잡아서 고침(아래 startsWith+endsWith 조합만 맞고 "prepareLintJarForPublish"
// 같은 무관한 태스크는 제외되는 것까지 확인).
tasks.matching { it.name.startsWith("pre") && it.name.endsWith("Build") }.configureEach {
    dependsOn(checkDartKotlinSync)
}
