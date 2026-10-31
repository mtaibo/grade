import Engine
import Foundation

/// A home-screen view made by hand: any subjects, from any year or term, shown together. For when
/// the degree's own split doesn't match someone's real semester — a repeated subject, one brought
/// forward from a later year, one validated.
struct CustomSelection: Identifiable, Codable, Equatable {
    /// What the home screen shows as the big title.
    enum Title: Codable, Equatable, Hashable {
        /// The year alone when the view holds exactly one whole year; otherwise the year and term
        /// of the subject furthest along in the degree.
        case automatic
        /// A year and term picked by hand (`term` nil for "Todo el año").
        case period(year: Int, term: Int?)
        /// Free text.
        case name(String)
    }

    var id = UUID()
    var title: Title = .automatic
    /// In the order the home screen shows them.
    var subjectIDs: [SubjectRecord.ID] = []
}

extension Library {
    /// The big title and the line under it for a custom view, as the home screen shows them.
    func heading(for selection: CustomSelection) -> (title: String, subtitle: String?) {
        switch selection.title {
        case .name(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return (trimmed.isEmpty ? "Mi vista" : trimmed, nil)
        case .period(let year, let term):
            let period = Period(year: year, term: term)
            return (period.title(in: degree), period.subtitle(in: degree))
        case .automatic:
            if let year = wholeYear(of: selection.subjectIDs) { return (degree.yearLabel(year), nil) }
            guard let period = furthestPeriod(of: selection.subjectIDs) else { return ("Mi vista", nil) }
            return (period.title(in: degree), period.subtitle(in: degree))
        }
    }

    /// The year these subjects are, when they're every one of its subjects and nothing else: one
    /// missing, or one from another year, and it's `nil`.
    func wholeYear(of ids: [SubjectRecord.ID]) -> Int? {
        let picked = Set(ids)
        return courses.first { course in
            !course.subjects.isEmpty && Set(course.subjects.map(\.id)) == picked
        }?.year
    }

    /// The latest year and term among these subjects; a year-long one counts as its year's last.
    func furthestPeriod(of ids: [SubjectRecord.ID]) -> Period? {
        ids.compactMap(period(of:)).max { lhs, rhs in
            (lhs.year, lhs.term ?? .max) < (rhs.year, rhs.term ?? .max)
        }
    }
}
