import Flutter
import UIKit

// Test harness only. Seeds native storage using the pinned SDK's path APIs.
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
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StorageProbe")!
    FlutterMethodChannel(name: "confidence.storage-probe", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        do {
          let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).last!
          let bundleId = Bundle.main.bundleIdentifier!
          let cache = support.appendingPathComponent("com.confidence.cache/\(bundleId)")
          let flags = cache.appendingPathComponent("confidence.flags.resolve")
          let apply = cache.appendingPathComponent("confidence.flags.apply")
          let events = support.appendingPathComponent("com.confidence.events.storage/\(bundleId)/events")
          switch call.method {
          case "seed":
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
            try Data("legacy-flags".utf8).write(to: flags)
            try Data("legacy-apply".utf8).write(to: apply)
            try Data("sealed-event".utf8).write(to: events.appendingPathComponent("batch.READY"))
            try Data("unfinished-event".utf8).write(to: events.appendingPathComponent("unfinished"))
            UserDefaults.standard.set("native-visitor", forKey: "confidence.visitor_id")
            UserDefaults.standard.set("wrong-visitor", forKey: "flutter.confidence.visitor_id")
            result([
              "flags": flags.resolvingSymlinksInPath().path,
              "apply": apply.resolvingSymlinksInPath().path,
              "events": events.resolvingSymlinksInPath().path
            ])
          case "changeIdentity":
            UserDefaults.standard.set("updated-native-visitor", forKey: "confidence.visitor_id")
            result(nil)
          case "removeIdentity":
            UserDefaults.standard.removeObject(forKey: "confidence.visitor_id")
            result(nil)
          default:
            result(FlutterMethodNotImplemented)
          }
        } catch {
          result(FlutterError(code: "seed_failed", message: error.localizedDescription, details: nil))
        }
      }
  }
}
