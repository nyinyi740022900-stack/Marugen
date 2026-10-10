# Flutter's embedding classes are referenced reflectively by the engine.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# flutter_stripe (payment sheet, 3DS webview) relies on reflection to look up
# its own model/serialization classes at runtime — stripping or renaming
# them silently breaks the payment sheet instead of failing the build.
-keep class com.stripe.android.** { *; }
-keep class com.reactnativestripesdk.** { *; }
-dontwarn com.stripe.android.**

# stripe-android-issuing-push-provisioning (a transitive dependency of
# flutter_stripe's Android SDK, unused by this app — see the `lint` block
# comment in build.gradle.kts) references Google's play-services-tapandpay,
# which isn't on public Maven and isn't present at runtime either. Silence
# the resulting "missing class" warnings rather than keeping it.
-dontwarn com.google.android.gms.tapandpay.**

# Google Play Core split-install/deferred-component classes are referenced
# by Flutter's embedding even when this app doesn't use dynamic feature
# delivery — without this, R8 fails with "Missing classes" for
# com.google.android.play.core.* rather than just leaving the dead code out.
-dontwarn com.google.android.play.core.**

# Firebase Crashlytics needs de-obfuscated stack traces; it uploads the
# mapping file automatically via its Gradle plugin, but keep line numbers
# and source file names so traces are still readable if that upload is
# ever skipped.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
