import Engine
import Foundation

/// One top-level part of the evaluation, with the share of the grade it carries.
struct PartItem: Identifiable {
    let id: String
    let node: Node
    let weightPercent: Double?
    /// The least it can carry, when a formula moves its share with other grades ("60–80 %").
    var lowestPercent: Double?

    var isExam: Bool { node.isFinalExamPart }

    var weightText: String? { weightPercent.map { Self.percentText(lowest: lowestPercent, highest: $0) } }

    static func percentText(lowest: Double?, highest: Double) -> String {
        let number = { (value: Double) in value.formatted(.number.precision(.fractionLength(0...1))) }
        return "\(lowest.map { "\(number($0))–" } ?? "")\(number(highest))\u{00A0}%"
    }

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
            return group.children.map { child in
                let share = group.sharePercent(of: child)
                return PartItem(id: child.id.uuidString, node: child.node, weightPercent: share?.highest, lowestPercent: share?.lowest)
            }
        } else if case .formula(let formula) = root {
            let keys = formula.expression.variableOrder.filter { formula.variables[$0] != nil }
                + formula.variables.keys.sorted().filter { !formula.expression.variableOrder.contains($0) }
            return keys.compactMap { key in
                formula.variables[key].map {
                    let share = formula.sharePercent(of: key)
                    return PartItem(id: key, node: $0, weightPercent: share.highest, lowestPercent: share.lowest)
                }
            }
        } else {
            return [PartItem(id: "root", node: root, weightPercent: nil)]
        }
    }
}

extension Formula {
    /// How much of the final grade a variable accounts for, in percent: `lowest` is only there when
    /// its weight moves with other grades.
    func sharePercent(of key: String) -> (lowest: Double?, highest: Double) {
        let range = contributionRange(of: key)
        let low = max(0, range.lowerBound) * 10, high = max(0, range.upperBound) * 10
        return (high - low < 0.5 ? nil : low, high)
    }
}

extension Engine.Group {
    /// How much of this group's grade a section accounts for, in percent: `lowest` is only there when
    /// a rule can hand its weight to another section or bring it another's. `nil` with no weights.
    func sharePercent(of child: WeightedChild) -> (lowest: Double?, highest: Double)? {
        let allWeights = children.reduce(0) { $0 + $1.weight }
        let scale = combination == .weightedAverage ? allWeights : 1
        guard scale > 0 else { return nil }
        let percent = { (weight: Double) in weight / scale * 100 }
        guard combination == .weightedAverage || combination == .sum else { return (nil, percent(child.weight)) }

        let ids = Set(children.map(\.id))
        let moving = children.filter { section in
            let consequence = section.node.ownMinimum?.consequence.section
            return [consequence, section.absorbedBy].contains { $0 != section.id && $0.map(ids.contains) == true }
        }
        let givesAll = { (section: WeightedChild) -> UUID? in
            if case .everythingGoesTo(let id)? = section.node.ownMinimum?.consequence, id != section.id, ids.contains(id) { return id }
            return nil
        }
        let received = moving.filter { givesAll($0) == nil && ($0.absorbedBy == child.id || $0.node.ownMinimum?.consequence.section == child.id) }
        var highest = percent(child.weight + received.reduce(0) { $0 + $1.weight })
        if moving.contains(where: { givesAll($0) == child.id }) { highest = percent(allWeights) }
        // Handing its own weight away, or left out when another section decides everything.
        let canLoseIt = moving.contains { $0.id == child.id || (givesAll($0) != nil && givesAll($0) != child.id) }
        let lowest = canLoseIt ? 0 : percent(child.weight)
        return (highest - lowest < 0.5 ? nil : lowest, highest)
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
