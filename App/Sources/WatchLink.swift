import Foundation
import WatchConnectivity

/// The iPhone's end of the watch app: sends the study whenever it changes and applies the grades
/// that come back. The watch never saves anything for good; its grades live here, and go on to
/// iCloud like any other change.
@MainActor
final class WatchLink: NSObject {
    private let library: Library
    private var pushTask: Task<Void, Never>?
    /// The watch's latest changes already applied, kept so a repeat isn't applied again.
    private var applied: [UUID] {
        get { UserDefaults.standard.stringArray(forKey: "watchAppliedChanges")?.compactMap(UUID.init(uuidString:)) ?? [] }
        set { UserDefaults.standard.set(newValue.suffix(100).map(\.uuidString), forKey: "watchAppliedChanges") }
    }

    init(library: Library) {
        self.library = library
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The library changed: tells the watch in a moment, once a burst of saves has finished.
    func noteChange() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            push()
        }
    }

    private func snapshotData() -> Data? {
        guard !library.isWaitingForFile else { return nil }
        let defaults = UserDefaults.standard
        let year = defaults.integer(forKey: "selectedYear")
        let term = defaults.integer(forKey: "selectedTerm")
        return try? library.watchSnapshot(year: year == 0 ? nil : year, term: term == 0 ? nil : term, appliedChanges: applied).encodedForTransfer()
    }

    private func push() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = snapshotData() else { return }
        try? session.updateApplicationContext([WatchMessage.snapshot: data])
    }

    private func receive(_ data: Data) {
        // The file can't be read until the iPhone's first unlock: the watch sends it again later.
        library.reloadIfNeeded()
        guard !library.isWaitingForFile, let change = try? Library.fileDecoder.decode(WatchChange.self, from: data) else { return }
        if !applied.contains(change.id) {
            library.apply(change)
            applied.append(change.id)
        }
        noteChange()
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Back to work with the newly paired watch.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchMessage.change] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchMessage.change] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping @Sendable ([String: Any]) -> Void) {
        let change = message[WatchMessage.change] as? Data
        Task { @MainActor in
            if let change { self.receive(change) }
            replyHandler(self.snapshotData().map { [WatchMessage.snapshot: $0] } ?? [:])
        }
    }
}
