plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.arasedas.arassaha_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Bildirim Sistemi (Modül 6): flutter_local_notifications kendi Android
        // tarafında core library desugaring gerektiriyor (java.time API kullanımı) —
        // bu, kullanan uygulama modülünde de AÇIKÇA etkinleştirilmek zorunda,
        // aksi halde Gradle "requires core library desugaring to be enabled" hatasıyla
        // derlemeyi durdurur.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.arasedas.arassaha_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // flutter_local_notifications'ın gerektirdiği core library desugaring
    // (isCoreLibraryDesugaringEnabled = true, yukarıda) için gerekli kütüphane.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
