import Foundation
import Testing
import Engine

/// The Ingeniería Informática template: the seven syllabi added for it (hand-calculated against
/// each guide) and the template's own shape.
struct InformaticaTemplateTests {
    private func final(_ subject: Subject, _ inputs: [String: Double]) -> Double {
        subject.root.evaluate(inputs, pendingFraction: 0)
    }

    @Test func matematicaDiscretaGEIIsTwentyEighty() {
        // 0.2 * 10 + 0.8 * 5 = 6
        #expect(abs(final(.matematicaDiscretaGEI, ["Prácticas de laboratorio": 10, "Prueba objetiva": 5]) - 6) < 0.0001)
    }

    @Test func calculoExamTakesWhatTheSeminarsLeave() {
        let full: [String: Double] = ["Control 1": 10, "Control 2": 10, "Control 3": 10]
        // Seminars 6 points, so the exam is worth 40%: 6 + 0.4 * 5 = 8.
        #expect(abs(final(.calculo, full.merging(["Examen final": 5]) { $1 }) - 8) < 0.0001)
        // Seminars 3 points: 3 + 0.7 * 4 = 5.8.
        let half: [String: Double] = ["Control 1": 5, "Control 2": 5, "Control 3": 5, "Examen final": 4]
        #expect(abs(final(.calculo, half) - 5.8) < 0.0001)
    }

    @Test func calculoUnderTwoAndAHalfOnTheExamDropsTheSeminars() {
        let inputs: [String: Double] = ["Control 1": 10, "Control 2": 10, "Control 3": 10, "Examen final": 2]
        #expect(abs(final(.calculo, inputs) - 2) < 0.0001)
        #expect(Subject.calculo.root.status(inputs) == .impossible)
    }

    @Test func programacion1NeedsThreeAndAHalfOnTheExam() {
        let weakExam: [String: Double] = ["Prácticas de laboratorio": 10, "Prueba práctica": 10, "Examen final": 3.4]
        // 3 + 1 + 2.04 = 6.04 would pass, but the exam minimum fails it.
        #expect(final(.programacion1, weakExam) > 5)
        #expect(Subject.programacion1.root.status(weakExam) == .impossible)
        let enough: [String: Double] = ["Prácticas de laboratorio": 10, "Prueba práctica": 10, "Examen final": 3.5]
        #expect(Subject.programacion1.root.status(enough) == .guaranteed)
    }

    @Test func fundamentosCapsAt4Point9UnderAQuarterOfAnyPart() {
        // 3 + 3 + 0.8 = 6.8, but 2 < 2.5 on the exam caps it.
        let inputs: [String: Double] = ["Prácticas de laboratorio": 10, "Controles": 10, "Examen final": 2]
        #expect(abs(final(.fundamentosComputadores, inputs) - 4.9) < 0.0001)
    }

    @Test func programacion2CapsAt4Point5AndOnlyAddsTheBonusOncePassed() {
        let passed: [String: Double] = ["Prácticas de laboratorio": 8, "Prueba objetiva": 6, "Solución de problemas": 1]
        // 3.2 + 3.6 = 6.8, plus the extra point.
        #expect(abs(final(.programacion2, passed) - 7.8) < 0.0001)
        let weakLabs: [String: Double] = ["Prácticas de laboratorio": 4, "Prueba objetiva": 10, "Solución de problemas": 1]
        #expect(abs(final(.programacion2, weakLabs) - 4.5) < 0.0001)
        let perfect: [String: Double] = ["Prácticas de laboratorio": 10, "Prueba objetiva": 10, "Solución de problemas": 1]
        #expect(abs(final(.programacion2, perfect) - 10) < 0.0001)
    }

    @Test func tecnologiaElectronicaHalvesTheSumUnderOnePointFiveOnTheExam() {
        let weak: [String: Double] = ["Prácticas de laboratorio": 3, "Solución de problemas": 2, "Prueba mixta": 1]
        #expect(abs(final(.tecnologiaElectronica, weak) - 3) < 0.0001)
        let enough: [String: Double] = ["Prácticas de laboratorio": 2, "Solución de problemas": 1, "Prueba mixta": 1.5]
        #expect(abs(final(.tecnologiaElectronica, enough) - 4.5) < 0.0001)
    }

    @Test func algoritmosWeighsTheTwoExamsInsideTheObjectiveTest() {
        let inputs: [String: Double] = [
            "Prácticas de laboratorio": 10, "Prueba 1": 10, "Prueba 2": 10, "Solución de problemas": 10,
            "Examen de teoría": 5, "Examen de prácticas": 5,
        ]
        // 1 + 0.5 + 1 + 0.75 * 5 = 6.25
        #expect(abs(final(.algoritmos, inputs) - 6.25) < 0.0001)
    }

    @Test func informaticaTemplateCoversTwoYearsWithoutRepeats() {
        let template = DegreeTemplate.informatica
        #expect(template.years == [1, 2])
        #expect(template.entries.count == 15)
        for year in template.years {
            for term in 1...2 {
                let names = template.entries(year: year, term: term).map(\.subject.name)
                #expect(Set(names).count == names.count)
            }
        }
        #expect(template.entries(year: 1, term: 1).count == 5)
        #expect(template.entries(year: 1, term: 2).count == 5)
        #expect(template.entries(year: 2, term: 1).count == 5)
        #expect(template.entries(year: 2, term: 2).isEmpty)
    }
}

struct FinalExamMarkerTests {
    @Test func everyReferenceSubjectMarksItsFinalExam() {
        for subject in Subject.all {
            #expect(subject.root.grades.contains { $0.isFinalExam == true }, "\(subject.name)")
        }
    }

    @Test func gradesSavedWithoutTheMarkerStillDecode() throws {
        let json = #"{"name":"Examen","scaleMax":10}"#
        let grade = try JSONDecoder().decode(Grade.self, from: Data(json.utf8))
        #expect(grade.isFinalExam == nil)
    }
}

struct GradeCategoryTests {
    @Test func categoryIsGuessedFromTheNameUnlessChosen() {
        #expect(Grade(name: "Prácticas de laboratorio").kind == .work)
        #expect(Grade(name: "Solución de problemas").kind == .work)
        #expect(Grade(name: "Prueba práctica").kind == .quiz)
        #expect(Grade(name: "Controles").kind == .quiz)
        #expect(Grade(name: "Prueba objetiva", isFinalExam: true).kind == .exam)
        #expect(Grade(name: "Examen de teoría").kind == .exam)
        #expect(Grade(name: "Prácticas", category: .exam).kind == .exam)
    }
}
