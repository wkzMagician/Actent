import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static var openFilesChannel: FlutterMethodChannel?
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
