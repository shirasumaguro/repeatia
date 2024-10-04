import UIKit
import Flutter
import AudioToolbox

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let CHANNEL = "com.shirasumaguro.repeatia/beep"
  private let TAG = "AppDelegate"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let beepChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)
    
    print("\(TAG): didFinishLaunchingWithOptions called")
    
    beepChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      print("\(self.TAG): Method call received: \(call.method)")
      if call.method == "playBeepok" {
        print("\(self.TAG): playBeepok method called")
        AudioServicesPlaySystemSound(1256) // 1105 is the system sound ID for a short beep sound
        result(nil)
        print("\(self.TAG): Beep sound played (ok)")
      } else if call.method == "playBeepng" {
        print("\(self.TAG): playBeepng method called")
        //AudioServicesPlaySystemSound(1254) // 1200 is the system sound ID for a different beep sound
        AudioServicesPlaySystemSound(1256) // 1200 is the system sound ID for a different beep sound
        result(nil)
        print("\(self.TAG): Beep sound played (ng)")
      } else {
        print("\(self.TAG): Method not implemented: \(call.method)")
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
