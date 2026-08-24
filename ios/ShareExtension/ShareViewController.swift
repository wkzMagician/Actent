import Social
import UniformTypeIdentifiers

/// App configuration for Dartloom's iOS external-input inbox protocol.
///
/// The extension persists a generic batch and exits. It deliberately never
/// tries to open or otherwise launch the containing application.
final class ShareViewController: SLComposeServiceViewController {
  private let appGroupIdentifier = "group.com.example.actent"
  private let inboxDirectoryName = "DartloomExternalInput"

  override func isContentValid() -> Bool { true }

  override func didSelectPost() {
    let providers = (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
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
      try? self.writeBatch(items: inputs)
      self.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  override func configurationItems() -> [Any]! { [] }

  private func load(
    provider: NSItemProvider,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      loadFile(
        provider: provider,
        typeIdentifier: UTType.fileURL.identifier,
        completion: completion
      )
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
        item, error in
        completion(error == nil ? (item as? String).map { ["type": "text", "text": $0] } : nil)
      }
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
        item, error in
        let url = (item as? URL) ?? (item as? NSURL).map { $0 as URL }
        completion(
          error == nil ? url.map { ["type": "url", "url": $0.absoluteString] } : nil
        )
      }
      return
    }
    let fallback = provider.registeredTypeIdentifiers.first {
      UTType($0)?.conforms(to: .data) == true
    } ?? UTType.data.identifier
    loadFile(provider: provider, typeIdentifier: fallback, completion: completion)
  }

  private func loadFile(
    provider: NSItemProvider,
    typeIdentifier: String,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
      guard let self, let url, error == nil else {
        completion(nil)
        return
      }
      do {
        let destination = try self.fileDestination(suggestedName: url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        var input: [String: Any] = [
          "type": "file",
          "path": destination.path,
          "name": url.lastPathComponent,
        ]
        if let mimeType = UTType(typeIdentifier)?.preferredMIMEType {
          input["mimeType"] = mimeType
        }
        completion(input)
      } catch {
        completion(nil)
      }
    }
  }

  private func writeBatch(items: [[String: Any]]) throws {
    guard !items.isEmpty else { return }
    let directories = try inboxDirectories()
    let data = try JSONSerialization.data(
      withJSONObject: ["items": items, "source": "share"],
      options: []
    )
    try data.write(
      to: directories.batches.appendingPathComponent("\(UUID().uuidString).json"),
      options: .atomic
    )
  }

  private func fileDestination(suggestedName: String) throws -> URL {
    let directories = try inboxDirectories()
    let sanitized = suggestedName.replacingOccurrences(of: "/", with: "_")
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
    try FileManager.default.createDirectory(
      at: batches,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: files,
      withIntermediateDirectories: true
    )
    return (batches, files)
  }
}
