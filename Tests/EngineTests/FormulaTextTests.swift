import Testing
import Engine

/// Formulas typed by hand: reading, printing back, and the "up to N %" shown per variable.
struct FormulaTextTests {
    private func value(_ text: String, _ variables: [String: Double] = [:]) throws -> Double {
        try Expression.parse(text, variables: Set(variables.keys)).evaluate(variables)
    }

    @Test func everyReferenceFormulaSurvivesPrintingAndReadingBack() throws {
        for subject in Subject.all {
            guard case .formula(let formula) = subject.root else { continue }
            let parsed = try Expression.parse(formula.expression.source, variables: Set(formula.variables.keys))
            #expect(parsed == formula.expression, "\(subject.name): \(formula.expression.source)")
        }
    }

    @Test func operatorsFollowTheUsualPrecedence() throws {
        #expect(try value("1 + 2 * 3") == 7)
        #expect(try value("(1 + 2) * 3") == 9)
        #expect(try value("10 - 4 - 3") == 3)
        #expect(try value("8 / 2 / 2") == 2)
        #expect(try value("-3 + 5") == 2)
    }

    @Test func decimalsTakeACommaOrAPoint() throws {
        #expect(abs(try value("0,1 * 10") - 1) < 1e-9)
        #expect(abs(try value("0.5 + 0,25") - 0.75) < 1e-9)
    }

    @Test func variablesMinMaxAndConditionals() throws {
        let vars: [String: Double] = ["E": 5, "N": 7]
        #expect(try value("min(N; 4,5)", vars) == 4.5)
        #expect(try value("máx(E; N)", vars) == 7)
        #expect(try value("si(E >= 4; N; 0)", vars) == 7)
        #expect(try value("si(E <= 4; 1; 2)", vars) == 2)
    }

    @Test func mistakesComeBackAsReadableErrors() {
        func message(_ text: String) -> String? {
            do {
                _ = try Expression.parse(text, variables: ["A"])
                return nil
            } catch {
                return (error as? FormulaParseError)?.message
            }
        }
        #expect(message("A + Z")?.contains("Z") == true)
        #expect(message("(A + 1") != nil)
        #expect(message("A +") != nil)
        #expect(message("min(A, 1)")?.contains(";") == true)
        #expect(message("min(A)") != nil)
        #expect(message("foo(A)") != nil)
        #expect(message("A + 1)") != nil)
    }

    @Test func renamingAVariableUpdatesEveryUse() throws {
        let expression = try Expression.parse("P + 0,1 * (8 - P) * F", variables: ["P", "F"])
        #expect(expression.renamingVariable("P", to: "X").source == "X + 0,1 * (8 - X) * F")
    }

    @Test func paradigmasShowsHowMuchEachPartCanGive() {
        guard case .formula(let formula) = Subject.paradigmasProgramacion.root else {
            Issue.record("Paradigmas should be a formula")
            return
        }
        // Labs and practical tests are up to 20% each; the exam up to 80% (when the tests give 0).
        #expect(abs(formula.maxShare(of: "L") - 2) < 1e-9)
        #expect(abs(formula.maxShare(of: "P") - 2) < 1e-9)
        #expect(abs(formula.maxShare(of: "E") - 8) < 1e-9)
    }

    @Test func rangesOfAFixedWeightFormula() throws {
        let formula = Formula(
            name: "Fija",
            expression: try Expression.parse("0,3 * A + 0,7 * B", variables: ["A", "B"]),
            variables: ["A": .grade(Grade(name: "A")), "B": .grade(Grade(name: "B"))]
        )
        #expect(abs(formula.resultRange.lowerBound) < 1e-9)
        #expect(abs(formula.resultRange.upperBound - 10) < 1e-9)
        let a = formula.contributionRange(of: "A")
        #expect(abs(a.lowerBound - 3) < 1e-9 && abs(a.upperBound - 3) < 1e-9)
    }

    @Test func rangesFollowAWeightThatMoves() throws {
        // The exam weighs 80 % when the tests give 0, and 60 % when they give their maximum.
        let formula = Formula(
            name: "Variable",
            expression: try Expression.parse("max(E; 0,6 * E + 0,4 * T)", variables: ["E", "T"]),
            variables: ["E": .grade(Grade(name: "E")), "T": .grade(Grade(name: "T"))]
        )
        let exam = formula.contributionRange(of: "E")
        #expect(abs(exam.lowerBound - 6) < 1e-9)
        #expect(abs(exam.upperBound - 10) < 1e-9)
        #expect(formula.resultRange.upperBound <= 10 + 1e-9)
    }

    @Test func aFormulaThatOverflowsShowsIt() throws {
        let formula = Formula(
            name: "Mal",
            expression: try Expression.parse("A + B", variables: ["A", "B"]),
            variables: ["A": .grade(Grade(name: "A")), "B": .grade(Grade(name: "B"))]
        )
        #expect(abs(formula.resultRange.upperBound - 20) < 1e-9)
    }

    @Test func everyReferenceFormulaStaysWithinTen() {
        for subject in Subject.all {
            guard case .formula(let formula) = subject.root else { continue }
            let range = formula.resultRange
            #expect(range.lowerBound >= -1e-9 && range.upperBound <= 10 + 1e-9, "\(subject.name): \(range)")
        }
    }
}
