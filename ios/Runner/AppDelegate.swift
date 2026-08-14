import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register attestation method channel
    let controller = window?.rootViewController as! FlutterViewController
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
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
