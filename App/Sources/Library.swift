import Engine
import Foundation
import Observation

/// A grade as the user typed it: `value` out of `outOf`, not necessarily the leaf's own scale —
/// e.g. a teacher grades out of 2 while the model's leaf is out of 10. A percentage is stored out
/// of 100 and a letter as its value out of 10, with `letter` kept to show it back.
struct GradeEntry: Codable, Equatable {
    var value: Double
    var outOf: Double
    var letter: String?
}

/// The two exam sittings of an academic year.
enum Convocatoria: String, CaseIterable, Identifiable {
    case ordinary, extraordinary

    var id: Self { self }

    var label: String {
        switch self {
        case .ordinary: "Ordinaria"
        case .extraordinary: "Extraordinaria"
        }
    }
}

/// One subject in a course: its (editable) evaluation tree plus the grades entered for it, keyed
/// by leaf name, for each sitting.
///
/// The extraordinary sitting reuses the same tree: a part the guide keeps (`Grade.recovery`) carries
/// its ordinary grade over unless re-entered; anything else (usually the exam) starts empty.
struct SubjectRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var subject: Subject
    var entries: [String: GradeEntry]
    var extraordinaryEntries: [String: GradeEntry]
    var ordinaryExamDate: Date?
    var extraordinaryExamDate: Date?

    init(id: UUID = UUID(), subject: Subject, entries: [String: GradeEntry] = [:]) {
        self.id = id
        self.subject = subject
        self.entries = entries
        self.extraordinaryEntries = [:]
    }

    /// Fields added after the first release decode as empty, so older libraries keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        subject = try container.decode(Subject.self, forKey: .subject)
        entries = try container.decodeIfPresent([String: GradeEntry].self, forKey: .entries) ?? [:]
        extraordinaryEntries = try container.decodeIfPresent([String: GradeEntry].self, forKey: .extraordinaryEntries) ?? [:]
        ordinaryExamDate = try container.decodeIfPresent(Date.self, forKey: .ordinaryExamDate)
        extraordinaryExamDate = try container.decodeIfPresent(Date.self, forKey: .extraordinaryExamDate)
    }

    /// The sitting worth showing by default: the extraordinary one once anything's been entered there.
    var activeSession: Convocatoria {
        extraordinaryEntries.isEmpty ? .ordinary : .extraordinary
    }

    func examDate(for session: Convocatoria) -> Date? {
        switch session {
        case .ordinary: ordinaryExamDate
        case .extraordinary: extraordinaryExamDate
        }
    }

    /// Whether this leaf's ordinary grade carries over to the extraordinary sitting.
    func keepsForExtraordinary(_ leaf: String) -> Bool {
        switch subject.root.leaf(named: leaf)?.asGrade?.recovery {
        case .notRecoverable, .savedForExtraordinary, .savedForNextYear, .partiallyRecoverableInFinal: true
        case .recoverableInExtraordinary, nil: false
        }
    }

    func entry(for leaf: String, in session: Convocatoria) -> GradeEntry? {
        switch session {
        case .ordinary:
            entries[leaf]
        case .extraordinary:
            extraordinaryEntries[leaf] ?? (keepsForExtraordinary(leaf) ? entries[leaf] : nil)
        }
    }

    /// True when the extraordinary sitting is showing a grade carried over from the ordinary one.
    func isCarriedOver(_ leaf: String, in session: Convocatoria) -> Bool {
        session == .extraordinary && extraordinaryEntries[leaf] == nil && keepsForExtraordinary(leaf) && entries[leaf] != nil
    }

    func entries(for session: Convocatoria) -> [String: GradeEntry] {
        let leaves = subject.root.allLeafNames()
        return Dictionary(uniqueKeysWithValues: leaves.compactMap { leaf in entry(for: leaf, in: session).map { (leaf, $0) } })
    }
}

struct Course: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var subjects: [SubjectRecord]
}

/// Every course, subject and grade, persisted as one JSON file in Application Support. A stopgap
/// ahead of the brief's SwiftData model (§6); every mutation goes through a method here so there's
/// exactly one place that saves.
@MainActor
@Observable
final class Library {
    private(set) var courses: [Course]
    /// Example subjects already added once, so a new one shipped later (e.g. a newly extracted
    /// syllabus) reaches existing installs without re-adding ones the user already has.
    @ObservationIgnored private var offeredExamples: Set<String>
    @ObservationIgnored private let fileURL: URL

    private struct Snapshot: Codable {
        var courses: [Course]
        var offeredExamples: Set<String>
    }

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "library.json")) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        if let data, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            courses = snapshot.courses
            offeredExamples = snapshot.offeredExamples
        } else if let data, let courses = try? JSONDecoder().decode([Course].self, from: data) {
            // Files saved before `offeredExamples` existed: whatever they hold was offered.
            self.courses = courses
            offeredExamples = Set(courses.flatMap(\.subjects).map(\.subject.name))
        } else {
            courses = []
            offeredExamples = []
        }
        addMissingExamples(migratingLegacyGrades: true)
        save()
    }

    func record(id: SubjectRecord.ID) -> SubjectRecord? {
        courses.lazy.flatMap(\.subjects).first { $0.id == id }
    }

    func setEntry(_ entry: GradeEntry?, forLeaf leaf: String, in recordID: SubjectRecord.ID, session: Convocatoria) {
        mutateRecord(recordID) { record in
            switch session {
            case .ordinary: record.entries[leaf] = entry
            case .extraordinary: record.extraordinaryEntries[leaf] = entry
            }
        }
    }

    func setExamDate(_ date: Date?, for session: Convocatoria, in recordID: SubjectRecord.ID) {
        mutateRecord(recordID) { record in
            switch session {
            case .ordinary: record.ordinaryExamDate = date
            case .extraordinary: record.extraordinaryExamDate = date
            }
        }
    }

    func update(_ record: SubjectRecord) {
        mutateRecord(record.id) { $0 = record }
    }

    func clearAllGrades() {
        for course in courses.indices {
            for subject in courses[course].subjects.indices {
                courses[course].subjects[subject].entries = [:]
                courses[course].subjects[subject].extraordinaryEntries = [:]
            }
        }
        save()
    }

    func restoreExamples() {
        courses = []
        offeredExamples = []
        addMissingExamples(migratingLegacyGrades: false)
        save()
    }

    private func mutateRecord(_ id: SubjectRecord.ID, _ body: (inout SubjectRecord) -> Void) {
        for course in courses.indices {
            if let index = courses[course].subjects.firstIndex(where: { $0.id == id }) {
                body(&courses[course].subjects[index])
                save()
                return
            }
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Snapshot(courses: courses, offeredExamples: offeredExamples))
                .write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Couldn't save the library: \(error)")
        }
    }

    /// The reference subjects, grouped by the year their syllabus places them in.
    private static let exampleCatalog: [(course: String, subjects: [Subject])] = [
        ("1.º curso", [.estadistica, .matematicaDiscreta, .algebra, .administracionGestionOrganizaciones, .informaticaBasica]),
        ("2.º curso", [.estructuraComputadores, .sistemasOperativos, .disenoSoftware, .paradigmasProgramacion]),
    ]

    /// Adds every catalog subject not offered before to its course, creating the course if needed.
    private func addMissingExamples(migratingLegacyGrades: Bool) {
        for (courseName, subjects) in Self.exampleCatalog {
            for subject in subjects where !offeredExamples.contains(subject.name) {
                let record = SubjectRecord(
                    subject: subject,
                    entries: migratingLegacyGrades ? Self.legacyEntries(for: subject.name) : [:]
                )
                if let index = courses.firstIndex(where: { $0.name == courseName }) {
                    courses[index].subjects.append(record)
                } else {
                    courses.append(Course(name: courseName, subjects: [record]))
                }
                offeredExamples.insert(subject.name)
            }
        }
    }

    /// Grades saved by the earlier `UserDefaults`-only version, so nothing typed before is lost.
    private static func legacyEntries(for subjectName: String) -> [String: GradeEntry] {
        guard let data = UserDefaults.standard.data(forKey: "com.migueltaibo.mark.grades.\(subjectName)"),
              let entries = try? JSONDecoder().decode([String: GradeEntry].self, from: data)
        else { return [:] }
        return entries
    }
}

/// What the engine says about one subject given what's been entered — the numbers the home card,
/// the detail screen and the record tab show.
struct SubjectProgress {
    let worst: Double
    let best: Double
    let threshold: Double
    let status: PassStatus
    /// Average needed on everything pending (out of 10) to reach `threshold`, when still in play.
    let neededAverage: Double?
    let enteredCount: Int
    let leafCount: Int
    let inputs: [String: Double]

    var isComplete: Bool { leafCount > 0 && enteredCount == leafCount }

    let session: Convocatoria

    init(_ record: SubjectRecord, session: Convocatoria? = nil) {
        let session = session ?? record.activeSession
        let root = record.subject.root
        let inputs = Self.inputs(for: root, entries: record.entries(for: session))
        self.session = session
        let threshold = root.minimumThreshold ?? 5
        let status = root.status(inputs)

        self.inputs = inputs
        self.worst = root.evaluate(inputs, pendingFraction: 0)
        self.best = root.evaluate(inputs, pendingFraction: 1)
        self.threshold = threshold
        self.status = status
        self.neededAverage = status == .possible ? root.neededFraction(inputs, target: threshold).map { $0 * 10 } : nil
        self.enteredCount = inputs.count
        self.leafCount = root.allLeafNames().count
    }

    /// Entries converted from whatever scale the user typed them on to each leaf's own scale.
    private static func inputs(for root: Node, entries: [String: GradeEntry]) -> [String: Double] {
        entries.reduce(into: [:]) { result, pair in
            let (name, entry) = pair
            guard entry.outOf > 0, let max = root.leaf(named: name)?.scaleMax else { return }
            result[name] = min(Swift.max(entry.value / entry.outOf * max, 0), max)
        }
    }
}
