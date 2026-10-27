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
    /// The degree-wide term (cuatrimestre) it's taught in — 3 is the first term of the second
    /// year. `nil` for a year-long subject. The UI shows it relative to the year (see `Period`).
    var term: Int?
    /// Tile customisation: an SF Symbol name and a `SubjectColor` raw value. `nil` falls back to
    /// ones derived from the subject (see `SubjectStyle`).
    var symbol: String?
    var colorName: String?

    init(id: UUID = UUID(), subject: Subject, entries: [String: GradeEntry] = [:], term: Int? = nil) {
        self.id = id
        self.subject = subject
        self.entries = entries
        self.extraordinaryEntries = [:]
        self.term = term
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
        term = try container.decodeIfPresent(Int.self, forKey: .term)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName)
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

/// One year of the degree and the subjects taken in it.
struct Course: Identifiable, Codable, Equatable {
    var id = UUID()
    var year: Int
    var subjects: [SubjectRecord]

    var name: String { Period(year: year).title }

    init(id: UUID = UUID(), year: Int, subjects: [SubjectRecord] = []) {
        self.id = id
        self.year = year
        self.subjects = subjects
    }

    private enum CodingKeys: String, CodingKey { case id, year, name, subjects }

    /// Older libraries stored only a name like "2.º curso": the year is the number in it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        subjects = try container.decode([SubjectRecord].self, forKey: .subjects)
        if let year = try container.decodeIfPresent(Int.self, forKey: .year) {
            self.year = year
        } else {
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            year = Int(name.filter(\.isNumber)) ?? 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(year, forKey: .year)
        try container.encode(subjects, forKey: .subjects)
    }
}

/// Every course, subject and grade, persisted as one JSON file in Application Support. A stopgap
/// ahead of the brief's SwiftData model (§6); every mutation goes through a method here so there's
/// exactly one place that saves.
@MainActor
@Observable
final class Library {
    private(set) var courses: [Course]
    private(set) var degree = DegreeSettings()
    /// Example subjects already added once, so a new one shipped later (e.g. a newly extracted
    /// syllabus) reaches existing installs without re-adding ones the user already has.
    @ObservationIgnored private var offeredExamples: Set<String>
    @ObservationIgnored private let fileURL: URL

    private struct Snapshot: Codable {
        var courses: [Course]
        var offeredExamples: Set<String>
        /// 2 = subjects carry a `term`. Earlier files have none, so the examples get theirs once.
        var version: Int?
        var degree: DegreeSettings?
    }

    private static let currentVersion = 2

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "library.json")) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        var needsTermMigration = false
        if let data, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            courses = snapshot.courses
            offeredExamples = snapshot.offeredExamples
            degree = snapshot.degree ?? DegreeSettings()
            needsTermMigration = (snapshot.version ?? 0) < Self.currentVersion
        } else if let data, let courses = try? JSONDecoder().decode([Course].self, from: data) {
            // Files saved before `offeredExamples` existed: whatever they hold was offered.
            self.courses = courses
            offeredExamples = Set(courses.flatMap(\.subjects).map(\.subject.name))
            needsTermMigration = true
        } else {
            courses = []
            offeredExamples = []
        }
        if needsTermMigration { assignExampleTerms() }
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

    /// Adds a subject with a single 100 % exam to start from; its evaluation is edited afterwards.
    @discardableResult
    func addSubject(name: String, ects: Double = 6, year: Int, term: Int?) -> SubjectRecord.ID {
        let root = Node.group(Group(name: name, combination: .weightedAverage, children: [
            WeightedChild(weight: 1, node: .grade(Grade(name: "Examen"))),
        ]))
        let record = SubjectRecord(subject: Subject(name: name, ectsCredits: ects, root: root), term: term)
        courses[courseIndex(forYear: year)].subjects.append(record)
        save()
        return record.id
    }

    func move(_ id: SubjectRecord.ID, toYear year: Int, term: Int?) {
        guard var record = record(id: id) else { return }
        record.term = term
        removeSubject(id)
        courses[courseIndex(forYear: year)].subjects.append(record)
        save()
    }

    func setStyle(symbol: String, colorName: String, for id: SubjectRecord.ID) {
        mutateRecord(id) {
            $0.symbol = symbol
            $0.colorName = colorName
        }
    }

    /// Changing how many terms a year has keeps each subject in the same year and in the same
    /// position within it, clamped to the new count (4th of 4 becomes 2nd of 2).
    func updateDegree(_ new: DegreeSettings) {
        let old = degree
        if new.termsPerYear != old.termsPerYear {
            for course in courses.indices {
                for index in courses[course].subjects.indices {
                    guard let term = courses[course].subjects[index].term else { continue }
                    let relative = min(old.relativeTerm(term), new.termsPerYear)
                    courses[course].subjects[index].term = new.absoluteTerm(year: courses[course].year, relative: relative)
                }
            }
        }
        degree = new
        save()
    }

    /// Moves `sources` before `target` (or to the end) among `group` — the subjects one grid shows,
    /// in the order it shows them — leaving every other subject of the year where it was.
    func reorderSubjects(_ sources: [SubjectRecord.ID], before target: SubjectRecord.ID?, among group: [SubjectRecord.ID]) {
        guard let course = courses.firstIndex(where: { $0.subjects.contains { group.contains($0.id) } }) else { return }
        let moving = sources.filter(group.contains)
        var ordered = group.filter { !moving.contains($0) }
        ordered.insert(contentsOf: moving, at: target.flatMap(ordered.firstIndex(of:)) ?? ordered.count)

        let slots = courses[course].subjects.indices.filter { group.contains(courses[course].subjects[$0].id) }
        let byID = Dictionary(uniqueKeysWithValues: slots.map { (courses[course].subjects[$0].id, courses[course].subjects[$0]) })
        for (slot, id) in zip(slots, ordered) { courses[course].subjects[slot] = byID[id]! }
        save()
    }

    func deleteSubject(id: SubjectRecord.ID) {
        removeSubject(id)
        save()
    }

    /// The year each subject currently lives in.
    func year(of id: SubjectRecord.ID) -> Int? {
        courses.first { $0.subjects.contains { $0.id == id } }?.year
    }

    private func removeSubject(_ id: SubjectRecord.ID) {
        for course in courses.indices { courses[course].subjects.removeAll { $0.id == id } }
    }

    /// The course for a year, created (in year order) when it doesn't exist yet.
    private func courseIndex(forYear year: Int) -> Int {
        if let index = courses.firstIndex(where: { $0.year == year }) { return index }
        courses.append(Course(year: year))
        courses.sort { $0.year < $1.year }
        return courses.firstIndex { $0.year == year }!
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
            try JSONEncoder().encode(Snapshot(courses: courses, offeredExamples: offeredExamples, version: Self.currentVersion, degree: degree))
                .write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Couldn't save the library: \(error)")
        }
    }

    /// The reference subjects with the year and degree-wide term their syllabus places them in.
    private static let exampleCatalog: [(year: Int, term: Int, subjects: [Subject])] = [
        (1, 1, [.matematicaDiscreta, .administracionGestionOrganizaciones, .informaticaBasica]),
        (1, 2, [.estadistica, .algebra]),
        (2, 3, [.estructuraComputadores, .sistemasOperativos, .disenoSoftware, .paradigmasProgramacion]),
    ]

    /// Gives the examples already in a pre-term library their term, without touching anything else.
    private func assignExampleTerms() {
        for (_, term, subjects) in Self.exampleCatalog {
            for subject in subjects {
                for course in courses.indices {
                    for index in courses[course].subjects.indices
                    where courses[course].subjects[index].subject.name == subject.name && courses[course].subjects[index].term == nil {
                        courses[course].subjects[index].term = term
                    }
                }
            }
        }
    }

    /// Adds every catalog subject not offered before to its course, creating the course if needed.
    private func addMissingExamples(migratingLegacyGrades: Bool) {
        for (year, term, subjects) in Self.exampleCatalog {
            for subject in subjects where !offeredExamples.contains(subject.name) {
                let record = SubjectRecord(
                    subject: subject,
                    entries: migratingLegacyGrades ? Self.legacyEntries(for: subject.name) : [:],
                    term: term
                )
                courses[courseIndex(forYear: year)].subjects.append(record)
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
