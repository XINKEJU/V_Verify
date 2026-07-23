# Keep WebView JavaScript interface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.xinkeju.vverify.MainActivity { *; }
