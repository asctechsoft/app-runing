import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Khóa ký lấy từ android/debug_keystore.properties (và productKeyPath trỏ tới file khóa phát hành) — cùng
// quy ước với các app ASC khác. Các file này + *.jks bị gitignore; thiếu file (máy mới, CI) thì dùng khóa debug mặc định.
fun loadProps(file: File): Properties? =
    if (file.exists()) Properties().also { p -> FileInputStream(file).use { p.load(it) } } else null

val debugKeystoreProps = loadProps(rootProject.file("debug_keystore.properties"))
val productKeystoreProps = (debugKeystoreProps?.getProperty("productKeyPath"))?.let { loadProps(rootProject.file(it)) }

android {
    namespace = "com.asc.app_runing"
    // permission_handler_android 13 yêu cầu SDK 37; compileSdk tương thích ngược nên ghim tường minh thay vì tin mặc định của Flutter.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications cần desugaring java.time
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.asc.app_runing"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob (dsp_base): mặc định là app ID test của Google. Bản phát hành truyền ID thật qua
        // `-PADMOB_APP_ID=ca-app-pub-xxxx~yyyy` hoặc gradle.properties cục bộ — không commit ID thật vào repo.
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("ADMOB_APP_ID") as String?) ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        // Debug: khóa của đội nếu có, không thì khóa debug mặc định của Android (giữ nguyên cấu hình sẵn của AGP).
        getByName("debug") {
            debugKeystoreProps?.let { p ->
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
                storeFile = file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
            }
        }
        // Dev/Alpha release: ký bằng khóa đội (hoặc debug khi chưa có) để cài thử và phân phối qua App Distribution.
        create("release") {
            val p = debugKeystoreProps
            if (p != null) {
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
                storeFile = file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
            } else {
                initWith(getByName("debug"))
            }
        }
        // Product release (lên store): khóa upload riêng; thiếu khóa thì rơi về khóa debug để build thử, KHÔNG dùng để phát hành.
        create("productRelease") {
            val p = productKeystoreProps
            if (p != null) {
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
                storeFile = file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
            } else {
                initWith(getByName("debug"))
            }
        }
    }

    // Flavor khớp AscBuildFlavor trong asc_common: alpha (không quảng cáo), dev, product, claude.
    flavorDimensions += "environment"

    productFlavors {
        create("alpha") {
            dimension = "environment"
            resValue("string", "app_name", "STRIDE")
            signingConfig = signingConfigs.getByName("productRelease")
            ndk { abiFilters += listOf("arm64-v8a") }
        }
        create("dev") {
            dimension = "environment"
            resValue("string", "app_name", "STRIDE")
            signingConfig = signingConfigs.getByName("release")
            ndk { abiFilters += listOf("arm64-v8a") }
        }
        create("product") {
            dimension = "environment"
            resValue("string", "app_name", "STRIDE")
            signingConfig = signingConfigs.getByName("productRelease")
        }
        create("claude") {
            dimension = "environment"
            resValue("string", "app_name", "STRIDE")
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
