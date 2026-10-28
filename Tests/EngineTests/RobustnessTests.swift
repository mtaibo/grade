import Foundation
import Testing
import Engine

/// Inputs the app can't fully control (hand-typed formulas, old or edited files, empty groups)
/// must give a number on screen, never a crash or a NaN.
struct RobustnessTests {
    private static var everySubject: [Subject] {
        Subject.all + DegreeTemplate.all.flatMap { $0.entries.map(\.subject) }
    }

    @Test func aVariableTheFormulaNoLongerHasCountsAsZero() {
        let expression = Expression.add(.variable("A"), .variable("B"))
        #expect(expression.evaluate(["A": 4]) == 4)
    }

    @Test func dividingByAGradeStillAtZeroGivesAFiniteResult() {
        let formula = Formula(
            name: "F",
            expression: .divide(.variable("A"), .variable("B")),
            variables: ["A": .grade(Grade(name: "A")), "B": .grade(Grade(name: "B"))]
        )
        let node = Node.formula(formula)
        for fraction in [0.0, 0.5, 1.0] {
            #expect(node.evaluate([:], pendingFraction: fraction).isFinite)
        }
        #expect(node.evaluate(["A": 5, "B": 0], pendingFraction: 0) == 0)
        _ = node.status([:])
        _ = node.neededFraction([:], target: 5)
    }

    @Test func anEmptyGroupEvaluatesToZero() {
        for combination in [Group.Combination.weightedAverage, .sum, .max, .min, .bestOf(2)] {
            let node = Node.group(Group(name: "Vacía", combination: combination, children: []))
            #expect(node.evaluate([:], pendingFraction: 1) == 0)
            #expect(node.status([:]) == .impossible)
            #expect(node.neededFraction([:], target: 5) == nil)
        }
    }

    @Test func zeroWeightsAndZeroScalesDoNotProduceNaN() {
        let node = Node.group(Group(name: "G", combination: .weightedAverage, children: [
            WeightedChild(weight: 0, node: .grade(Grade(name: "A", scaleMax: 0))),
            WeightedChild(weight: 0, node: .grade(Grade(name: "B"))),
        ]))
        #expect(node.evaluate(["A": 3], pendingFraction: 1).isFinite)
    }

    /// Grades are stored by leaf name, so two leaves with the same name in one subject would share
    /// (and overwrite) each other's grade.
    @Test func everyBundledSubjectHasUniqueLeafNames() {
        for subject in Self.everySubject {
            let names = subject.root.allLeafNames()
            #expect(Set(names).count == names.count, "\(subject.name) repeats a leaf name")
        }
    }

    @Test func everyBundledFormulaOnlyUsesItsOwnVariables() {
        for subject in Self.everySubject {
            guard case .formula(let formula) = subject.root else { continue }
            for name in formula.expression.variableOrder {
                #expect(formula.variables[name] != nil, "\(subject.name) uses «\(name)» without defining it")
            }
        }
    }

    /// Whatever is typed in the formula field, parsing either succeeds or explains why — it never traps.
    @Test func parsingArbitraryTextNeverTraps() {
        let pieces = ["A", "B", "1", "0,5", ".", ",", ";", "+", "-", "*", "/", "(", ")", "min(", "max(", "si(", ">=", "<=", ">", " ", "x", "é", "∞", "1e999"]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<5_000 {
            let text = (0..<Int.random(in: 0...12, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
            if let expression = try? Expression.parse(text, variables: ["A", "B"]) {
                _ = expression.evaluate(["A": 5, "B": 0])
                _ = expression.source
            }
        }
    }

    @Test func deeplyNestedTextIsRejectedInsteadOfOverflowing() {
        for opener in ["(", "-", "min(", "si("] {
            let text = String(repeating: opener, count: 20_000) + "A"
            #expect(throws: FormulaParseError.self) { try Expression.parse(text, variables: ["A"]) }
        }
        #expect(throws: Never.self) { try Expression.parse("((((A))))", variables: ["A"]) }
    }

    @Test func printedFormulasReadBack() throws {
        for subject in Self.everySubject {
            guard case .formula(let formula) = subject.root else { continue }
            let reparsed = try Expression.parse(formula.expression.source, variables: Set(formula.variables.keys))
            let values = formula.variables.mapValues { _ in 7.3 }
            #expect(abs(reparsed.evaluate(values) - formula.expression.evaluate(values)) < 1e-6, "\(subject.name)")
        }
    }
}
