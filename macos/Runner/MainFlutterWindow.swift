import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static var openFilesChannel: FlutterMethodChannel?
  private static var pendingOpenFiles: [String] = []

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "actent/open_files",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MainFlutterWindow.openFilesChannel = channel
    if !MainFlutterWindow.pendingOpenFiles.isEmpty {
      channel.invokeMethod("openFiles", arguments: MainFlutterWindow.pendingOpenFiles)
      MainFlutterWindow.pendingOpenFiles.removeAll()
    }

    super.awakeFromNib()
  }

  static func deliverOpenFiles(_ paths: [String]) {
    if let channel = openFilesChannel {
      DispatchQueue.main.async {
        channel.invokeMethod("openFiles", arguments: paths)
      }
    } else {
      pendingOpenFiles.append(contentsOf: paths)
    }
  }
}
