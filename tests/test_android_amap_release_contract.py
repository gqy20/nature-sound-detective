from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ANDROID_APP = ROOT / "mobile" / "android" / "app"


def test_release_build_keeps_amap_jni_packages():
    rules = (ANDROID_APP / "proguard-rules.pro").read_text(encoding="utf-8")
    assert "-keep class com.amap.api.maps.** { *; }" in rules
    assert "-keep class com.autonavi.** { *; }" in rules
    assert "-keep class com.amap.api.trace.** { *; }" in rules

    gradle = (ANDROID_APP / "build.gradle.kts").read_text(encoding="utf-8")
    assert 'getDefaultProguardFile("proguard-android-optimize.txt")' in gradle
    assert '"proguard-rules.pro"' in gradle


def test_native_map_failure_falls_back_instead_of_escaping_platform_view():
    source = (
        ANDROID_APP
        / "src"
        / "main"
        / "kotlin"
        / "com"
        / "xykw"
        / "nature_sound_detective"
        / "AmapSoundscapeView.kt"
    ).read_text(encoding="utf-8")
    assert 'handleMapFailure(context, "高德动态地图初始化失败", error)' in source
    assert "private fun releaseMapResources()" in source
    assert 'component = "amap"' in source


def test_creation_api_key_uses_android_keystore_and_is_not_backed_up():
    manifest = (ANDROID_APP / "src" / "main" / "AndroidManifest.xml").read_text(
        encoding="utf-8"
    )
    assert 'android:allowBackup="false"' in manifest

    activity = (
        ANDROID_APP
        / "src"
        / "main"
        / "kotlin"
        / "com"
        / "xykw"
        / "nature_sound_detective"
        / "MainActivity.kt"
    ).read_text(encoding="utf-8")
    assert 'KeyStore.getInstance("AndroidKeyStore")' in activity
    assert 'Cipher.getInstance("AES/GCM/NoPadding")' in activity
    assert '"com.xykw.nature_sound/creation_secrets"' in activity
