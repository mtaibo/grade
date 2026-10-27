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
