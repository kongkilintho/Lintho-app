import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// 🔒 [AUDIT PERF-6 / 2026-08-02 — Critical, fresh re-audit] ກ່ອນໜ້ານີ້
// buildTypes.release.signingConfig ຊີ້ໄປຫາ signingConfigs.debug ຕົງໆ — ໝາຍ
// ຄວາມວ່າ "release" build ບໍ່ເຄີຍໄດ້ signed ດ້ວຍ key ຈິງເລີຍ, ບໍ່ສາມາດ upload
// ຂຶ້ນ Play Store ໄດ້ຢ່າງຖືກຕ້ອງ. ຕອນນີ້ອ່ານ key.properties (ບໍ່ commit — ເບິ່ງ
// key.properties.example) ຖ້າມີ, ໃຊ້ signing ຈິງ — ຖ້າຍັງບໍ່ມີ (dev machine/CI
// ທີ່ຍັງບໍ່ທັນຕັ້ງຄ່າ) fallback ໄປ debug signing ຄືເກົ່າ ແຕ່ print ຄຳເຕືອນທີ່ເຫັນ
// ໄດ້ຊັດເຈນ (ບໍ່ແມ່ນງຽບໆຄືເກົ່າ) ເພື່ອບໍ່ໃຫ້ໃຜອັບໂຫຼດ artifact ນັ້ນຂຶ້ນ store ໂດຍບໍ່ຮູ້ໂຕ.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    println("⚠️  android/key.properties not found — release build will be signed with the DEBUG key and is NOT suitable for Play Store upload. See android/key.properties.example.")
}

android {
    namespace = "com.lintho.app.lintho"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.lintho.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 🔒 [AUDIT PERF-6 / 2026-08-02] ບໍ່ເຄີຍເປີດ shrink/obfuscate ມາກ່ອນ —
            // release APK ໃຫຍ່ກວ່າທີ່ຄວນ ແລະ ບໍ່ obfuscated. proguard-rules.pro
            // ມີ keep rules ພື້ນຖານສຳລັບ Flutter/Firebase ແລ້ວ — ຕ້ອງທົດສອບ
            // release build ເຕັມຮູບແບບເທິງອຸປະກອນຈິງກ່ອນ ship (R8 ອາດທຳລາຍ
            // reflection-based code ຂອງ plugin ບາງໂຕ ຖ້າ keep rules ບໍ່ພຽງພໍ).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
