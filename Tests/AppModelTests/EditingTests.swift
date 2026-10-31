import Engine
import Foundation
import Testing
@testable import AppModel

/// Whatever is renamed, moved, copied or deleted in the editor, each stored grade ends up on its
/// own note — the editor follows notes by id, not by name.
struct EditingTests {
    /// Opens a record the way the editor does: every note gets an id, remembered by name.
    static func open(_ names: [String], grades: [String: Double]) -> (SubjectRecord, [String: UUID]) {
        var root = Node.group(Group(name: "S", combination: .weightedAverage, children: names.map {
            WeightedChild(weight: 1 / Double(names.count), node: .grade(Grade(name: $0)))
        }))
        root.identifyGrades()
        var record = SubjectRecord(subject: Subject(name: "S", ectsCredits: 6, root: root))
        record.entries = grades.mapValues { GradeEntry(value: $0, outOf: 10) }
        record.extraordinaryEntries = grades.mapValues { GradeEntry(value: $0 + 0.5, outOf: 10) }
        return (record, root.gradeIDsByName)
    }

    static func rename(_ record: inout SubjectRecord, _ old: String, to new: String) {
        record.subject.root.updateGrades { if $0.name == old { $0.name = new } }
    }

    /// The case that used to cross grades: swap two names going through a duplicate.
    @Test func swappingTwoNamesThroughADuplicateKeepsEachGrade() {
        let (opened, ids) = Self.open(["A", "B"], grades: ["A": 3, "B": 8])
        var record = opened
        Self.rename(&record, "A", to: "B")   // two «B» for a moment
        // The original B (the second note) becomes A.
        record.subject.root = .group(Group(name: "S", combination: .weightedAverage, children: record.subject.root.asGroup!.children.enumerated().map { index, child in
            var child = child
            if index == 1 { child.node.title = "A" }
            return child
        }))
        record.reassignGrades(openingIDs: ids)
        #expect(record.entries["B"]?.value == 3)
        #expect(record.entries["A"]?.value == 8)
        #expect(record.extraordinaryEntries["B"]?.value == 3.5)
    }

    @Test func aDeletedNotesNameGivenToAnotherDoesntHandItsGradeOver() {
        let (opened, ids) = Self.open(["A", "B"], grades: ["A": 3, "B": 8])
        var record = opened
        record.subject.root.asGroup!.children.removeFirst()
        Self.rename(&record, "B", to: "A")
        record.reassignGrades(openingIDs: ids)
        #expect(record.entries == ["A": GradeEntry(value: 8, outOf: 10)])
    }

    @Test func aNewNoteWithAnOldNameStartsEmpty() {
        let (opened, ids) = Self.open(["A"], grades: ["A": 3])
        var record = opened
        record.subject.root = .group(Group(name: "S", combination: .weightedAverage, children: [
            WeightedChild(weight: 1, node: .grade(Grade(name: "A"))),
        ]))
        record.reassignGrades(openingIDs: ids)
        #expect(record.entries.isEmpty)
    }

    @Test func splittingANoteIntoSeveralKeepsItsGradeOnTheFirst() {
        let (opened, ids) = Self.open(["Prácticas", "Examen"], grades: ["Prácticas": 6, "Examen": 9])
        var record = opened
        record.subject.root.asGroup!.children[0].node.resizeNotes(to: 3)
        record.reassignGrades(openingIDs: ids)
        #expect(record.entries["Prácticas 1"]?.value == 6)
        #expect(record.entries["Prácticas 2"] == nil)
        #expect(record.entries["Examen"]?.value == 9)
        let allIDs = record.subject.root.grades.compactMap(\.id)
        #expect(Set(allIDs).count == allIDs.count)
    }

    @Test func movingANoteIntoAnotherSectionKeepsItsGrade() {
        let (opened, ids) = Self.open(["A", "B", "C"], grades: ["A": 1, "B": 2, "C": 3])
        var record = opened
        var group = record.subject.root.asGroup!
        let moved = group.children.removeFirst()
        group.children[1].node = .group(Group(name: "Bloque", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.5, node: group.children[1].node), moved,
        ]))
        record.subject.root = .group(group)
        Self.rename(&record, "A", to: "A bis")
        record.reassignGrades(openingIDs: ids)
        #expect(record.entries.mapValues(\.value) == ["A bis": 1, "B": 2, "C": 3])
    }

    @Test func notesFromOlderFilesAndTemplatesGetUniqueIds() {
        for subject in Subject.all + DegreeTemplate.all.flatMap({ $0.entries.map(\.subject) }) {
            var root = subject.root
            #expect(root.grades.allSatisfy { $0.id == nil })
            root.identifyGrades()
            let ids = root.grades.compactMap(\.id)
            #expect(ids.count == root.grades.count && Set(ids).count == ids.count, "\(subject.name)")
            var again = root
            again.identifyGrades()
            #expect(again == root, "ids change on a second pass in \(subject.name)")
        }
    }

    @Test func oldFilesWithoutIdsStillDecode() throws {
        let json = #"{"grade":{"_0":{"name":"Examen","scaleMax":10}}}"#
        let node = try JSONDecoder().decode(Node.self, from: Data(json.utf8))
        #expect(node.asGrade?.id == nil && node.asGrade?.name == "Examen")
    }
}
