import UIKit
import UniformTypeIdentifiers

/// A deterministic Share Extension UI which imports immediately.
final class ShareViewController: UIViewController {
  private let appGroupIdentifier = "group.com.example.actent"
  private let inboxDirectoryName = "DartloomExternalInput"
  private let statusLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .large)
  private let openButton = UIButton(type: .system)
  private let closeButton = UIButton(type: .system)
  private var started = false
  private var importedItems = [[String: Any]]()
  private var storedInInbox = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    preferredContentSize = CGSize(width: 420, height: 260)
    statusLabel.text = "Importing into Actent…"
    statusLabel.font = .preferredFont(forTextStyle: .headline)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    openButton.setTitle("Open Actent", for: .normal)
    openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    openButton.isHidden = true
    openButton.addTarget(self, action: #selector(openActent), for: .touchUpInside)
    closeButton.setTitle("Close", for: .normal)
    closeButton.isHidden = true
    closeButton.addTarget(self, action: #selector(closeExtension), for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [
      activityIndicator, statusLabel, openButton, closeButton,
    ])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    activityIndicator.startAnimating()
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
      finishWithError("Nothing was provided to Actent.")
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
      guard !inputs.isEmpty else {
        self.finishWithError(
          "Actent could not read this item. For files, verify that the signed app and Share Extension both keep the App Group entitlement."
        )
        return
      }
      self.importedItems = inputs
      do {
        try self.writeBatch(items: inputs)
        self.storedInInbox = true
        self.finishAndOpen(payload: nil)
      } catch {
        if inputs.allSatisfy({ ($0["type"] as? String) != "file" }),
           let payload = self.encodedPayload(items: inputs) {
          self.finishAndOpen(payload: payload)
        } else {
          self.finishWithError(
            "The shared container is unavailable. Re-sign Actent and its Share Extension with the App Group \(self.appGroupIdentifier)."
          )
        }
      }
    }
  }

  private func finishAndOpen(payload: String?) {
    activityIndicator.stopAnimating()
    statusLabel.text = "Imported. Opening Actent…"
    extensionContext?.open(actentURL(payload: payload)) { [weak self] opened in
      DispatchQueue.main.async {
        guard let self else { return }
        if opened {
          self.extensionContext?.completeRequest(returningItems: nil)
        } else {
          self.statusLabel.text = "Imported successfully. Tap Open Actent to continue."
          self.openButton.isHidden = false
          self.closeButton.isHidden = false
        }
      }
    }
  }

  private func finishWithError(_ message: String) {
    activityIndicator.stopAnimating()
    statusLabel.text = message
    openButton.isHidden = false
    closeButton.isHidden = false
  }

  @objc private func openActent() {
    let transferable = !storedInInbox &&
      importedItems.allSatisfy { ($0["type"] as? String) != "file" }
    let payload = transferable ? encodedPayload(items: importedItems) : nil
    extensionContext?.open(actentURL(payload: payload)) { [weak self] opened in
      if opened { self?.extensionContext?.completeRequest(returningItems: nil) }
    }
  }

  @objc private func closeExtension() {
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func actentURL(payload: String?) -> URL {
    var components = URLComponents()
    components.scheme = "actent"
    components.host = "external-input"
    if let payload {
      components.queryItems = [URLQueryItem(name: "payload", value: payload)]
    }
    return components.url!
  }

  private func encodedPayload(items: [[String: Any]]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: ["items": items]) else {
      return nil
    }
    return data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func load(provider: NSItemProvider, completion: @escaping ([String: Any]?) -> Void) {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
        [weak self] item, error in
        let url = (item as? URL) ?? (item as? NSURL).map { $0 as URL }
        guard let self, let url, error == nil else {
          completion(nil)
          return
        }
        completion(try? self.retainSharedFile(url, typeIdentifier: UTType.data.identifier))
      }
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
        completion(error == nil ? url.map { ["type": "url", "url": $0.absoluteString] } : nil)
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
        completion(try self.retainSharedFile(url, typeIdentifier: typeIdentifier))
      } catch {
        completion(nil)
      }
    }
  }

  private func retainSharedFile(_ source: URL, typeIdentifier: String) throws -> [String: Any] {
    let destination = try fileDestination(suggestedName: source.lastPathComponent)
    let accessing = source.startAccessingSecurityScopedResource()
    defer { if accessing { source.stopAccessingSecurityScopedResource() } }
    try FileManager.default.copyItem(at: source, to: destination)
    var input: [String: Any] = [
      "type": "file", "path": destination.path, "name": source.lastPathComponent,
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
