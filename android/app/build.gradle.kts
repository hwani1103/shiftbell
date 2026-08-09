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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.hwani1103.shiftbell"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 18
        versionName = "1.0.16"
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
