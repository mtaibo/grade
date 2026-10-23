import SwiftUI

struct SettingsView: View {
    @Environment(Library.self) private var library
    @State private var isConfirmingClear = false
    @State private var isConfirmingRestore = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Borrar todas las notas", role: .destructive) { isConfirmingClear = true }
                    Button("Restaurar asignaturas de ejemplo", role: .destructive) { isConfirmingRestore = true }
                } header: {
                    Text("Datos")
                } footer: {
                    Text("Restaurar deshace los cambios que hayas hecho en la evaluación de las asignaturas y borra sus notas.")
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: version)
                }
            }
            .navigationTitle("Ajustes")
            .confirmationDialog("¿Borrar todas las notas?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Borrar notas", role: .destructive) { library.clearAllGrades() }
            } message: {
                Text("Se borran las notas de todas las asignaturas. No se puede deshacer.")
            }
            .confirmationDialog("¿Restaurar las asignaturas de ejemplo?", isPresented: $isConfirmingRestore, titleVisibility: .visible) {
                Button("Restaurar", role: .destructive) { library.restoreExamples() }
            } message: {
                Text("Vuelven las asignaturas de ejemplo tal como venían, sin notas. No se puede deshacer.")
            }
        }
    }
}
