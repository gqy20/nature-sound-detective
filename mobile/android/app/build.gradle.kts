plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun readRootDotEnv(name: String): String? {
    val envFile = rootProject.file("../../.env")
    if (!envFile.isFile) return null
    return envFile.useLines { lines ->
        lines.map(String::trim)
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { line ->
                val separator = line.indexOf('=')
                if (separator <= 0 || line.substring(0, separator).trim() != name) {
                    null
                } else {
                    line.substring(separator + 1).trim()
                        .removeSurrounding("\"")
                        .removeSurrounding("'")
                        .takeIf(String::isNotEmpty)
                }
            }
            .firstOrNull()
    }
}

val amapAndroidKey = providers.environmentVariable("AMAP_ANDROID_KEY").orNull
    ?.trim()
    ?.takeIf(String::isNotEmpty)
    ?: readRootDotEnv("AMAP_ANDROID_KEY")
    ?: ""
android {
    namespace = "com.xykw.nature_sound_detective"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.xykw.nature_sound_detective"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["AMAP_ANDROID_KEY"] = amapAndroidKey
        buildConfigField("boolean", "AMAP_NATIVE_MAP_ENABLED", "false")
    }

    buildTypes {
        debug {
            // Debug is a logging/instrumentation build of the same app. Keeping
            // the release package name lets it use the same package-bound AMap key.
            versionNameSuffix = "-debug"
            manifestPlaceholders["AMAP_ANDROID_KEY"] = amapAndroidKey
            buildConfigField(
                "boolean",
                "AMAP_NATIVE_MAP_ENABLED",
                amapAndroidKey.isNotEmpty().toString(),
            )
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            buildConfigField(
                "boolean",
                "AMAP_NATIVE_MAP_ENABLED",
                amapAndroidKey.isNotEmpty().toString(),
            )
        }
    }

    packaging {
        jniLibs {
            // All inference paths use the CPU interpreter. Avoid shipping the
            // unused GPU delegate in the competition APK.
            excludes += setOf("**/libtensorflowlite_gpu_jni.so")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.amap.api:3dmap:10.0.600")
    implementation("androidx.media3:media3-transformer:1.10.1")
    implementation("androidx.media3:media3-effect:1.10.1")
    implementation("androidx.work:work-runtime:2.11.2")
}
