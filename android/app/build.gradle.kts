import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // El plugin de Flutter debe estar al final
    id("dev.flutter.flutter-gradle-plugin")
    // Si usas Firebase/Google Services (Analytics, Auth, etc.)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.appconductores"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "11" }

    // Fallbacks seguros por si el plugin de Flutter no expone las props
    val fallbackVersionCode = (project.findProperty("flutter.versionCode") as? String)?.toIntOrNull() ?: 1
    val fallbackVersionName = (project.findProperty("flutter.versionName") as? String) ?: "1.0.0"

    defaultConfig {
        applicationId = "driver.primebox.mx"
        minSdk = 21
        targetSdk = 35

        // Usa las props del plugin de Flutter si existen; si no, usa fallback
        @Suppress("UNNECESSARY_NOT_NULL_ASSERTION")
        versionCode = try {
            // Algunos setups exponen flutter.versionCode directamente
            flutter.versionCode
        } catch (_: Throwable) {
            fallbackVersionCode
        }

        versionName = try {
            flutter.versionName
        } catch (_: Throwable) {
            fallbackVersionName
        }
    }

    // --- Firma release segura desde key.properties ---
    val keystoreProps = Properties()
    val keyPropsFile = rootProject.file("key.properties")
    if (keyPropsFile.exists()) {
        keystoreProps.load(FileInputStream(keyPropsFile))
    }

    signingConfigs {
        create("release") {
            if (!keyPropsFile.exists()) {
                throw GradleException("No se encontró android/key.properties. Crea el archivo y define storeFile/storePassword/keyAlias/keyPassword.")
            }

            val storePath = keystoreProps.getProperty("storeFile")
                ?: throw GradleException("key.properties: falta 'storeFile'")
            val storePass = keystoreProps.getProperty("storePassword")
                ?: throw GradleException("key.properties: falta 'storePassword'")
            val alias = keystoreProps.getProperty("keyAlias")
                ?: throw GradleException("key.properties: falta 'keyAlias'")
            val keyPass = keystoreProps.getProperty("keyPassword")
                ?: throw GradleException("key.properties: falta 'keyPassword'")

            val fileRef = file(storePath)
            if (!fileRef.exists()) {
                throw GradleException("El keystore no existe: $storePath  (verifica la ruta o crea el archivo)")
            }

            storeFile = fileRef
            storePassword = storePass
            keyAlias = alias
            keyPassword = keyPass
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // sin cambios
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Si necesitas multidex (por error de 64K métodos), descomenta:
    // implementation("androidx.multidex:multidex:2.0.1")
}
