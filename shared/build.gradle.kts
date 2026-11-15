plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.android.library")
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    // macOS-таргеты временно отключены: они тянут Kotlin/Native и конфликтуют
    // с Gradle 8.9 (баг ':commonizeNativeDistribution'). Для macOS используется
    // нативный Swift-хаб (macos/), который повторяет тот же протокол.
    //
    // Чтобы вернуть фреймворк IGoogleShared:
    //   1) поднимите Kotlin до 2.1.x в корневом build.gradle.kts;
    //   2) раскомментируйте блок ниже.
    //
    // listOf(macosX64(), macosArm64()).forEach { target ->
    //     target.binaries.framework {
    //         baseName = "IGoogleShared"
    //         isStatic = true
    //     }
    // }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("com.squareup.okhttp3:okhttp:4.12.0")
            }
        }
        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
            }
        }
    }
}

android {
    namespace = "com.igoogle.shared"
    compileSdk = 34
    defaultConfig {
        minSdk = 26
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
