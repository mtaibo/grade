import Engine
import Testing
@testable import AppModel

/// What a failed subject shows and averages, and weights that don't add up.
struct GradeRulesTests {
    private func record(minimum: Minimum? = nil, _ entries: [String: GradeEntry]) -> SubjectRecord {
        var record = SubjectRecord(subject: Subject(name: "Física", ectsCredits: 6, root: .group(Group(name: "Física", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.3, node: .grade(Grade(name: "P"))),
            WeightedChild(weight: 0.7, node: .grade(Grade(name: "E", isFinalExam: true, minimum: minimum))),
        ], minimum: Minimum(threshold: 5, consequence: .fails)))))
        record.entries = entries
        return record
    }

    private func entry(_ value: Double) -> GradeEntry { GradeEntry(value: value, outOf: 10) }

    @Test func aSubjectFailedForAMinimumDoesNotShowAPassingGrade() {
        let minimum = Minimum(threshold: 4, consequence: .fails)
        let progress = SubjectProgress(record(minimum: minimum, ["P": entry(10), "E": entry(3)]))
        #expect(progress.status == .impossible)
        #expect(abs(progress.worst - 4.9) < 0.0001)
    }

    @Test func aMissedRequirementDoesNotAverageAsAPass() {
        var record = record(["P": entry(8), "E": entry(8)])
        record.requirements = [SubjectRequirement(name: "Asistencia", isMet: false)]
        let summary = RecordSummary([Course(year: 1, subjects: [record])], degree: DegreeSettings())
        #expect(abs((summary.average ?? 0) - 4.9) < 0.0001)
        #expect(summary.passed.isEmpty)
    }

    @Test func roundingDoesNotLiftAFailedSubjectBackToAPass() {
        var record = record(minimum: Minimum(threshold: 4, consequence: .fails), ["P": entry(10), "E": entry(3)])
        record.rounding = .unit
        #expect(abs(SubjectProgress(record).worst - 4.9) < 0.0001)
    }

    @Test func aFailedGradeBelowTheLineKeepsItsNumber() {
        #expect(abs(SubjectProgress(record(["P": entry(2), "E": entry(2)])).worst - 2) < 0.0001)
    }

    @Test func weightsThatDoNotAddUpAreFound() {
        let inner = Node.group(Group(name: "Prácticas", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.5, node: .grade(Grade(name: "A"))),
            WeightedChild(weight: 0.4, node: .grade(Grade(name: "B"))),
        ]))
        let root = Node.group(Group(name: "x", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.6, node: inner),
            WeightedChild(weight: 0.3, node: .grade(Grade(name: "E"))),
        ]))
        #expect(root.sectionsWithOffWeights(rootName: "Física") == ["Física", "Prácticas"])
    }

    @Test func aSumAndEveryBundledSubjectHaveNothingToFix() {
        let sum = Node.group(Group(name: "x", combination: .sum, children: [WeightedChild(weight: 1.1, node: .grade(Grade(name: "E")))]))
        #expect(sum.sectionsWithOffWeights(rootName: "x").isEmpty)
        for subject in Subject.all {
            #expect(subject.root.sectionsWithOffWeights(rootName: subject.name).isEmpty, "\(subject.name)")
        }
    }
}
