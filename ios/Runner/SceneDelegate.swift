import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard let controller = window?.rootViewController as? FlutterViewController else { return }

    let attestationChannel = FlutterMethodChannel(
      name: "com.najime.attestation",
      binaryMessenger: controller.binaryMessenger
    )
    attestationChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getAttestationKey":
        result(AppAttestationKey.shared.getRawKey())
      case "getDeviceId":
        result(AppAttestationKey.shared.getDeviceId())
      case "sign":
        if let data = call.arguments as? String {
          result(AppAttestationKey.shared.sign(data))
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
