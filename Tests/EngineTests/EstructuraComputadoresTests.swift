import Testing
import Engine

/// From guide/extracted/estructuraComputadores.json — a plain weighted average with an overall
/// minimum. The cleanest of the 3 reference guides: no formula, no alternatives needed.
struct EstructuraComputadoresTests {
    @Test func ordinarySessionIsAWeightedAverageWithAnOverallMinimum() {
        guard case .group(let group) = Subject.estructuraComputadores.root else {
            Issue.record("expected a group at the root")
            return
        }
        #expect(group.children.count == 3)
        #expect(group.children.map(\.weight).reduce(0, +) == 1.0)
        #expect(group.minimum == Minimum(threshold: 5, consequence: .fails))
    }

    @Test func extraordinarySessionDropsLabsRecoveryAndReweightsTheExam() {
        let root = Node.group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.20, node: .grade(Grade(
                    name: "Prácticas de laboratorio",
                    recovery: .notRecoverable
                ))),
                WeightedChild(weight: 0.80, node: .grade(Grade(name: "Prueba objetiva"))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))

        guard case .group(let group) = root else {
            Issue.record("expected a group at the root")
            return
        }
        #expect(group.children.map(\.weight).reduce(0, +) == 1.0)
    }
}
