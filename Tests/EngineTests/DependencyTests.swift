import Testing
import Engine
import Foundation

/// What happens when a section misses its minimum: each `Minimum.Consequence` on a labs 40 % /
/// exam 60 % subject with a 4 on the labs as the minimum.
struct DependencyTests {
    private func subject(_ consequence: Minimum.Consequence) -> Node {
        .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.4, node: .grade(Grade(name: "Prácticas", minimum: Minimum(threshold: 4, consequence: consequence)))),
                WeightedChild(weight: 0.6, node: .grade(Grade(name: "Examen", isFinalExam: true))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    }

    private let missed: [String: Double] = ["Prácticas": 3, "Examen": 8]
    private let met: [String: Double] = ["Prácticas": 6, "Examen": 8]

    @Test func voidedSectionCountsAsZero() {
        let root = subject(.voids)
        #expect(abs(root.evaluate(missed, pendingFraction: 0) - 4.8) < 0.0001)
        #expect(abs(root.evaluate(met, pendingFraction: 0) - 7.2) < 0.0001)
    }

    @Test func sectionThatDoesNotAverageLeavesItsWeightToTheRest() {
        // Only the exam counts: 8.
        #expect(abs(subject(.doesNotAverage).evaluate(missed, pendingFraction: 0) - 8) < 0.0001)
    }

    @Test func capLimitsTheFinalGradeEvenFromANestedSection() {
        let root = Node.group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.4, node: .group(Group(name: "Prácticas", combination: .weightedAverage, children: [
                    WeightedChild(weight: 0.5, node: .grade(Grade(name: "P1", minimum: Minimum(threshold: 4, consequence: .capAt(4.5))))),
                    WeightedChild(weight: 0.5, node: .grade(Grade(name: "P2"))),
                ]))),
                WeightedChild(weight: 0.6, node: .grade(Grade(name: "Examen"))),
            ]
        ))
        // Uncapped: 0.4 * 6.5 + 0.6 * 9 = 8; P1 under 4 caps the whole subject at 4.5.
        #expect(abs(root.evaluate(["P1": 3, "P2": 10, "Examen": 9], pendingFraction: 0) - 4.5) < 0.0001)
    }

    @Test func missingTheMinimumForTheOrdinaryFailsItButNotTheExtraordinary() {
        let root = subject(.sendsToExtraordinary)
        #expect(root.status(missed) == .impossible)
        #expect(root.status(met) == .guaranteed)
        #expect(root.forExtraordinary.status(missed) == .guaranteed)
        #expect(root.leavesSentToExtraordinary(missed) == ["Prácticas"])
        #expect(root.leavesSentToExtraordinary(["Examen": 8]).isEmpty)
    }

    @Test func newConsequencesSurviveAJSONRoundTrip() throws {
        for consequence: Minimum.Consequence in [.voids, .doesNotAverage, .sendsToExtraordinary, .capAt(4.5), .fails] {
            let root = subject(consequence)
            #expect(try JSONDecoder().decode(Node.self, from: JSONEncoder().encode(root)) == root)
        }
    }
}
