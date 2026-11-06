import Foundation

/// What the user is studying: a university degree, Bachillerato or ESO for now. It picks the usual
/// years and terms, whether there are credits, and how subjects and the tutorial are set up.
enum StudyType: String, Codable, CaseIterable, Identifiable {
    case university, highSchool, secondary

    var id: Self { self }

    /// Studies saved when there were more types (máster, FP, otros) go with university.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .university
    }

    var label: String {
        switch self {
        case .university: "Universidad"
        case .highSchool: "Bachillerato"
        case .secondary: "ESO"
        }
    }

    var symbol: String {
        switch self {
        case .university: "graduationcap"
        case .highSchool: "books.vertical"
        case .secondary: "backpack"
        }
    }

    /// Whether its subjects usually carry credits (ECTS).
    var usesCredits: Bool { self == .university }

    /// Whether its subjects usually last the whole year with a grade per term.
    var gradesPerTerm: Bool { self != .university }

    /// The usual years, terms per year and term name, applied when the type is picked.
    var defaults: (years: Int, termsPerYear: Int, termName: String) {
        switch self {
        case .university: (4, 2, "Cuatrimestre")
        case .highSchool: (2, 3, "Trimestre")
        case .secondary: (4, 3, "Trimestre")
        }
    }
}

/// How the transcript turns the worked-out grade into the final one: as it is, to a whole number
/// (4,5 → 5), or to one decimal rounding (4,95 → 5,0) or cutting (4,99 → 4,9) — it decides a pass
/// right at the line.
enum GradeRounding: String, Codable, CaseIterable, Identifiable {
    case none
    /// Not stored as «unit»: development builds saved that on every subject when it was briefly
    /// the default, and read as unknown those subjects go back to `.standard`.
    case unit = "wholeNumber"
    case round, truncate

    /// What a subject starts with: the grade as it's worked out, until its guide says otherwise.
    static let standard = GradeRounding.none

    var id: Self { self }

    var label: String {
        switch self {
        case .none: "Sin redondear"
        case .unit: "A la unidad"
        case .round: "A una décima"
        case .truncate: "A una décima, truncando"
        }
    }

    func apply(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        switch self {
        case .none: return value
        // A hair added first, so a 4,95 that's 4,9499999… in binary still goes up.
        case .unit: return (value + 1e-9).rounded(.toNearestOrAwayFromZero)
        case .round: return (value * 10 + 1e-9).rounded(.toNearestOrAwayFromZero) / 10
        case .truncate: return (value * 10 + 1e-9).rounded(.towardZero) / 10
        }
    }

    /// The lowest worked-out grade that ends up at `threshold` or above.
    func lowestPassing(_ threshold: Double) -> Double {
        switch self {
        case .unit: threshold - 0.5 - 1e-9
        case .round: threshold - 0.05 - 1e-9
        case .none, .truncate: threshold
        }
    }
}

/// How the user's degree is divided, set in the account tab: what they study, how many years it
/// has and what its terms are (cuatrimestres, semestres, trimestres…). Stored term numbers are
/// degree-wide, so this is also what turns them into "1º Cuatrimestre" on screen. Years and
/// terms are named by the user ("Año", "Curso"; "Cuatrimestre", "Trimestre"…).
struct DegreeSettings: Codable, Equatable {
    static let maxYears = 10
    static let maxTermsPerYear = 4
    static let defaultTermName = "Cuatrimestre"
    static let defaultYearName = "Año"

    var studyType = StudyType.university
    /// What the user calls it ("Ingeniería Informática"); empty shows the study type.
    var name = ""
    /// Where ("UDC"); optional.
    var institution = ""
    var years = 4
    var termsPerYear = 2
    var termName = defaultTermName
    var yearName = defaultYearName
    /// Off: no credits anywhere (record, editor) and averages count every subject the same.
    var usesCredits = true
    /// How the final grade went on the transcript when it was one setting for the whole study.
    /// Each subject has its own now (`SubjectRecord.rounding`); this is only read from older files
    /// to hand it to their subjects, and is `.none` once it has.
    var legacyRounding = GradeRounding.none

    /// The name given to the study, or its type when it has none.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? studyType.label : trimmed
    }

    /// The study type with its usual years and terms.
    func switching(to type: StudyType) -> DegreeSettings {
        var new = self
        new.studyType = type
        new.usesCredits = type.usesCredits
        new.years = type.defaults.years
        new.termsPerYear = type.defaults.termsPerYear
        new.termName = type.defaults.termName
        // "1º Bachillerato", "3º ESO", "2º Año".
        new.yearName = type == .university ? Self.defaultYearName : type.label
        return new
    }

    /// "4 años · 2 cuatrimestres por año", for the collapsed studies row.
    var summary: String {
        let years = years == 1 ? "1 año" : "\(years) años"
        let name = displayTermName.lowercased()
        let terms = termsPerYear == 1 ? "1 \(name)" : "\(termsPerYear) \(Self.plural(name))"
        return "\(years) · \(terms) por año"
    }

    /// "Trimestres", or the plural of whatever the terms are called.
    var pluralTermName: String { Self.plural(displayTermName) }

    private static func plural(_ word: String) -> String {
        if word.hasSuffix("ón") { return word.dropLast(2) + "ones" }
        if let last = word.last, "aeiou".contains(last) { return word + "s" }
        return word + "es"
    }

    /// "Año", or what the user calls the years.
    var displayYearName: String {
        let trimmed = yearName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.defaultYearName : trimmed
    }

    private var displayTermName: String {
        let trimmed = termName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.defaultTermName : trimmed
    }

    /// Never below 1, whatever a file says, since it divides.
    private var safeTermsPerYear: Int { Swift.max(termsPerYear, 1) }

    /// The term's position within its own year: with 2 per year, 3 → 1 and 4 → 2.
    func relativeTerm(_ term: Int) -> Int {
        let count = safeTermsPerYear
        return ((term - 1) % count + count) % count + 1
    }

    /// The degree-wide term for the `n`th term of a year: year 2, 1st → 3.
    func absoluteTerm(year: Int, relative n: Int) -> Int {
        (year - 1) * safeTermsPerYear + n
    }

    /// "2º Año", or whatever the years are called.
    func yearLabel(_ year: Int) -> String {
        "\(year)º \(displayYearName)"
    }

    /// Each term's name within a year ("1º Trimestre", "2º Trimestre"…), in order.
    var termLabels: [String] {
        (1...safeTermsPerYear).map { termLabel($0) }
    }

    /// "1º Cuatrimestre", for a degree-wide term number.
    func termLabel(_ term: Int) -> String {
        "\(relativeTerm(term))º \(displayTermName)"
    }
}

extension DegreeSettings {
    private enum CodingKeys: String, CodingKey { case studyType, name, institution, years, termsPerYear, termName, yearName, usesCredits, legacyRounding = "rounding" }

    /// Clamped to what the settings screen allows, so a hand-edited backup can't hand the app zero
    /// terms a year (which it divides by) or a hundred years.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let years = try container.decodeIfPresent(Int.self, forKey: .years) ?? 4
        let terms = try container.decodeIfPresent(Int.self, forKey: .termsPerYear) ?? 2
        let studyType = (try? container.decodeIfPresent(StudyType.self, forKey: .studyType)) ?? .university
        self.init(
            studyType: studyType,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            institution: try container.decodeIfPresent(String.self, forKey: .institution) ?? "",
            years: min(max(years, 1), Self.maxYears),
            termsPerYear: min(max(terms, 1), Self.maxTermsPerYear),
            termName: try container.decodeIfPresent(String.self, forKey: .termName) ?? Self.defaultTermName,
            yearName: try container.decodeIfPresent(String.self, forKey: .yearName) ?? Self.defaultYearName,
            // Studies saved before the setting existed get their type's usual one.
            usesCredits: try container.decodeIfPresent(Bool.self, forKey: .usesCredits) ?? studyType.usesCredits,
            legacyRounding: (try? container.decodeIfPresent(GradeRounding.self, forKey: .legacyRounding)) ?? .none
        )
    }
}

/// A year of the degree and, optionally, one of its terms (`nil` = the whole year).
struct Period: Hashable {
    var year: Int
    /// Degree-wide term number (1-based).
    var term: Int?

    init(year: Int, term: Int? = nil) {
        self.year = year
        self.term = term
    }

    func title(in degree: DegreeSettings) -> String {
        degree.yearLabel(year)
    }

    func subtitle(in degree: DegreeSettings) -> String? {
        term.map(degree.termLabel)
    }
}

extension Period {
    /// Every period that has subjects, oldest first. A year-long subject belongs to every term of
    /// its year, so a year with one has all its terms, even if it's the only subject; one graded
    /// per term also adds the year's "Final" (term nil), after its terms, for the whole-year grade.
    static func all(in courses: [Course], degree: DegreeSettings) -> [Period] {
        var result: [Period] = []
        for course in courses {
            var terms = Set(course.subjects.compactMap(\.term))
            if course.subjects.contains(where: { $0.term == nil }) {
                terms.formUnion((1...max(degree.termsPerYear, 1)).map { degree.absoluteTerm(year: course.year, relative: $0) })
            }
            result += terms.sorted().map { Period(year: course.year, term: $0) }
            if course.subjects.contains(where: { $0.term == nil && $0.isPerTerm }) {
                result.append(Period(year: course.year))
            }
        }
        return result.sorted { ($0.year, $0.term ?? .max) < ($1.year, $1.term ?? .max) }
    }
}

/// A study put away to start another (high school before university, a finished degree…): its
/// settings, subjects with their grades, and custom views, kept to look back at or pick up again.
struct ArchivedStudy: Identifiable, Codable, Equatable {
    var id = UUID()
    var degree: DegreeSettings
    var courses: [Course]
    var selections: [CustomSelection] = []
    var archivedAt = Date.now

    var subjectIDs: [SubjectRecord.ID] { courses.flatMap(\.subjects).map(\.id) }
}
