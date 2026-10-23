import Testing
import Engine

/// From guide/extracted/estadistica.json — grade = P + C + 0.1 * (8 - C) * F. The final exam's
/// weight depends continuously on C (between 60% and 80%), so this needs `Formula`'s `Expression`,
/// not fixed weights in `Group`/`Alternatives`. See docs/modelo.md.
struct EstadisticaTests {
    private var formula: Formula {
        guard case .formula(let formula) = Subject.estadistica.root else {
            fatalError("Subject.estadistica.root is expected to be a formula")
        }
        return formula
    }

    @Test func ordinarySessionNeedsAFormulaNotFixedWeights() {
        #expect(formula.variables.count == 3)
        #expect(formula.variables["F"] != nil)
    }

    @Test func formulaEvaluatesTheSameAsTheGuidesWorkedExample() {
        // P = 1.5/2, C = 1.0/2, F = 7/10 → 1.5 + 1.0 + 0.1 * (8 - 1.0) * 7 = 7.4
        let result = formula.expression.evaluate(["P": 1.5, "C": 1.0, "F": 7])
        #expect(result == 7.4)
    }

    @Test func examWeightVariesBetween60And80PercentDependingOnC() {
        // C at its max (2/2): coefficient of F is 0.1 * (8 - 2) = 0.6 → 60% weight.
        let atMaxC = formula.expression.evaluate(["P": 0, "C": 2, "F": 10])
        #expect(atMaxC == 2 + 6)

        // C at its min (0/2): coefficient of F is 0.1 * (8 - 0) = 0.8 → 80% weight.
        let atMinC = formula.expression.evaluate(["P": 0, "C": 0, "F": 10])
        #expect(atMinC == 0 + 8)
    }
}
