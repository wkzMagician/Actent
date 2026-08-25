import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    IosOpenUrlExternalInputBridge.shared.enqueue(url)
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ActentPlatformConfiguration"
    ) else {
      return
    }
    let workChannel = FlutterMethodChannel(
      name: "actent/ios_work",
      binaryMessenger: registrar.messenger()
    )
    workChannel.setMethodCallHandler { call, result in
      guard call.method == "openUrl",
            let arguments = call.arguments as? [String: Any],
            let value = arguments["url"] as? String,
            let url = URL(string: value) else {
        result(FlutterError(
          code: "invalid_url",
          message: "A valid URL is required",
          details: nil
        ))
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
    deviceChannel.setMethodCallHandler { call, result in
      guard call.method == "displayName" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(UIDevice.current.name)
    }
    IosOpenUrlExternalInputBridge.shared.register(with: registrar)
  }
}

/// Bridges the containing application's regular iOS open-URL lifecycle to
/// Actent's external-input contract. It is intentionally not a LiveContainer
/// adapter: a URL or file opened by LiveContainer is indistinguishable from
/// one opened by any other iOS application.
final class IosOpenUrlExternalInputBridge: NSObject, FlutterStreamHandler {
  static let shared = IosOpenUrlExternalInputBridge()

  private let lock = NSLock()
  private var eventSink: FlutterEventSink?
  private var pending = [[String: Any]]()

  func register(with registrar: FlutterPluginRegistrar) {
    let methods = FlutterMethodChannel(
      name: "actent/ios_open_url/methods",
      binaryMessenger: registrar.messenger()
    )
    methods.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takePending" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.takePending() ?? [])
    }
    let events = FlutterEventChannel(
      name: "actent/ios_open_url/events",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(self)
  }

  func enqueue(_ url: URL) {
    let item: [String: Any]
    let source: String
    if url.isFileURL {
      item = [
        "type": "file",
        "path": url.path,
        "name": url.lastPathComponent,
      ]
      source = "openWith"
    } else {
      item = ["type": "url", "url": url.absoluteString]
      source = "deepLink"
    }
    let batch: [String: Any] = ["items": [item], "source": source]
    lock.lock()
    let sink = eventSink
    if sink == nil {
      pending.append(batch)
    }
    lock.unlock()
    sink?(batch)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    lock.lock()
    eventSink = events
    let queued = pending
    pending.removeAll()
    lock.unlock()
    for batch in queued {
      events(batch)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    lock.lock()
    eventSink = nil
    lock.unlock()
    return nil
  }

  private func takePending() -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    let queued = pending
    pending.removeAll()
    return queued
  }
}
