# 🔒 [AUDIT PERF-6 / 2026-08-02] Baseline keep rules for the release build's
# R8 shrinking/obfuscation (enabled in build.gradle.kts). Most plugin AARs
# (Firebase, geolocator, image_picker, google_sign_in, etc.) ship their own
# consumer-rules.pro that AGP merges in automatically — these are the extra
# rules for the parts that don't:

# Flutter embedding / generated plugin registrant
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase Cloud Messaging background handler + data payload classes
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.** { *; }

# JNI native method names must survive obfuscation
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelable CREATOR fields (used by many plugin platform-channel classes)
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Enums accessed via values()/valueOf() reflection
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
