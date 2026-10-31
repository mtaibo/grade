import Foundation
import Testing
import Engine

/// "Evaluación continua" (labs 40 %, exam 60 % with a 4 minimum) or "examen único" (the same
/// exam, 100 %): chosen by the student, or the best of the two.
struct AlternativesTests {
    static func subject(pickBest: Bool, selected: Int? = nil) -> Node {
        let exam = Node.grade(Grade(name: "Examen", isFinalExam: true))
        let continuous = Node.group(Group(name: "Continua", combination: .weightedAverage, children: [
            WeightedChild(weight: 0.4, node: .grade(Grade(name: "Prácticas"))),
            WeightedChild(weight: 0.6, node: .grade(Grade(name: "Examen", isFinalExam: true, minimum: Minimum(threshold: 4, consequence: .fails)))),
        ]))
        let single = Node.group(Group(name: "Único", combination: .weightedAverage, children: [WeightedChild(weight: 1, node: exam)]))
        return .alternatives(Alternatives(name: "Física", branches: [.init(node: continuous), .init(node: single)], pickBest: pickBest, selected: selected, minimum: Minimum(threshold: 5, consequence: .fails)))
    }

    @Test func theChosenSchemeIsTheOneThatCounts() {
        let continuous = Self.subject(pickBest: false, selected: 0)
        let single = Self.subject(pickBest: false, selected: 1)
        let inputs: [String: Double] = ["Prácticas": 10, "Examen": 4.5]
        // 0,4 · 10 + 0,6 · 4,5 = 6,7 by continuous; just the 4,5 by the single exam.
        #expect(abs(continuous.evaluate(inputs, pendingFraction: 0) - 6.7) < 1e-9)
        #expect(continuous.status(inputs) == .guaranteed)
        #expect(single.evaluate(inputs, pendingFraction: 0) == 4.5)
        #expect(single.status(inputs) == .impossible)
        // The single exam doesn't ask for the labs.
        #expect(single.allLeafNames() == ["Examen"])
        #expect(Set(continuous.allLeafNames()) == ["Prácticas", "Examen"])
    }

    @Test func theBestOfBothIsTakenWhenTheGuideSaysSo() {
        let best = Self.subject(pickBest: true)
        #expect(abs(best.evaluate(["Prácticas": 10, "Examen": 4.5], pendingFraction: 0) - 6.7) < 1e-9)
        // Weak labs: the exam alone is better.
        #expect(best.evaluate(["Prácticas": 1, "Examen": 8], pendingFraction: 0) == 8)
        // The shared exam is one note.
        #expect(best.allLeafNames().filter { $0 == "Examen" }.count == 1)
    }

    /// Under 4 in the exam fails the continuous scheme however good the labs; the single exam
    /// isn't passed with a 3,5 either.
    @Test func aFailedSchemeCantBeTheOneThatPasses() {
        let best = Self.subject(pickBest: true)
        let inputs: [String: Double] = ["Prácticas": 10, "Examen": 3.5]
        #expect(best.status(inputs) == .impossible)
        // The grade shown is still the higher one, as with any failed minimum.
        #expect(abs(best.evaluate(inputs, pendingFraction: 0) - 6.1) < 1e-9)
    }

    @Test func theNeededGradeAndPlanFollowTheEasiestScheme() throws {
        let best = Self.subject(pickBest: true)
        // With a 10 in labs, continuous needs (5 − 4) / 0,6 ≈ 1,7, but its minimum asks for a 4.
        let needed = try #require(best.neededFraction(["Prácticas": 10], target: 5))
        #expect(abs(needed - 0.4) < 0.001)
        let plan = try #require(best.passPlan(["Prácticas": 10], target: 5))
        #expect(abs((plan["Examen"] ?? 0) - 0.4) < 0.001)
        // Nothing in yet: the plan goes for whichever needs less.
        let empty = try #require(best.passPlan([:], target: 5))
        #expect(Set(empty.keys) == ["Prácticas", "Examen"])
    }

    @Test func aChoicePastTheEndFallsBackToTheFirst() {
        let broken = Self.subject(pickBest: false, selected: 7)
        #expect(Set(broken.allLeafNames()) == ["Prácticas", "Examen"])
        let empty = Node.alternatives(Alternatives(name: "Vacía", branches: []))
        #expect(empty.evaluate([:], pendingFraction: 1) == 0)
        #expect(empty.status([:]) == .impossible)
    }

    @Test func roundingCanBeAskedForThroughTheThreshold() {
        let best = Self.subject(pickBest: true)
        // 4,95 rounds to 5,0 when the transcript rounds to one decimal.
        #expect(best.status(["Prácticas": 0, "Examen": 4.95]) == .impossible)
        #expect(best.status(["Prácticas": 0, "Examen": 4.95], threshold: 4.95) == .guaranteed)
    }

    @Test func schemesSurviveAJSONRoundTrip() throws {
        for root in [Self.subject(pickBest: true), Self.subject(pickBest: false, selected: 1)] {
            #expect(try JSONDecoder().decode(Node.self, from: JSONEncoder().encode(root)) == root)
        }
        // Older files without the new fields still read.
        let old = #"{"alternatives":{"_0":{"name":"A","branches":[],"pickBest":false}}}"#
        #expect(throws: Never.self) { try JSONDecoder().decode(Node.self, from: Data(old.utf8)) }
    }
}
