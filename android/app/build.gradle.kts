import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val ciEmulatorAbi = System.getenv("CI_EMULATOR_ABI")

// B-045: a plain `flutter run -d emulator-5554 --debug` used to be a footgun.
// This file unconditionally forced target-platform / abiFilters to arm64-v8a
// (a release-size choice), so a debug run against an x86_64 emulator
// cross-compiled flutter_soloud for arm64 — and the NDK 27 aarch64 sysroot
// leaked host snap glibc headers, breaking the build. Fix: only force arm64
// for RELEASE / app-bundle builds. Debug / profile builds leave
// target-platform unset so the ABI that `flutter run` already detected for
// the connected device (passed via -Ptarget-platform) wins — the emulator
// builds x86_64 with no env var needed. CI_EMULATOR_ABI=x86_64 stays as an
// explicit escape hatch (e.g. an x86_64 release on CI).
val isReleaseBuild = gradle.startParameter.taskNames.any { name ->
    name.contains("Release", ignoreCase = true) ||
        name.contains("Bundle", ignoreCase = true)
}

when {
    ciEmulatorAbi == "x86_64" -> extra["target-platform"] = "android-x64"
    isReleaseBuild -> extra["target-platform"] = "android-arm64"
    // else (debug / profile): leave target-platform unset; honour the
    // device ABI Flutter detected.
}

android {
    namespace = "com.saplin.nothingness"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.saplin.nothingness"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // B-017: Android 10 (API 29) floor. Scoped storage is universal from
        // API 29, so Permission.audio (mapped to READ_MEDIA_AUDIO on 33+ and
        // to legacy READ_EXTERNAL_STORAGE on 29-32) covers the library on
        // every supported version. Do NOT lower below 29.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // B-045: mirror the target-platform decision above. Only restrict
            // to a single ABI for CI-x86_64 or release/arm64 builds; debug /
            // profile builds leave abiFilters unset so the build packages
            // whatever Flutter compiled for the connected device's ABI.
            when {
                ciEmulatorAbi == "x86_64" -> abiFilters.add("x86_64")
                isReleaseBuild -> abiFilters.add("arm64-v8a")
            }
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (keystoreProperties["storeFile"] != null) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            val jniExcludes = mutableListOf("**/armeabi-v7a/**")
            // B-045: keep the x86_64 native libs for debug/profile (they may
            // target an x86_64 emulator). Only strip them for release/arm64
            // builds, where size matters and the target is real arm64 HW.
            if (ciEmulatorAbi != "x86_64" && isReleaseBuild) {
                jniExcludes += "**/x86_64/**"
            }
            excludes += jniExcludes
        }
        resources {
            excludes += "**/flutter_soloud/web/**"
        }
    }
}

flutter {
    source = "../.."
}
