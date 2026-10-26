plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mybot.assistant"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mybot.assistant"
        // 26 = Android 8.0. Screenshots need Android 11 (API 30); the app
        // degrades gracefully below that and says so instead of crashing.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // A fixed signing key, committed with the project. Without it every CI run
    // would sign with a fresh debug key, and Android would refuse to install a
    // new build over an old one — losing your data on each update.
    // This key protects nothing but this app's identity: it is a sideload
    // convenience, not a secret. Never reuse it for anything published.
    signingConfigs {
        create("sideload") {
            storeFile = file("mybot-release.jks")
            storePassword = "mybot-sideload"
            keyAlias = "mybot"
            keyPassword = "mybot-sideload"
        }
    }

    buildTypes {
        release {
            signingConfig = if (file("mybot-release.jks").exists()) {
                signingConfigs.getByName("sideload")
            } else {
                // Falls back so a stripped checkout still builds.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
