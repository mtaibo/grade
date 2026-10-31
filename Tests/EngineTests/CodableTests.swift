import Foundation
import Testing
import Engine

/// The app now stores subjects as JSON so they can be edited; a tree that doesn't survive the
/// round trip unchanged would silently corrupt a student's subject on the next launch.
struct CodableTests {
    @Test func referenceSubjectsSurviveAJSONRoundTrip() throws {
        for subject in Subject.all {
            let data = try JSONEncoder().encode(subject)
            let decoded = try JSONDecoder().decode(Subject.self, from: data)
            #expect(decoded == subject, "\(subject.name) changed after encoding and decoding")
        }
    }

    /// Libraries saved before grades had dates must still load.
    @Test func gradeWithoutADateStillDecodes() throws {
        let json = Data(#"{"name":"Prueba 1","scaleMax":10}"#.utf8)
        let grade = try JSONDecoder().decode(Grade.self, from: json)
        #expect(grade.name == "Prueba 1")
        #expect(grade.date == nil)
    }

    /// "Por definir": sections with no weights, kept as they are until the evaluation is chosen.
    @Test func undecidedGroupSurvivesARoundTrip() throws {
        let root = Node.group(Group(name: "Física", combination: .undecided, children: [
            WeightedChild(weight: 0, node: .grade(Grade(name: "Práctica 1"))),
            WeightedChild(weight: 0, node: .grade(Grade(name: "Control 1", scaleMax: 2))),
        ]))
        let decoded = try JSONDecoder().decode(Node.self, from: JSONEncoder().encode(root))
        #expect(decoded == root)
        // Weightless parts still give the engine a value in range, even if the app never shows it.
        #expect(abs(root.evaluate(["Práctica 1": 8, "Control 1": 1], pendingFraction: 0) - 6.5) < 1e-9)
    }

    @Test func gradeDateSurvivesARoundTrip() throws {
        let grade = Grade(name: "Entrega práctica 1", date: Date(timeIntervalSinceReferenceDate: 815_000_000))
        let decoded = try JSONDecoder().decode(Grade.self, from: JSONEncoder().encode(grade))
        #expect(decoded == grade)
    }

    @Test func letterGradeStyleSurvivesARoundTrip() throws {
        let grade = Grade(name: "Prácticas", inputStyle: .letters([LetterGrade(letter: "A", value: 10), LetterGrade(letter: "B", value: 7.5)]))
        let decoded = try JSONDecoder().decode(Grade.self, from: JSONEncoder().encode(grade))
        #expect(decoded == grade)
    }
}
