import Engine
import Foundation

/// A grade entered (or cleared) on the watch, on its way to the iPhone. It's sent until the iPhone
/// confirms it, so it can arrive twice; its id makes that harmless.
struct WatchChange: Codable, Equatable, Identifiable {
    var id = UUID()
    var recordID: SubjectRecord.ID
    var leaf: String
    var session: Convocatoria
    var entry: GradeEntry?

    func apply(to courses: inout [Course]) {
        for course in courses.indices {
            guard let index = courses[course].subjects.firstIndex(where: { $0.id == recordID }) else { continue }
            switch session {
            case .ordinary: courses[course].subjects[index].entries[leaf] = entry
            case .extraordinary: courses[course].subjects[index].extraordinaryEntries[leaf] = entry
            }
            return
        }
    }
}

/// What the watch shows: the current study as the iPhone has it. Travels compressed in a `Data`,
/// since the system caps what it carries, and the watch keeps the last one to open without the iPhone.
struct WatchSnapshot: Codable, Equatable {
    var degree: DegreeSettings
    var hasStudy: Bool
    var courses: [Course]
    /// The period the iPhone was last on, where the watch starts.
    var year: Int?
    var term: Int?
    /// The watch's changes already in `courses`; it drops them from what it still has to send.
    var appliedChanges: [UUID] = []

    /// About what the system lets through in one application context.
    static let sizeLimit = 60_000

    func encoded() throws -> Data {
        try (Library.fileEncoder.encode(self) as NSData).compressed(using: .lzfse) as Data
    }

    static func decoded(from data: Data) throws -> WatchSnapshot {
        try Library.fileDecoder.decode(WatchSnapshot.self, from: (data as NSData).decompressed(using: .lzfse) as Data)
    }

    /// The compressed copy to send: everything if it fits, else just the year the iPhone is on.
    func encodedForTransfer() throws -> Data {
        let data = try encoded()
        guard data.count > Self.sizeLimit, let year else { return data }
        var trimmed = self
        trimmed.courses = courses.filter { $0.year == year }
        return try trimmed.encoded()
    }

    /// The subjects of a period, in the order the home screen lists them.
    func subjects(in period: Period) -> [SubjectRecord] {
        let subjects = courses.first { $0.year == period.year }?.subjects ?? []
        guard period.term != nil else { return subjects.filter { $0.term == nil && $0.isPerTerm } }
        return subjects.filter { $0.term == period.term || ($0.term == nil && $0.isPerTerm) }
            + subjects.filter { $0.term == nil && !$0.isPerTerm }
    }
}

/// How the watch and the iPhone label what they send each other.
enum WatchMessage {
    static let snapshot = "snapshot"
    static let change = "change"
    /// The watch asks for a fresh snapshot.
    static let refresh = "refresh"
}

extension Library {
    /// The current study as the watch needs it.
    func watchSnapshot(year: Int?, term: Int?, appliedChanges: [UUID]) -> WatchSnapshot {
        WatchSnapshot(degree: degree, hasStudy: hasStudy, courses: courses, year: year, term: term, appliedChanges: appliedChanges)
    }

    /// A grade from the watch. A note renamed or removed on the iPhone meanwhile is dropped.
    func apply(_ change: WatchChange) {
        guard let root = record(id: change.recordID).map({ $0.root(for: change.session) }),
              root.allLeafNames().contains(change.leaf) else { return }
        setEntry(change.entry, forLeaf: change.leaf, in: change.recordID, session: change.session)
    }
}
