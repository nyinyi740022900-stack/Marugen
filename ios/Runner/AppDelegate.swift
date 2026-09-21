import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // This app uses the UIScene lifecycle (SceneDelegate.swift +
  // UIApplicationSceneManifest in Info.plist), so the UIWindow lives on the
  // scene delegate and `AppDelegate.window` is never set. flutter_stripe
  // (stripe_ios) still resolves its presenting view controller via
  // `UIApplication.shared.delegate?.window??.rootViewController` — with
  // that nil it falls back to a bare, detached `UIViewController()` and
  // presenting the PaymentSheet from it kills the app (looks like tapping
  // "Pay with Stripe" throws the user out to the home screen). Bridge the
  // scene's key window through here so the sheet presents on the real
  // Flutter view controller.
  override var window: UIWindow? {
    get {
      if let w = super.window { return w }
      return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }
        ?? UIApplication.shared.connectedScenes
          .compactMap { ($0 as? UIWindowScene)?.windows.first }
          .first
    }
    set { super.window = newValue }
  }
}
