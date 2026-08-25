import Flutter
import UIKit

/// External input is consumed from Dartloom's App Group inbox when Flutter
/// starts and whenever the application becomes active. URLs and files opened
/// by another application use the ordinary scene lifecycle below.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      IosOpenUrlExternalInputBridge.shared.enqueueOrWake(context.url)
    }
    for activity in connectionOptions.userActivities {
      if let url = activity.webpageURL {
        IosOpenUrlExternalInputBridge.shared.enqueue(url)
      }
    }
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for context in URLContexts {
      IosOpenUrlExternalInputBridge.shared.enqueueOrWake(context.url)
    }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL {
      IosOpenUrlExternalInputBridge.shared.enqueue(url)
    }
  }
}
