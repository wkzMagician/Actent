import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static var openFilesChannel: FlutterMethodChannel?
  private static var iosWorkChannel: FlutterMethodChannel?
  private static var deviceChannel: FlutterMethodChannel?
  private static var pendingOpenFiles: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ActentOpenFiles"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "actent/open_files",
      binaryMessenger: registrar.messenger()
    )
    Self.openFilesChannel = channel
    if !Self.pendingOpenFiles.isEmpty {
      channel.invokeMethod("openFiles", arguments: Self.pendingOpenFiles)
      Self.pendingOpenFiles.removeAll()
    }
    let workChannel = FlutterMethodChannel(
      name: "actent/ios_work",
      binaryMessenger: registrar.messenger()
    )
    Self.iosWorkChannel = workChannel
    workChannel.setMethodCallHandler { call, result in
      guard call.method == "openUrl",
            let arguments = call.arguments as? [String: Any],
            let value = arguments["url"] as? String,
            let url = URL(string: value) else {
        result(FlutterError(code: "invalid_url", message: "A valid URL is required", details: nil))
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }
    let deviceChannel = FlutterMethodChannel(
      name: "actent/device",
      binaryMessenger: registrar.messenger()
    )
    Self.deviceChannel = deviceChannel
    deviceChannel.setMethodCallHandler { call, result in
      guard call.method == "displayName" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(UIDevice.current.name)
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "actent",
       url.host == "share",
       let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "paths" })?.value {
      Self.deliverOpenFiles(value.split(separator: ",").map(String.init))
      return true
    }
    Self.deliverOpenFiles([url.path])
    return true
  }

  private static func deliverOpenFiles(_ paths: [String]) {
    if let channel = openFilesChannel {
      DispatchQueue.main.async {
        channel.invokeMethod("openFiles", arguments: paths)
      }
    } else {
      pendingOpenFiles.append(contentsOf: paths)
    }
  }
}
