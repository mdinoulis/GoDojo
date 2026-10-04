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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GoDojoEngine") {
      let channel = FlutterMethodChannel(
        name: "godojo/engine", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "installEngineFiles":
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let dir = try AppDelegate.installEngineFiles()
              DispatchQueue.main.async { result(dir) }
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "install", message: "\(error)", details: nil))
              }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// Copies the networks and config bundled in the app's "katago" folder to
  /// Application Support (KataGo writes logs next to them).
  static func installEngineFiles() throws -> String {
    let fm = FileManager.default
    let support = try fm.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let dir = support.appendingPathComponent("katago", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let src = Bundle.main.resourceURL?.appendingPathComponent("katago") else {
      return dir.path
    }
    for name in try fm.contentsOfDirectory(atPath: src.path) {
      let from = src.appendingPathComponent(name)
      let to = dir.appendingPathComponent(name)
      let size = (try? fm.attributesOfItem(atPath: from.path)[.size] as? NSNumber)??.int64Value
      let existing = (try? fm.attributesOfItem(atPath: to.path)[.size] as? NSNumber)??.int64Value
      if existing != nil && existing == size { continue }
      try? fm.removeItem(at: to)
      try fm.copyItem(at: from, to: to)
    }
    return dir.path
  }
}
