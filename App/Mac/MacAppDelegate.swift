import AppKit

/// Closing the window ends the app, and there's no background time after that: what's waiting goes
/// up on the way out instead of staying here until the next launch.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// How long leaving can wait for iCloud: without a connection it shouldn't hold the app open.
    private static let longestWait = Duration.seconds(8)

    var cloud: CloudSync?
    private var hasReplied = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.registerForRemoteNotifications()
    }

    /// Left to itself, `CKSyncEngine` answers a push whenever the system's scheduler gets round to it.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { await cloud?.refresh() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let cloud, cloud.hasPendingChanges else { return .terminateNow }
        Task {
            await cloud.syncNow()
            reply(to: sender)
        }
        Task {
            try? await Task.sleep(for: Self.longestWait)
            reply(to: sender)
        }
        return .terminateLater
    }

    private func reply(to sender: NSApplication) {
        guard !hasReplied else { return }
        hasReplied = true
        sender.reply(toApplicationShouldTerminate: true)
    }
}
