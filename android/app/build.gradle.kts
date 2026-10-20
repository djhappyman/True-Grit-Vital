plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.truegrit.vital"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.truegrit.vital"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // No signingConfig is declared in this development tree. Owner-supplied
            // release signing is a G07 release decision, never a debug-key fallback.
        }
    }
}

// Fail closed rather than producing a distributable artifact signed for development.
// Replace this guard together with real owner-supplied signing configuration.
gradle.taskGraph.whenReady(object : org.gradle.api.Action<org.gradle.api.execution.TaskExecutionGraph> {
    override fun execute(graph: org.gradle.api.execution.TaskExecutionGraph) {
        val releaseRequested = graph.allTasks.any { task ->
            task.name.startsWith("assembleRelease") ||
                task.name.startsWith("bundleRelease") ||
                task.name.startsWith("packageRelease")
        }
        if (releaseRequested) {
            throw org.gradle.api.GradleException(
                "Release signing is not configured. This development tree must not " +
                    "produce a distributable artifact. Configure owner-supplied signing first."
            )
        }
    }
})

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
