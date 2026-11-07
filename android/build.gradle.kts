buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // AGP 9 builds Kotlin itself; this picks the Kotlin version. GeckoView
        // brings the Kotlin 2.4 standard library, so the compiler must be 2.4.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21")
    }
}

plugins {
    id("com.android.application") version "9.5.1" apply false
}
