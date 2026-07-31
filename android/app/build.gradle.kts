import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, read from the environment in CI and from a
// gitignored android/key.properties locally.
//
// Neither source is required. With nothing configured the release build falls
// back to the debug key so a plain `flutter build apk --release` still works on
// a fresh clone. That fallback is fine locally and wrong for distribution:
// every machine and every hosted runner generates its own debug keystore, so
// consecutive CI builds would each carry a different signature and Android
// would refuse to install one over another. The publish workflow therefore
// asserts a real key was used before it uploads anything.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun signingSecret(envName: String, propName: String): String? =
    (System.getenv(envName) ?: keystoreProperties.getProperty(propName))
        ?.takeIf { it.isNotBlank() }

val releaseStoreFilePath = signingSecret("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingSecret("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingSecret("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingSecret("ANDROID_KEY_PASSWORD", "keyPassword")

val releaseKeystore = releaseStoreFilePath?.let(::file)?.takeIf { it.isFile }
val hasReleaseSigning = releaseKeystore != null &&
    releaseStorePassword != null && releaseKeyAlias != null && releaseKeyPassword != null

android {
    namespace = "click.magento2.clickalize"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "click.magento2.clickalize"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Both come from android/local.properties, which only `flutter build`
        // writes. Invoking Gradle directly (./gradlew assembleRelease) silently
        // yields versionCode 1 — the Flutter Gradle plugin defaults the missing
        // property rather than failing.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Must stay ABOVE buildTypes. The Kotlin DSL evaluates top to bottom and
    // getByName("release") resolves eagerly, so declaring this afterwards fails
    // configuration with "SigningConfig with name 'release' not found".
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.lifecycle(
                    "Clickalize: no release signing configured — falling back to the " +
                        "debug key. Fine for local builds, never for distribution.",
                )
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

flutter {
    source = "../.."
}
