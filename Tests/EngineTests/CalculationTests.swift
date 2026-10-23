import Testing
import Engine

/// §5 of the brief: current grade, needed grade (binary search), and status, checked against
/// the 3 reference guides from `Subject.all` — including the monotonicity check the brief
/// explicitly asks for ("si alguna guía la rompe, avísame: cambia el enfoque").
struct CalculationTests {
    @Test func worstCaseIsZeroOnEverythingPending() {
        for subject in Subject.all {
            #expect(subject.root.evaluate([:], pendingFraction: 0) == 0)
        }
    }

    @Test func bestCaseIsTheMaxOnEverythingPending() {
        for subject in Subject.all {
            #expect(subject.root.evaluate([:], pendingFraction: 1) == 10)
        }
    }

    @Test func estructuraComputadoresWeightedAverageMatchesAHandCalculation() {
        // 8/10 labs (20%), problem solving 9 and 7 (20% + 20%), 6/10 final exam (40%).
        let inputs: [String: Double] = [
            "Prácticas de laboratorio": 8,
            "Prueba 1": 9,
            "Prueba 2": 7,
            "Prueba objetiva": 6,
        ]
        // 0.20*8 + 0.40*((9+7)/2) + 0.40*6 = 1.6 + 3.2 + 2.4 = 7.2
        let result = Subject.estructuraComputadores.root.evaluate(inputs, pendingFraction: 0)
        #expect(abs(result - 7.2) < 0.0001)
    }

    @Test func pendingLeavesListsWhatIsMissing() {
        let inputs: [String: Double] = ["Prácticas de laboratorio": 8]
        let pending = Subject.estructuraComputadores.root.pendingLeaves(inputs)
        #expect(Set(pending) == ["Prueba 1", "Prueba 2", "Prueba objetiva"])
    }

    @Test func statusIsGuaranteedOncePassingEvenInTheWorstCase() {
        // Labs, both problem-solving tests and a strong partial exam already lock in a pass.
        let inputs: [String: Double] = [
            "Prácticas de laboratorio": 10,
            "Prueba 1": 10,
            "Prueba 2": 10,
        ]
        #expect(Subject.estructuraComputadores.root.status(inputs) == .guaranteed)
    }

    @Test func statusIsImpossibleOnceEvenTheBestCaseFallsShort() {
        let inputs: [String: Double] = [
            "Prácticas de laboratorio": 0,
            "Prueba 1": 0,
            "Prueba 2": 0,
        ]
        // Best case left: 0.40 * 10 (final exam) = 4.0, short of the 5.0 threshold.
        #expect(Subject.estructuraComputadores.root.status(inputs) == .impossible)
    }

    @Test func neededFractionHitsTheRequestedTargetWhenPluggedBackIn() {
        let inputs: [String: Double] = [
            "Prácticas de laboratorio": 6,
            "Prueba 1": 5,
            "Prueba 2": 5,
        ]
        let root = Subject.estructuraComputadores.root
        guard let fraction = root.neededFraction(inputs, target: 5) else {
            Issue.record("expected 5 to be reachable")
            return
        }
        let result = root.evaluate(inputs, pendingFraction: fraction)
        #expect(abs(result - 5) < 0.001)
    }

    @Test func neededFractionIsNilWhenTheTargetIsUnreachable() {
        let inputs: [String: Double] = [
            "Prácticas de laboratorio": 0,
            "Prueba 1": 0,
            "Prueba 2": 0,
        ]
        #expect(Subject.estructuraComputadores.root.neededFraction(inputs, target: 5) == nil)
    }

    @Test func matematicaDiscretaStatusReflectsTheExamCapWhenItIsTheOnlyUnknown() {
        // P and M maxed out, only the exam (E) left — but even E = 10 only reaches N = 3 + 2 +
        // 0.1 * (7 - 2) * 10 = 10, so the subject isn't guaranteed; it's only possible, and it
        // can't be impossible since a high-enough E clearly passes.
        let inputs: [String: Double] = ["P": 3, "M": 2]
        #expect(Subject.matematicaDiscreta.root.status(inputs) == .possible)
    }

    /// The brief's own invariant: raising a partial grade never lowers the final one. Checked by
    /// sampling `pendingFraction` across each reference subject, as it explicitly asks for.
    @Test func evaluateIsMonotonicInPendingFractionAcrossAllReferenceSubjects() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.05)
        for subject in Subject.all {
            var previous = subject.root.evaluate([:], pendingFraction: 0)
            for fraction in samples {
                let value = subject.root.evaluate([:], pendingFraction: fraction)
                #expect(value >= previous - 0.0001, "\(subject.name) dropped going from a lower to a higher pendingFraction")
                previous = value
            }
        }
    }
}
