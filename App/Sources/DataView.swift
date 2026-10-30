import SwiftUI

/// Picks the part of the degree an export or a delete works on: all of it, a year or one of its
/// terms — only the years and terms that have subjects.
private struct ScopePicker: View {
    @Binding var scope: DataScope
    @Environment(Library.self) private var library

    var body: some View {
        Picker("Alcance", selection: $scope) {
            Text("Todo el estudio").tag(DataScope.all)
            ForEach(library.courses.filter { !$0.subjects.isEmpty }) { course in
                Section(course.name(in: library.degree)) {
                    Text("\(course.name(in: library.degree)) completo").tag(DataScope.year(course.year))
                    ForEach(Set(course.subjects.compactMap(\.term)).sorted(), id: \.self) { term in
                        // The section already names the year; the full title would wrap in the menu.
                        Text(library.degree.termLabel(term)).tag(DataScope.term(term))
                    }
                }
            }
        }
        .onChange(of: library.courses) {
            // The picked year or term may have just lost its last subject.
            if scope != .all, library.records(in: scope).isEmpty { scope = .all }
        }
    }
}

/// "Copia de seguridad": export a `.grade` with exactly what you choose, or import one.
struct BackupView: View {
    @Environment(Library.self) private var library
    @Environment(BackupImportCenter.self) private var backupCenter
    @State private var options = BackupOptions()

    private func subjectsLabel(_ count: Int) -> String {
        count == 1 ? "1 asignatura" : "\(count) asignaturas"
    }

    var body: some View {
        let count = library.records(in: options.scope).count
        let scope = options.scope == .all ? "" : " de \(options.scope.title(in: library.degree))"
        List {
            Section {
                ScopePicker(scope: $options.scope)
                Toggle("Notas", isOn: $options.includesGrades)
                if !library.guideIDs.isEmpty {
                    Toggle("Guías docentes", isOn: $options.includesGuides)
                }
                if !library.selections.isEmpty {
                    Toggle("Vistas personalizadas", isOn: $options.includesViews)
                }
                if !library.archives.isEmpty, options.scope == .all {
                    Toggle("Estudios archivados", isOn: $options.includesArchives)
                }
            } header: {
                Text("Qué guardar")
            } footer: {
                Text("Se guardan \(subjectsLabel(count))\(scope) con su evaluación\(options.includesGrades ? ", sus fechas y sus notas" : " y sus fechas, sin notas"). Sin notas sirve para pasarle tus asignaturas a un compañero.")
            }

            Section {
                ShareLink(item: BackupFile(library: library, options: options), preview: SharePreview("Copia de Grade")) {
                    Label("Exportar copia", systemImage: "square.and.arrow.up")
                }
                .disabled(count == 0)
            }

            Section {
                Button("Importar copia", systemImage: "square.and.arrow.down") { backupCenter.isPicking = true }
            } header: {
                Text("Recuperar")
            } footer: {
                Text("Elige un archivo .grade (también puedes abrirlo con Grade desde Archivos o AirDrop). Puedes añadir sus asignaturas a las tuyas o sustituir tu estudio actual por el de la copia.")
            }
        }
        .navigationTitle("Copia de seguridad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Borrar datos": empty the grades or remove the subjects, of the whole degree or part of it.
struct EraseDataView: View {
    private enum Action: Identifiable {
        case grades, subjects
        var id: Self { self }
    }

    @Environment(Library.self) private var library
    @State private var scope = DataScope.all
    @State private var confirming: Action?

    private func subjectsLabel(_ count: Int) -> String {
        count == 1 ? "1 asignatura" : "\(count) asignaturas"
    }

    var body: some View {
        let count = library.records(in: scope).count
        let scopeName = scope == .all ? "todo el estudio" : scope.title(in: library.degree)
        List {
            Section {
                ScopePicker(scope: $scope)
            } footer: {
                Text("Afecta a \(subjectsLabel(count))\(scope == .all ? "" : " de \(scopeName)").")
            }

            Section {
                Button("Borrar notas", role: .destructive) { confirming = .grades }
                    .disabled(count == 0)
            } footer: {
                Text("Vacía las notas; la evaluación, las fechas y las guías se quedan.")
            }

            Section {
                Button("Borrar asignaturas", role: .destructive) { confirming = .subjects }
                    .disabled(count == 0)
            } footer: {
                Text("Elimina las asignaturas con sus notas, fechas y guías.")
            }
        }
        .navigationTitle("Borrar datos")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            confirming == .subjects ? "¿Borrar las asignaturas de \(scopeName)?" : "¿Borrar las notas de \(scopeName)?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            switch action {
            case .grades: Button("Borrar notas", role: .destructive) { library.clearGrades(in: scope) }
            case .subjects: Button("Borrar asignaturas", role: .destructive) { library.removeSubjects(in: scope) }
            }
        } message: { _ in
            Text("Afecta a \(subjectsLabel(count)). No se puede deshacer.")
        }
    }
}
