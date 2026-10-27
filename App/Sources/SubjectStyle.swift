import SwiftUI

/// The colours a subject's tile can take.
enum SubjectColor: String, CaseIterable, Identifiable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, brown, gray

    var id: Self { self }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .brown: .brown
        case .gray: .gray
        }
    }

    /// The first eight, which suit a white glyph best, are what an uncustomised subject gets.
    static let automatic: [SubjectColor] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .red]
}

/// The icon and colour of a subject's tile: the ones the user picked, else ones derived from the
/// subject so every tile still gets something stable.
struct SubjectStyle {
    let symbol: String
    let colorName: String

    var tint: Color { (SubjectColor(rawValue: colorName) ?? .blue).color }

    static let pickableSymbols = [
        "book.closed", "function", "chart.bar.xaxis", "terminal", "chevron.left.forwardslash.chevron.right",
        "cpu", "atom", "flask", "leaf", "briefcase", "character.bubble", "building.columns",
        "scroll", "globe.europe.africa", "pencil.and.ruler", "paintpalette", "music.note", "camera",
        "stethoscope", "cross.case", "hammer", "gearshape.2", "network", "externaldrive",
        "lightbulb", "brain.head.profile", "graduationcap", "sum", "percent", "dna",
        "bolt", "map", "theatermasks", "figure.run", "banknote", "scalemass",
    ]

    private static let derivedSymbols: [(keywords: [String], symbol: String)] = [
        (["matematic", "algebra", "calculo", "analisis"], "function"),
        (["estadistic", "probabilidad"], "chart.bar.xaxis"),
        (["sistemas operativos", "redes", "arquitectura"], "terminal"),
        (["programacion", "software", "algoritm", "paradigma", "diseno"], "chevron.left.forwardslash.chevron.right"),
        (["computador", "informatica", "ordenador", "electronica", "digital"], "cpu"),
        (["fisica", "mecanica"], "atom"),
        (["quimica"], "flask"),
        (["biolog", "ecolog"], "leaf"),
        (["organizacion", "empresa", "gestion", "econom", "contab"], "briefcase"),
        (["ingles", "idioma", "lengua", "linguist"], "character.bubble"),
        (["derecho", "legal", "juridic"], "building.columns"),
        (["historia", "filosofia"], "scroll"),
    ]

    init(_ record: SubjectRecord) {
        let name = record.subject.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        symbol = record.symbol
            ?? Self.derivedSymbols.first { entry in entry.keywords.contains { name.contains($0) } }?.symbol
            ?? "book.closed"
        // A byte of the id: random across subjects, fixed for each one.
        colorName = record.colorName
            ?? SubjectColor.automatic[Int(record.id.uuid.0) % SubjectColor.automatic.count].rawValue
    }
}
