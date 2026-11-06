import SwiftUI
import TipKit

/// Short tips where they matter, each the first time it does, the way Apple's own apps teach
/// (TipKit) rather than a guided tour. A tip goes for good with its ✗ or once the user does what
/// it says; the screens with several show them one at a time (`TipGroup`).
enum GradeTips {
    private static let generationKey = "tipsGeneration"

    /// Part of every tip's id. «Volver a ver los consejos» bumps it, so each tip is new again:
    /// TipKit can't reset what it remembers while the app is running.
    nonisolated static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }

    static func showAgain() {
        UserDefaults.standard.set(generation + 1, forKey: generationKey)
        setShown(true)
    }

    /// «Mostrar consejos» in Cuenta, and the first tip's «No mostrar más consejos». Kept in the
    /// defaults for the switch to read, and in `areShown` for the tips' rules.
    static let shownKey = "tipsShown"

    @Parameter static var areShown: Bool = true

    static func setShown(_ shown: Bool) {
        UserDefaults.standard.set(shown, forKey: shownKey)
        areShown = shown
    }

    static func configure() {
        try? Tips.configure([.displayFrequency(.immediate)])
        areShown = UserDefaults.standard.object(forKey: shownKey) as? Bool ?? true
    }

    /// The first tip's button that turns them all off.
    static let turnOff = "turnOffTips"

    /// A subject opened. Reordering is worth a tip only once a few have been.
    static let subjectOpened = Tips.Event(id: "subjectOpened")
}

/// A tip whose id carries the current generation (see `GradeTips.generation`), shown only while
/// tips are on.
protocol GradeTip: Tip {}

extension GradeTip {
    var id: String { "\(Self.self)-\(GradeTips.generation)" }

    var rules: [Rule] {
        [#Rule(GradeTips.$areShown) { $0 }]
    }
}

// MARK: Home

/// Usually the first tip anyone sees, so it's the one that offers to turn them off.
struct SubjectTileTip: GradeTip {
    var title: Text { Text("Tu asignatura") }
    var message: Text? { Text("Tócala para poner tus notas. Mantenla pulsada para personalizarla, moverla o editarla.") }
    var image: Image? { Image(systemName: "hand.tap") }

    var actions: [Action] {
        [Action(id: GradeTips.turnOff, title: "No mostrar más consejos")]
    }
}

struct PeriodTip: GradeTip {
    var title: Text { Text("Cambia de periodo") }
    var message: Text? { Text("Aquí pasas de un periodo a otro, o creas vistas con las asignaturas que quieras.") }
    var image: Image? { Image(systemName: "calendar") }
}

struct ReorderTip: GradeTip {
    var title: Text { Text("Ordénalas a tu manera") }
    var message: Text? { Text("Mantén pulsado el fondo para moverlas, añadir o quitar asignaturas.") }
    var image: Image? { Image(systemName: "hand.draw") }

    var rules: [Rule] {
        [
            #Rule(GradeTips.$areShown) { $0 },
            #Rule(GradeTips.subjectOpened) { $0.donations.count >= 3 },
        ]
    }
}

// MARK: Subject

struct GradeEntryTip: GradeTip {
    var title: Text { Text("Pon tus notas") }
    var message: Text? { Text("Toca una parte para poner la nota que te han dado. Arriba ves lo que llevas y lo que te falta para aprobar.") }
    var image: Image? { Image(systemName: "pencil") }
}

struct EvaluationTip: GradeTip {
    var title: Text { Text("¿Se evalúa de otra forma?") }
    var message: Text? { Text("En Editar pones sus partes, los pesos y las notas mínimas, como en la guía docente.") }
    var image: Image? { Image(systemName: "slider.horizontal.3") }
}

// MARK: Editor

struct CalculationTip: GradeTip {
    var title: Text { Text("Cómo se calcula la nota") }
    var message: Text? { Text("Media ponderada si cada parte tiene un porcentaje, suma si da puntos y fórmula si la guía da una cuenta.") }
    var image: Image? { Image(systemName: "function") }
}

// MARK: Account

struct AccountTip: GradeTip {
    var title: Text { Text("Tu cuenta") }
    var message: Text? { Text("Aquí cambias qué estudias, ves tu expediente con las medias, haces copias de seguridad de tus notas y eliges si ver estos consejos.") }
    var image: Image? { Image(systemName: "person.crop.circle") }
}

// MARK: Calendar

struct CalendarFilterTip: GradeTip {
    var title: Text { Text("Elige qué ver") }
    var message: Text? { Text("Filtra por exámenes, entregas, controles u otras fechas.") }
    var image: Image? { Image(systemName: "line.3.horizontal.decrease") }
}
