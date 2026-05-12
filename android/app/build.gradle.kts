import com.android.build.api.dsl.ApplicationExtension
import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.safechild.safechild"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.safechild.safechild"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion //flutter.minSdkVersion
        targetSdk = 34
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

    // fasttext_flutter (native assets) links against `c++_shared`. Ship the NDK
    // libc++_shared.so next to other JNI libs so dlopen can resolve libc++ ABI
    // symbols (e.g. std::length_error typeinfo) in full apps with many .so files.
    packaging {
        jniLibs {
            pickFirsts += "**/libc++_shared.so"
        }
    }

    sourceSets.getByName("main") {
        jniLibs.srcDir(project.layout.buildDirectory.dir("generated/libcxx-jni"))
    }
}


dependencies {
    // For AGP 7.4+
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
 
}

flutter {
    source = "../.."
}

/** NDK prebuilt host folder name (toolchains/llvm/prebuilt/<tag>/…). */
fun ndkHostTag(): String {
    val os = System.getProperty("os.name").lowercase()
    val arch = System.getProperty("os.arch")?.lowercase().orEmpty()
    return when {
        os.contains("win") -> "windows-x86_64"
        os.contains("mac") || os.contains("darwin") -> when {
            arch.contains("aarch64") || arch.contains("arm64") -> "darwin-arm64"
            else -> "darwin-x86_64"
        }
        else -> "linux-x86_64"
    }
}

tasks.register("prepareLibcxxShared") {
    description = "Copies libc++_shared.so from the Android NDK into generated jniLibs for fasttext_flutter (c++_shared)."
    val outDir = layout.buildDirectory.dir("generated/libcxx-jni")
    outputs.dir(outDir)

    doLast {
        val props = Properties()
        val lp = rootProject.file("local.properties")
        if (lp.exists()) lp.reader().use { props.load(it) }
        val sdk = props.getProperty("sdk.dir")
            ?: System.getenv("ANDROID_HOME")
            ?: System.getenv("ANDROID_SDK_ROOT")
            ?: throw GradleException("sdk.dir (local.properties) or ANDROID_HOME not set")
        val ndkVer = project.extensions.getByType(ApplicationExtension::class.java).ndkVersion
            ?: throw GradleException("android.ndkVersion is not set")
        val ndkRoot = File(sdk, "ndk/$ndkVer")
        val base = File(ndkRoot, "toolchains/llvm/prebuilt/${ndkHostTag()}/sysroot/usr/lib")
        if (!base.isDirectory) {
            throw GradleException(
                "NDK sysroot not found at ${base.absolutePath}. " +
                    "Install NDK $ndkVer (Flutter's ndkVersion) via Android SDK Manager.",
            )
        }
        val destRoot = outDir.get().asFile
        destRoot.deleteRecursively()
        destRoot.mkdirs()
        data class AbiTriple(val abi: String, val triple: String)
        val pairs = listOf(
            AbiTriple("arm64-v8a", "aarch64-linux-android"),
            AbiTriple("armeabi-v7a", "arm-linux-androideabi"),
            AbiTriple("x86_64", "x86_64-linux-android"),
            AbiTriple("x86", "i686-linux-android"),
        )
        var copied = 0
        for ((abi, triple) in pairs) {
            val src = File(base, "$triple/libc++_shared.so")
            if (src.isFile) {
                val d = File(destRoot, abi)
                d.mkdirs()
                src.copyTo(File(d, "libc++_shared.so"), overwrite = true)
                copied++
            }
        }
        check(copied > 0) {
            "prepareLibcxxShared: no libc++_shared.so under ${base.absolutePath}"
        }
    }
}

tasks.named("preBuild").configure { dependsOn("prepareLibcxxShared") }

