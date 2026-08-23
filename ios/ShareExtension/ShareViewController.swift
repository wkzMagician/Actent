import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
  override func isContentValid() -> Bool { true }

  override func didSelectPost() {
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    let appGroupURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.example.actent"
    )
    let directory = appGroupURL?.appendingPathComponent("Shared", isDirectory: true)
    if let directory {
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil
      )
    }

    let waitGroup = DispatchGroup()
    var paths: [String] = []
    let lock = NSLock()
    for (index, provider) in providers.enumerated() {
      waitGroup.enter()
      let finish: (URL?) -> Void = { destination in
        if let destination {
          lock.lock()
          paths.append(destination.path)
          lock.unlock()
        }
        waitGroup.leave()
      }
      if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
        provider.loadItem(
          forTypeIdentifier: UTType.plainText.identifier,
          options: nil
        ) { item, error in
          guard error == nil,
                let text = item as? String,
                let directory else {
            finish(nil)
            return
          }
          let destination = directory.appendingPathComponent(
            "share-\(UUID().uuidString)-\(index).actent-text"
          )
          do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            finish(destination)
          } catch {
            finish(nil)
          }
        }
        continue
      }
      if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
          item, error in
          let sharedURL = (item as? URL) ?? (item as? NSURL).map { $0 as URL }
          guard error == nil, let sharedURL, let directory else {
            finish(nil)
            return
          }
          let destination = directory.appendingPathComponent(
            "share-\(UUID().uuidString)-\(index).actent-url"
          )
          do {
            try sharedURL.absoluteString.write(
              to: destination,
              atomically: true,
              encoding: .utf8
            )
            finish(destination)
          } catch {
            finish(nil)
          }
        }
        continue
      }
      let type = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        defer { waitGroup.leave() }
        guard let url, error == nil, let directory else { return }
        let destination = directory.appendingPathComponent(
          "share-\(UUID().uuidString)-\(index)-\(url.lastPathComponent)"
        )
        do {
          try FileManager.default.copyItem(at: url, to: destination)
          lock.lock()
          paths.append(destination.path)
          lock.unlock()
        } catch {
          // The host app will simply receive fewer files.
        }
      }
    }
    waitGroup.notify(queue: .main) {
      var components = URLComponents()
      components.scheme = "actent"
      components.host = "share"
      components.queryItems = paths.map { URLQueryItem(name: "path", value: $0) }
      if let url = components.url, !paths.isEmpty {
        self.extensionContext?.open(url) { _ in
          self.extensionContext?.completeRequest(returningItems: nil)
        }
      } else {
        self.extensionContext?.completeRequest(returningItems: nil)
      }
    }
  }

  override func configurationItems() -> [Any]! { [] }
}
