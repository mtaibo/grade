#if os(iOS)
import BackgroundTasks
#endif
import CloudKit
import Foundation
import Observation
import OSLog
#if os(iOS)
import UIKit
#endif

/// Keeps the library in the user's private iCloud database. Changes wait as `SyncSchedule` says and
/// then go up; what other devices send is applied as soon as it comes down. The library stays the
/// source of truth on each device: this only compares it with what iCloud has (`SyncLedger`).
@MainActor
@Observable
final class CloudSync: NSObject {
    enum Status: Equatable {
        case off, checking, noAccount, unavailable, upToDate, waiting, syncing, quotaExceeded
    }

    static let backgroundTask = "com.migueltaibo.grade.sync"
    private static let recordType = "GradeItem"
    private static let zoneID = CKRecordZone.ID(zoneName: "Library", ownerName: CKCurrentUserDefaultName)
    private static let log = Logger(subsystem: "com.migueltaibo.grade", category: "iCloud")

    /// Everything that has to survive the app closing, in one file next to the library.
    private struct State: Codable {
        var isEnabled = true
        var engine: CKSyncEngine.State.Serialization?
        var ledger = SyncLedger()
        var schedule = SyncSchedule()
        var lastSync: Date?
    }

    private(set) var status = Status.checking
    private(set) var lastSync: Date?
    /// When the changes waiting will go up, for the status line.
    private(set) var nextSync: Date?
    var isEnabled: Bool { state.isEnabled }
    var hasPendingChanges: Bool { state.schedule.hasPendingChanges }
    /// How long to wait between asks while on screen; there's no point insisting if iCloud isn't answering.
    var pollInterval: Duration { status == .unavailable ? .seconds(15) : .seconds(3) }

    @ObservationIgnored private let library: Library
    /// Development builds and TestFlight or App Store ones see different iClouds, so what one knows
    /// of its iCloud means nothing to the other.
    #if DEBUG
    @ObservationIgnored private let stateURL = URL.applicationSupportDirectory.appending(path: "icloud-sync.json")
    #else
    @ObservationIgnored private let stateURL = URL.applicationSupportDirectory.appending(path: "icloud-sync-production.json")
    #endif
    @ObservationIgnored private let uploads = URL.temporaryDirectory.appending(path: "CloudUploads")
    @ObservationIgnored private var state = State()
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// The version of each record on its way up, recorded once it's confirmed.
    @ObservationIgnored private var inFlight: [String: String] = [:]
    @ObservationIgnored private var isSyncing = false
    /// iCloud refused a save that uses `payloadData`: until the app closes, everything goes as an
    /// asset, which every schema has. Not stored, so each launch tries the quick way again.
    @ObservationIgnored private var sendsOnlyAssets = false

    init(library: Library) {
        self.library = library
        super.init()
        if let data = try? Data(contentsOf: stateURL), let saved = try? Library.fileDecoder.decode(State.self, from: data) {
            state = saved
        }
        lastSync = state.lastSync
        // Its contents were lost, so what iCloud has isn't a list of things it deleted: read it all back.
        if library.lostItsFile { forgetCloud() }
        try? FileManager.default.removeItem(at: uploads)
        start()
    }

    // MARK: Turning it on and off

    func setEnabled(_ enabled: Bool) {
        guard enabled != state.isEnabled else { return }
        state.isEnabled = enabled
        persist()
        if enabled {
            start()
        } else {
            engine = nil
            timer?.cancel()
            status = .off
            nextSync = nil
        }
    }

    private func start() {
        guard state.isEnabled else {
            status = .off
            return
        }
        status = .checking
        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: "iCloud.com.migueltaibo.grade").privateCloudDatabase,
            stateSerialization: state.engine,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if state.engine == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        Task { await refreshOnOpening() }
    }

    // MARK: Going up

    /// The library changed. Called on every change; changes from iCloud don't come here.
    func noteLocalChange() {
        guard state.isEnabled, !library.isWaitingForFile else { return }
        let now = Date.now
        state.ledger.lastChange = now
        state.schedule.recordChange(at: now)
        persist()
        schedulePending()
        // Changed from the watch with the app in the background: no timer runs there.
        #if os(iOS)
        if UIApplication.shared.applicationState != .active { syncBeforeSuspension() }
        #endif
    }

    /// Sets the timer for the next sync, or syncs if it's already due.
    private func schedulePending() {
        timer?.cancel()
        // Everything goes up the first time, without waiting: it's not a change.
        let isFirstUpload = state.ledger.hasFetched && state.ledger.entries.isEmpty
        guard let next = state.schedule.nextSync ?? (isFirstUpload ? .now : nil) else {
            nextSync = nil
            return
        }
        guard engine != nil else { return }
        nextSync = next
        if status == .upToDate { status = .waiting }
        timer = Task { [weak self] in
            let wait = next.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            // Not in this task: a change made meanwhile cancels the timer, not a sync under way.
            Task { await self?.syncNow() }
        }
    }

    /// Sends everything that differs from what iCloud has, now.
    func syncNow() async {
        guard let engine, !library.isWaitingForFile, !isSyncing else { return }
        isSyncing = true
        var reachedSend = false
        defer {
            isSyncing = false
            // A change made while this one was going up found the sync busy and is still waiting.
            if reachedSend, state.schedule.hasPendingChanges { schedulePending() }
        }
        status = .syncing
        timer?.cancel()
        if !state.ledger.hasFetched { await fetch() }
        guard state.ledger.hasFetched, let items = try? library.syncItems() else {
            if status == .syncing { status = .unavailable }
            return
        }
        let pending = state.ledger.pendingChanges(for: items)
        let id = { (name: String) in CKRecord.ID(recordName: name, zoneID: Self.zoneID) }
        engine.state.add(pendingRecordZoneChanges: pending.saves.map { .saveRecord(id($0)) } + pending.deletes.map { .deleteRecord(id($0)) })
        state.schedule.reset()
        nextSync = nil
        persist()
        reachedSend = true
        do {
            try await engine.sendChanges()
            // Only if every record really went up: a save can fail without the send itself failing.
            guard status == .syncing else { return }
            status = state.schedule.hasPendingChanges ? .waiting : .upToDate
            state.lastSync = .now
            lastSync = state.lastSync
            persist()
        } catch {
            Self.log.error("Send failed: \(error)")
            settleStatus(after: error)
        }
    }

    /// Reads what other devices have sent, and what the account is doing.
    func refresh() async {
        guard engine != nil else { return }
        do {
            let account = try await CKContainer(identifier: "iCloud.com.migueltaibo.grade").accountStatus()
            guard account == .available else {
                status = .noAccount
                return
            }
        } catch {
            status = .unavailable
            return
        }
        let hadFailed = status == .unavailable
        let isReachable = await fetch()
        // iCloud is back: what couldn't go up goes now.
        if hadFailed, isReachable {
            await syncNow()
            return
        }
        if status == .checking { status = state.schedule.hasPendingChanges ? .waiting : .upToDate }
        // Anything left over from the last session, and everything the first time.
        if state.ledger.hasFetched, state.schedule.hasPendingChanges || state.ledger.entries.isEmpty {
            schedulePending()
        }
    }

    /// The app has come on screen. A save that failed left nothing waiting in `SyncSchedule`, so
    /// whatever still differs from iCloud goes up now rather than with the next change.
    func refreshOnOpening() async {
        await refresh()
        guard status == .upToDate, let items = try? library.syncItems(), state.ledger.differs(from: items) else { return }
        await syncNow()
    }

    @discardableResult
    private func fetch() async -> Bool {
        guard let engine else { return false }
        do {
            try await engine.fetchChanges()
            let isFirstFetch = !state.ledger.hasFetched
            state.ledger.hasFetched = true
            state.lastSync = .now
            lastSync = state.lastSync
            // Not on every poll: what really changed is saved when it comes in.
            if isFirstFetch { persist() }
            return true
        } catch {
            Self.log.error("Fetch failed: \(error)")
            settleStatus(after: error)
            return false
        }
    }

    private func settleStatus(after error: Error) {
        switch (error as? CKError)?.code {
        case .notAuthenticated: status = .noAccount
        case .quotaExceeded: status = .quotaExceeded
        default: status = .unavailable
        }
    }

    // MARK: In the background

    /// The app is leaving the screen: what's waiting goes up in the little time iOS still gives it,
    /// with a wake-up asked for in case that isn't enough.
    func syncBeforeSuspension() {
        guard state.schedule.hasPendingChanges else { return }
        #if os(iOS)
        scheduleBackgroundSync()
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        let finish = {
            guard backgroundTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "iCloud", expirationHandler: finish)
        Task {
            await syncNow()
            finish()
        }
        #else
        Task { await syncNow() }
        #endif
    }

    /// iOS stops timers once the app leaves the screen: asks it to wake the app when the sync is due.
    func scheduleBackgroundSync() {
        #if os(iOS)
        guard let next = state.schedule.nextSync else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTask)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTask)
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    /// The system's woken the app for that sync.
    func runBackgroundSync() async {
        if let next = state.schedule.nextSync, next > .now {
            scheduleBackgroundSync()
            await refresh()
        } else if state.schedule.hasPendingChanges {
            await syncNow()
        } else {
            await refresh()
        }
    }

    // MARK: Storing

    private func persist() {
        guard let data = try? Library.fileEncoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// As if this device had never talked to iCloud; the library itself isn't touched.
    private func forgetCloud() {
        state.engine = nil
        state.ledger = SyncLedger()
        state.schedule.reset()
        persist()
    }

    private func encodedSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private func record(named name: String) -> CKRecord {
        if let data = state.ledger.entries[name]?.systemFields,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data),
           let record = CKRecord(coder: coder) {
            return record
        }
        return CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name, zoneID: Self.zoneID))
    }

    /// The item's current contents as a record. What's small goes inside it, which is much quicker
    /// than an asset (uploaded and downloaded apart from the record); the rest goes as a file.
    private func filledRecord(for item: SyncItem) -> CKRecord? {
        let record = record(named: item.name)
        if !sendsOnlyAssets, let data = item.inlineData {
            record["payloadData"] = data as NSData
            record["payload"] = nil
        } else {
            let url: URL
            switch item.content {
            case .file(let file):
                url = file
            case .data(let data):
                url = uploads.appending(path: "\(item.name)-\(item.version).json")
                do {
                    try FileManager.default.createDirectory(at: uploads, withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                } catch {
                    return nil
                }
            }
            record["payload"] = CKAsset(fileURL: url)
            // Not even to clear it: a schema that doesn't have the field can refuse that too.
            if !sendsOnlyAssets { record["payloadData"] = nil }
        }
        record["modifiedAt"] = (state.ledger.lastChange ?? .now) as NSDate
        inFlight[item.name] = item.version
        return record
    }

    // MARK: Coming down

    /// What a record holds, whichever way it went up. The asset goes first: a save inside the record
    /// clears it, while one as an asset can leave the other field behind (an older version of the
    /// app, or `sendsOnlyAssets`).
    private func payload(of record: CKRecord) -> Data? {
        if let url = (record["payload"] as? CKAsset)?.fileURL { return try? Data(contentsOf: url) }
        return record["payloadData"] as? Data
    }

    private func apply(_ modifications: [CKRecord], deletions: [String]) {
        let items = (try? library.syncItems()) ?? [:]
        var changes: [CloudChange] = []
        var names: Set<String> = []
        for record in modifications {
            let name = record.recordID.recordName
            let fields = encodedSystemFields(of: record)
            let accepts = state.ledger.acceptsRemoteSave(
                of: name, modifiedAt: record["modifiedAt"] as? Date, items: items, hasOwnSubjects: library.hasOwnSubjects
            )
            guard accepts, let data = payload(of: record) else {
                // This one's newer and stays: its next save goes over what's just come down.
                state.ledger.entries[name, default: .init(version: "", systemFields: nil)].systemFields = fields
                continue
            }
            changes.append(.save(name: name, data: data))
            names.insert(name)
            state.ledger.entries[name] = .init(version: "", systemFields: fields)
        }
        for name in deletions {
            if state.ledger.acceptsRemoteDelete(of: name, items: items) { changes.append(.delete(name: name)) }
            state.ledger.entries[name] = nil
        }
        library.applyFromCloud(changes)
        // Versions as the library has them now, after normalising, so nothing bounces back up.
        let updated = (try? library.syncItems()) ?? [:]
        for name in names {
            // One it couldn't read (from a newer version) isn't here: that mustn't read as deleted here.
            if let version = updated[name]?.version {
                state.ledger.entries[name]?.version = version
            } else {
                state.ledger.entries[name] = nil
            }
        }
        persist()
    }

    private func handleSent(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        guard let engine else { return }
        for record in event.savedRecords {
            let name = record.recordID.recordName
            let version = inFlight.removeValue(forKey: name) ?? ""
            state.ledger.entries[name] = .init(version: version, systemFields: encodedSystemFields(of: record))
        }
        for id in event.deletedRecordIDs { state.ledger.entries[id.recordName] = nil }
        var retries: [CKSyncEngine.PendingRecordZoneChange] = []
        var pendingZone = false
        // Decided before the loop: every record of the batch was refused for the same reason.
        let canFallBack = !sendsOnlyAssets
        for failure in event.failedRecordSaves {
            let name = failure.record.recordID.recordName
            inFlight[name] = nil
            switch failure.error.code {
            case .serverRecordChanged:
                // Someone else got there first: the newest edit stays, whichever that is.
                guard let server = failure.error.serverRecord else { continue }
                let items = (try? library.syncItems()) ?? [:]
                let accepts = state.ledger.acceptsRemoteSave(
                    of: name, modifiedAt: server["modifiedAt"] as? Date, items: items, hasOwnSubjects: true
                )
                if accepts {
                    apply([server], deletions: [])
                } else {
                    state.ledger.entries[name, default: .init(version: "", systemFields: nil)].systemFields = encodedSystemFields(of: server)
                    retries.append(.saveRecord(failure.record.recordID))
                }
            case .zoneNotFound:
                pendingZone = true
                state.ledger.entries[name]?.systemFields = nil
                retries.append(.saveRecord(failure.record.recordID))
            case .unknownItem:
                state.ledger.entries[name]?.systemFields = nil
                retries.append(.saveRecord(failure.record.recordID))
            case .quotaExceeded:
                status = .quotaExceeded
            case .invalidArguments where canFallBack, .serverRejectedRequest where canFallBack:
                // Most likely a Production schema that doesn't have `payloadData` yet. Asked for
                // once, like a change: `syncNow` picks it up as soon as this send ends.
                Self.log.error("Going back to assets, iCloud refused \(name): \(failure.error)")
                sendsOnlyAssets = true
                state.schedule.recordChange(at: .now)
                retries.append(.saveRecord(failure.record.recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled, .requestRateLimited:
                // The engine tries these again by itself.
                break
            default:
                Self.log.error("Couldn't save \(name): \(failure.error)")
                status = .unavailable
            }
        }
        if pendingZone { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))]) }
        if !retries.isEmpty { engine.state.add(pendingRecordZoneChanges: retries) }
        persist()
    }
}

extension CloudSync: CKSyncEngineDelegate {
    /// CKSyncEngine stops the app if it's asked to fetch or send from inside one of its own events,
    /// so whatever does that runs apart from the event (detached: a plain `Task` would count as inside).
    private func afterThisEvent(_ work: @escaping @MainActor () async -> Void) {
        Task.detached { await work() }
    }

    private func restart() {
        engine = nil
        start()
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            state.engine = update.stateSerialization
            persist()
        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                afterThisEvent { await self.refresh() }
            case .signOut, .switchAccounts:
                // The study stays on the device, and goes up to whichever account comes next.
                forgetCloud()
                afterThisEvent { self.restart() }
            @unknown default:
                break
            }
        case .fetchedDatabaseChanges(let changes):
            guard let deletion = changes.deletions.first(where: { $0.zoneID == Self.zoneID }) else { break }
            forgetCloud()
            if deletion.reason == .purged {
                // The user deleted Grade's data from iCloud's settings: it shouldn't go straight back up.
                setEnabled(false)
            } else {
                afterThisEvent { self.restart() }
            }
        case .fetchedRecordZoneChanges(let changes):
            apply(changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID.recordName))
        case .sentRecordZoneChanges(let sent):
            handleSent(sent)
        case .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let items = (try? library.syncItems()) ?? [:]
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await MainActor.run {
                if let record = items[id.recordName].flatMap({ self.filledRecord(for: $0) }) { return record }
                // Gone since it was queued: it'll go up as a delete if iCloud has it.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                return nil
            }
        }
    }
}
