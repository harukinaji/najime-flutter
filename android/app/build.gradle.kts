import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Optional release signing.
//
// Create `android/key.properties` (gitignored) with:
//   storeFile=/absolute/path/to/keystore.jks
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
//
// When the file is absent the release build falls back to the debug keystore,
// so `flutter run --release` and CI smoke builds keep working. CI/CD injects
// the keystore from GitHub secrets (see .github/workflows/release.yml).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.naji.najimessenger"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.naji.najimessenger"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
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
            // Use the configured upload keystore when present, otherwise fall
            // back to the debug keystore so local/CI smoke builds still work.
            val releaseConfigured = keystorePropertiesFile.exists() &&
                keystoreProperties["storeFile"] != null &&
                keystoreProperties["storePassword"] != null &&
                keystoreProperties["keyAlias"] != null &&
                keystoreProperties["keyPassword"] != null
            signingConfig = if (releaseConfigured) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        incremental = false
    }
}

android.buildTypes.configureEach {
    enableAndroidTestCoverage = false
    enableUnitTestCoverage = false
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")



}
