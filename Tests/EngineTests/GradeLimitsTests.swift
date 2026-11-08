import Testing
@testable import Engine

/// Rules where a higher grade can lower the result, and results that must stay on the 0–10 scale.
struct GradeLimitsTests {
    private func grade(_ name: String, _ scale: Double = 10, minimum: Minimum? = nil) -> Node {
        .grade(Grade(name: name, scaleMax: scale, minimum: minimum))
    }

    private func formula(_ text: String, _ variables: [String: Node]) throws -> Node {
        .formula(Formula(name: "Nota", expression: try Expression.parse(text, variables: Set(variables.keys)), variables: variables))
    }

    /// 40 % final, 40 % controls, 20 % labs; under a 4 in controls the final is worth 80 %.
    private func conditionalWeight() throws -> Node {
        try formula("si(C >= 4; 0,4 * F + 0,4 * C + 0,2 * P; 0,8 * F + 0,2 * P)", ["F": grade("F"), "C": grade("C"), "P": grade("P")])
    }

    @Test func aConditionalWeightDoesNotPromiseAPassThatAGradeCanTakeAway() throws {
        let node = try conditionalWeight()
        let inputs = ["F": 6.5, "P": 0.0]
        // A 0 passes (5,2) and a 10 passes (6,6), but a 4 in controls leaves a 4,2.
        #expect(node.evaluate(inputs.merging(["C": 4]) { $1 }, pendingFraction: 0) < 5)
        #expect(node.status(inputs, threshold: 5) == .possible)
    }

    @Test func theNeededGradeIsTheOneThatIsSafeToAimFor() throws {
        let needed = try #require(try conditionalWeight().neededFraction(["F": 6.5, "P": 0], target: 5))
        #expect(abs(needed - 0.6) < 0.001)
    }

    @Test func aPartThatDoesNotAverageCanBeWorseThanFailingIt() {
        let node = Node.group(Group(name: "Nota", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.3, node: grade("P")),
            WeightedChild(weight: 0.7, node: grade("E", minimum: Minimum(threshold: 4, consequence: .doesNotAverage))),
        ]))
        #expect(node.status(["P": 7], threshold: 5) == .possible)
        let needed = node.neededFraction(["P": 7], target: 5)
        #expect(abs((needed ?? 0) - 2.9 / 7) < 0.001)
    }

    @Test func aPendingGradeThatOnlySubtractsIsNotImpossible() throws {
        let node = try formula("E - 2 * F", ["E": grade("E"), "F": grade("F", 5)])
        #expect(node.status(["E": 6], threshold: 5) == .possible)
        #expect(node.neededFraction(["E": 6], target: 5) == 0)
    }

    @Test func statusStaysExactWhereGradesOnlyHelp() {
        let node = Node.group(Group(name: "Nota", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.5, node: grade("A")),
            WeightedChild(weight: 0.5, node: grade("B")),
        ]))
        #expect(node.isMonotonic)
        #expect(node.status(["A": 10], threshold: 5) == .guaranteed)
        #expect(node.status(["A": 0], threshold: 5) == .possible)
        #expect(node.status(["A": 0, "B": 9], threshold: 5) == .impossible)
    }

    @Test func extraPointsInASumStopAtTen() {
        let node = Node.group(Group(name: "Nota", combination: .sum, children: [
            WeightedChild(weight: 0.6, node: grade("E")),
            WeightedChild(weight: 0.4, node: grade("P")),
            WeightedChild(weight: 0.1, node: grade("X")),
        ]))
        #expect(node.evaluate(["E": 10, "P": 10, "X": 10], pendingFraction: 0) == 10)
        #expect(abs(node.evaluate(["E": 5, "P": 5, "X": 10], pendingFraction: 0) - 6) < 0.0001)
    }

    @Test func aSumInsideAPartStillScalesInItsParent() {
        let inner = Node.group(Group(name: "Partes", combination: .sum, children: [
            WeightedChild(weight: 0.7, node: grade("A")),
            WeightedChild(weight: 0.8, node: grade("B")),
        ]))
        let node = Node.group(Group(name: "Nota", combination: .weightedAverage, children: [WeightedChild(weight: 1, node: inner)]))
        #expect(abs(node.evaluate(["A": 10, "B": 10], pendingFraction: 0) - 10) < 0.0001)
    }

    @Test func aFormulaStaysBetweenZeroAndTen() throws {
        let node = try formula("E - 2 * F", ["E": grade("E"), "F": grade("F", 5)])
        #expect(node.evaluate(["E": 3, "F": 3], pendingFraction: 0) == 0)
        let over = try formula("E + F", ["E": grade("E"), "F": grade("F")])
        #expect(over.evaluate(["E": 10, "F": 10], pendingFraction: 0) == 10)
    }
}
