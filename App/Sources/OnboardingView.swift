import Engine
import SwiftUI

/// The first launch: what Grade does, what you study (years, terms, credits, how the transcript
/// rounds) and, for a degree that has one, its template. It ends offering the guided tour.
struct OnboardingView: View {
    /// Called when it's done; `true` to start the tour.
    let onFinish: (Bool) -> Void

    @Environment(Library.self) private var library
    @State private var path: [Step] = []
    @State private var draft = DegreeSettings()

    private enum Step: Hashable { case study, templates, done }

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .study: study
                    case .templates: templates
                    case .done: done
                    }
                }
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 24)
            Text("Te dice qué necesitas para aprobar")
                .font(.system(.largeTitle, design: .rounded).bold())
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 22) {
                Feature(symbol: "list.bullet.rectangle", title: "Cada asignatura, como su guía", text: "Pesos, notas mínimas, fórmulas, evaluación continua o examen único, y su extraordinaria.")
                Feature(symbol: "target", title: "Lo que te falta", text: "Con cada nota que pones, lo que necesitas en el resto para aprobar.")
                Feature(symbol: "calendar", title: "Fechas y expediente", text: "Entregas y exámenes en el calendario, y tu media por periodo, año y carrera.")
            }
            Spacer()
            Button {
                path.append(.study)
            } label: {
                Text("Empezar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var study: some View {
        List {
            StudySettingsSections(degree: $draft)
            Section {
                Button("Siguiente") {
                    library.startStudy(draft)
                    path.append(draft.studyType == .university ? .templates : .done)
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            } footer: {
                Text("Todo esto se puede cambiar después en Cuenta → Estudio actual.")
            }
        }
        .navigationTitle("¿Qué estudias?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var templates: some View {
        List {
            Section {
                ForEach(DegreeTemplate.all) { template in
                    NavigationLink {
                        TemplateView(template: template)
                    } label: {
                        AccountRow(title: template.name, detail: "\(template.university) · \(TemplatesView.subjectsLabel(template.entries.count))", symbol: "graduationcap")
                    }
                }
            } footer: {
                Text("Asignaturas ya preparadas con la evaluación de su guía docente. Si tu grado no está, crea las tuyas desde la pantalla principal: solo hace falta copiar cómo te evalúan.")
            }
            Section {
                Button(library.courses.contains { !$0.subjects.isEmpty } ? "Siguiente" : "Seguir sin plantilla") {
                    path.append(.done)
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("Tu grado")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Todo listo")
                .font(.system(.largeTitle, design: .rounded).bold())
            Text("¿Te enseño cómo funciona? Es un recorrido de un par de minutos con un estudio de prueba; lo tuyo no se toca. Lo tienes siempre en Cuenta → Tutoriales.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                onFinish(true)
            } label: {
                Text("Ver el tour").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
