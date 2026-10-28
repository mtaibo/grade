import Engine
import SwiftUI

/// The account tab: the things you look at occasionally rather than while the term runs — the
/// record (expediente) and the app's settings.
struct AccountView: View {
    @Environment(Library.self) private var library
    @Environment(BackupImportCenter.self) private var backupCenter
    @State private var isConfirmingClear = false
    @State private var isConfirmingRemoveAll = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var degreeBinding: Binding<DegreeSettings> {
        Binding(get: { library.degree }, set: { library.updateDegree($0) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RecordView()
                    } label: {
                        Label("Expediente", systemImage: "chart.bar.doc.horizontal")
                    }
                }

                Section {
                    ForEach(DegreeTemplate.all) { template in
                        NavigationLink {
                            TemplateView(template: template)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                    Text("\(template.university) · \(template.entries.count) asignaturas")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "graduationcap")
                            }
                        }
                    }
                } header: {
                    Text("Plantillas")
                } footer: {
                    Text("Asignaturas ya preparadas con la evaluación de su guía docente. Después puedes editarlas.")
                }

                Section {
                    Stepper(value: degreeBinding.years, in: 1...DegreeSettings.maxYears) {
                        LabeledContent("Años de carrera", value: library.degree.years.formatted())
                    }
                    Stepper(value: degreeBinding.termsPerYear, in: 1...DegreeSettings.maxTermsPerYear) {
                        LabeledContent("Periodos por año", value: library.degree.termsPerYear.formatted())
                    }
                    LabeledContent("Nombre del periodo") {
                        TextField("Cuatrimestre", text: degreeBinding.termName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("Tu carrera")
                } footer: {
                    Text("Se usa en los títulos, p. ej. «2º Año · 1º \(library.degree.termName.isEmpty ? "Cuatrimestre" : library.degree.termName)». Si cambias los periodos por año, cada asignatura conserva su año y su posición dentro de él.")
                }

                Section {
                    ShareLink(item: BackupFile(library: library), preview: SharePreview("Copia de Mark")) {
                        Label("Exportar datos", systemImage: "square.and.arrow.up")
                    }
                    Button("Importar datos", systemImage: "square.and.arrow.down") { backupCenter.isPicking = true }
                } header: {
                    Text("Copia de seguridad")
                } footer: {
                    Text("Exporta todas tus asignaturas, notas, fechas y ajustes a un archivo .mark. Para recuperarlos, impórtalo aquí o ábrelo con Mark.")
                }

                Section {
                    Button("Borrar todas las notas", role: .destructive) { isConfirmingClear = true }
                    Button("Borrar todas las asignaturas", role: .destructive) { isConfirmingRemoveAll = true }
                } header: {
                    Text("Datos")
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: version)
                }
            }
            .navigationTitle("Cuenta")
            .confirmationDialog("¿Borrar todas las notas?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Borrar notas", role: .destructive) { library.clearAllGrades() }
            } message: {
                Text("Se borran las notas de todas las asignaturas. No se puede deshacer.")
            }
            .confirmationDialog("¿Borrar todas las asignaturas?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
                Button("Borrar todo", role: .destructive) { library.removeAllSubjects() }
            } message: {
                Text("Se borran todas tus asignaturas y sus notas. No se puede deshacer.")
            }
        }
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
