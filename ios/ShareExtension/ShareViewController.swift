import UIKit
import UniformTypeIdentifiers

/// Standard iOS Share Extension handoff.
///
/// The extension only copies the incoming providers into the App Group inbox.
/// The containing app owns the task/workflow picker and consumes the batch
/// after iOS brings it to the foreground.
final class ShareViewController: UIViewController {
  private let appGroupIdentifier = "group.com.example.actent"
  private let inboxDirectoryName = "DartloomExternalInput"
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    importAttachments()
  }

  private func importAttachments() {
    let providers = (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty else {
      cancel(with: CocoaError(.fileReadNoSuchFile))
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var inputs = [[String: Any]]()
    var firstError: Error?
    for provider in providers {
      group.enter()
      load(provider: provider) { input, error in
        lock.lock()
        if let input {
          inputs.append(input)
        } else if firstError == nil {
          firstError = error ?? CocoaError(.fileReadUnknown)
        }
        lock.unlock()
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      guard firstError == nil, !inputs.isEmpty else {
        self.cancel(with: firstError ?? CocoaError(.fileReadUnknown))
        return
      }
      do {
        try self.writeBatch(items: inputs)
        self.openContainingApp()
      } catch {
        self.cancel(with: error)
      }
    }
  }

  private func openContainingApp() {
    var components = URLComponents()
    components.scheme = "actent"
    components.host = "external-input"
    guard let url = components.url else {
      extensionContext?.completeRequest(returningItems: nil)
      return
    }
    extensionContext?.open(url) { [weak self] _ in
      // The App Group batch is durable even when iOS declines to foreground
      // the containing app. It will be consumed on the next app launch.
      DispatchQueue.main.async {
        self?.extensionContext?.completeRequest(returningItems: nil)
      }
    }
  }

  private func cancel(with error: Error) {
    extensionContext?.cancelRequest(withError: error)
  }

  private func load(
    provider: NSItemProvider,
    completion: @escaping ([String: Any]?, Error?) -> Void
  ) {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
        [weak self] item, error in
        guard let self,
              error == nil,
              let url = (item as? URL) ?? (item as? NSURL).map({ $0 as URL }) else {
          completion(nil, error ?? CocoaError(.fileReadUnknown))
          return
        }
        do {
          completion(try self.retainSharedFile(url, typeIdentifier: UTType.data.identifier), nil)
        } catch {
          completion(nil, error)
        }
      }
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
        item, error in
        guard error == nil, let text = item as? String else {
          completion(nil, error ?? CocoaError(.fileReadUnknown))
          return
        }
        completion(["type": "text", "text": text], nil)
      }
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
        item, error in
        let url = (item as? URL) ?? (item as? NSURL).map({ $0 as URL })
        guard error == nil, let url else {
          completion(nil, error ?? CocoaError(.fileReadUnknown))
          return
        }
        completion(["type": "url", "url": url.absoluteString], nil)
      }
      return
    }
    let fallback = provider.registeredTypeIdentifiers.first {
      UTType($0)?.conforms(to: .data) == true
    } ?? UTType.data.identifier
    provider.loadFileRepresentation(forTypeIdentifier: fallback) { [weak self] url, error in
      guard let self, error == nil, let url else {
        completion(nil, error ?? CocoaError(.fileReadUnknown))
        return
      }
      do {
        completion(try self.retainSharedFile(url, typeIdentifier: fallback), nil)
      } catch {
        completion(nil, error)
      }
    }
  }

  private func retainSharedFile(
    _ source: URL,
    typeIdentifier: String
  ) throws -> [String: Any] {
    let destination = try fileDestination(suggestedName: source.lastPathComponent)
    let accessing = source.startAccessingSecurityScopedResource()
    defer {
      if accessing { source.stopAccessingSecurityScopedResource() }
    }
    try FileManager.default.copyItem(at: source, to: destination)
    var input: [String: Any] = [
      "type": "file",
      "path": destination.path,
      "name": source.lastPathComponent,
    ]
    if let mimeType = UTType(typeIdentifier)?.preferredMIMEType {
      input["mimeType"] = mimeType
    }
    return input
  }

  private func writeBatch(items: [[String: Any]]) throws {
    let directories = try inboxDirectories()
    let data = try JSONSerialization.data(
      withJSONObject: ["items": items, "source": "share"]
    )
    try data.write(
      to: directories.batches.appendingPathComponent("\(UUID().uuidString).json"),
      options: .atomic
    )
  }

  private func fileDestination(suggestedName: String) throws -> URL {
    let directories = try inboxDirectories()
    let sanitized = suggestedName
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\0", with: "")
    return directories.files.appendingPathComponent(
      "\(UUID().uuidString)-\(sanitized.isEmpty ? "attachment" : sanitized)"
    )
  }

  private func inboxDirectories() throws -> (batches: URL, files: URL) {
    guard let group = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let root = group.appendingPathComponent(inboxDirectoryName, isDirectory: true)
    let batches = root.appendingPathComponent("batches", isDirectory: true)
    let files = root.appendingPathComponent("files", isDirectory: true)
    try FileManager.default.createDirectory(at: batches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    return (batches, files)
  }
}
