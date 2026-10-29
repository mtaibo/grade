/// A degree's subjects laid out by year and term, ready to be added to a library. Built from each
/// subject's teaching guide, so the evaluation of every subject is already modelled.
public struct DegreeTemplate: Sendable, Identifiable {
    public struct Entry: Sendable {
        public var year: Int
        /// Position within the year (1 = first term), not the degree-wide number.
        public var term: Int
        public var subject: Subject
    }

    public var id: String
    public var name: String
    public var university: String
    public var entries: [Entry]

    public var years: [Int] { Array(Set(entries.map(\.year))).sorted() }

    public func entries(year: Int, term: Int) -> [Entry] {
        entries.filter { $0.year == year && $0.term == term }
    }
}

extension DegreeTemplate {
    public static let all: [DegreeTemplate] = [.informatica, .cienciaDatos]

    /// Grado en Ciencia e Ingeniería de Datos (UDC), 2025/26: only Matemática Discreta so far. Its
    /// guide says "Primer cuatrimestre" but not the year; first year is assumed.
    public static let cienciaDatos = DegreeTemplate(
        id: "udc-ciencia-datos",
        name: "Ciencia e Ingeniería de Datos",
        university: "UDC · guías 2025/26",
        entries: [
            .init(year: 1, term: 1, subject: .matematicaDiscreta),
        ]
    )

    /// Grado en Ingeniería Informática (UDC), 2025/26 guides: first year and the first term of the
    /// second. The second term of the second year isn't included yet.
    public static let informatica = DegreeTemplate(
        id: "udc-informatica",
        name: "Ingeniería Informática",
        university: "UDC · guías 2025/26",
        entries: [
            .init(year: 1, term: 1, subject: .calculo),
            .init(year: 1, term: 1, subject: .programacion1),
            .init(year: 1, term: 1, subject: .matematicaDiscretaGEI),
            .init(year: 1, term: 1, subject: .informaticaBasica),
            .init(year: 1, term: 1, subject: .administracionGestionOrganizaciones),
            .init(year: 1, term: 2, subject: .algebra),
            .init(year: 1, term: 2, subject: .estadistica),
            .init(year: 1, term: 2, subject: .fundamentosComputadores),
            .init(year: 1, term: 2, subject: .programacion2),
            .init(year: 1, term: 2, subject: .tecnologiaElectronica),
            .init(year: 2, term: 1, subject: .algoritmos),
            .init(year: 2, term: 1, subject: .disenoSoftware),
            .init(year: 2, term: 1, subject: .estructuraComputadores),
            .init(year: 2, term: 1, subject: .paradigmasProgramacion),
            .init(year: 2, term: 1, subject: .sistemasOperativos),
        ]
    )
}
