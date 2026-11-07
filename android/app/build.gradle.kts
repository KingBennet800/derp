import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Derp's version comes from the repo's VERSION file, like the desktop installers.
val derpVersion = rootDir.resolve("../VERSION").readText().trim()
val (major, minor, patch) = derpVersion.split(".").map { it.toInt() }
val generated = layout.buildDirectory.dir("generated/derp")

android {
    namespace = "io.github.kingbennet800.derp"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.github.kingbennet800.derp"
        minSdk = 26
        targetSdk = 36
        versionCode = major * 10000 + minor * 100 + patch
        versionName = derpVersion
    }

    // Release builds are signed with Derp's key when CI provides it
    // (DERP_KEYSTORE etc.); otherwise with the debug key, for testing.
    val releaseKey = System.getenv("DERP_KEYSTORE")
    signingConfigs {
        if (releaseKey != null) {
            create("derp") {
                storeFile = file(releaseKey)
                storeType = "pkcs12"
                storePassword = System.getenv("DERP_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DERP_KEY_ALIAS") ?: "derp"
                keyPassword = System.getenv("DERP_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName(if (releaseKey != null) "derp" else "debug")
        }
    }

    // One APK per processor family keeps each download small.
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    sourceSets["main"].assets.srcDir(generated.map { it.dir("assets") })
    sourceSets["main"].res.srcDir(generated.map { it.dir("res") })

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    // The newest GeckoView release at build time, like desktop Derp's engine.
    implementation("org.mozilla.geckoview:geckoview:latest.release")
    // Draws your dork (SVG) for the toolbar.
    implementation("com.caverock:androidsvg-aar:1.4")
}

// Derp's logo, wordmark and dork drawing code, from the rest of the repo.
val prepareDerpAssets by tasks.registering(Exec::class) {
    val script = rootDir.resolve("prepare_assets.py")
    inputs.file(script)
    inputs.file(rootDir.resolve("../src/features/DerpDork.sys.mjs"))
    inputs.dir(rootDir.resolve("../brand"))
    outputs.dir(generated)
    commandLine("python3", script.path, generated.get().asFile.path)
}

tasks.named("preBuild") {
    dependsOn(prepareDerpAssets)
}
