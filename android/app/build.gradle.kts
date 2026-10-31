import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key is environment-specific and is NEVER committed. Read it from
// android/key.properties (local) or the properties CI writes from secrets.
//
// This build does NOT fall back to the debug key for release: a debug-signed
// bundle is refused by Play, and a build that looks successful while being
// unuploadable is worse than one that stops. Release therefore requires a
// usable key, and says so in one line when it is missing. DEBUG builds are
// untouched and keep signing with the debug key, so contributors and the
// integration lane never need the upload key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keystorePropertiesExist = keystorePropertiesFile.exists()
if (keystorePropertiesExist) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

/** Every value a release signing config is built from. */
val uploadKeyEntries =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingUploadKeyEntries =
    uploadKeyEntries.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
val hasUploadKey = keystorePropertiesExist && missingUploadKeyEntries.isEmpty()

android {
    // Play rejects any package starting with com.example, and the ID is
    // permanent once the first build is uploaded. azaman.app is the product
    // domain, so this is its reverse.
    namespace = "com.azaman.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.azaman.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                // Resolved against android/, matching key.properties itself.
                storeFile = rootProject.file(
                    keystoreProperties.getProperty("storeFile")
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Set only when the key is complete; the guard below refuses to run
            // a release task without one, so this branch can never silently
            // produce a debug-signed release.
            if (hasUploadKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// One clear sentence instead of a bundle Play will reject. The check is bound
// to the task graph, so it only speaks when a release artifact is actually
// requested: `flutter build apk --debug`, `flutter test` and the analyzer are
// never affected.
gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter { it.name.contains("Release") }
    if (releaseTasks.isEmpty() || hasUploadKey) return@whenReady
    val reason = if (!keystorePropertiesExist) {
        "android/key.properties does not exist"
    } else {
        "android/key.properties is missing " +
            missingUploadKeyEntries.joinToString(", ")
    }
    throw GradleException(
        "Release builds are signed with the upload key, and $reason. " +
            "Create the key as described in docs/RELEASE_SIGNING.md, or set the four " +
            "ANDROID_* repository secrets so CI can materialise it. " +
            "Debug builds are unaffected: they sign with the debug key by design."
    )
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
