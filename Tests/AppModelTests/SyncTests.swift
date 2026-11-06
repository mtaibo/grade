import Engine
import Foundation
import Testing
@testable import AppModel

/// When changes go up to iCloud.
struct SyncScheduleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func oneChangeGoesUpAfterAPause() {
        var schedule = SyncSchedule()
        #expect(schedule.nextSync == nil)
        schedule.recordChange(at: start)
        #expect(schedule.nextSync == start.addingTimeInterval(SyncSchedule.delay))
    }

    @Test func typingKeepsItWaitingForThePause() {
        var schedule = SyncSchedule()
        schedule.recordChange(at: start)
        schedule.recordChange(at: start.addingTimeInterval(1))
        #expect(schedule.nextSync == start.addingTimeInterval(1 + SyncSchedule.delay))
    }

    @Test func constantChangesStillGoUp() {
        var schedule = SyncSchedule()
        for second in 0..<60 { schedule.recordChange(at: start.addingTimeInterval(Double(second))) }
        #expect(schedule.nextSync == start.addingTimeInterval(SyncSchedule.longestWait))
    }

    @Test func aSyncClearsItAndItSurvivesClosingTheApp() throws {
        var schedule = SyncSchedule()
        for step in 0..<8 { schedule.recordChange(at: start.addingTimeInterval(Double(step) * 10)) }
        let copy = try JSONDecoder().decode(SyncSchedule.self, from: JSONEncoder().encode(schedule))
        #expect(copy == schedule)
        schedule.reset()
        #expect(!schedule.hasPendingChanges)
        #expect(schedule.nextSync == nil)
    }
}

/// Two devices through iCloud, with what's in iCloud played by a plain dictionary.
@MainActor
struct CloudMergeTests {
    private static func subject(_ name: String = "Física") -> Subject {
        Subject(name: name, ectsCredits: 6, root: .group(Group(name: name, combination: .weightedAverage, children: [
            WeightedChild(weight: 0.4, node: .grade(Grade(name: "Prácticas"))),
            WeightedChild(weight: 0.6, node: .grade(Grade(name: "Examen", isFinalExam: true))),
        ])))
    }

    /// A device: its library and what it knows of iCloud.
    @MainActor
    final class Device {
        let sandbox = Sandbox()
        let library: Library
        var ledger = SyncLedger()

        init() {
            library = sandbox.open()
            ledger.hasFetched = true
        }

        /// Sends what differs, like `CloudSync.syncNow`.
        func push(to cloud: inout [String: Data]) throws {
            let items = try library.syncItems()
            let pending = ledger.pendingChanges(for: items)
            for name in pending.saves {
                guard let item = items[name], case .data(let data) = item.content else { continue }
                cloud[name] = data
                ledger.entries[name] = .init(version: item.version)
            }
            for name in pending.deletes {
                cloud[name] = nil
                ledger.entries[name] = nil
            }
        }

        /// Reads everything in iCloud, like `CloudSync.apply`.
        func pull(from cloud: [String: Data]) throws {
            let items = try library.syncItems()
            var changes: [CloudChange] = cloud.map { .save(name: $0.key, data: $0.value) }
            changes += ledger.entries.keys.filter { cloud[$0] == nil && ledger.acceptsRemoteDelete(of: $0, items: items) }.map { .delete(name: $0) }
            for name in ledger.entries.keys where cloud[name] == nil { ledger.entries[name] = nil }
            library.applyFromCloud(changes)
            let updated = try library.syncItems()
            for name in cloud.keys { ledger.entries[name] = updated[name].map { .init(version: $0.version) } }
        }
    }

    private func sameContents(_ a: Library, _ b: Library) throws -> Bool {
        try a.syncItems().mapValues(\.version) == b.syncItems().mapValues(\.version)
    }

    @Test func aChangeOnOneDeviceReachesTheOther() throws {
        var cloud: [String: Data] = [:]
        let (phone, other) = (Device(), Device())
        let id = phone.library.addSubject(Self.subject(), year: 2, term: 3)
        phone.library.setEntry(GradeEntry(value: 8, outOf: 10), forLeaf: "Examen", in: id, session: .ordinary)
        try phone.push(to: &cloud)
        try other.pull(from: cloud)
        #expect(other.library.record(id: id)?.entries["Examen"]?.value == 8)
        #expect(other.library.year(of: id) == 2)
        #expect(try sameContents(phone.library, other.library))

        phone.library.setEntry(GradeEntry(value: 9, outOf: 10), forLeaf: "Examen", in: id, session: .ordinary)
        try phone.push(to: &cloud)
        try other.pull(from: cloud)
        #expect(other.library.record(id: id)?.entries["Examen"]?.value == 9)
    }

    @Test func onlyWhatChangedGoesUp() throws {
        var cloud: [String: Data] = [:]
        let phone = Device()
        let first = phone.library.addSubject(Self.subject("A"), year: 1, term: 1)
        phone.library.addSubject(Self.subject("B"), year: 1, term: 1)
        try phone.push(to: &cloud)
        #expect(phone.ledger.pendingChanges(for: try phone.library.syncItems()).saves.isEmpty)
        phone.library.setEntry(GradeEntry(value: 5, outOf: 10), forLeaf: "Examen", in: first, session: .ordinary)
        #expect(phone.ledger.pendingChanges(for: try phone.library.syncItems()).saves == [SyncItem.subjectName(first)])
    }

    @Test func reorderingOnlySendsTheStudyAndTravels() throws {
        var cloud: [String: Data] = [:]
        let (phone, other) = (Device(), Device())
        let a = phone.library.addSubject(Self.subject("A"), year: 1, term: 1)
        let b = phone.library.addSubject(Self.subject("B"), year: 1, term: 1)
        try phone.push(to: &cloud)
        try other.pull(from: cloud)
        phone.library.reorderSubjects([b], before: a, among: [a, b])
        #expect(phone.ledger.pendingChanges(for: try phone.library.syncItems()).saves == [SyncItem.studyName])
        try phone.push(to: &cloud)
        try other.pull(from: cloud)
        #expect(other.library.courses[0].subjects.map(\.id) == [b, a])
    }

    @Test func deletingAndArchivingTravel() throws {
        var cloud: [String: Data] = [:]
        let (phone, other) = (Device(), Device())
        let a = phone.library.addSubject(Self.subject("A"), year: 1, term: 1)
        let b = phone.library.addSubject(Self.subject("B"), year: 1, term: 1)
        try phone.push(to: &cloud)
        try other.pull(from: cloud)

        phone.library.deleteSubject(id: a)
        try phone.push(to: &cloud)
        try other.pull(from: cloud)
        #expect(other.library.record(id: a) == nil)
        #expect(other.library.record(id: b) != nil)

        phone.library.archiveCurrentStudy()
        try phone.push(to: &cloud)
        try other.pull(from: cloud)
        #expect(other.library.record(id: b) == nil)
        #expect(other.library.archives.first?.subjectIDs == [b])
        #expect(!other.library.hasStudy)
    }

    @Test func guidesTravel() throws {
        let (phone, other) = (Device(), Device())
        let id = phone.library.addSubject(Self.subject(), year: 1, term: 1)
        try phone.library.setGuide(Data("%PDF".utf8), for: id)
        let item = try #require(try phone.library.syncItems()[SyncItem.guideName(id)])
        guard case .file(let file) = item.content else {
            Issue.record("A guide is a file")
            return
        }
        other.library.applyFromCloud([.save(name: item.name, data: try Data(contentsOf: file))])
        #expect(other.library.guideIDs == [id])
        other.library.applyFromCloud([.delete(name: item.name)])
        #expect(other.library.guideIDs.isEmpty)
    }

    @Test func eraseTakesEverythingOutOfICloud() throws {
        var cloud: [String: Data] = [:]
        let phone = Device()
        phone.library.addSubject(Self.subject(), year: 1, term: 1)
        try phone.push(to: &cloud)
        #expect(cloud.keys.contains { $0.hasPrefix("subject-") })
        phone.library.eraseAll()
        try phone.push(to: &cloud)
        #expect(!cloud.keys.contains { $0.hasPrefix("subject-") })
    }

    @Test func comingFromICloudIsNotReportedAsAChange() throws {
        var cloud: [String: Data] = [:]
        let (phone, other) = (Device(), Device())
        phone.library.addSubject(Self.subject(), year: 1, term: 1)
        try phone.push(to: &cloud)
        var reports: [Bool] = []
        other.library.onChange = { reports.append($0) }
        try other.pull(from: cloud)
        #expect(reports == [true])
        #expect(other.library.wasRestoredFromCloud)
        #expect(other.ledger.pendingChanges(for: try other.library.syncItems()).saves.isEmpty)
    }

    @Test func aSaveThatChangesNothingIsNotAChange() {
        let device = Device()
        var reports = 0
        let id = device.library.addSubject(Self.subject(), year: 1, term: 1)
        device.library.onChange = { _ in reports += 1 }
        device.library.setEntry(GradeEntry(value: 5, outOf: 10), forLeaf: "Examen", in: id, session: .ordinary)
        device.library.setEntry(GradeEntry(value: 5, outOf: 10), forLeaf: "Examen", in: id, session: .ordinary)
        #expect(reports == 1)
    }

    @Test func aRecordFromANewerVersionIsLeftOut() {
        let device = Device()
        let id = device.library.addSubject(Self.subject(), year: 1, term: 1)
        device.library.applyFromCloud([.save(name: SyncItem.subjectName(id), data: Data("{ not json".utf8))])
        #expect(device.library.record(id: id) != nil)
    }

    // The rules for a record changed on both sides.

    private func item(_ name: String, version: String) -> SyncItem {
        SyncItem(name: name, file: URL(filePath: "/dev/null"), version: version)
    }

    @Test func theNewestEditWins() {
        var ledger = SyncLedger(hasFetched: true)
        ledger.entries["a"] = .init(version: "old")
        ledger.lastChange = Date(timeIntervalSinceReferenceDate: 100)
        let modified = ["a": item("a", version: "new")]
        #expect(!ledger.acceptsRemoteSave(of: "a", modifiedAt: Date(timeIntervalSinceReferenceDate: 50), items: modified, hasOwnSubjects: true))
        #expect(ledger.acceptsRemoteSave(of: "a", modifiedAt: Date(timeIntervalSinceReferenceDate: 150), items: modified, hasOwnSubjects: true))
        // No changes here: whatever comes, comes.
        let clean = ["a": item("a", version: "old")]
        #expect(ledger.acceptsRemoteSave(of: "a", modifiedAt: Date(timeIntervalSinceReferenceDate: 50), items: clean, hasOwnSubjects: true))
    }

    @Test func anEditBringsBackWhatAnotherDeviceDeleted() {
        var ledger = SyncLedger(hasFetched: true)
        ledger.entries["a"] = .init(version: "old")
        #expect(!ledger.acceptsRemoteDelete(of: "a", items: ["a": item("a", version: "new")]))
        #expect(ledger.acceptsRemoteDelete(of: "a", items: ["a": item("a", version: "old")]))
    }

    @Test func aNewDeviceTakesWhatICloudHasOverItsFirstAnswers() {
        var ledger = SyncLedger()
        ledger.lastChange = Date(timeIntervalSinceReferenceDate: 100)
        let answered = [SyncItem.studyName: item(SyncItem.studyName, version: "answers")]
        #expect(ledger.acceptsRemoteSave(of: SyncItem.studyName, modifiedAt: Date(timeIntervalSinceReferenceDate: 50), items: answered, hasOwnSubjects: false))
        #expect(!ledger.acceptsRemoteSave(of: SyncItem.studyName, modifiedAt: Date(timeIntervalSinceReferenceDate: 50), items: answered, hasOwnSubjects: true))
    }

    @Test func anUnreadableFileIsNoticed() throws {
        let sandbox = Sandbox()
        try Data("{ not json".utf8).write(to: sandbox.file)
        #expect(sandbox.open().lostItsFile)
    }
}

/// What travels between the iPhone and the watch.
@MainActor
struct WatchLinkTests {
    private func makeLibrary() -> (Sandbox, Library, SubjectRecord.ID) {
        let sandbox = Sandbox()
        let library = sandbox.open()
        let id = library.addSubject(Subject(name: "Física", ectsCredits: 6, root: .group(Group(name: "Física", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.4, node: .grade(Grade(name: "Prácticas"))),
            WeightedChild(weight: 0.6, node: .grade(Grade(name: "Examen", isFinalExam: true))),
        ]))), year: 2, term: 3)
        return (sandbox, library, id)
    }

    @Test func theSnapshotSurvivesTheTrip() throws {
        let (sandbox, library, _) = makeLibrary()
        _ = sandbox
        let snapshot = library.watchSnapshot(year: 2, term: 3, appliedChanges: [UUID()])
        #expect(try WatchSnapshot.decoded(from: snapshot.encoded()) == snapshot)
    }

    @Test func aWholeDegreeFitsInOneContext() throws {
        let sandbox = Sandbox()
        let library = sandbox.open()
        // Every reference subject, as many as a whole degree's first two years.
        for (index, subject) in Subject.all.enumerated() { library.addSubject(subject, year: index < 8 ? 1 : 2, term: index % 2 + 1) }
        let data = try library.watchSnapshot(year: 1, term: 1, appliedChanges: []).encodedForTransfer()
        #expect(data.count < WatchSnapshot.sizeLimit)
    }

    @Test func aGradeFromTheWatchReachesTheLibrary() {
        let (sandbox, library, id) = makeLibrary()
        _ = sandbox
        var reports: [Bool] = []
        library.onChange = { reports.append($0) }
        let change = WatchChange(recordID: id, leaf: "Examen", session: .ordinary, entry: GradeEntry(value: 7.5, outOf: 10))
        library.apply(change)
        library.apply(change)
        #expect(library.record(id: id)?.entries["Examen"]?.value == 7.5)
        // It goes on to iCloud like any other change, and only one change it is.
        #expect(reports == [false])
        library.apply(WatchChange(recordID: id, leaf: "Examen", session: .ordinary, entry: nil))
        #expect(library.record(id: id)?.entries["Examen"] == nil)
    }

    @Test func aRenamedNoteOrDeletedSubjectIsDropped() {
        let (sandbox, library, id) = makeLibrary()
        _ = sandbox
        library.apply(WatchChange(recordID: id, leaf: "Ya no existe", session: .ordinary, entry: GradeEntry(value: 7, outOf: 10)))
        #expect(library.record(id: id)?.entries.isEmpty == true)
        library.apply(WatchChange(recordID: UUID(), leaf: "Examen", session: .ordinary, entry: GradeEntry(value: 7, outOf: 10)))
    }

    @Test func aChangeShowsOnTheWatchBeforeTheIPhoneConfirmsIt() {
        let (sandbox, library, id) = makeLibrary()
        _ = sandbox
        var courses = library.courses
        WatchChange(recordID: id, leaf: "Examen", session: .extraordinary, entry: GradeEntry(value: 6, outOf: 10)).apply(to: &courses)
        #expect(courses[0].subjects[0].extraordinaryEntries["Examen"]?.value == 6)
    }

    @Test func theWatchListsTheSubjectsOfAPeriodLikeHome() {
        let sandbox = Sandbox()
        let library = sandbox.open()
        let subject = Subject(name: "X", ectsCredits: 6, root: .grade(Grade(name: "Nota")))
        let term = library.addSubject(subject, year: 1, term: 1)
        let annual = library.addSubject(subject, year: 1, term: nil)
        let other = library.addSubject(subject, year: 1, term: 2)
        let snapshot = library.watchSnapshot(year: nil, term: nil, appliedChanges: [])
        let ids = snapshot.subjects(in: Period(year: 1, term: 1)).map(\.id)
        #expect(ids == [term, annual])
        #expect(!ids.contains(other))
    }
}
