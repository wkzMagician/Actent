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
      let type = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
        defer { waitGroup.leave() }
        guard error == nil, let directory else { return }
        let destination = directory.appendingPathComponent(
          "share-\(UUID().uuidString)-\(index)"
        )
        do {
          if let url = item as? URL {
            try FileManager.default.copyItem(at: url, to: destination)
          } else if let text = item as? String {
            try text.write(to: destination, atomically: true, encoding: .utf8)
          } else if let data = item as? Data {
            try data.write(to: destination)
          } else {
            return
          }
          lock.lock()
          paths.append(destination.path)
          lock.unlock()
        } catch {
          // The host app will simply receive fewer files.
        }
      }
    }
    waitGroup.notify(queue: .main) {
      let encoded = paths
        .map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "" }
        .joined(separator: ",")
      if let url = URL(string: "actent://share?paths=\(encoded)"), !paths.isEmpty {
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
