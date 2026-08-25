import Flutter
import UIKit
import UniformTypeIdentifiers

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
    IosOpenUrlExternalInputBridge.shared.enqueueOrWake(url)
    return true
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    guard let url = userActivity.webpageURL else {
      return false
    }
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
    ActentIosClipboardBridge.register(with: registrar)
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
    if url.isFileURL {
      do {
        let retained = try retainIncomingFile(url)
        enqueue(
          item: [
            "type": "file",
            "path": retained.path,
            "name": retained.lastPathComponent,
          ],
          source: "openWith"
        )
      } catch {
        // The original URL may be security-scoped or transient. Do not queue a
        // path which will fail after Flutter has finished starting.
      }
      return
    }
    enqueue(item: ["type": "url", "url": url.absoluteString], source: "deepLink")
  }

  func enqueueOrWake(_ url: URL) {
    guard url.scheme?.lowercased() == "actent",
          url.host?.lowercased() == "external-input" else {
      enqueue(url)
      return
    }
    // The Share Extension has already persisted the batch in the App Group.
    // This URL only asks the containing app to foreground and consume it.
  }

  private func enqueue(item: [String: Any], source: String) {
    enqueue(batch: ["items": [item], "source": source])
  }

  private func enqueue(batch: [String: Any]) {
    lock.lock()
    let sink = eventSink
    if sink == nil {
      pending.append(batch)
    }
    lock.unlock()
    sink?(batch)
  }

  private func retainIncomingFile(_ source: URL) throws -> URL {
    let manager = FileManager.default
    let directory = try manager.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appendingPathComponent("ActentIncoming", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = source.lastPathComponent
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\0", with: "")
    let destination = directory.appendingPathComponent(
      "\(UUID().uuidString)-\(name.isEmpty ? "attachment" : name)"
    )
    let accessing = source.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        source.stopAccessingSecurityScopedResource()
      }
    }
    try manager.copyItem(at: source, to: destination)
    return destination
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

/// Reads file-backed pasteboard providers while their temporary URLs remain
/// valid and retains them inside Actent before returning to Flutter.
final class ActentIosClipboardBridge {
  private let pasteboard = UIPasteboard.general

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ActentIosClipboardBridge()
    let channel = FlutterMethodChannel(
      name: "actent/ios_clipboard",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      instance.read(afterChangeToken: arguments?["afterChangeToken"] as? String, result: result)
    }
  }

  private func read(afterChangeToken: String?, result: @escaping FlutterResult) {
    let token = String(pasteboard.changeCount)
    if afterChangeToken == token {
      result(["kind": "unchanged"])
      return
    }
    let providers = pasteboard.itemProviders
    guard !providers.isEmpty else {
      result(fallbackResult(token: token))
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var inputs = [[String: Any]]()
    for provider in providers {
      group.enter()
      load(provider: provider) { input in
        if let input {
          lock.lock()
          inputs.append(input)
          lock.unlock()
        }
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      if inputs.isEmpty {
        result(self.fallbackResult(token: token))
      } else {
        result([
          "kind": "content",
          "changeToken": token,
          "batch": ["items": inputs, "source": "clipboard"],
        ])
      }
    }
  }

  private func load(provider: NSItemProvider, completion: @escaping ([String: Any]?) -> Void) {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
        [weak self] item, error in
        guard let self, error == nil, let url = Self.url(from: item) else {
          completion(nil)
          return
        }
        completion(try? self.retainFile(url))
      }
      return
    }
    if let type = provider.registeredTypeIdentifiers.first(where: {
      guard let value = UTType($0) else { return false }
      return value.conforms(to: .data) &&
        !value.conforms(to: .text) &&
        !value.conforms(to: .url)
    }) {
      provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
        guard let self, error == nil, let url else {
          completion(nil)
          return
        }
        completion(try? self.retainFile(url))
      }
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
        let url = Self.url(from: item)
        completion(error == nil ? url.map { ["type": "url", "url": $0.absoluteString] } : nil)
      }
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
        completion(error == nil ? (item as? String).map { ["type": "text", "text": $0] } : nil)
      }
      return
    }
    completion(nil)
  }

  private func retainFile(_ source: URL) throws -> [String: Any] {
    let manager = FileManager.default
    let directory = try manager.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("ActentClipboard", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = source.lastPathComponent
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\0", with: "")
    let destination = directory.appendingPathComponent(
      "\(UUID().uuidString)-\(name.isEmpty ? "attachment" : name)"
    )
    let accessing = source.startAccessingSecurityScopedResource()
    defer { if accessing { source.stopAccessingSecurityScopedResource() } }
    try manager.copyItem(at: source, to: destination)
    return ["type": "file", "path": destination.path, "name": source.lastPathComponent]
  }

  private func fallbackResult(token: String) -> [String: Any] {
    if let url = pasteboard.url {
      if url.isFileURL, let file = try? retainFile(url) {
        return contentResult(token: token, item: file)
      }
      return contentResult(token: token, item: ["type": "url", "url": url.absoluteString])
    }
    if let text = pasteboard.string, !text.isEmpty {
      return contentResult(token: token, item: ["type": "text", "text": text])
    }
    return ["kind": "empty", "changeToken": token]
  }

  private func contentResult(token: String, item: [String: Any]) -> [String: Any] {
    [
      "kind": "content",
      "changeToken": token,
      "batch": ["items": [item], "source": "clipboard"],
    ]
  }

  private static func url(from item: Any?) -> URL? {
    if let url = item as? URL { return url }
    if let url = item as? NSURL { return url as URL }
    if let value = item as? String { return URL(string: value) }
    if let data = item as? Data,
       let value = String(data: data, encoding: .utf8) {
      return URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
  }
}
