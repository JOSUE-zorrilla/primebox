plugins {
    id("com.android.application")
    id("kotlin-android")
    // El plugin de Flutter debe estar al final
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.appconductores"
    compileSdk = 34 // ✅ Asegura que esté en al menos 33 o superior

    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.appconductores"

        // ✅ Asegúrate de estas versiones:
        minSdk = 21
        targetSdk = 34 // >= 33 para permisos modernos

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

apply(plugin = "com.google.gms.google-services")
