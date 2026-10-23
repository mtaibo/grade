/// The calculation engine from the brief's §5: current grade, projected/needed grade, and status.
/// Works by evaluating a `Node` twice — once assuming every ungraded leaf scores 0 (worst case)
/// and once assuming it scores its max (best case) — and binary-searching between them for
/// "needed grade", which only works because `evaluate` is monotonic in `pendingFraction`
/// (every combination here is a weighted sum of non-negative contributions). `EngineTests`
/// checks that monotonicity against the 3 reference guides, per the brief's explicit request.
extension Node {
    /// This node's own maximum achievable value. Always 10 except for a `.sum` group, whose
    /// children's weights needn't cover the whole scale — e.g. a sub-group worth 40% of its
    /// parent reports a max of 4, so that 40% shows up correctly once its parent weighs it.
    public var scaleMax: Double {
        switch self {
        case .grade(let grade):
            return grade.scaleMax
        case .group(let group):
            switch group.combination {
            case .sum:
                return group.children.reduce(0) { $0 + $1.weight } * 10
            case .weightedAverage, .max, .min, .bestOf:
                return 10
            }
        case .alternatives(let alternatives):
            return Self.defaultBranch(alternatives)?.node.scaleMax ?? 10
        case .bonus(let bonus):
            return bonus.parentCap
        case .requirement:
            return 0
        case .formula:
            return 10
        }
    }

    /// This node's value given `inputs` for any leaf that has one, and `pendingFraction` — a
    /// fraction (0 = worst, 1 = best) of *that leaf's own scale* — for any leaf that doesn't.
    public func evaluate(_ inputs: [String: Double], pendingFraction: Double) -> Double {
        switch self {
        case .grade(let grade):
            return inputs[grade.name] ?? pendingFraction * grade.scaleMax
        case .group(let group):
            func fraction(_ child: WeightedChild) -> Double {
                let max = child.node.scaleMax
                guard max > 0 else { return 0 }
                return child.node.evaluate(inputs, pendingFraction: pendingFraction) / max
            }
            switch group.combination {
            case .weightedAverage:
                let totalWeight = group.children.reduce(0) { $0 + $1.weight }
                guard totalWeight > 0 else { return 0 }
                let weighted = group.children.reduce(0) { $0 + $1.weight * fraction($1) }
                return (weighted / totalWeight) * 10
            case .sum:
                return group.children.reduce(0) { $0 + $1.weight * fraction($1) } * 10
            case .max:
                return (group.children.map(fraction).max() ?? 0) * 10
            case .min:
                return (group.children.map(fraction).min() ?? 0) * 10
            case .bestOf(let n):
                let count = Swift.max(n, 1)
                let best = group.children.map(fraction).sorted(by: >).prefix(count)
                return best.isEmpty ? 0 : (best.reduce(0, +) / Double(best.count)) * 10
            }
        case .alternatives(let alternatives):
            return Self.defaultBranch(alternatives)?.node.evaluate(inputs, pendingFraction: pendingFraction) ?? 0
        case .bonus(let bonus):
            let value = inputs[bonus.name] ?? pendingFraction * bonus.scaleMax
            return Swift.min(value, bonus.parentCap)
        case .requirement:
            // Gradeless — not wired into the numeric result yet, see docs/modelo.md.
            return 0
        case .formula(let formula):
            let values = formula.variables.mapValues { $0.evaluate(inputs, pendingFraction: pendingFraction) }
            return formula.expression.evaluate(values)
        }
    }

    /// Every leaf (`Grade`/`Bonus`) name under this node, in tree order.
    public func allLeafNames() -> [String] {
        switch self {
        case .grade(let grade):
            return [grade.name]
        case .group(let group):
            return group.children.flatMap { $0.node.allLeafNames() }
        case .alternatives(let alternatives):
            return Self.defaultBranch(alternatives)?.node.allLeafNames() ?? []
        case .bonus(let bonus):
            return [bonus.name]
        case .requirement:
            return []
        case .formula(let formula):
            return formula.variables.values.flatMap { $0.allLeafNames() }
        }
    }

    /// Leaf names under this node that `inputs` doesn't have a value for yet.
    public func pendingLeaves(_ inputs: [String: Double]) -> [String] {
        allLeafNames().filter { inputs[$0] == nil }
    }

    /// The leaf node named `name`, searched recursively, if any.
    public func leaf(named name: String) -> Node? {
        switch self {
        case .grade(let grade):
            return grade.name == name ? self : nil
        case .group(let group):
            return group.children.lazy.compactMap { $0.node.leaf(named: name) }.first
        case .alternatives(let alternatives):
            return Self.defaultBranch(alternatives)?.node.leaf(named: name)
        case .bonus(let bonus):
            return bonus.name == name ? self : nil
        case .requirement:
            return nil
        case .formula(let formula):
            return formula.variables.values.lazy.compactMap { $0.leaf(named: name) }.first
        }
    }

    /// The pass threshold on this node's own computed result, if it declares one.
    public var minimumThreshold: Double? {
        switch self {
        case .group(let group): return group.minimum?.threshold
        case .formula(let formula): return formula.minimum?.threshold
        case .grade(let grade): return grade.minimum?.threshold
        default: return nil
        }
    }

    /// The uniform fraction (0...1) every pending leaf would need of its own scale for this
    /// node's value to reach `target` — `nil` if `target` is out of [worst, best] reach.
    /// "Misma nota en todos los pendientes" per the brief: later, a simulator could fix some and
    /// solve only the rest, but that's not needed yet.
    public func neededFraction(_ inputs: [String: Double], target: Double, tolerance: Double = 0.0001) -> Double? {
        let worst = evaluate(inputs, pendingFraction: 0)
        let best = evaluate(inputs, pendingFraction: 1)
        guard target >= worst, target <= best else { return nil }
        var low = 0.0
        var high = 1.0
        while high - low > tolerance {
            let mid = (low + high) / 2
            if evaluate(inputs, pendingFraction: mid) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return high
    }

    /// `Alternatives` picks a branch "by condition or the best" per the brief — but a branch's
    /// `condition` is still a free, unevaluated string (see docs/modelo.md), so until that's
    /// resolved this can only pick the explicit default branch (no condition) or fall back to
    /// the first one. Not exercised by any of the 3 reference guides yet.
    private static func defaultBranch(_ alternatives: Alternatives) -> Alternatives.Branch? {
        alternatives.branches.first(where: { $0.condition == nil }) ?? alternatives.branches.first
    }
}

/// Whether passing is still reachable given what's been entered so far.
public enum PassStatus: Sendable, Equatable {
    /// Even the worst case (0 on everything pending) reaches the pass threshold.
    case guaranteed
    /// Reachable, but not guaranteed — depends on what's left.
    case possible
    /// Even the best case (max on everything pending) falls short.
    case impossible
}

extension Node {
    /// Status against this node's own `minimumThreshold`, or 5 (out of 10) if it doesn't declare
    /// one — the universal default for the Spanish grading scale the brief targets.
    public func status(_ inputs: [String: Double]) -> PassStatus {
        let threshold = minimumThreshold ?? 5
        let worst = evaluate(inputs, pendingFraction: 0)
        let best = evaluate(inputs, pendingFraction: 1)
        if worst >= threshold { return .guaranteed }
        if best < threshold { return .impossible }
        return .possible
    }
}
