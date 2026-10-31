import Foundation

/// A node in a subject's evaluation tree. See `docs/modelo.md` for the model this implements.
public indirect enum Node: Sendable, Equatable, Codable {
    case grade(Grade)
    case group(Group)
    case alternatives(Alternatives)
    case bonus(Bonus)
    case requirement(Requirement)
    case formula(Formula)
}

/// A leaf grade entered by the user, on its own scale.
public struct Grade: Sendable, Equatable, Codable {
    public var name: String
    /// Marks the final exam (every subject has one): shown in its own card with an ordinary and an
    /// extraordinary slot. Presentation only. `nil` means it isn't.
    public var isFinalExam: Bool?
    /// What kind of thing this is, for the calendar's colours. `nil` lets `kind` guess from the name.
    public var category: GradeCategory?
    public var scaleMax: Double
    public var minimum: Minimum?
    public var recovery: Recovery?
    /// When it's due or taken (a lab hand-in, an exam). Not used by the calculation — it's the
    /// "fecha" the brief's data model (§6) puts on each node, so it travels with its grade.
    public var date: Date?
    /// How the teacher gives this grade — points, a percentage or letters. Presentation only: the
    /// app converts what's typed to `scaleMax` before the engine sees it. `nil` means points.
    public var inputStyle: GradeInputStyle?

    public init(
        name: String,
        isFinalExam: Bool? = nil,
        category: GradeCategory? = nil,
        scaleMax: Double = 10,
        minimum: Minimum? = nil,
        recovery: Recovery? = nil,
        date: Date? = nil,
        inputStyle: GradeInputStyle? = nil
    ) {
        self.name = name
        self.isFinalExam = isFinalExam
        self.category = category
        self.scaleMax = scaleMax
        self.minimum = minimum
        self.recovery = recovery
        self.date = date
        self.inputStyle = inputStyle
    }
}

public enum GradeInputStyle: Sendable, Equatable, Codable {
    case points
    case percent
    /// Letter grades and what each is worth, out of 10.
    case letters([LetterGrade])
}

public struct LetterGrade: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var letter: String
    /// Out of 10, whatever the grade's own scale.
    public var value: Double

    public init(id: UUID = UUID(), letter: String, value: Double) {
        self.id = id
        self.letter = letter
        self.value = value
    }
}

/// A node combined from weighted children.
public struct Group: Sendable, Equatable, Codable {
    public enum Combination: Sendable, Equatable, Codable {
        case weightedAverage
        case sum
        case max
        case min
        case bestOf(Int)
        /// The guide's rule isn't known yet: the parts are only listed, with no weights. The app
        /// shows no result for it; the engine averages the parts equally just to stay total.
        case undecided
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

/// `id` is a stable identity for a child slot, so an editor can list, reorder and delete children
/// without keying on their (editable) names.
public struct WeightedChild: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var weight: Double
    public var node: Node

    public init(id: UUID = UUID(), weight: Double, node: Node) {
        self.id = id
        self.weight = weight
        self.node = node
    }
}

/// Several evaluation schemes for the same node; one is picked by condition, or the best of all.
///
/// `condition` is a free-form description for now (e.g. "Controles >= 4"), not yet a structured
/// expression — the 3 reference guides don't need more than picking a branch to validate the shape.
public struct Alternatives: Sendable, Equatable, Codable {
    public struct Branch: Sendable, Equatable, Codable {
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
public struct Bonus: Sendable, Equatable, Codable {
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
public struct Requirement: Sendable, Equatable, Codable {
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
public struct Formula: Sendable, Equatable, Codable {
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
public struct Subject: Sendable, Equatable, Codable {
    public var name: String
    public var ectsCredits: Double
    public var root: Node

    public init(name: String, ectsCredits: Double, root: Node) {
        self.name = name
        self.ectsCredits = ectsCredits
        self.root = root
    }
}

/// A colour-coded classification for anything with a date: an assignment, a quiz-style control or an exam.
public enum GradeCategory: String, Sendable, Codable, CaseIterable, Equatable {
    case work, quiz, exam
}

extension Grade {
    /// The chosen category, or a guess from what it's called: final exams and "examen" are exams;
    /// "control", "prueba", "test"… are controls; everything else (labs, seminars, problem sets) is work.
    public var kind: GradeCategory {
        if let category { return category }
        if isFinalExam == true { return .exam }
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        if folded.contains("examen") { return .exam }
        if ["control", "prueba", "test", "quiz", "moodle"].contains(where: folded.contains) { return .quiz }
        return .work
    }
}
