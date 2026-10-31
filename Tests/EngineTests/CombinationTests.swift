import Foundation
import Testing
import Engine

/// Every mix of evaluations the editor can build — weighted averages, sums, formulas, "Nota única",
/// "Por definir", per-term subjects, nested sections, letters, odd scales and every minimum with
/// every consequence — checked against the rules the screens rely on: a finite grade in range,
/// worst ≤ best, a needed grade that really reaches the target, a pass plan that works and a JSON
/// round trip that loses nothing. Random trees come from a fixed seed, so a failure always
/// reproduces.
struct CombinationTests {
    // MARK: Building trees

    /// A small, seeded generator (SplitMix64): the same trees on every run and every machine.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let consequences: [Minimum.Consequence?] = [nil, .fails, .capAt(4.5), .voids, .doesNotAverage, .sendsToExtraordinary]

    static let letters = GradeInputStyle.letters([
        LetterGrade(letter: "A", value: 9), LetterGrade(letter: "B", value: 7),
        LetterGrade(letter: "C", value: 5), LetterGrade(letter: "D", value: 3),
    ])

    /// Builds trees the way the editor does, with unique leaf names (the editor refuses to save
    /// duplicates, and grades are stored by name).
    struct Builder {
        var random: Seeded
        var count = 0

        mutating func name(_ prefix: String) -> String {
            count += 1
            return "\(prefix) \(count)"
        }

        mutating func minimum(on scale: Double) -> Minimum? {
            guard let consequence = CombinationTests.consequences.randomElement(using: &random)!, Bool.random(using: &random) else { return nil }
            let threshold = (Double(Int.random(in: 2...6, using: &random)) / 10 * scale * 100).rounded() / 100
            return Minimum(threshold: threshold, consequence: consequence)
        }

        mutating func grade() -> Node {
            let scale = [10.0, 10, 10, 2, 1, 4, 100, 3.5].randomElement(using: &random)!
            return .grade(Grade(
                name: name("Nota"),
                isFinalExam: Int.random(in: 0..<6, using: &random) == 0 ? true : nil,
                category: GradeCategory.allCases.randomElement(using: &random),
                scaleMax: scale,
                minimum: minimum(on: scale),
                inputStyle: [nil, .points, .percent, CombinationTests.letters].randomElement(using: &random)!
            ))
        }

        /// Weights that add up to 1 (a weighted average or a subject's sum), or anything for a
        /// sum inside another section, which its parent scales.
        mutating func weights(_ count: Int, normalised: Bool) -> [Double] {
            let raw = (0..<count).map { _ in Double(Int.random(in: 1...10, using: &random)) }
            guard normalised else { return raw.map { $0 / 10 } }
            let total = raw.reduce(0, +)
            return raw.map { $0 / total }
        }

        mutating func node(depth: Int, isRoot: Bool = false) -> Node {
            if depth == 0 || (!isRoot && Int.random(in: 0..<3, using: &random) == 0) { return grade() }
            switch Int.random(in: 0..<10, using: &random) {
            case 0...3: return group(.weightedAverage, depth: depth, isRoot: isRoot)
            case 4...5: return group(.sum, depth: depth, isRoot: isRoot)
            case 6: return formula(depth: depth)
            case 7: return group([.max, .min, .bestOf(Int.random(in: 1...3, using: &random))].randomElement(using: &random)!, depth: depth, isRoot: isRoot)
            case 8: return isRoot ? group(.undecided, depth: depth, isRoot: true) : group(.weightedAverage, depth: depth, isRoot: false)
            default: return grade()
            }
        }

        mutating func group(_ combination: Group.Combination, depth: Int, isRoot: Bool) -> Node {
            let count = Int.random(in: 1...5, using: &random)
            let weights = combination == .undecided
                ? Array(repeating: 0, count: count)
                : weights(count, normalised: combination != .sum || isRoot)
            let children = weights.map { WeightedChild(weight: $0, node: node(depth: depth - 1)) }
            return .group(Group(
                name: name("Sección"),
                combination: combination,
                children: children,
                minimum: isRoot ? Minimum(threshold: 5, consequence: .fails) : minimum(on: 10)
            ))
        }

        /// A formula like the guides': a weighted sum, sometimes with a `min`, `max` or `si`.
        mutating func formula(depth: Int) -> Node {
            let keys = Array(["A", "B", "C", "D"].prefix(Int.random(in: 1...4, using: &random)))
            var variables: [String: Node] = [:]
            for key in keys { variables[key] = Bool.random(using: &random) ? grade() : node(depth: depth - 1) }
            let weights = weights(keys.count, normalised: true)
            // Each variable on its own scale, brought to 0–10 before weighing.
            var expression = keys.indices.map { index -> Engine.Expression in
                let scale = variables[keys[index]]!.scaleMax
                return .multiply(.constant(weights[index] * 10 / Swift.max(scale, 1e-9)), .variable(keys[index]))
            }.reduce(Engine.Expression.constant(0)) { .add($0, $1) }
            switch Int.random(in: 0..<4, using: &random) {
            case 0: expression = .min(expression, .constant(10))
            case 1: expression = .max(expression, .constant(0))
            case 2:
                let first = keys[0]
                expression = .ifGreaterOrEqual(
                    lhs: .variable(first), rhs: .constant(variables[first]!.scaleMax * 0.4),
                    then: expression, otherwise: .min(expression, .constant(4.5))
                )
            default: break
            }
            return .formula(Formula(name: name("Fórmula"), expression: expression, variables: variables, minimum: minimum(on: 10)))
        }

        /// A year-long subject graded per term: one section per term with its own evaluation.
        mutating func perTerm(terms: Int) -> Node {
            .group(Group(
                name: name("Anual"),
                combination: .weightedAverage,
                children: (0..<terms).map { _ in WeightedChild(weight: 1 / Double(terms), node: group(.weightedAverage, depth: 2, isRoot: false)) },
                minimum: Minimum(threshold: 5, consequence: .fails)
            ))
        }

        /// "Evaluación continua" or "examen único", sharing the final exam: chosen, or the best.
        mutating func alternatives() -> Node {
            let exam = Grade(name: name("Examen final"), isFinalExam: true, scaleMax: 10, minimum: Bool.random(using: &random) ? Minimum(threshold: 4, consequence: .fails) : nil)
            var continuous = group(.weightedAverage, depth: 2, isRoot: false)
            if case .group(var g) = continuous {
                g.children = g.children.map { WeightedChild(weight: $0.weight * 0.6, node: $0.node) } + [WeightedChild(weight: 0.4, node: .grade(exam))]
                g.minimum = nil
                continuous = .group(g)
            }
            let single = Node.group(Group(name: name("Único"), combination: .weightedAverage, children: [WeightedChild(weight: 1, node: .grade(exam))]))
            let pickBest = Bool.random(using: &random)
            return .alternatives(Alternatives(
                name: name("Modalidad"),
                branches: [.init(node: continuous), .init(node: single)],
                pickBest: pickBest,
                selected: pickBest ? nil : Int.random(in: 0...1, using: &random),
                minimum: Minimum(threshold: 5, consequence: .fails)
            ))
        }

        /// "Nota única": the root is one grade.
        mutating func single() -> Node {
            let scale = [10.0, 100, 4].randomElement(using: &random)!
            return .grade(Grade(name: name("Nota final"), category: .exam, scaleMax: scale))
        }
    }

    /// Several hundred subjects of every shape, and the bundled ones.
    static let trees: [Node] = {
        var builder = Builder(random: Seeded(state: 2026))
        var trees: [Node] = []
        for index in 0..<600 {
            switch index % 10 {
            case 0: trees.append(builder.perTerm(terms: Int.random(in: 2...3, using: &builder.random)))
            case 1: trees.append(builder.single())
            case 2: trees.append(builder.alternatives())
            default: trees.append(builder.node(depth: Int.random(in: 1...4, using: &builder.random), isRoot: true))
            }
        }
        return trees + Subject.all.map(\.root) + DegreeTemplate.all.flatMap { $0.entries.map(\.subject.root) }
    }()

    // MARK: Inputs

    /// Grades for some or all of a tree's leaves, from 0 to above the maximum (the app clamps what's
    /// typed, but a merged backup or an older file could still hold anything).
    static func inputs(for root: Node, using random: inout Seeded, filling share: Double) -> [String: Double] {
        var inputs: [String: Double] = [:]
        for name in root.allLeafNames() where Double.random(in: 0..<1, using: &random) < share {
            let max = root.leaf(named: name)?.scaleMax ?? 10
            inputs[name] = [0, max, max * 0.4, max * 0.5, Double.random(in: 0...max, using: &random)].randomElement(using: &random)!
        }
        return inputs
    }

    /// Whether the tree only has parts the engine promises to be monotonic for: `doesNotAverage`
    /// can lower an average by letting a weak part back in, and a hand-written formula can
    /// subtract. The generated formulas only add, take `min`/`max` and cap with `si`.
    static func isMonotonic(_ node: Node) -> Bool {
        if node.ownMinimum?.consequence == .doesNotAverage { return false }
        switch node {
        case .group(let group): return group.children.allSatisfy { isMonotonic($0.node) }
        case .formula(let formula): return formula.variables.values.allSatisfy(isMonotonic)
        case .alternatives(let alternatives): return alternatives.branches.allSatisfy { isMonotonic($0.node) }
        default: return true
        }
    }

    /// The most the tree can give: 10, or the points of a subject graded as a sum, or a single
    /// grade's own scale.
    static func ceiling(_ root: Node) -> Double {
        Swift.max(root.scaleMax, 10)
    }

    // MARK: Invariants

    @Test func everyTreeGivesAFiniteGradeInRange() {
        var random = Seeded(state: 1)
        for root in Self.trees {
            for share in [0, 0.3, 0.7, 1] {
                let inputs = Self.inputs(for: root, using: &random, filling: share)
                for fraction in [0, 0.25, 0.5, 1.0] {
                    let value = root.evaluate(inputs, pendingFraction: fraction)
                    #expect(value.isFinite)
                    #expect(value >= -1e-9 && value <= Self.ceiling(root) + 1e-9, "\(value) out of range")
                }
            }
        }
    }

    @Test func worstNeverBeatsBest() {
        var random = Seeded(state: 2)
        for root in Self.trees where Self.isMonotonic(root) {
            for share in [0, 0.5, 0.9] {
                let inputs = Self.inputs(for: root, using: &random, filling: share)
                var previous = -Double.infinity
                for step in 0...10 {
                    let value = root.evaluate(inputs, pendingFraction: Double(step) / 10)
                    #expect(value >= previous - 1e-9, "grade drops as pending grades rise")
                    previous = value
                }
            }
        }
    }

    @Test func raisingOneGradeNeverLowersTheFinalOne() {
        var random = Seeded(state: 3)
        for root in Self.trees where Self.isMonotonic(root) {
            let inputs = Self.inputs(for: root, using: &random, filling: 1)
            let before = root.evaluate(inputs, pendingFraction: 0)
            for name in root.allLeafNames() {
                guard let max = root.leaf(named: name)?.scaleMax else { continue }
                var raised = inputs
                raised[name] = max
                #expect(root.evaluate(raised, pendingFraction: 0) >= before - 1e-9, "raising «\(name)» lowered the grade")
            }
        }
    }

    @Test func aCompleteSubjectHasOneGradeWhateverIsAssumedForThePending() {
        var random = Seeded(state: 4)
        for root in Self.trees {
            let inputs = Self.inputs(for: root, using: &random, filling: 1)
            #expect(root.pendingLeaves(inputs).isEmpty)
            #expect(abs(root.evaluate(inputs, pendingFraction: 0) - root.evaluate(inputs, pendingFraction: 1)) < 1e-9)
            #expect(root.status(inputs) != .possible)
            #expect(root.passPlan(inputs, target: 5) == [:])
        }
    }

    @Test func statusAgreesWithTheBestAndWorstCase() {
        var random = Seeded(state: 5)
        for root in Self.trees {
            let threshold = root.minimumThreshold ?? 5
            for share in [0, 0.5, 1] {
                let inputs = Self.inputs(for: root, using: &random, filling: share)
                let worst = root.evaluate(inputs, pendingFraction: 0)
                let best = root.evaluate(inputs, pendingFraction: 1)
                switch root.status(inputs) {
                case .guaranteed:
                    #expect(worst >= threshold && root.meetsMinimums(inputs, pendingFraction: 0))
                case .impossible:
                    // With several schemes, each has to pass on its own: the best grade alone says little.
                    if case .alternatives = root { break }
                    #expect(best < threshold || !root.meetsMinimums(inputs, pendingFraction: 1))
                case .possible:
                    #expect(best >= threshold || !Self.isMonotonic(root))
                }
            }
        }
    }

    @Test func theNeededGradeReachesTheTarget() {
        var random = Seeded(state: 6)
        for root in Self.trees {
            for share in [0, 0.4, 0.8] {
                let inputs = Self.inputs(for: root, using: &random, filling: share)
                for asked in [5.0, 7, 9] {
                    // The subject's own pass mark stands in for its own minimum, so a target is never below it.
                    let target = Swift.max(asked, root.minimumThreshold ?? 0)
                    guard let fraction = root.neededFraction(inputs, target: target) else {
                        // Out of reach: even full marks on everything pending don't make it.
                        if Self.isMonotonic(root) {
                            #expect(root.evaluate(inputs, pendingFraction: 1) < target || !root.meetsMinimums(inputs, pendingFraction: 1))
                        }
                        continue
                    }
                    #expect(fraction >= 0 && fraction <= 1)
                    #expect(root.evaluate(inputs, pendingFraction: fraction) >= target - 1e-9)
                    #expect(root.meetsMinimums(inputs, pendingFraction: fraction))
                    // And it's the lowest that does, give or take the search's tolerance.
                    if Self.isMonotonic(root), fraction > 0.001, root.asAlternatives == nil {
                        let lower = fraction - 0.001
                        #expect(root.evaluate(inputs, pendingFraction: lower) < target || !root.meetsMinimums(inputs, pendingFraction: lower))
                    }
                }
            }
        }
    }

    @Test func thePassPlanReachesTheTarget() {
        var random = Seeded(state: 7)
        for root in Self.trees where Self.isMonotonic(root) {
            for share in [0, 0.5] {
                let inputs = Self.inputs(for: root, using: &random, filling: share)
                let target = root.minimumThreshold ?? 5
                // With nothing pending there's nothing to plan, reached or not.
                guard !root.pendingLeaves(inputs).isEmpty else { continue }
                guard let plan = root.passPlan(inputs, target: target) else {
                    #expect(root.neededFraction(inputs, target: target) == nil)
                    continue
                }
                #expect(Set(plan.keys) == Set(root.pendingLeaves(inputs)))
                var filled = inputs
                for (leaf, fraction) in plan {
                    #expect(fraction >= 0 && fraction <= 1)
                    filled[leaf] = fraction * (root.leaf(named: leaf)?.scaleMax ?? 10)
                }
                #expect(root.evaluate(filled, pendingFraction: 0) >= target - 0.01)
                #expect(root.meetsMinimums(filled, pendingFraction: 0))
            }
        }
    }

    @Test func everyTreeSurvivesAJSONRoundTrip() throws {
        for root in Self.trees {
            let decoded = try JSONDecoder().decode(Node.self, from: JSONEncoder().encode(root))
            #expect(decoded == root)
        }
    }

    @Test func theExtraordinarySittingNoLongerSendsAnyoneThere() {
        var random = Seeded(state: 8)
        func sends(_ node: Node) -> Bool {
            node.ownMinimum?.consequence == .sendsToExtraordinary || node.childNodes.contains(where: sends)
        }
        for root in Self.trees {
            let extraordinary = root.forExtraordinary
            #expect(!sends(extraordinary))
            #expect(extraordinary.allLeafNames() == root.allLeafNames())
            let inputs = Self.inputs(for: root, using: &random, filling: 0.6)
            #expect(root.leavesSentToExtraordinary(inputs).isSubset(of: Set(root.allLeafNames())))
            #expect(extraordinary.leavesSentToExtraordinary(inputs).isEmpty)
        }
    }

    @Test func leafNamesStayUniqueAndFindable() {
        for root in Self.trees {
            let names = root.allLeafNames()
            #expect(Set(names).count == names.count)
            for name in names { #expect(root.leaf(named: name) != nil) }
            // Two schemes share their exam, so a note can appear twice among the grades.
            #expect(Set(root.grades.map(\.name)).isSuperset(of: names))
        }
    }

    // MARK: Every evaluation with every kind of part and minimum

    enum PartKind: CaseIterable {
        case grade, gradeOutOfTwo, letters, weightedSection, sumSection, formulaSection
    }

    /// A subject with `kind` as its first part (carrying the minimum) and a final exam as its
    /// second, combined by `combination`.
    static func subject(_ combination: Group.Combination?, part kind: PartKind, minimum consequence: Minimum.Consequence?) -> Node {
        let threshold: Double = kind == .gradeOutOfTwo ? 0.8 : 4
        let minimum = consequence.map { Minimum(threshold: threshold, consequence: $0) }
        let part: Node
        switch kind {
        case .grade:
            part = .grade(Grade(name: "Prácticas", minimum: minimum))
        case .gradeOutOfTwo:
            part = .grade(Grade(name: "Prácticas", scaleMax: 2, minimum: minimum))
        case .letters:
            part = .grade(Grade(name: "Prácticas", minimum: minimum, inputStyle: letters))
        case .weightedSection:
            part = .group(Group(name: "Prácticas", combination: .weightedAverage, children: [
                WeightedChild(weight: 0.5, node: .grade(Grade(name: "P1"))),
                WeightedChild(weight: 0.5, node: .grade(Grade(name: "P2"))),
            ], minimum: minimum))
        case .sumSection:
            // Two labs worth 5 points each: the section is out of 10.
            part = .group(Group(name: "Prácticas", combination: .sum, children: [
                WeightedChild(weight: 0.5, node: .grade(Grade(name: "P1"))),
                WeightedChild(weight: 0.5, node: .grade(Grade(name: "P2"))),
            ], minimum: minimum))
        case .formulaSection:
            part = .formula(Formula(
                name: "Prácticas",
                expression: .add(.multiply(.constant(0.5), .variable("A")), .multiply(.constant(0.5), .variable("B"))),
                variables: ["A": .grade(Grade(name: "P1")), "B": .grade(Grade(name: "P2"))],
                minimum: minimum
            ))
        }
        let exam = Node.grade(Grade(name: "Examen", isFinalExam: true))
        let pass = Minimum(threshold: 5, consequence: .fails)
        guard let combination else {
            // A formula subject: 40 % labs, 60 % exam.
            let labs = part.scaleMax
            return .formula(Formula(
                name: "Asignatura",
                expression: .add(.multiply(.constant(4 / labs), .variable("L")), .multiply(.constant(0.6), .variable("E"))),
                variables: ["L": part, "E": exam],
                minimum: pass
            ))
        }
        let weights: [Double] = combination == .undecided ? [0, 0] : [0.4, 0.6]
        return .group(Group(name: "Asignatura", combination: combination, children: [
            WeightedChild(weight: weights[0], node: part),
            WeightedChild(weight: weights[1], node: exam),
        ], minimum: pass))
    }

    static let combinations: [Group.Combination?] = [.weightedAverage, .sum, .max, .min, .bestOf(1), .undecided, nil]

    /// The part's leaves at `fraction` of their scale.
    static func part(_ root: Node, at fraction: Double) -> [String: Double] {
        var inputs: [String: Double] = [:]
        for name in root.allLeafNames() where name != "Examen" {
            inputs[name] = fraction * (root.leaf(named: name)?.scaleMax ?? 10)
        }
        return inputs
    }

    @Test(arguments: combinations)
    func everyMixKeepsItsPromises(_ combination: Group.Combination?) throws {
        for kind in PartKind.allCases {
            for consequence in Self.consequences {
                let root = Self.subject(combination, part: kind, minimum: consequence)
                let label = "\(String(describing: combination)) · \(kind) · \(String(describing: consequence))"
                // Every state a student goes through: nothing, only the labs (below and above the
                // minimum), only the exam, everything.
                let states: [[String: Double]] = [
                    [:],
                    Self.part(root, at: 0.2),
                    Self.part(root, at: 0.9),
                    ["Examen": 7],
                    Self.part(root, at: 0.2).merging(["Examen": 9]) { $1 },
                    Self.part(root, at: 0.9).merging(["Examen": 9]) { $1 },
                    Self.part(root, at: 1).merging(["Examen": 10]) { $1 },
                    Self.part(root, at: 0).merging(["Examen": 0]) { $1 },
                ]
                for inputs in states {
                    let worst = root.evaluate(inputs, pendingFraction: 0)
                    let best = root.evaluate(inputs, pendingFraction: 1)
                    #expect(worst.isFinite && best.isFinite, "\(label)")
                    #expect(worst >= 0 && best <= 10 + 1e-9, "\(label): \(worst)…\(best)")
                    if consequence != .doesNotAverage { #expect(worst <= best + 1e-9, "\(label)") }
                    if let needed = root.neededFraction(inputs, target: 5) {
                        #expect(root.evaluate(inputs, pendingFraction: needed) >= 5 - 1e-9, "\(label)")
                    }
                    _ = root.passPlan(inputs, target: 5)
                    _ = root.leavesSentToExtraordinary(inputs)
                    _ = root.forExtraordinary.status(inputs)
                }
                #expect(try JSONDecoder().decode(Node.self, from: JSONEncoder().encode(root)) == root, "\(label)")
            }
        }
    }

    // MARK: Worked examples

    /// Labs 40 % with a minimum of 4, exam 60 %: what each consequence does to a 3 in the labs and
    /// a 9 in the exam, worked out by hand, for a section of each kind.
    @Test(arguments: PartKind.allCases)
    func eachConsequenceOnAMissedMinimum(_ kind: PartKind) {
        let missed = Self.part(Self.subject(.weightedAverage, part: kind, minimum: nil), at: 0.3).merging(["Examen": 9]) { $1 }
        func grade(_ consequence: Minimum.Consequence?) -> Double {
            Self.subject(.weightedAverage, part: kind, minimum: consequence).evaluate(missed, pendingFraction: 0)
        }
        func status(_ consequence: Minimum.Consequence?) -> PassStatus {
            Self.subject(.weightedAverage, part: kind, minimum: consequence).status(missed)
        }
        // 0,4 · 3 + 0,6 · 9 = 6,6.
        #expect(abs(grade(nil) - 6.6) < 1e-9)
        #expect(status(nil) == .guaranteed)
        // Failed regardless of the 6,6.
        #expect(abs(grade(.fails) - 6.6) < 1e-9)
        #expect(status(.fails) == .impossible)
        // Capped at 4,5.
        #expect(abs(grade(.capAt(4.5)) - 4.5) < 1e-9)
        #expect(status(.capAt(4.5)) == .impossible)
        // The labs count as a 0: 0,6 · 9 = 5,4.
        #expect(abs(grade(.voids) - 5.4) < 1e-9)
        #expect(status(.voids) == .guaranteed)
        // The labs are left out: only the exam, 9.
        #expect(abs(grade(.doesNotAverage) - 9) < 1e-9)
        // The ordinary is failed; the extraordinary keeps the 6,6.
        let sends = Self.subject(.weightedAverage, part: kind, minimum: .sendsToExtraordinary)
        #expect(sends.status(missed) == .impossible)
        #expect(sends.forExtraordinary.status(missed) == .guaranteed)
        #expect(Set(sends.leavesSentToExtraordinary(missed)) == Set(sends.allLeafNames().filter { $0 != "Examen" }))
    }

    @Test(arguments: [Group.Combination?.some(.weightedAverage), .some(.sum), nil])
    func theSameGradesGiveTheSameResultHoweverTheSubjectIsWritten(_ combination: Group.Combination?) {
        // 40 % labs, 60 % exam written as a weighted average, a 4 + 6 point sum or a formula.
        let root = Self.subject(combination, part: .grade, minimum: nil)
        #expect(abs(root.evaluate(["Prácticas": 5, "Examen": 8], pendingFraction: 0) - 6.8) < 1e-9)
        #expect(abs((root.neededFraction(["Prácticas": 5], target: 5) ?? -1) - 0.5) < 0.001)
        #expect(root.status(["Prácticas": 10]) == .possible)
        // 4 + 0,6 · 1 = 4,6.
        #expect(root.status(["Prácticas": 10, "Examen": 1]) == .impossible)
    }

    @Test func maxMinAndBestOfPickTheRightParts() {
        let parts: [String: Double] = ["Prácticas": 3, "Examen": 9]
        #expect(Self.subject(.max, part: .grade, minimum: nil).evaluate(parts, pendingFraction: 0) == 9)
        #expect(Self.subject(.min, part: .grade, minimum: nil).evaluate(parts, pendingFraction: 0) == 3)
        #expect(Self.subject(.bestOf(1), part: .grade, minimum: nil).evaluate(parts, pendingFraction: 0) == 9)
    }

    @Test func aSectionOutOfTwoIsWeighedOnItsOwnScale() {
        // 1,6 out of 2 is an 8.
        let root = Self.subject(.weightedAverage, part: .gradeOutOfTwo, minimum: nil)
        #expect(abs(root.evaluate(["Prácticas": 1.6, "Examen": 5], pendingFraction: 0) - 6.2) < 1e-9)
    }

    @Test func aPerTermSubjectAveragesItsTerms() {
        let term = { (index: Int) in
            Node.group(Group(name: "\(index)º Trimestre", combination: .weightedAverage, children: [
                WeightedChild(weight: 0.3, node: .grade(Grade(name: "Trabajo (\(index)º Trimestre)"))),
                WeightedChild(weight: 0.7, node: .grade(Grade(name: "Examen (\(index)º Trimestre)"))),
            ]))
        }
        let root = Node.group(Group(name: "Anual", combination: .weightedAverage, children: (1...3).map {
            WeightedChild(weight: 1.0 / 3, node: term($0))
        }, minimum: Minimum(threshold: 5, consequence: .fails)))
        var inputs: [String: Double] = [:]
        for index in 1...3 {
            inputs["Trabajo (\(index)º Trimestre)"] = 10
            inputs["Examen (\(index)º Trimestre)"] = Double(index * 2)
        }
        // Terms: 4,4 · 5,8 · 7,2 → 5,8.
        #expect(abs(root.evaluate(inputs, pendingFraction: 0) - 5.8) < 1e-9)
        inputs["Examen (3º Trimestre)"] = nil
        // 3rd term: 3 + 0,7·x; average ≥ 5 needs 4,4 + 5,8 + 3 + 0,7x ≥ 15 → x ≥ 2,57.
        let needed = try! #require(root.neededFraction(inputs, target: 5))
        #expect(abs(needed * 10 - 1.8 / 0.7) < 0.01)
    }

    @Test func aSingleGradeSubjectIsJustThatGrade() {
        let root = Node.grade(Grade(name: "Nota final", category: .exam, scaleMax: 100))
        #expect(root.evaluate(["Nota final": 73], pendingFraction: 0) == 73)
        #expect(root.status([:]) == .possible)
        #expect(root.status(["Nota final": 4]) == .impossible)
        #expect(root.allLeafNames() == ["Nota final"])
    }

    @Test func anUndecidedSubjectStaysInRangeWhateverItsSectionsAre() {
        let root = Self.subject(.undecided, part: .sumSection, minimum: .voids)
        for inputs: [String: Double] in [[:], ["P1": 10, "P2": 10, "Examen": 10], ["P1": 0, "P2": 1, "Examen": 3]] {
            let value = root.evaluate(inputs, pendingFraction: 0.5)
            #expect(value >= 0 && value <= 10)
        }
    }

    // MARK: Hostile values

    /// Values an old or hand-edited file could hold: negative and huge weights, zero and negative
    /// scales, thresholds above the scale, inputs above the maximum.
    @Test func hostileValuesNeverGiveANonNumber() {
        let scales: [Double] = [0, -5, 1e-12, 10, 1e12]
        let weights: [Double] = [0, -1, 0.5, 1e9]
        for scale in scales {
            for weight in weights {
                for combination in [Group.Combination.weightedAverage, .sum, .max, .min, .bestOf(0), .bestOf(-3), .undecided] {
                    let root = Node.group(Group(name: "G", combination: combination, children: [
                        WeightedChild(weight: weight, node: .grade(Grade(name: "A", scaleMax: scale, minimum: Minimum(threshold: 1e9, consequence: .voids)))),
                        WeightedChild(weight: 1 - weight, node: .grade(Grade(name: "B"))),
                    ], minimum: Minimum(threshold: 5, consequence: .fails)))
                    for inputs in [[:], ["A": 1e300, "B": -1e300], ["A": 5, "B": 5]] {
                        for fraction in [0.0, 1] {
                            #expect(!root.evaluate(inputs, pendingFraction: fraction).isNaN)
                        }
                        _ = root.status(inputs)
                        _ = root.neededFraction(inputs, target: 5)
                        _ = root.passPlan(inputs, target: 5)
                    }
                }
            }
        }
    }

    // MARK: Speed

    /// The home screen works out every subject on each redraw: even a big one (a year-long subject
    /// graded per term with ten labs a term) must take a few milliseconds, not a noticeable pause.
    @Test func aBigSubjectIsWorkedOutQuickly() {
        let term = { (index: Int) in
            Node.group(Group(name: "Periodo \(index)", combination: .weightedAverage, children: [
                WeightedChild(weight: 0.4, node: .group(Group(name: "Prácticas \(index)", combination: .weightedAverage, children: (1...10).map {
                    WeightedChild(weight: 0.1, node: .grade(Grade(name: "P\($0) (\(index))", minimum: Minimum(threshold: 3, consequence: .voids))))
                }, minimum: Minimum(threshold: 4, consequence: .capAt(4.5))))),
                WeightedChild(weight: 0.2, node: .group(Group(name: "Controles \(index)", combination: .bestOf(3), children: (1...5).map {
                    WeightedChild(weight: 0.2, node: .grade(Grade(name: "C\($0) (\(index))", scaleMax: 2)))
                }))),
                WeightedChild(weight: 0.4, node: .grade(Grade(name: "Examen (\(index))", isFinalExam: true, minimum: Minimum(threshold: 4, consequence: .fails)))),
            ]))
        }
        let root = Node.group(Group(name: "Anual", combination: .weightedAverage, children: (1...4).map {
            WeightedChild(weight: 0.25, node: term($0))
        }, minimum: Minimum(threshold: 5, consequence: .fails)))
        var inputs: [String: Double] = [:]
        for (index, name) in root.allLeafNames().enumerated() where index % 2 == 0 { inputs[name] = 6 }

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<10 {
                _ = root.evaluate(inputs, pendingFraction: 0)
                _ = root.evaluate(inputs, pendingFraction: 1)
                _ = root.status(inputs)
                _ = root.neededFraction(inputs, target: 5)
                _ = root.passPlan(inputs, target: 5)
            }
        }
        // Ten full workings-out, generously under a second even on a slow test machine.
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }
}

extension Node {
    var asAlternatives: Alternatives? { if case .alternatives(let a) = self { a } else { nil } }

    /// The nodes right below this one, in the tests' own words (the engine's are internal).
    var childNodes: [Node] {
        switch self {
        case .group(let group): group.children.map(\.node)
        case .formula(let formula): Array(formula.variables.values)
        case .alternatives(let alternatives): alternatives.branches.map(\.node)
        case .grade, .bonus, .requirement: []
        }
    }
}
