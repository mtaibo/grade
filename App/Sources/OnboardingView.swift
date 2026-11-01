import Engine
import SwiftUI

/// The first launch, and the first one after "Borrar todos los datos": what Grade does, then one
/// question per screen — what you study, how long it lasts and which year you're in, how the year
/// is split, its name — and, for a degree, its template. It ends offering the guided tour.
struct OnboardingView: View {
    /// Called when it's done; `true` to start the tour.
    let onFinish: (Bool) -> Void

    @Environment(Library.self) private var library
    @AppStorage("selectedYear") private var selectedYear = 0
    @AppStorage("selectedTerm") private var selectedTerm = 0
    @State private var path: [Step] = []
    @State private var draft = DegreeSettings()
    /// The year the student is in now, so the home screen opens there.
    @State private var currentYear = 1

    private enum Step: Hashable { case type, years, terms, name, templates, done }

    private var isUniversity: Bool { draft.studyType == .university }

    /// The question steps, for the progress bar (the welcome and the end don't count). Bachillerato
    /// always lasts two years split in trimestres, so it isn't asked.
    private var questions: [Step] {
        isUniversity ? [.type, .years, .terms, .name, .templates] : [.type, .years, .name]
    }

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .type: typeStep
                    case .years: yearsStep
                    case .terms: termsStep
                    case .name: nameStep
                    case .templates: templatesStep
                    case .done: done
                    }
                }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 24)
            Text("Te dice qué necesitas para aprobar")
                .font(.system(.largeTitle, design: .rounded).bold())
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 22) {
                Feature(symbol: "list.bullet.rectangle", title: "Cada asignatura, a su manera", text: "Pesos, notas mínimas, exámenes y trabajos, tal como te evalúan.")
                Feature(symbol: "target", title: "Lo que te falta", text: "Con cada nota que pones, lo que necesitas en el resto para aprobar.")
                Feature(symbol: "calendar", title: "Fechas y medias", text: "Exámenes y entregas en el calendario, y tu media de cada periodo y curso.")
            }
            Spacer()
            PrimaryButton("Empezar") { path.append(.type) }
        }
        .padding(24)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Questions

    private var typeStep: some View {
        QuestionScreen(progress: progress(of: .type), title: "¿Qué estudias?", subtitle: "Así te enseño las cosas como las llamas en tu centro.") {
            VStack(spacing: 10) {
                ForEach(StudyType.allCases) { type in
                    ChoiceRow(title: type.label, symbol: type.symbol, isSelected: draft.studyType == type) {
                        choose(type)
                    }
                }
            }
        } footer: {
            PrimaryButton("Continuar") { path.append(.years) }
        }
    }

    private var yearsStep: some View {
        QuestionScreen(progress: progress(of: .years), title: "¿En qué curso estás?", subtitle: isUniversity ? "Y cuántos años dura en total." : nil) {
            VStack(alignment: .leading, spacing: 20) {
                if isUniversity {
                    HStack {
                        Text("Años en total")
                            .font(.headline)
                        Spacer()
                        Text(draft.years.formatted())
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                        Stepper("Años en total", value: $draft.years, in: 1...DegreeSettings.maxYears)
                            .labelsHidden()
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                    .animation(.snappy, value: draft.years)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(1...max(draft.years, 1), id: \.self) { year in
                        ChoiceRow(title: draft.yearLabel(year), isSelected: currentYear == year) { currentYear = year }
                    }
                }
            }
        } footer: {
            PrimaryButton("Continuar") { path.append(isUniversity ? .terms : .name) }
        }
        .onChange(of: draft.years) { _, years in currentYear = min(currentYear, years) }
    }

    private var termsStep: some View {
        QuestionScreen(progress: progress(of: .terms), title: "¿Cómo se divide el curso?", subtitle: "Cada asignatura irá en su periodo, o en todos si dura el año entero.") {
            VStack(spacing: 10) {
                ForEach(Division.all) { division in
                    ChoiceRow(
                        title: division.title,
                        detail: division.detail,
                        isSelected: draft.termsPerYear == division.terms && draft.termName == division.termName
                    ) {
                        draft.termsPerYear = division.terms
                        draft.termName = division.termName
                    }
                }
            }
        } footer: {
            PrimaryButton("Continuar") { path.append(.name) }
        }
    }

    private var nameStep: some View {
        QuestionScreen(progress: progress(of: .name), title: namePrompt.title, subtitle: "Opcional. Sale en Cuenta y en tu expediente.") {
            VStack(spacing: 0) {
                TextField(namePrompt.name, text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .padding(16)
                Divider().padding(.leading, 16)
                TextField(namePrompt.institution, text: $draft.institution)
                    .textInputAutocapitalization(.words)
                    .padding(16)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        } footer: {
            PrimaryButton(draft.name.isEmpty && draft.institution.isEmpty ? "Saltar" : "Continuar") { finishQuestions() }
        }
    }

    private var templatesStep: some View {
        QuestionScreen(progress: progress(of: .templates), title: "¿Está tu grado?", subtitle: "Asignaturas ya preparadas con la evaluación de su guía docente. Si el tuyo no está, crearás las tuyas copiando cómo te evalúan.") {
            VStack(spacing: 10) {
                ForEach(DegreeTemplate.all) { template in
                    NavigationLink {
                        TemplateView(template: template)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "graduationcap")
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).font(.headline)
                                Text("\(template.university) · \(TemplatesView.subjectsLabel(template.entries.count))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            PrimaryButton(library.courses.contains { !$0.subjects.isEmpty } ? "Continuar" : "Seguir sin plantilla") { path.append(.done) }
        }
    }

    // MARK: End

    private var done: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Todo listo")
                .font(.system(.largeTitle, design: .rounded).bold())
            Text("¿Te enseño cómo funciona? Es un recorrido de un par de minutos con asignaturas de prueba; lo tuyo no se toca. Lo tienes siempre en Cuenta → Tutoriales.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            PrimaryButton("Ver el tutorial") { onFinish(true) }
            Button {
                onFinish(false)
            } label: {
                Text("Ahora no").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(24)
        .navigationBarBackButtonHidden()
    }

    // MARK: Logic

    private func progress(of step: Step) -> Double {
        guard let index = questions.firstIndex(of: step) else { return 1 }
        return Double(index + 1) / Double(questions.count)
    }

    private var namePrompt: (title: String, name: String, institution: String) {
        switch draft.studyType {
        case .university: ("¿Cómo se llama tu grado?", "Ingeniería Informática", "Universidad o facultad")
        case .highSchool: ("¿Qué modalidad haces?", "Ciencias, Humanidades…", "Instituto")
        }
    }

    /// The type's usual years and split, and what its years are called ("1º Bachillerato").
    private func choose(_ type: StudyType) {
        draft = draft.switching(to: type)
        currentYear = min(currentYear, draft.years)
    }

    /// Saves the study and has the home screen open on the year picked, in its first period.
    private func finishQuestions() {
        library.startStudy(draft)
        selectedYear = currentYear
        selectedTerm = draft.absoluteTerm(year: currentYear, relative: 1)
        path.append(isUniversity ? .templates : .done)
    }
}

/// The ways a year usually splits.
private struct Division: Identifiable {
    let terms: Int
    let termName: String
    let title: String
    let detail: String

    var id: String { title }

    static let all = [
        Division(terms: 2, termName: "Cuatrimestre", title: "Cuatrimestres", detail: "Dos por curso"),
        Division(terms: 2, termName: "Semestre", title: "Semestres", detail: "Dos por curso"),
        Division(terms: 3, termName: "Trimestre", title: "Trimestres", detail: "Tres evaluaciones por curso"),
    ]
}

/// One question: a thin progress bar, the question in big type, its options, and the button to
/// go on pinned to the bottom.
private struct QuestionScreen<Content: View, Footer: View>: View {
    let progress: Double
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded).bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .principal) {
                ProgressView(value: progress)
                    .frame(width: 120)
                    .animation(.snappy, value: progress)
                    .accessibilityLabel("Progreso")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A big tappable option, ✓ and tinted when it's the chosen one.
private struct ChoiceRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.tint, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
