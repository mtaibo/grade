import CryptoKit
import Foundation

/// When the changes waiting for iCloud go up: as soon as they pause, so other devices see them
/// straight away without a request for every key typed. Pure and `Codable`, so a pending sync
/// survives the app being closed.
struct SyncSchedule: Codable, Equatable {
    /// The pause after a change that means it's finished: a grade typed digit by digit saves on each key.
    static let delay: TimeInterval = 0.3
    /// Nothing waits longer than this after its change, however busy the app stays.
    static let longestWait: TimeInterval = 2

    private(set) var firstChange: Date?
    private var lastChange: Date?

    var hasPendingChanges: Bool { firstChange != nil }

    mutating func recordChange(at date: Date) {
        if firstChange == nil { firstChange = date }
        lastChange = date
    }

    /// When the waiting changes should go up, `nil` when there are none.
    var nextSync: Date? {
        guard let firstChange else { return nil }
        let settled = (lastChange ?? firstChange).addingTimeInterval(Self.delay)
        return min(settled, firstChange.addingTimeInterval(Self.longestWait))
    }

    mutating func reset() { self = SyncSchedule() }
}

/// One piece of the library as iCloud sees it: its record's name and a version that changes with
/// its contents. Each subject, archived study and guide is a record of its own, plus one for the
/// study's settings, so a change sends just that piece and two devices only clash over the same one.
struct SyncItem: Equatable {
    enum Content: Equatable {
        case data(Data)
        case file(URL)
    }

    let name: String
    let version: String
    let content: Content

    static let studyName = "study"
    /// CloudKit allows 1 MB for a record's own fields; anything near that goes as a file.
    static let largestInline = 512 * 1024

    static func subjectName(_ id: UUID) -> String { "subject-\(id.uuidString)" }
    static func archiveName(_ id: UUID) -> String { "archive-\(id.uuidString)" }
    static func guideName(_ id: UUID) -> String { "guide-\(id.uuidString)" }

    init(name: String, data: Data) {
        self.name = name
        version = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        content = .data(data)
    }

    init(name: String, file: URL, version: String) {
        self.name = name
        self.version = version
        content = .file(file)
    }

    /// The contents, when they're small enough to go inside the record.
    var inlineData: Data? {
        guard case .data(let data) = content, data.count <= Self.largestInline else { return nil }
        return data
    }
}

/// What the "study" record holds.
struct SyncedStudy: Codable, Equatable {
    var degree: DegreeSettings
    var hasStudy: Bool
    var selections: [CustomSelection]
    /// Subjects in the order they're shown, so reordering doesn't resend every one of them.
    var order: [UUID]
}

/// What a subject's record holds.
struct SyncedSubject: Codable, Equatable {
    var year: Int
    var record: SubjectRecord
}

/// A change that came from iCloud, already read. Applied with `Library.applyFromCloud(_:)`.
enum CloudChange: Equatable {
    case save(name: String, data: Data)
    case delete(name: String)
}

/// What this device last knows to be in iCloud, by record. Comparing it with the library's items
/// tells what's changed, so the sync doesn't depend on every edit reporting what it touched.
struct SyncLedger: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var version: String
        /// The record's CloudKit metadata, needed to save over it.
        var systemFields: Data?
    }

    var entries: [String: Entry] = [:]
    /// When something last changed here: what a clash with another device's edit is decided by.
    var lastChange: Date?
    /// `false` until this device has read what iCloud already had. Nothing goes up before that, and
    /// with nothing here of its own, what's up there wins even over answers just given in the
    /// first-launch questions: a new iPhone gets the old one's study.
    var hasFetched = false

    /// What should go up: items new or different from what iCloud has, and records whose item is gone.
    func pendingChanges(for items: [String: SyncItem]) -> (saves: [String], deletes: [String]) {
        let saves = items.values.filter { entries[$0.name]?.version != $0.version }.map(\.name)
        let deletes = entries.keys.filter { items[$0] == nil }
        return (saves.sorted(), deletes.sorted())
    }

    /// Whether anything here isn't in iCloud yet, whatever happened to the change that caused it.
    func differs(from items: [String: SyncItem]) -> Bool {
        let pending = pendingChanges(for: items)
        return !pending.saves.isEmpty || !pending.deletes.isEmpty
    }

    func isModifiedHere(_ name: String, in items: [String: SyncItem]) -> Bool {
        items[name]?.version != entries[name]?.version
    }

    /// Whether a record edited on another device replaces this one: always, unless this one has
    /// changes that haven't gone up and are newer. The newest edit of the piece wins.
    func acceptsRemoteSave(of name: String, modifiedAt: Date?, items: [String: SyncItem], hasOwnSubjects: Bool) -> Bool {
        if !hasFetched, !hasOwnSubjects { return true }
        guard isModifiedHere(name, in: items), items[name] != nil else { return true }
        guard let modifiedAt, let lastChange else { return modifiedAt != nil }
        return modifiedAt > lastChange
    }

    /// Whether a record deleted on another device goes here too: not if it has changes here that
    /// haven't gone up, which bring it back.
    func acceptsRemoteDelete(of name: String, items: [String: SyncItem]) -> Bool {
        items[name] == nil || !isModifiedHere(name, in: items)
    }
}
