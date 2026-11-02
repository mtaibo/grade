import Engine
import Foundation

/// One top-level part of the evaluation, with the share of the grade it carries.
struct PartItem: Identifiable {
    let id: String
    let node: Node
    let weightPercent: Double?
    /// True when the share is a ceiling ("hasta 80 %") because the formula decides the real one.
    var isMaximum = false

    var isExam: Bool { node.isFinalExamPart }

    /// The cards for a sitting: the parts of its tree (the extraordinary's own, if it has one). With
    /// continuous and single-exam schemes, the chosen one's parts, or both's when the best counts
    /// — a note they share shows once.
    static func items(of record: SubjectRecord, session: Convocatoria) -> [PartItem] {
        let root = session == .extraordinary ? (record.extraordinaryRoot ?? record.subject.root) : record.subject.root
        guard case .alternatives(let alternatives) = root else { return items(of: root) }
        var seen: Set<String> = []
        return Node.activeBranches(alternatives).flatMap { items(of: $0.node) }.filter { item in
            let leaves = item.node.allLeafNames()
            defer { seen.formUnion(leaves) }
            return leaves.isEmpty || !leaves.allSatisfy(seen.contains)
        }
    }

    /// A subject graded per term, opened from one of its terms: that term's parts. Nil — show the
    /// whole subject — when no term is given or the general evaluation no longer has one part per
    /// term.
    static func termScope(of record: SubjectRecord, session: Convocatoria, term: Int?, termsPerYear: Int) -> (node: Node, items: [PartItem])? {
        guard record.isPerTerm, let term else { return nil }
        let terms = items(of: record, session: session)
        guard terms.count == termsPerYear, terms.indices.contains(term - 1) else { return nil }
        let node = terms[term - 1].node
        return (node, items(of: node))
    }

    static func items(of root: Node) -> [PartItem] {
        if case .group(let group) = root, group.combination == .undecided {
            return group.children.map { PartItem(id: $0.id.uuidString, node: $0.node, weightPercent: nil) }
        } else if case .group(let group) = root {
            let total = group.combination == .weightedAverage ? group.children.reduce(0) { $0 + $1.weight } : 1
            return group.children.map { child in
                PartItem(id: child.id.uuidString, node: child.node, weightPercent: total > 0 ? child.weight / total * 100 : nil)
            }
        } else if case .formula(let formula) = root {
            let keys = formula.expression.variableOrder.filter { formula.variables[$0] != nil }
                + formula.variables.keys.sorted().filter { !formula.expression.variableOrder.contains($0) }
            return keys.compactMap { key in
                formula.variables[key].map {
                    PartItem(id: key, node: $0, weightPercent: formula.maxShare(of: key) * 10, isMaximum: true)
                }
            }
        } else {
            return [PartItem(id: "root", node: root, weightPercent: nil)]
        }
    }
}

extension SubjectRecord {
    /// A note as it was given: its letter, a percentage, or points ("8,5", or "1,7 / 2" off 10).
    func displayedEntry(for grade: Grade, in session: Convocatoria) -> String {
        guard let entry = entry(for: grade.name, in: session), entry.value.isFinite, entry.outOf.isFinite, entry.outOf > 0 else { return "—" }
        let number = { (value: Double) in value.formatted(.number.precision(.fractionLength(0...2))) }
        if let letter = entry.letter { return letter }
        switch grade.inputStyle ?? .points {
        case .percent:
            return "\(number(entry.outOf == 100 ? entry.value : entry.value / entry.outOf * 100)) %"
        case .points, .letters:
            return entry.outOf == 10 ? number(entry.value) : "\(number(entry.value)) / \(number(entry.outOf))"
        }
    }
}
