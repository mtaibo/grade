import Foundation
import Testing
@testable import Engine

/// Sections that hand their weight to another one.
struct WeightTransferTests {
    private let examID = UUID()
    private let labsID = UUID()
    private let taskID = UUID()

    private func grade(_ name: String, minimum: Minimum? = nil) -> Node {
        .grade(Grade(name: name, minimum: minimum))
    }

    /// Prácticas 20 %, Tarea 20 %, Examen 60 %.
    private func subject(task: WeightedChild? = nil, labsMinimum: Minimum? = nil) -> Node {
        .group(Group(name: "Nota", combination: .weightedAverage, children: [
            WeightedChild(id: labsID, weight: 0.2, node: grade("P", minimum: labsMinimum)),
            task ?? WeightedChild(id: taskID, weight: 0.2, node: grade("T")),
            WeightedChild(id: examID, weight: 0.6, node: grade("E")),
        ]))
    }

    private func value(_ node: Node, _ p: Double, _ t: Double, _ e: Double) -> Double {
        node.evaluate(["P": p, "T": t, "E": e], pendingFraction: 0)
    }

    @Test func absorbingIsWhatParadigmasGuideDescribes() {
        // 0,2 P + 0,2 T + (0,8 − T / 10 × 0,2) E
        let node = subject(task: WeightedChild(id: taskID, weight: 0.2, node: grade("T"), absorbedBy: examID))
        for p in stride(from: 0.0, through: 10, by: 2.5) {
            for t in stride(from: 0.0, through: 10, by: 2.5) {
                for e in stride(from: 0.0, through: 10, by: 2.5) {
                    #expect(abs(value(node, p, t, e) - (0.2 * p + 0.2 * t + (0.8 - t / 10 * 0.2) * e)) < 1e-9)
                }
            }
        }
    }

    @Test func aFullMarkLeavesNothingToAbsorb() {
        let node = subject(task: WeightedChild(id: taskID, weight: 0.2, node: grade("T"), absorbedBy: examID))
        #expect(abs(value(node, 10, 10, 5) - 7) < 1e-9)
        #expect(abs(value(node, 10, 0, 5) - 6) < 1e-9)
    }

    @Test func absorbingKeepsARaiseFromEverLowering() {
        let node = subject(task: WeightedChild(id: taskID, weight: 0.2, node: grade("T"), absorbedBy: examID))
        #expect(node.isMonotonic)
    }

    @Test func belowTheMinimumItsWeightMoves() {
        let node = subject(labsMinimum: Minimum(threshold: 5, consequence: .weightGoesTo(examID)))
        // Under it: the exam weighs 80 %.
        #expect(abs(value(node, 4, 10, 10) - 10) < 1e-9)
        #expect(abs(value(node, 4, 0, 5) - 4) < 1e-9)
        // At it: as usual.
        #expect(abs(value(node, 5, 0, 5) - 4) < 1e-9)
        #expect(abs(value(node, 10, 0, 5) - 5) < 1e-9)
    }

    @Test func belowTheMinimumEverythingDependsOnAnother() {
        let node = subject(labsMinimum: Minimum(threshold: 5, consequence: .everythingGoesTo(examID)))
        #expect(abs(value(node, 4, 10, 6) - 6) < 1e-9)
        #expect(abs(value(node, 5, 10, 6) - (1 + 2 + 3.6)) < 1e-9)
    }

    @Test func worksOnASumToo() {
        let node = Node.group(Group(name: "Nota", combination: .sum, children: [
            WeightedChild(id: taskID, weight: 0.3, node: grade("T"), absorbedBy: examID),
            WeightedChild(id: examID, weight: 0.7, node: grade("E")),
        ]))
        #expect(abs(node.evaluate(["T": 0, "E": 10], pendingFraction: 0) - 10) < 1e-9)
        #expect(abs(node.evaluate(["T": 5, "E": 0], pendingFraction: 0) - 1.5) < 1e-9)
    }

    @Test func aRuleWithNowhereToGoIsIgnored() {
        let gone = subject(task: WeightedChild(id: taskID, weight: 0.2, node: grade("T"), absorbedBy: UUID()))
        let itself = subject(task: WeightedChild(id: taskID, weight: 0.2, node: grade("T"), absorbedBy: taskID))
        #expect(abs(value(gone, 10, 0, 5) - 5) < 1e-9)
        #expect(abs(value(itself, 10, 0, 5) - 5) < 1e-9)
    }

    @Test func sectionsPointingAtEachOtherDoNotGoRound() {
        let node = Node.group(Group(name: "Nota", combination: .weightedAverage, children: [
            WeightedChild(id: taskID, weight: 0.5, node: grade("T"), absorbedBy: examID),
            WeightedChild(id: examID, weight: 0.5, node: grade("E"), absorbedBy: taskID),
        ]))
        // Each keeps half its weight and the other half goes by the other's 5: 3,75 + 3,75.
        let result = node.evaluate(["T": 5, "E": 5], pendingFraction: 0)
        #expect(abs(result - 7.5) < 1e-9)
    }

    @Test func missingTheMinimumCanStillBePassedAndIsNotGuaranteed() {
        // A 3 in the labs: the exam alone decides their 20 %.
        let node = subject(labsMinimum: Minimum(threshold: 5, consequence: .weightGoesTo(examID)))
        #expect(node.status(["P": 3, "T": 5]) == .possible)
        #expect(node.status(["P": 3, "T": 0, "E": 0]) == .impossible)
        #expect(node.neededFraction(["P": 3, "T": 5], target: 5) != nil)
    }

    @Test func aPlanStillAsksTheExamForWhatIsLeft() throws {
        let node = subject(task: WeightedChild(id: taskID, weight: 0.2, node: grade("T"), absorbedBy: examID))
        let plan = try #require(node.passPlan(["P": 10, "T": 0], target: 5))
        // 2 of the labs, and the exam on 80 %: a 3,75.
        #expect(abs((plan["E"] ?? 0) - 0.375) < 0.001)
    }

    @Test func survivesAFileAndReadsOlderOnes() throws {
        let node = subject(
            task: WeightedChild(id: taskID, weight: 0.2, node: grade("T"), absorbedBy: examID),
            labsMinimum: Minimum(threshold: 5, consequence: .everythingGoesTo(examID))
        )
        let copy = try JSONDecoder().decode(Node.self, from: JSONEncoder().encode(node))
        #expect(copy == node)
        let older = #"{"id":"\#(UUID().uuidString)","weight":0.5,"node":{"grade":{"_0":{"name":"A","scaleMax":10}}}}"#
        #expect(try JSONDecoder().decode(WeightedChild.self, from: Data(older.utf8)).absorbedBy == nil)
    }
}
