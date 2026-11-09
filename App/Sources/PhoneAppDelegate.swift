#if os(iOS)
import UIKit

/// Left to itself, `CKSyncEngine` answers a push whenever the system's scheduler gets round to it:
/// heard here, what another device has just sent is read straight away.
@MainActor
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    var cloud: CloudSync?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await cloud?.refresh()
        return .newData
    }
}
#endif
