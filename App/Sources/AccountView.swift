import Engine
import SwiftUI

/// The account tab, four modules top to bottom: what you study (a fold-out with its years and
/// terms), your record, your data (backups and deletes) and about the app.
struct AccountView: View {
    @Environment(Library.self) private var library
    @State private var isStudiesExpanded = false

    static let website = URL(string: "https://www.migueltaibo.com")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                StudiesSection(isExpanded: $isStudiesExpanded)

                Section {
                    RecordStats(summary: RecordSummary(library))
                    NavigationLink {
                        RecordView()
                    } label: {
                        Label("Ver expediente", systemImage: "chart.bar.doc.horizontal")
                    }
                } header: {
                    Text("Expediente")
                } footer: {
                    Text("Tu media por año, por \(library.degree.termName.isEmpty ? "periodo" : library.degree.termName.lowercased()) y de toda la carrera.")
                }

                Section("Datos") {
                    NavigationLink {
                        BackupView()
                    } label: {
                        AccountRow(title: "Copia de seguridad", detail: "Exportar o importar tus datos", symbol: "externaldrive")
                    }
                    NavigationLink {
                        EraseDataView()
                    } label: {
                        AccountRow(title: "Borrar datos", detail: "Notas o asignaturas", symbol: "trash")
                    }
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: version)
                    LabeledContent("Autor", value: "Miguel Taibo")
                    Link(destination: Self.website) {
                        LabeledContent("Web") {
                            Text("www.migueltaibo.com")
                                .foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        RoadmapView()
                    } label: {
                        Text("Próximas implementaciones")
                    }
                }
            }
            .navigationTitle("Cuenta")
        }
    }
}

/// A navigation row with an icon, a title and a line saying what's inside.
struct AccountRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

/// What you study, folded into one row ("Grado universitario · 4 años · 2 cuatrimestres por
/// año") that opens to edit the type, years and terms, plus the subject templates.
private struct StudiesSection: View {
    @Binding var isExpanded: Bool
    @Environment(Library.self) private var library

    private var degree: Binding<DegreeSettings> {
        Binding(get: { library.degree }, set: { library.updateDegree($0) })
    }

    private var studyType: Binding<StudyType> {
        Binding(get: { library.degree.studyType }, set: { library.updateDegree(library.degree.switching(to: $0)) })
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                Picker("Estudios", selection: studyType) {
                    ForEach(StudyType.allCases) { type in
                        Label(type.label, systemImage: type.symbol).tag(type)
                    }
                }
                Stepper(value: degree.years, in: 1...DegreeSettings.maxYears) {
                    LabeledContent("Años", value: library.degree.years.formatted())
                }
                Stepper(value: degree.termsPerYear, in: 1...DegreeSettings.maxTermsPerYear) {
                    LabeledContent("Periodos por año", value: library.degree.termsPerYear.formatted())
                }
                LabeledContent("Nombre del periodo") {
                    TextField("Cuatrimestre", text: degree.termName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
            } label: {
                AccountRow(title: library.degree.studyType.label, detail: library.degree.summary, symbol: library.degree.studyType.symbol)
            }

            NavigationLink {
                TemplatesView()
            } label: {
                AccountRow(title: "Plantillas", detail: "Asignaturas ya preparadas de tu carrera", symbol: "square.stack")
            }
        } header: {
            Text("Tus estudios")
        } footer: {
            if isExpanded {
                Text("Por ahora Grade está pensada para la universidad. Los periodos se usan en los títulos, p. ej. «2º Año · 1º \(library.degree.termName.isEmpty ? "Cuatrimestre" : library.degree.termName)»; si cambias cuántos hay por año, cada asignatura conserva su año y su posición dentro de él.")
            }
        }
    }
}

/// The bundled templates, each opening what it contains.
private struct TemplatesView: View {
    var body: some View {
        List {
            Section {
                ForEach(DegreeTemplate.all) { template in
                    NavigationLink {
                        TemplateView(template: template)
                    } label: {
                        AccountRow(title: template.name, detail: "\(template.university) · \(template.entries.count) asignaturas", symbol: "graduationcap")
                    }
                }
            } footer: {
                Text("Asignaturas ya preparadas con la evaluación de su guía docente. Después puedes editarlas.")
            }
        }
        .navigationTitle("Plantillas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What a template contains, by year and term, and the button that adds it to your degree.
private struct TemplateView: View {
    let template: DegreeTemplate

    @Environment(Library.self) private var library
    @State private var result: (added: Int, skipped: Int)?

    var body: some View {
        List {
            ForEach(template.years, id: \.self) { year in
                ForEach(1...max(library.degree.termsPerYear, 1), id: \.self) { term in
                    let entries = template.entries(year: year, term: term)
                    if !entries.isEmpty {
                        Section("\(year)º Año · \(library.degree.termLabel(library.degree.absoluteTerm(year: year, relative: term)))") {
                            ForEach(entries.indices, id: \.self) { index in
                                LabeledContent(entries[index].subject.name, value: "\(entries[index].subject.ectsCredits.formatted()) ECTS")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                result = library.apply(template)
            } label: {
                Text("Añadir a mi carrera")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .alert("Plantilla añadida", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("Vale") {}
        } message: {
            if let result {
                Text(result.skipped == 0
                     ? "Se han añadido \(result.added) asignaturas."
                     : "Se han añadido \(result.added) asignaturas. Las otras \(result.skipped) ya las tenías.")
            }
        }
    }
}
