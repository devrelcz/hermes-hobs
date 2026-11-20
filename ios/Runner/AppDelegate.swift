import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: show banners in the foreground and report taps.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HobsBackgroundTime") {
      BackgroundTime.register(with: registrar)
    }
  }
}

/// `hobs/background`: asks iOS for a little more time after the app leaves the
/// screen, so a Hob reply that is still streaming can finish and notify.
/// iOS ends it after roughly 30 seconds; this is not a keep-alive.
final class BackgroundTime: NSObject {
  private var task: UIBackgroundTaskIdentifier = .invalid

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "hobs/background", binaryMessenger: registrar.messenger())
    let instance = BackgroundTime()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "begin":
        instance.begin()
        result(nil)
      case "end":
        instance.end()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func begin() {
    guard task == .invalid else { return }
    task = UIApplication.shared.beginBackgroundTask(withName: "hob-reply") { [weak self] in
      self?.end()
    }
  }

  private func end() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }
}
