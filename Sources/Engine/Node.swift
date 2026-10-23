/// A node in a subject's evaluation tree. See `docs/modelo.md` for the model this implements.
public indirect enum Node: Sendable, Equatable {
    case grade(Grade)
    case group(Group)
    case alternatives(Alternatives)
    case bonus(Bonus)
    case requirement(Requirement)
    case formula(Formula)
}

/// A leaf grade entered by the user, on its own scale.
public struct Grade: Sendable, Equatable {
    public var name: String
    public var scaleMax: Double
    public var minimum: Minimum?
    public var recovery: Recovery?

    public init(name: String, scaleMax: Double = 10, minimum: Minimum? = nil, recovery: Recovery? = nil) {
        self.name = name
        self.scaleMax = scaleMax
        self.minimum = minimum
        self.recovery = recovery
    }
}

/// A node combined from weighted children.
public struct Group: Sendable, Equatable {
    public enum Combination: Sendable, Equatable {
        case weightedAverage
        case sum
        case max
        case min
        case bestOf(Int)
    }

    public var name: String
    public var combination: Combination
    public var children: [WeightedChild]
    public var minimum: Minimum?

    public init(name: String, combination: Combination, children: [WeightedChild], minimum: Minimum? = nil) {
        self.name = name
        self.combination = combination
        self.children = children
        self.minimum = minimum
    }
}

public struct WeightedChild: Sendable, Equatable {
    public var weight: Double
    public var node: Node

    public init(weight: Double, node: Node) {
        self.weight = weight
        self.node = node
    }
}

/// Several evaluation schemes for the same node; one is picked by condition, or the best of all.
///
/// `condition` is a free-form description for now (e.g. "Controles >= 4"), not yet a structured
/// expression — the 3 reference guides don't need more than picking a branch to validate the shape.
public struct Alternatives: Sendable, Equatable {
    public struct Branch: Sendable, Equatable {
        public var condition: String?
        public var node: Node

        public init(condition: String? = nil, node: Node) {
            self.condition = condition
            self.node = node
        }
    }

    public var name: String
    public var branches: [Branch]
    public var pickBest: Bool

    public init(name: String, branches: [Branch], pickBest: Bool = false) {
        self.name = name
        self.branches = branches
        self.pickBest = pickBest
    }
}

/// Points added to the parent's total, capped.
public struct Bonus: Sendable, Equatable {
    public var name: String
    public var scaleMax: Double
    public var parentCap: Double

    public init(name: String, scaleMax: Double, parentCap: Double = 10) {
        self.name = name
        self.scaleMax = scaleMax
        self.parentCap = parentCap
    }
}

/// A gradeless condition that blocks passing when unmet (e.g. mandatory attendance).
public struct Requirement: Sendable, Equatable {
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

/// A guide expresses the grade as an arithmetic formula over named variables, not as fixed weights.
///
/// Three reference guides (Estadística both sessions, Matemática Discreta both sessions) need the
/// final exam's *weight* to vary continuously with another grade, which neither `Group` nor
/// `Alternatives` can express — see `docs/modelo.md`. Each variable is still a full `Node`, so its
/// own rules (e.g. `recovery`) are expressed normally; `minimum` is the pass threshold on the
/// formula's own computed result, the same role `Group.minimum` plays for a weighted average.
public struct Formula: Sendable, Equatable {
    public var name: String
    public var expression: Expression
    public var variables: [String: Node]
    public var minimum: Minimum?

    public init(name: String, expression: Expression, variables: [String: Node], minimum: Minimum? = nil) {
        self.name = name
        self.expression = expression
        self.variables = variables
        self.minimum = minimum
    }
}

/// The root of a subject's evaluation tree, one per session (ordinary, extraordinary, early).
public struct Subject: Sendable, Equatable {
    public var name: String
    public var ectsCredits: Double
    public var root: Node

    public init(name: String, ectsCredits: Double, root: Node) {
        self.name = name
        self.ectsCredits = ectsCredits
        self.root = root
    }
}
