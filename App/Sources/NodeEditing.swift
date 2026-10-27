import Engine
import Foundation

/// Read/write views onto `Node`'s cases, so editors can bind straight into the tree
/// (`Binding($node.asGroup)`) instead of switching and reassembling by hand at every level.
extension Node {
    var title: String {
        get {
            switch self {
            case .grade(let grade): grade.name
            case .group(let group): group.name
            case .alternatives(let alternatives): alternatives.name
            case .bonus(let bonus): bonus.name
            case .requirement(let requirement): requirement.name
            case .formula(let formula): formula.name
            }
        }
        set {
            switch self {
            case .grade(var grade): grade.name = newValue; self = .grade(grade)
            case .group(var group): group.name = newValue; self = .group(group)
            case .alternatives(var alternatives): alternatives.name = newValue; self = .alternatives(alternatives)
            case .bonus(var bonus): bonus.name = newValue; self = .bonus(bonus)
            case .requirement(var requirement): requirement.name = newValue; self = .requirement(requirement)
            case .formula(var formula): formula.name = newValue; self = .formula(formula)
            }
        }
    }

    var asGrade: Grade? {
        get { if case .grade(let grade) = self { grade } else { nil } }
        set { if let newValue { self = .grade(newValue) } }
    }

    var asGroup: Group? {
        get { if case .group(let group) = self { group } else { nil } }
        set { if let newValue { self = .group(newValue) } }
    }

    var asFormula: Formula? {
        get { if case .formula(let formula) = self { formula } else { nil } }
        set { if let newValue { self = .formula(newValue) } }
    }

    /// Every grade under this node that has a due date, as (leaf name, date).
    var datedGrades: [(name: String, date: Date)] {
        switch self {
        case .grade(let grade): grade.date.map { [(grade.name, $0)] } ?? []
        case .group(let group): group.children.flatMap(\.node.datedGrades)
        case .formula(let formula): formula.variables.values.flatMap(\.datedGrades)
        case .alternatives(let alternatives): alternatives.branches.flatMap(\.node.datedGrades)
        case .bonus, .requirement: []
        }
    }

    /// A group made only of plain grades: what "several notes" in the editor turns a part into.
    var isGroupOfGrades: Bool {
        guard case .group(let group) = self else { return false }
        return !group.children.isEmpty && group.children.allSatisfy { $0.node.asGrade != nil }
    }

    /// 1 for a single grade, the number of notes for a group of grades.
    var noteCount: Int {
        switch self {
        case .group(let group): group.children.count
        default: 1
        }
    }

    /// Turns a single grade into a group of `count` equal notes, a group of notes into one with
    /// more or fewer, or back into a single grade at 1 — keeping how the notes are given. A grade's
    /// minimum moves to the group so it still applies to the whole part.
    mutating func resizeNotes(to count: Int) {
        let count = Swift.max(count, 1)
        switch self {
        case .grade(let grade):
            guard count > 1 else { return }
            var template = grade
            template.minimum = nil
            template.date = nil
            let children = (1...count).map { number -> WeightedChild in
                var note = template
                note.name = "\(grade.name) \(number)"
                return WeightedChild(weight: 1 / Double(count), node: .grade(note))
            }
            self = .group(Group(name: grade.name, combination: .weightedAverage, children: children, minimum: grade.minimum))
        case .group(var group):
            guard isGroupOfGrades, let first = group.children.first?.node.asGrade else { return }
            if count == 1 {
                var single = first
                single.name = group.name
                single.minimum = group.minimum
                single.date = nil
                self = .grade(single)
                return
            }
            let weights = group.children.map(\.weight)
            let equal = Set(weights).count <= 1
            let newWeight = weights.reduce(0, +) / Double(weights.count)
            while group.children.count > count { group.children.removeLast() }
            var taken = Set(group.children.map(\.node.title))
            while group.children.count < count {
                var note = first
                note.date = nil
                note.name = (1...).lazy.map { "\(group.name) \($0)" }.first { !taken.contains($0) }!
                taken.insert(note.name)
                group.children.append(WeightedChild(weight: newWeight, node: .grade(note)))
            }
            if equal {
                for index in group.children.indices { group.children[index].weight = 1 / Double(count) }
            }
            self = .group(group)
        default:
            break
        }
    }

    /// Sets the due date of the grade named `leaf`, wherever it sits in the tree.
    mutating func setDate(_ date: Date?, forLeaf leaf: String) {
        switch self {
        case .grade(var grade):
            guard grade.name == leaf else { return }
            grade.date = date
            self = .grade(grade)
        case .group(var group):
            for index in group.children.indices {
                group.children[index].node.setDate(date, forLeaf: leaf)
            }
            self = .group(group)
        case .formula(var formula):
            for key in formula.variables.keys {
                formula.variables[key]?.setDate(date, forLeaf: leaf)
            }
            self = .formula(formula)
        case .alternatives(var alternatives):
            for index in alternatives.branches.indices {
                alternatives.branches[index].node.setDate(date, forLeaf: leaf)
            }
            self = .alternatives(alternatives)
        case .bonus, .requirement:
            break
        }
    }

    /// Leaves carry the grades the user types; renaming one has to move its stored grade along.
    var isLeaf: Bool {
        switch self {
        case .grade, .bonus: true
        default: false
        }
    }

    var kindLabel: String {
        switch self {
        case .grade: "Nota"
        case .group(let group): "Grupo · \(group.children.count) \(group.children.count == 1 ? "parte" : "partes")"
        case .alternatives: "Alternativas"
        case .bonus: "Bonificación"
        case .requirement: "Requisito"
        case .formula: "Fórmula"
        }
    }

    /// The pass threshold on this node's own result. Setting it keeps an existing consequence.
    var passThreshold: Double {
        get { minimumThreshold ?? 5 }
        set {
            switch self {
            case .group(var group):
                group.minimum = Minimum(threshold: newValue, consequence: group.minimum?.consequence ?? .fails)
                self = .group(group)
            case .formula(var formula):
                formula.minimum = Minimum(threshold: newValue, consequence: formula.minimum?.consequence ?? .fails)
                self = .formula(formula)
            case .grade(var grade):
                grade.minimum = Minimum(threshold: newValue, consequence: grade.minimum?.consequence ?? .fails)
                self = .grade(grade)
            default:
                break
            }
        }
    }
}

/// `Group.Combination` without its associated value, for a `Picker`.
enum CombinationKind: String, CaseIterable, Identifiable {
    case weightedAverage, sum, max, min, bestOf

    var id: Self { self }

    var label: String {
        switch self {
        case .weightedAverage: "Media ponderada"
        case .sum: "Suma"
        case .max: "La mejor"
        case .min: "La peor"
        case .bestOf: "Las mejores N"
        }
    }

    var explanation: String {
        switch self {
        case .weightedAverage: "Cada parte cuenta según su peso. Es lo más habitual."
        case .sum: "Se suman los puntos de todas las partes."
        case .max: "Cuenta solo la mejor de las partes."
        case .min: "Cuenta solo la peor de las partes."
        case .bestOf: "Cuentan solo las mejores, haciendo la media entre ellas."
        }
    }
}

extension Group.Combination {
    var kind: CombinationKind {
        switch self {
        case .weightedAverage: .weightedAverage
        case .sum: .sum
        case .max: .max
        case .min: .min
        case .bestOf: .bestOf
        }
    }

    init(kind: CombinationKind, bestOf count: Int) {
        switch kind {
        case .weightedAverage: self = .weightedAverage
        case .sum: self = .sum
        case .max: self = .max
        case .min: self = .min
        case .bestOf: self = .bestOf(count)
        }
    }

    var bestOfCount: Int? {
        if case .bestOf(let count) = self { count } else { nil }
    }
}

extension Engine.Expression {
    /// Human-readable form, e.g. "P + C + 0,1 · (8 − C) · F".
    var display: String {
        switch self {
        case .constant(let value): value.formatted()
        case .variable(let name): name
        case .add(let lhs, let rhs): "\(lhs.display) + \(rhs.display)"
        case .subtract(let lhs, let rhs): "\(lhs.display) − \(rhs.parenthesized)"
        case .multiply(let lhs, let rhs): "\(lhs.parenthesized) · \(rhs.parenthesized)"
        case .divide(let lhs, let rhs): "\(lhs.parenthesized) / \(rhs.parenthesized)"
        case .min(let lhs, let rhs): "mín(\(lhs.display), \(rhs.display))"
        case .max(let lhs, let rhs): "máx(\(lhs.display), \(rhs.display))"
        case .ifGreaterOrEqual(let lhs, let rhs, let then, let otherwise):
            "si \(lhs.display) ≥ \(rhs.display): \(then.display)\nsi no: \(otherwise.display)"
        }
    }

    private var parenthesized: String {
        switch self {
        case .add, .subtract, .ifGreaterOrEqual: "(\(display))"
        default: display
        }
    }
}
