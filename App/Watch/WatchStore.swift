import Foundation
import Observation
import WatchConnectivity

/// The watch's copy of the study and its grades on their way to the iPhone. What's on screen is the
/// iPhone's last snapshot with those grades on top, so a new one shows straight away and survives a
/// snapshot that's older than it. A grade stays in the outbox until a snapshot confirms it.
@MainActor
@Observable
final class WatchStore: NSObject {
    private struct Saved: Codable {
        var snapshot: WatchSnapshot?
        var outbox: [WatchChange] = []
    }

    private(set) var snapshot: WatchSnapshot?
    /// The period on screen, once picked here; the iPhone's until then.
    var pickedPeriod: Period?
    private var outbox: [WatchChange] = []
    private var saved: WatchSnapshot?

    @ObservationIgnored private let fileURL = URL.applicationSupportDirectory.appending(path: "watch-study.json")

    /// Grades still going up: the row can say so.
    var unsentCount: Int { outbox.count }

    override init() {
        super.init()
        if let data = try? Data(contentsOf: fileURL), let file = try? Library.fileDecoder.decode(Saved.self, from: data) {
            saved = file.snapshot
            outbox = file.outbox
        }
        rebuild()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var periods: [Period] {
        guard let snapshot else { return [] }
        return Period.all(in: snapshot.courses, degree: snapshot.degree)
    }

    var period: Period? {
        let periods = periods
        if let pickedPeriod, periods.contains(pickedPeriod) { return pickedPeriod }
        if let snapshot, let year = snapshot.year {
            let phone = Period(year: year, term: snapshot.term)
            if periods.contains(phone) { return phone }
        }
        return periods.first
    }

    func record(id: SubjectRecord.ID) -> SubjectRecord? {
        snapshot?.courses.lazy.flatMap(\.subjects).first { $0.id == id }
    }

    /// A grade entered here: on screen now, on the iPhone as soon as it can get there.
    func setEntry(_ entry: GradeEntry?, forLeaf leaf: String, in recordID: SubjectRecord.ID, session: Convocatoria) {
        let change = WatchChange(recordID: recordID, leaf: leaf, session: session, entry: entry)
        outbox.append(change)
        persist()
        rebuild()
        send(change)
    }

    private func rebuild() {
        guard var snapshot = saved else {
            self.snapshot = nil
            return
        }
        for change in outbox { change.apply(to: &snapshot.courses) }
        self.snapshot = snapshot
    }

    private func persist() {
        guard let data = try? Library.fileEncoder.encode(Saved(snapshot: saved, outbox: outbox)) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    fileprivate func receive(_ data: Data) {
        guard let new = try? WatchSnapshot.decoded(from: data) else { return }
        saved = new
        outbox.removeAll { new.appliedChanges.contains($0.id) }
        persist()
        rebuild()
    }

    private func send(_ change: WatchChange) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              let data = try? Library.fileEncoder.encode(change) else { return }
        let payload = [WatchMessage.change: data]
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        // Wakes the iPhone app and answers with a snapshot that confirms it.
        session.sendMessage(payload) { reply in
            guard let data = reply[WatchMessage.snapshot] as? Data else { return }
            Task { @MainActor in self.receive(data) }
        } errorHandler: { _ in
            session.transferUserInfo(payload)
        }
    }

    /// When the iPhone can be reached: anything unconfirmed goes again, and a fresh study comes back.
    fileprivate func catchUp() {
        let session = WCSession.default
        if let data = session.receivedApplicationContext[WatchMessage.snapshot] as? Data { receive(data) }
        guard session.isReachable else { return }
        for change in outbox { send(change) }
        session.sendMessage([WatchMessage.refresh: true]) { reply in
            guard let data = reply[WatchMessage.snapshot] as? Data else { return }
            Task { @MainActor in self.receive(data) }
        } errorHandler: { _ in }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.catchUp() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.catchUp() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchMessage.snapshot] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
}
