import SwiftUI

/// One section of what's planned: a list of things on the way, or a paragraph about something bigger.
struct RoadmapSection: Identifiable {
    enum Content {
        case items([String])
        case text(String)
    }

    let title: String
    let content: Content

    var id: String { title }

    /// Written here for now; it'll be downloaded from migueltaibo.com so it can change without an
    /// app update.
    static let all = [
        RoadmapSection(title: "Próxima actualización", content: .items([
            "Widgets",
            "Notificaciones y alertas para tareas o exámenes",
        ])),
        RoadmapSection(title: "Asistente de IA", content: .text(
            "Pásale la guía docente y configurará la asignatura por ti. También podrás contarle las reglas («si saco menos de un 4 en tal parte, la otra no hace media») y hará los cambios sin que entres al editor."
        )),
        RoadmapSection(title: "Plantillas de la comunidad", content: .text(
            "Publica la configuración de tus asignaturas para que tus compañeros la descarguen como plantilla y la editen. Para compartirlas habrá cuentas de usuario."
        )),
    ]
}

/// "Próximas implementaciones", from the account tab: what's planned.
struct RoadmapView: View {
    var body: some View {
        List {
            ForEach(RoadmapSection.all) { section in
                Section {
                    switch section.content {
                    case .items(let items):
                        ForEach(items, id: \.self) { item in
                            Label(item, systemImage: "circle")
                                .labelStyle(RoadmapItemStyle())
                        }
                    case .text(let text):
                        Text(text)
                    }
                } header: {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
        }
        .navigationTitle("Próximas implementaciones")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A small dot in front of each planned item, top-aligned so long lines wrap under the text.
private struct RoadmapItemStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(.tint)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            configuration.title
        }
    }
}
