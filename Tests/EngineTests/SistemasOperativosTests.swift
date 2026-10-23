import Testing
import Engine

/// From guide/extracted/sistemasOperativos.json — labs 25%, exam 75%, and at least 4/10 on the exam
/// to pass no matter the average. The first guide where a single part's minimum fails the subject.
struct SistemasOperativosTests {
    private let root = Subject.sistemasOperativos.root

    @Test func averageAloneWouldPassButTheExamMinimumFailsIt() {
        // 0.25 * 10 + 0.75 * 3.8 = 5.35 ≥ 5, but 3.8 < 4 on the exam.
        let inputs: [String: Double] = ["Prácticas de laboratorio": 10, "Prueba objetiva": 3.8]
        #expect(abs(root.evaluate(inputs, pendingFraction: 0) - 5.35) < 0.0001)
        #expect(root.status(inputs) == .impossible)
    }

    @Test func passesWhenBothTheAverageAndTheExamMinimumAreMet() {
        let inputs: [String: Double] = ["Prácticas de laboratorio": 6, "Prueba objetiva": 5]
        #expect(root.status(inputs) == .guaranteed)
    }

    @Test func neededGradeIsTheExamMinimumWhenLabsAlreadyCoverTheAverage() {
        // Full labs: the average only needs 3.33 on the exam, but the exam itself needs a 4.
        let inputs: [String: Double] = ["Prácticas de laboratorio": 10]
        #expect(root.status(inputs) == .possible)
        let needed = root.neededFraction(inputs, target: 5)
        #expect(needed.map { abs($0 - 0.4) < 0.001 } == true)
    }

    @Test func neededGradeIsTheAverageWhenThatAsksForMoreThanTheMinimum() {
        // No labs: 0.75 * exam ≥ 5 → exam ≥ 6.67, above the 4 minimum.
        let inputs: [String: Double] = ["Prácticas de laboratorio": 0]
        let needed = root.neededFraction(inputs, target: 5)
        #expect(needed.map { abs($0 - 2.0 / 3.0) < 0.001 } == true)
    }
}
