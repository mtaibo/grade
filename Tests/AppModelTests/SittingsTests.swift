import Engine
import Foundation
import Testing
@testable import AppModel

/// What carries over to the extraordinary sitting, a sitting with its own evaluation, "no
/// presentado", "matrícula de honor", requirements and how the transcript rounds.
struct SittingsTests {
    /// Labs 40 % (two lab notes) and a final exam 60 %.
    static func record(labs: Recovery? = nil, lab1: Recovery? = nil) -> SubjectRecord {
        let labsGroup = Node.group(Group(name: "Prácticas", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.5, node: .grade(Grade(name: "P1", recovery: lab1))),
            WeightedChild(weight: 0.5, node: .grade(Grade(name: "P2"))),
        ], recovery: labs))
        var record = SubjectRecord(subject: Subject(name: "Física", ectsCredits: 6, root: .group(Group(name: "Física", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.4, node: labsGroup),
            WeightedChild(weight: 0.6, node: .grade(Grade(name: "Examen", isFinalExam: true))),
        ], minimum: Minimum(threshold: 5, consequence: .fails)))))
        record.entries = ["P1": GradeEntry(value: 3, outOf: 10), "P2": GradeEntry(value: 5, outOf: 10), "Examen": GradeEntry(value: 2, outOf: 10)]
        return record
    }

    @Test func byDefaultEverythingButTheExamCarriesOver() {
        let record = Self.record()
        #expect(record.keepsForExtraordinary("P1") && record.keepsForExtraordinary("P2"))
        #expect(!record.keepsForExtraordinary("Examen"))
    }

    @Test func aSectionTakenAgainStartsEmpty() {
        let record = Self.record(labs: .recoverableInExtraordinary)
        #expect(!record.keepsForExtraordinary("P1"))
        #expect(record.entry(for: "P1", in: .extraordinary) == nil)
    }

    @Test func aNotesOwnRuleWinsOverItsSections() {
        let record = Self.record(labs: .recoverableInExtraordinary, lab1: .savedForExtraordinary)
        #expect(record.keepsForExtraordinary("P1"))
        #expect(!record.keepsForExtraordinary("P2"))
    }

    /// Labs average 4: kept only from a 5 up, so they're taken again; with a 6 they stay.
    @Test func aSectionKeptOnlyFromAGrade() {
        var record = Self.record(labs: .savedIfAtLeast(5))
        #expect(!record.keepsForExtraordinary("P1"))
        record.entries["P1"] = GradeEntry(value: 7, outOf: 10)
        #expect(record.keepsForExtraordinary("P1") && record.keepsForExtraordinary("P2"))
    }

    @Test func aNoteThatCantBeRecoveredIsFixed() {
        let record = Self.record(lab1: .notRecoverable)
        #expect(record.isLockedInExtraordinary("P1"))
        #expect(!record.isLockedInExtraordinary("P2"))
        #expect(record.entry(for: "P1", in: .extraordinary)?.value == 3)
    }

    @Test func theExtraordinaryCanWeighDifferently() {
        var record = Self.record()
        // Extraordinary: the exam is 100 %.
        record.extraordinaryRoot = .group(Group(name: "Física", combination: .weightedAverage, children: [
            WeightedChild(weight: 1, node: .grade(Grade(name: "Examen", isFinalExam: true))),
        ], minimum: Minimum(threshold: 5, consequence: .fails)))
        record.extraordinaryEntries["Examen"] = GradeEntry(value: 6, outOf: 10)
        let progress = SubjectProgress(record, session: .extraordinary)
        #expect(progress.worst == 6)
        #expect(progress.leafCount == 1 && progress.isComplete)
        #expect(SubjectProgress(record, session: .ordinary).worst < 5)
    }

    @Test func aNoteOnlyInTheExtraordinaryTreeIsOnlyThere() {
        var record = Self.record()
        record.extraordinaryRoot = .group(Group(name: "Física", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.5, node: .grade(Grade(name: "Trabajo extra"))),
            WeightedChild(weight: 0.5, node: .grade(Grade(name: "Examen", isFinalExam: true))),
        ]))
        #expect(!record.keepsForExtraordinary("Trabajo extra"))
        record.extraordinaryEntries = ["Trabajo extra": GradeEntry(value: 8, outOf: 10), "Examen": GradeEntry(value: 6, outOf: 10)]
        #expect(SubjectProgress(record, session: .extraordinary).worst == 7)
        #expect(SubjectProgress.inputs(record, session: .ordinary)["Trabajo extra"] == nil)
    }

    @Test func editingFollowsNotesIntoTheExtraordinaryTree() {
        var record = Self.record()
        record.subject.root.identifyGrades()
        let ids = record.subject.root.gradeIDsByName
        record.extraordinaryEntries["Examen"] = GradeEntry(value: 6, outOf: 10)
        // The extraordinary tree is made during the edit, as a copy, and its exam renamed.
        var copy = record.subject.root
        copy.updateGrades { if $0.name == "Examen" { $0.name = "Examen extraordinario" } }
        record.extraordinaryRoot = copy
        record.reassignGrades(openingIDs: ids)
        #expect(record.extraordinaryEntries["Examen extraordinario"]?.value == 6)
        #expect(record.entries["Examen"]?.value == 2)
    }

    @Test func notPresentedIsNeitherAGradeNorAFail() {
        var record = Self.record()
        record.ordinaryNotPresented = true
        let progress = SubjectProgress(record, session: .ordinary)
        #expect(progress.isNotPresented && !progress.isComplete)
        let summary = RecordSummary([Course(year: 1, subjects: [record])], degree: DegreeSettings())
        #expect(summary.average == nil && summary.passed.isEmpty)
        // Not presented in the extraordinary moves the subject on to it.
        record.extraordinaryNotPresented = true
        #expect(record.activeSession == .extraordinary)
    }

    @Test func honorsOnlyShowOnceTheGradeIsIn() {
        var record = Self.record()
        record.hasHonors = true
        #expect(SubjectProgress(record).hasHonors)
        record.entries["Examen"] = nil
        #expect(!SubjectProgress(record).hasHonors)
    }

    @Test func aMissedRequirementFailsWhateverTheGrades() {
        var record = Self.record()
        record.entries = ["P1": GradeEntry(value: 10, outOf: 10), "P2": GradeEntry(value: 10, outOf: 10), "Examen": GradeEntry(value: 10, outOf: 10)]
        record.requirements = [SubjectRequirement(name: "Asistencia al 80 %")]
        #expect(SubjectProgress(record).status == .guaranteed)
        record.requirements[0].isMet = false
        #expect(SubjectProgress(record).status == .impossible)
        record.requirements[0].isMet = true
        #expect(SubjectProgress(record).status == .guaranteed)
    }

    /// 0,4 · 4,875 + 0,6 · 5 = 4,95: a pass only where the transcript rounds.
    @Test func roundingDecidesAPassAtTheLine() {
        var record = Self.record()
        record.entries = ["P1": GradeEntry(value: 4.875, outOf: 10), "P2": GradeEntry(value: 4.875, outOf: 10), "Examen": GradeEntry(value: 5, outOf: 10)]
        #expect(SubjectProgress(record).status == .impossible)
        #expect(SubjectProgress(record, rounding: .truncate).status == .impossible)
        let rounded = SubjectProgress(record, rounding: .round)
        #expect(rounded.status == .guaranteed)
        #expect(rounded.worst == 5)
        #expect(SubjectProgress(record, rounding: .truncate).worst == 4.9)
        #expect(GradeRounding.round.apply(4.95) == 5 && GradeRounding.truncate.apply(4.99) == 4.9)
    }

    @Test func newFieldsSurviveAndOldFilesStillRead() throws {
        var record = Self.record(labs: .savedIfAtLeast(5))
        record.extraordinaryRoot = record.subject.root
        record.ordinaryNotPresented = true
        record.hasHonors = true
        record.requirements = [SubjectRequirement(name: "Asistencia", isMet: false)]
        let decoded = try JSONDecoder().decode(SubjectRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        let old = #"{"id":"\#(UUID().uuidString)","subject":{"name":"A","ectsCredits":6,"root":{"grade":{"_0":{"name":"Examen","scaleMax":10}}}}}"#
        let plain = try JSONDecoder().decode(SubjectRecord.self, from: Data(old.utf8))
        #expect(plain.extraordinaryRoot == nil && plain.requirements.isEmpty && !plain.hasHonors)
        var degree = try JSONDecoder().decode(DegreeSettings.self, from: Data("{}".utf8))
        #expect(degree.rounding == .none)
        degree.rounding = .round
        #expect(try JSONDecoder().decode(DegreeSettings.self, from: JSONEncoder().encode(degree)).rounding == .round)
    }
}
