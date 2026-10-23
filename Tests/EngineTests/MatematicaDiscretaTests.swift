import Testing
import Engine

/// From guide/extracted/matematicaDiscreta.json.
/// N = P + M + 0.1 * (7 - M) * E, then F = N if E >= 4 else min(N, 4.5), and F must reach 5 to pass.
/// Same continuous-weight shape as Estadística (needs `Formula`), but here the "E < 4 → cap at
/// 4.5" part folds directly into the expression (`ifGreaterOrEqual`) instead of needing a
/// separate `Minimum` on `E` — the expression already fully determines F, so a second mechanism
/// claiming the same effect would just be two sources of truth for one rule.
struct MatematicaDiscretaTests {
    static let formula: Formula = {
        let n = Expression.add(
            .add(.variable("P"), .variable("M")),
            .multiply(
                .multiply(.constant(0.1), .subtract(.constant(7), .variable("M"))),
                .variable("E")
            )
        )
        return Formula(
            name: "Nota final",
            expression: .ifGreaterOrEqual(
                lhs: .variable("E"), rhs: .constant(4),
                then: n,
                otherwise: .min(n, .constant(4.5))
            ),
            variables: [
                "P": .grade(Grade(name: "Prácticas de laboratorio", scaleMax: 3, recovery: .notRecoverable)),
                "M": .grade(Grade(name: "Prueba Moodle", scaleMax: 2, recovery: .partiallyRecoverableInFinal)),
                "E": .grade(Grade(name: "Examen final", scaleMax: 10)),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        )
    }()

    @Test func ordinarySessionNeedsAFormulaWithAConditionalCap() {
        #expect(Self.formula.variables.count == 3)
        #expect(Self.formula.minimum == Minimum(threshold: 5, consequence: .fails))
    }

    @Test func passingExamKeepsTheFullFormulaResult() {
        // P = 2.5/3, M = 1.5/2, E = 6/10 (>= 4) → N = 2.5 + 1.5 + 0.1 * (7 - 1.5) * 6 = 7.3, F = N.
        let result = Self.formula.expression.evaluate(["P": 2.5, "M": 1.5, "E": 6])
        #expect(abs(result - 7.3) < 0.0001)
    }

    @Test func failingExamCapsTheResultAt4Point5() {
        // P = 2.5/3, M = 1.5/2, E = 3/10 (< 4) → N = 2.5 + 1.5 + 0.1 * (7 - 1.5) * 3 = 5.65, F = min(N, 4.5) = 4.5.
        let result = Self.formula.expression.evaluate(["P": 2.5, "M": 1.5, "E": 3])
        #expect(result == 4.5)
    }
}
