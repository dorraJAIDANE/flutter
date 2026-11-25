# Keep XFY native scanner, Google ML Kit Barcode Scanning & CameraX classes intact in Release R8 builds
-keep class tn.xfy.xfy_mobile.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.** { *; }
-keep class androidx.camera.** { *; }
-keepclassmembers class * extends java.lang.Enum {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-dontwarn com.google.mlkit.**
-dontwarn androidx.camera.**
