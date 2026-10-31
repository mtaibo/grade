extension Node {
    /// Every grade leaf under this node, in tree order.
    public var grades: [Grade] {
        switch self {
        case .grade(let grade): [grade]
        case .group(let group): group.children.flatMap(\.node.grades)
        case .formula(let formula): formula.variables.keys.sorted().flatMap { formula.variables[$0]?.grades ?? [] }
        case .alternatives(let alternatives): alternatives.branches.flatMap(\.node.grades)
        case .bonus, .requirement: []
        }
    }

    /// True when every grade under this node is the final exam — such a part gets the exam card.
    public var isFinalExamPart: Bool {
        let grades = grades
        return !grades.isEmpty && grades.allSatisfy { $0.isFinalExam == true }
    }

    /// Applies `body` to every grade leaf under this node.
    public mutating func updateGrades(_ body: (inout Grade) -> Void) {
        switch self {
        case .grade(var grade):
            body(&grade)
            self = .grade(grade)
        case .group(var group):
            for index in group.children.indices { group.children[index].node.updateGrades(body) }
            self = .group(group)
        case .formula(var formula):
            // Sorted, like `grades`, so every pass visits the notes in the same order.
            for key in formula.variables.keys.sorted() { formula.variables[key]?.updateGrades(body) }
            self = .formula(formula)
        case .alternatives(var alternatives):
            for index in alternatives.branches.indices { alternatives.branches[index].node.updateGrades(body) }
            self = .alternatives(alternatives)
        case .bonus, .requirement:
            break
        }
    }
}
