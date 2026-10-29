import Engine
import SwiftUI

// MARK: - Model

/// What a step waits for when it can't be skipped with "Siguiente": the user doing it for real.
enum TourAction: Hashable {
    case newSubjectOpened, subjectCreated, subjectOpened, editorOpened, editorClosed
}

struct TourStep {
    /// The highlighted element (see `tourTarget(_:)`); `nil` centres the pop-up over a dimmed screen.
    var target: String?
    var title: String
    var text: String
    /// Set: no "Siguiente", the step moves on once the user does it, tapping inside the highlight.
    var action: TourAction?
    /// The highlight opens a system menu, drawn outside it: once tapped, the dimming steps aside
    /// and every touch goes through until the action happens.
    var opensMenu = false
    /// The tab the step needs on screen.
    var tab: AppTab?
}

/// One part of the app, explained on its own from Cuenta → Tutoriales → Por sección.
enum TourSection: String, CaseIterable, Identifiable {
    case home, subject, editor, calendar, account

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Pantalla principal"
        case .subject: "Asignatura"
        case .editor: "Editar la evaluación"
        case .calendar: "Calendario"
        case .account: "Cuenta"
        }
    }

    var detail: String {
        switch self {
        case .home: "Tarjetas, cuatrimestres, vistas y orden"
        case .subject: "Tu nota, el examen final y cada parte"
        case .editor: "Cómo se calcula la nota de una asignatura"
        case .calendar: "Exámenes y entregas con fecha"
        case .account: "Estudios, expediente y datos"
        }
    }

    var symbol: String {
        switch self {
        case .home: "books.vertical"
        case .subject: "chart.bar"
        case .editor: "slider.horizontal.3"
        case .calendar: "calendar"
        case .account: "person.crop.circle"
        }
    }
}

// MARK: - Coordinator

/// Runs a guided tour over the real app. While it runs the app shows a throwaway study (empty for
/// the general tour, a template with dates for a section), so nothing the user has is touched; the
/// app is rebuilt on start and on end so no screen keeps pointing at the other library.
@MainActor
@Observable
final class Tour {
    private(set) var steps: [TourStep] = []
    private(set) var index = 0
    /// The library shown while the tour runs; `nil` when it isn't running.
    private(set) var sandbox: Library?
    /// Changes on start and end, to rebuild the app from scratch.
    private(set) var session = UUID()
    /// The tab to go back to when the tour ends.
    private(set) var returnTab = AppTab.subjects
    /// The UIKit views behind each target, by each view that marks it (a section marked on several
    /// rows is highlighted as their union). Measured in window coordinates on every frame while the
    /// tour runs: SwiftUI doesn't report a sheet moving as a whole, nor toolbar buttons at all.
    @ObservationIgnored private var anchors: [String: [UUID: Weak]] = [:]
    /// Toolbar buttons become native bar buttons that drop SwiftUI modifiers, so they're found by
    /// position instead: 0 is the rightmost button of the frontmost navigation bar, 1 the next one.
    private static let toolbarPositions = [
        "home.more": 0, "home.views": 1, "subject.more": 0, "new.save": 0, "editor.save": 0, "calendar.filter": 0,
    ]

    var isActive: Bool { sandbox != nil }
    /// The highlight on screen, in window coordinates, for `TourWindow` to let touches through.
    @ObservationIgnored var currentHole: CGRect?
    /// The pop-up on screen, in window coordinates; it keeps taking touches while a menu is open.
    @ObservationIgnored var currentBubble: CGRect?
    /// The highlight of an `opensMenu` step was tapped.
    private(set) var isMenuOpen = false
    var current: TourStep? { isActive && steps.indices.contains(index) ? steps[index] : nil }
    var isLast: Bool { index == steps.count - 1 }

    /// UserDefaults keys the home screen remembers, put back after the tour.
    private static let rememberedKeys = ["selectedYear", "selectedTerm", "selectedCustomView"]
    @ObservationIgnored private var remembered: [String: Any] = [:]

    func startGeneral(returningTo tab: AppTab) {
        start(Self.generalSteps, sandbox: Library(inMemory: DegreeSettings()), returningTo: tab)
    }

    func start(_ section: TourSection, degree: DegreeSettings, returningTo tab: AppTab) {
        let library = Library(inMemory: degree)
        if let template = DegreeTemplate.all.first { library.apply(template) }
        library.addSampleDates()
        start(Self.steps(for: section), sandbox: library, returningTo: tab)
    }

    private func start(_ steps: [TourStep], sandbox: Library, returningTo tab: AppTab) {
        for key in Self.rememberedKeys {
            remembered[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        self.steps = steps
        index = 0
        returnTab = tab
        self.sandbox = sandbox
        session = UUID()
    }

    func next() {
        // The keyboard sits above the tour's window: once past a step it would only cover the pop-up.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isMenuOpen = false
        if isLast { end() } else { index += 1 }
    }

    func menuOpened() { isMenuOpen = true }

    /// The user did something the current step may be waiting for.
    func perform(_ action: TourAction) {
        if current?.action == action { next() }
    }

    func end() {
        for key in Self.rememberedKeys {
            UserDefaults.standard.set(remembered[key], forKey: key)
        }
        remembered = [:]
        sandbox = nil
        isMenuOpen = false
        steps = []
        index = 0
        session = UUID()
    }

    func register(_ view: UIView?, for target: String, part: UUID) {
        anchors[target, default: [:]][part] = view.map(Weak.init)
    }

    /// Where a target is on screen right now, in window coordinates.
    func windowFrame(of target: String) -> CGRect? {
        let frames = (anchors[target] ?? [:]).values.compactMap { box -> CGRect? in
            guard let view = box.view, view.window != nil, !view.bounds.isEmpty else { return nil }
            return view.convert(view.bounds, to: nil)
        }
        if let first = frames.first { return frames.dropFirst().reduce(first) { $0.union($1) } }
        guard let position = Self.toolbarPositions[target] else { return nil }
        return Self.trailingBarButtonFrame(at: position)
    }

    /// The frame of the `position`th button from the right in the frontmost visible navigation bar
    /// of the app's window (a sheet's bar comes after the screen's below it).
    private static func trailingBarButtonFrame(at position: Int) -> CGRect? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { !($0 is TourWindow) && !$0.isHidden && $0.windowLevel == .normal }
        var bars: [UINavigationBar] = []
        func findBars(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let bar = view as? UINavigationBar, bar.window != nil, !bar.bounds.isEmpty { bars.append(bar) }
            view.subviews.forEach(findBars)
        }
        window.map(findBars)
        guard let bar = bars.last else { return nil }
        var controls: [CGRect] = []
        func findControls(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if view is UIControl {
                let frame = view.convert(view.bounds, to: nil)
                if frame.width > 20, frame.width < 140, frame.midX > bar.convert(bar.bounds, to: nil).midX {
                    controls.append(frame)
                    return
                }
            }
            view.subviews.forEach(findControls)
        }
        findControls(bar)
        let ordered = controls.sorted { $0.maxX > $1.maxX }
        return ordered.indices.contains(position) ? ordered[position] : nil
    }

    final class Weak {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }
}

// MARK: - Steps

extension Tour {
    static let generalSteps: [TourStep] = [
        TourStep(title: "Bienvenido a Grade", text: "Te enseño cómo funciona con un estudio de prueba. Tus asignaturas y notas no se tocan: al terminar vuelve todo como estaba.", tab: .subjects),
        TourStep(target: "home.add", title: "Tu primera asignatura", text: "Aquí verás las asignaturas del cuatrimestre. Toca «Añadir asignatura» para crear la primera.", action: .newSubjectOpened),
        TourStep(target: "new.name", title: "Ponle nombre", text: "Escribe cómo se llama, por ejemplo «Cálculo»."),
        TourStep(target: "new.period", title: "¿Cuándo es?", text: "Elige el año y el cuatrimestre. Si dura todo el curso, elige «Todo el año»."),
        TourStep(target: "new.save", title: "Créala", text: "Toca ✓ para añadirla. Si está gris, falta el nombre.", action: .subjectCreated),
        TourStep(target: "home.firstTile", title: "Tu asignatura", text: "Cada asignatura es una tarjeta. Si la mantienes pulsada puedes cambiar su icono y color, moverla de cuatrimestre, editar su evaluación o borrarla."),
        TourStep(target: "home.firstTile", title: "Ábrela", text: "Toca la tarjeta para entrar.", action: .subjectOpened),
        TourStep(target: "subject.summary", title: "Cómo vas", text: "La nota que llevas, lo que aún puedes sacar y lo que necesitas para aprobar. Tócala para ver el detalle."),
        TourStep(target: "subject.exam", title: "El examen final", text: "Toca una convocatoria para poner tu nota, y añade su fecha para verla en el Calendario."),
        TourStep(target: "subject.more", title: "La evaluación", text: "Cada asignatura se evalúa a su manera. Toca «…» y luego «Editar» para configurar la suya.", action: .editorOpened, opensMenu: true),
        TourStep(target: "editor.evaluation", title: "Cómo se calcula", text: "Elige si la nota final es una media ponderada, una suma de puntos o una fórmula."),
        TourStep(target: "editor.sections", title: "Las partes de la nota", text: "Añade cada parte de tu guía docente (exámenes, prácticas, trabajos) con su peso. El ✓ verde indica que todo cuadra."),
        TourStep(target: "editor.save", title: "Guarda", text: "Cuando acabes, toca ✓ para guardar los cambios.", action: .editorClosed),
        TourStep(target: "calendar.month", title: "Calendario", text: "Aquí aparecen tus exámenes y entregas con fecha. Toca un día para ver lo que tienes.", tab: .calendar),
        TourStep(target: "calendar.list", title: "Lo próximo", text: "Debajo, lo que viene. Toca una fecha para ir a su asignatura.", tab: .calendar),
        TourStep(target: "account.study", title: "Tu estudio", text: "En «Estudio actual» dices qué estudias: años, cuatrimestres, plantillas con asignaturas ya preparadas, o archivarlo para empezar otro.", tab: .account),
        TourStep(target: "account.record", title: "Expediente", text: "Tus medias por año, por cuatrimestre y de todo el estudio.", tab: .account),
        TourStep(target: "account.data", title: "Tus datos", text: "Haz copias de seguridad y recupéralas cuando quieras.", tab: .account),
        TourStep(target: "account.tutorials", title: "Cuando quieras", text: "Este tour y la explicación de cada sección están siempre aquí. ¡Listo!", tab: .account),
    ]

    static func steps(for section: TourSection) -> [TourStep] {
        switch section {
        case .home: [
            TourStep(target: "home.header", title: "Qué estás viendo", text: "El año y el cuatrimestre que tienes en pantalla, con sus asignaturas debajo.", tab: .subjects),
            TourStep(target: "home.views", title: "Cambiar de cuatrimestre", text: "Salta a otro año o cuatrimestre, o a una de tus vistas personalizadas."),
            TourStep(target: "home.more", title: "Más opciones", text: "Ver en cuadrícula o en lista, añadir una asignatura y crear vistas propias para juntar asignaturas de distintos periodos (una repetida, una adelantada…)."),
            TourStep(target: "home.firstTile", title: "Cada asignatura", text: "Tócala para abrirla. Mantenla pulsada para personalizar su icono y color, moverla, editar su evaluación o eliminarla. El círculo se llena según pones notas."),
            TourStep(title: "Ordenarlas", text: "Mantén pulsado el fondo para entrar en modo edición: arrastra las tarjetas para ordenarlas, la − borra una y el + añade otra."),
        ]
        case .subject: [
            TourStep(target: "home.firstTile", title: "Abre una asignatura", text: "Toca la tarjeta.", action: .subjectOpened, tab: .subjects),
            TourStep(target: "subject.summary", title: "Cómo vas", text: "La nota que llevas, lo que aún puedes sacar y la media que necesitas en lo que queda para aprobar. Tócala para ver el detalle."),
            TourStep(target: "subject.exam", title: "El examen final", text: "Sus dos convocatorias, ordinaria y extraordinaria. Toca una para poner la nota y añade la fecha para verla en el Calendario."),
            TourStep(target: "subject.parts", title: "El resto de notas", text: "Cada parte de la evaluación con su peso. Toca una para poner sus notas."),
            TourStep(target: "subject.more", title: "Más opciones", text: "Editar la evaluación, poner las fechas, el simulador para probar notas sin guardarlas y la guía docente en PDF."),
        ]
        case .editor: [
            TourStep(target: "home.firstTile", title: "Abre una asignatura", text: "Toca la tarjeta.", action: .subjectOpened, tab: .subjects),
            TourStep(target: "subject.more", title: "Abre el editor", text: "Toca «…» y luego «Editar».", action: .editorOpened, opensMenu: true),
            TourStep(target: "editor.name", title: "Nombre", text: "Cámbialo cuando quieras."),
            TourStep(target: "editor.evaluation", title: "Cómo se calcula", text: "Media ponderada (cada parte pesa un %), suma de puntos o una fórmula para las guías más raras."),
            TourStep(target: "editor.sections", title: "Secciones", text: "Cada parte de la nota con su peso. Toca una para cambiar su tipo, sus notas, su nota máxima o una nota mínima con su consecuencia. El ✓ verde indica que los pesos suman 100 %."),
            TourStep(target: "editor.save", title: "Guardar", text: "✓ guarda los cambios; ✗ sale sin guardar. Nada cambia hasta que guardas."),
        ]
        case .calendar: [
            TourStep(target: "calendar.month", title: "El mes", text: "Los puntos marcan los días con exámenes o entregas. Toca uno para ver solo lo de ese día.", tab: .calendar),
            TourStep(target: "calendar.list", title: "Lo próximo", text: "Las fechas que vienen, de la más cercana a la más lejana. Toca una para ir a su asignatura."),
            TourStep(target: "calendar.filter", title: "Filtrar", text: "Elige qué tipos de fechas ver: exámenes, entregas, controles…"),
        ]
        case .account: [
            TourStep(target: "account.study", title: "Estudio actual", text: "Qué estudias y cómo se divide, plantillas con asignaturas ya preparadas, y archivarlo para empezar otro sin perder nada.", tab: .account),
            TourStep(target: "account.record", title: "Expediente", text: "Tus medias por año, por cuatrimestre y de todo el estudio, contando solo las asignaturas terminadas."),
            TourStep(target: "account.data", title: "Datos", text: "Copias de seguridad (de todo o de una parte, con o sin notas) y borrar notas o asignaturas."),
            TourStep(target: "account.tutorials", title: "Tutoriales", text: "El tour completo y esta explicación de cada sección."),
        ]
        }
    }
}

// MARK: - Marking targets and hosting the overlay

extension View {
    /// Marks this view as a tour target, so a step can highlight it.
    func tourTarget(_ id: String?) -> some View {
        modifier(TourTargetModifier(id: id))
    }

    /// Tells the tour the user did something a step may be waiting for.
    func tourPerforms(_ action: TourAction, onAppear: Bool = true) -> some View {
        modifier(TourActionModifier(action: action, onAppear: onAppear))
    }
}

private struct TourTargetModifier: ViewModifier {
    let id: String?
    @Environment(Tour.self) private var tour: Tour?
    @State private var part = UUID()

    func body(content: Content) -> some View {
        if let id, let tour {
            content.background(ViewGrabber { tour.register($0, for: id, part: part) })
        } else {
            content
        }
    }
}

/// A clear UIKit view behind some SwiftUI content, handed over so it can be measured in window
/// coordinates.
private struct ViewGrabber: UIViewRepresentable {
    let grab: (UIView?) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        grab(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { grab(view) }
}

private struct TourActionModifier: ViewModifier {
    let action: TourAction
    let onAppear: Bool
    @Environment(Tour.self) private var tour: Tour?

    func body(content: Content) -> some View {
        content
            .onAppear { if onAppear { tour?.perform(action) } }
            .onDisappear { if !onAppear { tour?.perform(action) } }
    }
}

// MARK: - Overlay

/// The tour is drawn in a window of its own above the app, sheets included, so every element is
/// measured and highlighted in the same coordinates. It lets touches through only inside the
/// highlight of a step that waits for the user, and not at all while no tour runs.
@MainActor
final class TourWindow: UIWindow {
    private let tour: Tour

    init(scene: UIWindowScene, tour: Tour) {
        self.tour = tour
        super.init(windowScene: scene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        let host = UIHostingController(rootView: TourWindowContent(tour: tour))
        host.view.backgroundColor = .clear
        rootViewController = host
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard tour.isActive, let step = tour.current, let hit = super.hitTest(point, with: event) else { return nil }
        if tour.isMenuOpen {
            return tour.currentBubble?.contains(point) == true ? hit : nil
        }
        if step.action != nil, let hole = tour.currentHole, hole.contains(point) {
            if step.opensMenu { tour.menuOpened() }
            return nil
        }
        return hit
    }
}

/// Re-measures the highlighted element ten times a second, so the hole follows sheets, the keyboard
/// and scrolling; the overlay only redraws when it actually moved.
private struct TourWindowContent: View {
    let tour: Tour
    @State private var hole: CGRect?

    /// Within a couple of points: not worth a redraw.
    private static func isClose(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    var body: some View {
        if let step = tour.current {
            GeometryReader { proxy in
                TourOverlay(tour: tour, step: step, hole: hole, size: proxy.size, safeArea: proxy.safeAreaInsets)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .animation(.snappy, value: tour.index)
            .task(id: tour.index) {
                while !Task.isCancelled {
                    let measured = step.target.flatMap(tour.windowFrame(of:))?.insetBy(dx: -8, dy: -8).integral
                    if !Self.isClose(measured, hole) {
                        hole = measured
                        tour.currentHole = measured
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }
}

/// The dimmed screen with a hole around the highlighted element, and the pop-up next to it.
private struct TourOverlay: View {
    let tour: Tour
    let step: TourStep
    let hole: CGRect?
    let size: CGSize
    let safeArea: EdgeInsets

    private var paddedHole: CGRect? { hole }

    var body: some View {
        let shape = DimShape(hole: paddedHole)
        ZStack(alignment: .top) {
            shape
                .fill(.black.opacity(tour.isMenuOpen ? 0 : 0.55), style: FillStyle(eoFill: true))
                // Taps on the dimmed part go nowhere (`TourWindow` lets the ones in the hole through
                // when the step waits for the user).
                .contentShape(Rectangle())
                .onTapGesture {}

            if let paddedHole, !tour.isMenuOpen {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: paddedHole.width, height: paddedHole.height)
                    .position(x: paddedHole.midX, y: paddedHole.midY)
                    .allowsHitTesting(false)
            }

            bubble
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let card = TourBubble(tour: tour, step: step)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tour.currentBubble = $0 }
            .padding(.horizontal, 16)
        if tour.isMenuOpen {
            // Out of the menu's way.
            card
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, safeArea.bottom + 90)
        } else if let paddedHole {
            if paddedHole.midY > size.height / 2 {
                // Above the highlight.
                card
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, max(size.height - paddedHole.minY + 12, safeArea.bottom))
            } else {
                card
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, max(paddedHole.maxY + 12, safeArea.top))
            }
        } else {
            card.frame(maxHeight: .infinity)
        }
    }
}

private struct TourBubble: View {
    let tour: Tour
    let step: TourStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(tour.index + 1) de \(tour.steps.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(step.title)
                .font(.headline)
            Text(step.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Salir") { tour.end() }
                    .foregroundStyle(.secondary)
                Spacer()
                if step.action == nil {
                    Button(tour.isLast ? "Terminar" : "Siguiente") { tour.next() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Label("Toca lo resaltado", systemImage: "hand.tap")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: 500, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

/// The whole screen minus a rounded hole (even-odd), for the dimming and its hit area.
private struct DimShape: Shape {
    let hole: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16)) }
        return path
    }
}

// MARK: - Cuenta → Tutoriales → Por sección

struct TourSectionsView: View {
    @Environment(Tour.self) private var tour: Tour?
    @Environment(Library.self) private var library

    var body: some View {
        List {
            Section {
                ForEach(TourSection.allCases) { section in
                    Button {
                        tour?.start(section, degree: library.degree, returningTo: .account)
                    } label: {
                        AccountRow(title: section.title, detail: section.detail, symbol: section.symbol)
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("Te enseña la pantalla con asignaturas de ejemplo. Tus datos no se tocan.")
            }
        }
        .navigationTitle("Por sección")
        .navigationBarTitleDisplayMode(.inline)
    }
}
