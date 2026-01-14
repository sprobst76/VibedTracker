# Flutter Local Notifications - Gson TypeToken fix
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep generic signatures for Gson
-keepattributes Signature
-keepattributes *Annotation*

# Flutter Local Notifications Plugin
-keep class com.dexterous.** { *; }

# Keep Gson classes
-keep class com.google.gson.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Prevent stripping of generic type information
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Geofence Foreground Service - prevent obfuscation
-keep class com.f2fk.geofence_foreground_service.** { *; }
