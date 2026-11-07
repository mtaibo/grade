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

    /// «Mostrar consejos» in Cuenta, and the welcome tip's «No mostrar consejos». Kept in the
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

    /// The welcome tip's button that turns them all off.
    static let turnOff = "turnOffTips"

    /// A subject opened. Reordering is worth a tip only once a few have been.
    static let subjectOpened = Tips.Event(id: "subjectOpened")
}

// The pop-up ones are kept to about three lines: longer, and TipKit puts them in a scroll view
// that flashes its bar as it appears.

/// A tip whose id carries the current generation (see `GradeTips.generation`), shown only while
/// tips are on.
protocol GradeTip: Tip {}

extension GradeTip {
    var id: String { "\(Self.self)-\(GradeTips.generation)" }

    /// The title with where it stands among its screen's tips («2 de 4»), so it's clear how many
    /// more are coming. TipKit leaves no room by the ✗, so it follows the title, smaller and grey.
    func counted(_ title: String, _ position: Int, of total: Int) -> Text {
        let counter = Text("\(position) de \(total)").font(.subheadline).foregroundStyle(.secondary)
        return Text("\(title)  \(counter)")
    }

    var rules: [Rule] {
        [#Rule(GradeTips.$areShown) { $0 }]
    }
}

// MARK: Home

/// The first of all, a card on the home screen: says tips will come, before any does, and is
/// where they're turned off.
struct WelcomeTip: GradeTip {
    var title: Text { counted("Consejos", 1, of: 4) }
    var message: Text? { Text("La primera vez que pases por cada zona te dejaré un consejo como este. Si prefieres descubrirlo todo por tu cuenta, desactívalos aquí; puedes volver a activarlos cuando quieras en Cuenta.") }
    var image: Image? { Image(systemName: "lightbulb") }

    var actions: [Action] {
        [Action(id: GradeTips.turnOff, title: "No mostrar consejos")]
    }
}

/// On the title, which is always there: the calendar button only is once there's more than one view.
struct ViewsTip: GradeTip {
    var title: Text { counted("Tus vistas", 2, of: 4) }
    var message: Text? { Text("Lo que ves aquí: un periodo o una selección tuya de asignaturas. Créalas en «…» → Editar vistas y cambia de una a otra con el calendario.") }
    var image: Image? { Image(systemName: "rectangle.stack") }
}

struct SubjectTileTip: GradeTip {
    var title: Text { counted("Tu asignatura", 3, of: 4) }
    var message: Text? { Text("Toca para apuntar tus notas. Mantén pulsado para editarla o cambiar su icono y su color.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

struct ReorderTip: GradeTip {
    var title: Text { counted("Ordénalas a tu manera", 4, of: 4) }
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
    var title: Text { counted("Apunta tus notas", 1, of: 2) }
    var message: Text? { Text("Toca una sección para apuntar la nota que te han puesto. Arriba ves lo que llevas; tócalo para ver más detalles.") }
    var image: Image? { Image(systemName: "pencil") }
}

struct EvaluationTip: GradeTip {
    var title: Text { counted("¿Se evalúa de otra forma?", 2, of: 2) }
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
