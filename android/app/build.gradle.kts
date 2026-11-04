import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.magicvalleycentral.mvc_app"
    compileSdk = 36
//    ndkVersion = flutter.ndkVersion
    ndkVersion = "29.0.13846066"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.magicvalleycentral.mvc_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
    }


    flavorDimensions += "default"

    productFlavors {
        create("development") {
            dimension = "default"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appName"] = "MVC Dev"
        }
        create("production") {
            dimension = "default"
            manifestPlaceholders["appName"] = "MVC"
        }
    }


    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            val storeFileProp = keystoreProperties["storeFile"] as String?
            storeFile = storeFileProp?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Explicitly force these off. Flutter's own Gradle plugin can
            // apply resource-shrinking defaults for release builds that
            // don't appear anywhere in this file's plain text, and that
            // shrinking collapses resource names (res/xx.png-style short
            // names) in a way that breaks any runtime lookup-by-name call,
            // such as flutter_local_notifications resolving its icon via
            // getIdentifier(). This project doesn't use ProGuard/R8 rules
            // and doesn't need shrinking, so disable both explicitly.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
            // Exclude 32-bit libraries that don't support 16 KB alignment
            excludes += listOf(
                "lib/armeabi/**",
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/mips/**"
            )
            // Handle duplicate libraries by picking first occurrence
            pickFirsts += listOf(
                "lib/arm64-v8a/libc++_shared.so",
                "lib/x86_64/libc++_shared.so"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
