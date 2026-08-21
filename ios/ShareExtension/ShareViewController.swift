import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
  override func isContentValid() -> Bool { true }

  override func didSelectPost() {
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    let group = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.example.actent"
    )
    let directory = group?.appendingPathComponent("Shared", isDirectory: true)
    if let directory {
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil
      )
    }

    let group = DispatchGroup()
    var paths: [String] = []
    let lock = NSLock()
    for (index, provider) in providers.enumerated() {
      group.enter()
      let type = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        defer { group.leave() }
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
          // Some providers expose a temporary URL that disappears before the
          // copy completes. The host app will simply receive fewer files.
        }
      }
    }
    group.notify(queue: .main) {
      let encoded = paths
        .map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "" }
        .joined(separator: ",")
      if let url = URL(string: "actent://share?paths=\(encoded)") {
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
