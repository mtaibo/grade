import Foundation

/// How the user's degree is divided, set in the account tab: how many years it has and what its
/// terms are (cuatrimestres, semestres, trimestres…). Stored term numbers are degree-wide, so
/// this is also what turns them into "1º Cuatrimestre" on screen.
struct DegreeSettings: Codable, Equatable {
    static let maxYears = 10
    static let maxTermsPerYear = 4
    static let defaultTermName = "Cuatrimestre"

    var years = 4
    var termsPerYear = 2
    var termName = defaultTermName

    private var displayTermName: String {
        let trimmed = termName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.defaultTermName : trimmed
    }

    /// The term's position within its own year: with 2 per year, 3 → 1 and 4 → 2.
    func relativeTerm(_ term: Int) -> Int {
        (term - 1) % termsPerYear + 1
    }

    /// The degree-wide term for the `n`th term of a year: year 2, 1st → 3.
    func absoluteTerm(year: Int, relative n: Int) -> Int {
        (year - 1) * termsPerYear + n
    }

    /// "1º Cuatrimestre", for a degree-wide term number.
    func termLabel(_ term: Int) -> String {
        "\(relativeTerm(term))º \(displayTermName)"
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

    var title: String { "\(year)º Año" }

    func subtitle(in degree: DegreeSettings) -> String? {
        term.map(degree.termLabel)
    }
}
