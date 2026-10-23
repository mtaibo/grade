import Testing
import Engine

/// From guide/extracted/estadistica.json — grade = P + C + 0.1 * (8 - C) * F. The final exam's
/// weight depends continuously on C (between 60% and 80%), so this needs `Formula`'s `Expression`,
/// not fixed weights in `Group`/`Alternatives`. See docs/modelo.md.
struct EstadisticaTests {
    static let formula = Formula(
        name: "Nota final",
        expression: .add(
            .add(.variable("P"), .variable("C")),
            .multiply(
                .multiply(.constant(0.1), .subtract(.constant(8), .variable("C"))),
                .variable("F")
            )
        ),
        variables: [
            "P": .grade(Grade(name: "Prácticas de laboratorio", scaleMax: 2, recovery: .notRecoverable)),
            "C": .grade(Grade(name: "Controles (temas 1 y 2)", scaleMax: 2, recovery: .partiallyRecoverableInFinal)),
            "F": .grade(Grade(name: "Examen final", scaleMax: 10)),
        ]
    )

    @Test func ordinarySessionNeedsAFormulaNotFixedWeights() {
        #expect(Self.formula.variables.count == 3)
        #expect(Self.formula.variables["F"] != nil)
    }

    @Test func formulaEvaluatesTheSameAsTheGuidesWorkedExample() {
        // P = 1.5/2, C = 1.0/2, F = 7/10 → 1.5 + 1.0 + 0.1 * (8 - 1.0) * 7 = 7.4
        let result = Self.formula.expression.evaluate(["P": 1.5, "C": 1.0, "F": 7])
        #expect(result == 7.4)
    }

    @Test func examWeightVariesBetween60And80PercentDependingOnC() {
        // C at its max (2/2): coefficient of F is 0.1 * (8 - 2) = 0.6 → 60% weight.
        let atMaxC = Self.formula.expression.evaluate(["P": 0, "C": 2, "F": 10])
        #expect(atMaxC == 2 + 6)

        // C at its min (0/2): coefficient of F is 0.1 * (8 - 0) = 0.8 → 80% weight.
        let atMinC = Self.formula.expression.evaluate(["P": 0, "C": 0, "F": 10])
        #expect(atMinC == 0 + 8)
    }
}
