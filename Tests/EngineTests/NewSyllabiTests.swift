import Testing
import Engine

/// The second batch of syllabi: Álgebra, Administración y Gestión de Organizaciones, Informática
/// Básica, Diseño Software and Paradigmas de Programación. Hand-calculated against each guide.
struct NewSyllabiTests {
    @Test func algebraIsAPlainWeightedAverage() {
        // 0.3 * 8 + 0.7 * 5 = 5.9
        let inputs: [String: Double] = ["Prácticas de laboratorio": 8, "Prueba objetiva": 5]
        #expect(abs(Subject.algebra.root.evaluate(inputs, pendingFraction: 0) - 5.9) < 0.0001)
    }

    @Test func administracionPassesOnContinuousAssessmentPlusAWeakExam() {
        // 3 × 10% at 10 + 70% at 3 = 3 + 2.1 = 5.1
        let inputs: [String: Double] = ["Prácticas a través de TIC": 10, "Seminario": 10, "Solución de problemas": 10, "Prueba mixta": 3]
        let root = Subject.administracionGestionOrganizaciones.root
        #expect(abs(root.evaluate(inputs, pendingFraction: 0) - 5.1) < 0.0001)
        #expect(root.status(inputs) == .guaranteed)
    }

    @Test func informaticaBasicaCapsAt4Point9UnderTheExamMinimum() {
        // 4/4 labs + 2/6 exam would be 4 + 2 = 6, but 2 < 2.4 on the exam caps it at 4.9.
        let inputs: [String: Double] = ["Prácticas de laboratorio": 4, "Prueba mixta": 2]
        let root = Subject.informaticaBasica.root
        #expect(abs(root.evaluate(inputs, pendingFraction: 0) - 4.9) < 0.0001)
        #expect(root.status(inputs) == .impossible)
    }

    @Test func informaticaBasicaNeedsTheExamMinimumEvenWithFullLabs() {
        // Full labs: the average would need 1/6 of the exam, but the cap lifts only at 2.4/6 = 40%.
        let inputs: [String: Double] = ["Prácticas de laboratorio": 4]
        let needed = Subject.informaticaBasica.root.neededFraction(inputs, target: 5)
        #expect(needed.map { abs($0 - 0.4) < 0.001 } == true)
    }

    @Test func disenoSoftwareCapsAt4Point5UnderEitherMinimum() {
        // 0.33 * 3.5 + 0.67 * 9 = 7.185, but labs under 4 cap it at 4.5.
        let inputs: [String: Double] = ["Prácticas de laboratorio": 3.5, "Prueba objetiva": 9]
        let root = Subject.disenoSoftware.root
        #expect(abs(root.evaluate(inputs, pendingFraction: 0) - 4.5) < 0.0001)
        #expect(root.status(inputs) == .impossible)
    }

    @Test func disenoSoftwareIsUncappedOnceBothMinimumsAreMet() {
        // 0.33 * 4 + 0.67 * 6 = 1.32 + 4.02 = 5.34
        let inputs: [String: Double] = ["Prácticas de laboratorio": 4, "Prueba objetiva": 6]
        let root = Subject.disenoSoftware.root
        #expect(abs(root.evaluate(inputs, pendingFraction: 0) - 5.34) < 0.0001)
        #expect(root.status(inputs) == .guaranteed)
    }

    @Test func paradigmasExamWeightShrinksWithConsolidatedPracticalTests() {
        // L = 2, P = 1, E = 7 → 3 + 0.1 * (8 − 1) * 7 = 7.9
        let inputs: [String: Double] = ["Prácticas de laboratorio": 2, "Pruebas prácticas": 1, "Prueba objetiva": 7]
        #expect(abs(Subject.paradigmasProgramacion.root.evaluate(inputs, pendingFraction: 0) - 7.9) < 0.0001)
    }
}
