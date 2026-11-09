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

    @Test func notesFromOlderFilesAndReferenceSubjectsGetUniqueIds() {
        for subject in Subject.all {
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

/// The percentage shown on each part of a subject.
struct PartWeightTests {
    private static func parts(_ text: String, keys: Set<String>) throws -> [String: PartItem] {
        let formula = Formula(
            name: "Nota final",
            expression: try Engine.Expression.parse(text, variables: keys),
            variables: Dictionary(uniqueKeysWithValues: keys.map { ($0, Node.grade(Grade(name: $0))) })
        )
        return Dictionary(uniqueKeysWithValues: PartItem.items(of: .formula(formula)).map { ($0.id, $0) })
    }

    @Test func aWeightThatMovesWithAnotherGradeIsARange() throws {
        // Paradigmas: the task consolidates up to 20 % and the exam is what's left up to 80 %.
        let parts = try Self.parts("0,2 * P + 0,2 * T + (0,8 - T / 10 * 0,2) * E", keys: ["P", "T", "E"])
        #expect(abs((parts["P"]?.weightPercent ?? 0) - 20) < 1e-9 && parts["P"]?.lowestPercent == nil)
        #expect(abs((parts["T"]?.weightPercent ?? 0) - 20) < 1e-9 && abs((parts["T"]?.lowestPercent ?? 1)) < 1e-9)
        #expect(abs((parts["E"]?.weightPercent ?? 0) - 80) < 1e-9 && abs((parts["E"]?.lowestPercent ?? 0) - 60) < 1e-9)
    }

    @Test func aPartThatNeverAddsDoesNotClaimAShare() throws {
        let parts = try Self.parts("0,2 * P + (0,2 - T / 10 * 0,2) * T + (0,8 - T / 10 * 0,2) * E", keys: ["P", "T", "E"])
        #expect(parts["T"]?.weightPercent == 0 && parts["T"]?.lowestPercent == nil)
    }
}

/// Sections that hand their weight to another, as the editor and the subject's screen see them.
struct WeightRuleEditingTests {
    private let labs = UUID(), task = UUID(), exam = UUID()

    private func group(task taskChild: WeightedChild? = nil, labsMinimum: Minimum? = nil) -> Engine.Group {
        Engine.Group(name: "Nota", combination: .weightedAverage, children: [
            WeightedChild(id: labs, weight: 0.2, node: .grade(Grade(name: "P", minimum: labsMinimum))),
            taskChild ?? WeightedChild(id: task, weight: 0.2, node: .grade(Grade(name: "T"))),
            WeightedChild(id: exam, weight: 0.6, node: .grade(Grade(name: "E", isFinalExam: true))),
        ])
    }

    private func absorbing() -> Engine.Group {
        group(task: WeightedChild(id: task, weight: 0.2, node: .grade(Grade(name: "T")), absorbedBy: exam))
    }

    private func shares(_ group: Engine.Group) -> [UUID: PartItem] {
        Dictionary(uniqueKeysWithValues: PartItem.items(of: .group(group)).compactMap { item in UUID(uuidString: item.id).map { ($0, item) } })
    }

    @Test func absorbingShowsTheSameRangesAsTheGuide() {
        let parts = shares(absorbing())
        #expect(abs((parts[labs]?.weightPercent ?? 0) - 20) < 1e-9 && parts[labs]?.lowestPercent == nil)
        #expect(abs((parts[task]?.weightPercent ?? 0) - 20) < 1e-9 && parts[task]?.lowestPercent == 0)
        #expect(abs((parts[exam]?.weightPercent ?? 0) - 80) < 1e-9 && abs((parts[exam]?.lowestPercent ?? 0) - 60) < 1e-9)
    }

    @Test func whenAnotherDecidesEverythingTheRestCanCountForNothing() {
        let parts = shares(group(labsMinimum: Minimum(threshold: 5, consequence: .everythingGoesTo(exam))))
        #expect(abs((parts[exam]?.weightPercent ?? 0) - 100) < 1e-9 && abs((parts[exam]?.lowestPercent ?? 0) - 60) < 1e-9)
        #expect(abs((parts[task]?.weightPercent ?? 0) - 20) < 1e-9 && parts[task]?.lowestPercent == 0)
    }

    @Test func noRulesKeepOneFigure() {
        let parts = shares(group())
        #expect(parts.values.allSatisfy { $0.lowestPercent == nil })
    }

    @Test func deletingTheSectionTakesItsRulesWithIt() {
        var group = group(task: WeightedChild(id: task, weight: 0.2, node: .grade(Grade(name: "T")), absorbedBy: exam), labsMinimum: Minimum(threshold: 5, consequence: .weightGoesTo(exam)))
        group.children.removeAll { $0.id == exam }
        group.forgetMissingSections()
        #expect(group.children.allSatisfy { $0.absorbedBy == nil && $0.node.ownMinimum == nil })
    }

    @Test(arguments: [0, 1, 2])
    func aFormulaSaysTheSameAsTheRules(rule: Int) throws {
        let source: Engine.Group = switch rule {
        case 0: absorbing()
        case 1: group(labsMinimum: Minimum(threshold: 5, consequence: .weightGoesTo(exam)))
        default: group(labsMinimum: Minimum(threshold: 5, consequence: .everythingGoesTo(exam)))
        }
        let formula = Node.formula(try #require(source.asFormula()))
        for p in stride(from: 0.0, through: 10, by: 2.5) {
            for t in stride(from: 0.0, through: 10, by: 2.5) {
                for e in stride(from: 0.0, through: 10, by: 2.5) {
                    let inputs = ["P": p, "T": t, "E": e]
                    #expect(abs(Node.group(source).evaluate(inputs, pendingFraction: 0) - formula.evaluate(inputs, pendingFraction: 0)) < 1e-4)
                }
            }
        }
    }
}
