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
            let combined: Double
            switch group.combination {
            case .weightedAverage:
                let totalWeight = group.children.reduce(0) { $0 + $1.weight }
                let weighted = group.children.reduce(0) { $0 + $1.weight * fraction($1) }
                combined = totalWeight > 0 ? (weighted / totalWeight) * 10 : 0
            case .sum:
                combined = group.children.reduce(0) { $0 + $1.weight * fraction($1) } * 10
            case .max:
                combined = (group.children.map(fraction).max() ?? 0) * 10
            case .min:
                combined = (group.children.map(fraction).min() ?? 0) * 10
            case .bestOf(let n):
                let count = Swift.max(n, 1)
                let best = group.children.map(fraction).sorted(by: >).prefix(count)
                combined = best.isEmpty ? 0 : (best.reduce(0, +) / Double(best.count)) * 10
            }
            return Self.applyingCaps(combined, from: group.children.map(\.node), inputs, pendingFraction)
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
            return Self.applyingCaps(formula.expression.evaluate(values), from: Array(formula.variables.values), inputs, pendingFraction)
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
        ownMinimum?.threshold
    }

    private var ownMinimum: Minimum? {
        switch self {
        case .group(let group): group.minimum
        case .formula(let formula): formula.minimum
        case .grade(let grade): grade.minimum
        default: nil
        }
    }

    /// Whether every `Minimum` with a `.fails` consequence in this subtree is met — e.g. "at least
    /// 40% on the exam or the subject is failed", which no average can make up for. Monotonic in
    /// `pendingFraction` like `evaluate`, so it can share the same binary search.
    /// `.capAt` is handled by `evaluate` instead (it changes the number, not just pass/fail), and
    /// `.doesNotAverage` isn't wired in: no reference guide needs it yet.
    public func meetsMinimums(_ inputs: [String: Double], pendingFraction: Double) -> Bool {
        if let minimum = ownMinimum, minimum.consequence == .fails,
           evaluate(inputs, pendingFraction: pendingFraction) < minimum.threshold {
            return false
        }
        switch self {
        case .group(let group):
            return group.children.allSatisfy { $0.node.meetsMinimums(inputs, pendingFraction: pendingFraction) }
        case .formula(let formula):
            return formula.variables.values.allSatisfy { $0.meetsMinimums(inputs, pendingFraction: pendingFraction) }
        case .alternatives(let alternatives):
            return Self.defaultBranch(alternatives)?.node.meetsMinimums(inputs, pendingFraction: pendingFraction) ?? true
        case .grade, .bonus, .requirement:
            return true
        }
    }

    /// The uniform fraction (0...1) every pending leaf would need of its own scale for this
    /// node's value to reach `target` *and* every failing minimum to be met — `nil` if that's out
    /// of reach even with full marks. "Misma nota en todos los pendientes" per the brief: later, a
    /// simulator could fix some and solve only the rest, but that's not needed yet.
    public func neededFraction(_ inputs: [String: Double], target: Double, tolerance: Double = 0.0001) -> Double? {
        func reaches(_ fraction: Double) -> Bool {
            evaluate(inputs, pendingFraction: fraction) >= target && meetsMinimums(inputs, pendingFraction: fraction)
        }
        guard reaches(1) else { return nil }
        guard !reaches(0) else { return 0 }
        var low = 0.0
        var high = 1.0
        while high - low > tolerance {
            let mid = (low + high) / 2
            if reaches(mid) {
                high = mid
            } else {
                low = mid
            }
        }
        return high
    }

    /// A child whose `Minimum` has a `.capAt` consequence and isn't met caps its parent's result —
    /// "si no llegas a un 4 en el examen, la nota final no pasa de 4,5". Monotonic: raising the
    /// child past its threshold only ever lifts the cap.
    private static func applyingCaps(_ value: Double, from children: [Node], _ inputs: [String: Double], _ pendingFraction: Double) -> Double {
        children.reduce(value) { result, child in
            guard let minimum = child.ownMinimum, case .capAt(let cap) = minimum.consequence,
                  child.evaluate(inputs, pendingFraction: pendingFraction) < minimum.threshold
            else { return result }
            return Swift.min(result, cap)
        }
    }

    /// `Alternatives` picks a branch "by condition or the best" per the brief — but a branch's
    /// `condition` is still a free, unevaluated string (see docs/modelo.md), so until that's
    /// resolved this can only pick the explicit default branch (no condition) or fall back to
    /// the first one. Not exercised by any of the reference guides yet.
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
    /// A failed minimum anywhere (e.g. under 4 on an exam that needs it) also counts.
    public func status(_ inputs: [String: Double]) -> PassStatus {
        let threshold = minimumThreshold ?? 5
        func passes(_ fraction: Double) -> Bool {
            evaluate(inputs, pendingFraction: fraction) >= threshold && meetsMinimums(inputs, pendingFraction: fraction)
        }
        if passes(0) { return .guaranteed }
        if !passes(1) { return .impossible }
        return .possible
    }
}
