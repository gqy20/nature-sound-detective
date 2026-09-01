# AMap 3D Map SDK 5.0.0+ uses reflection and JNI lookups that require these
# package names and members to survive R8 optimization in Flutter release APKs.
# Source: https://lbs.amap.com/api/maps-sdk-for-android/guide/create-project/dev-attention
-keep class com.amap.api.maps.** { *; }
-keep class com.autonavi.** { *; }
-keep class com.amap.api.trace.** { *; }
