import SwiftUI

/// The account tab: the things you look at occasionally rather than while the term runs — the
/// record (expediente) and the app's settings.
struct AccountView: View {
    @Environment(Library.self) private var library
    @State private var isConfirmingClear = false
    @State private var isConfirmingRestore = false

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
                    Button("Borrar todas las notas", role: .destructive) { isConfirmingClear = true }
                    Button("Restaurar asignaturas de ejemplo", role: .destructive) { isConfirmingRestore = true }
                } header: {
                    Text("Datos")
                } footer: {
                    Text("Restaurar borra tus asignaturas y notas y deja solo las de ejemplo, tal como venían.")
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
            .confirmationDialog("¿Restaurar las asignaturas de ejemplo?", isPresented: $isConfirmingRestore, titleVisibility: .visible) {
                Button("Restaurar", role: .destructive) { library.restoreExamples() }
            } message: {
                Text("Vuelven las asignaturas de ejemplo tal como venían, sin notas, y se pierden las que hayas creado. No se puede deshacer.")
            }
        }
    }
}
