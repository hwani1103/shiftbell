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
        versionCode = 5
        versionName = "1.0.4"
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
