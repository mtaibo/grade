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
    @State private var isExporting = false
    @State private var exportError: String?

    /// Gathers the copy here and writes it in the background, so the spinner keeps turning.
    private func export() {
        isExporting = true
        let backup = library.backupContents(options)
        let name = library.backupFileName(options)
        Task {
            defer { isExporting = false }
            do {
                ShareSheet.present(try await backup.writeTemporaryFile(named: name))
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func subjectsLabel(_ count: Int) -> String {
        count == 1 ? "1 asignatura" : "\(count) asignaturas"
    }

    var body: some View {
        let count = library.records(in: options.scope).count
        let scope = options.scope == .all ? "" : " de \(options.scope.title(in: library.degree))"
        let archiveCount = options.scope == .all ? library.archives.count { !options.excludedArchives.contains($0.id) } : 0
        // Archived studies are worth a copy even while the current one is still empty.
        let canExport = count > 0 || archiveCount > 0
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
            } header: {
                Text("Qué guardar")
            } footer: {
                Text("Se guardan \(subjectsLabel(count))\(scope) con su evaluación\(options.includesGrades ? ", sus fechas y sus notas" : " y sus fechas, sin notas"). Sin notas sirve para pasarle tus asignaturas a un compañero.")
            }

            if !library.archives.isEmpty, options.scope == .all {
                Section {
                    ForEach(library.archives.reversed()) { study in
                        Toggle(isOn: Binding(
                            get: { !options.excludedArchives.contains(study.id) },
                            set: { if $0 { options.excludedArchives.remove(study.id) } else { options.excludedArchives.insert(study.id) } }
                        )) {
                            Label(study.degree.displayName, systemImage: "archivebox")
                        }
                    }
                } header: {
                    Text("Archivo")
                } footer: {
                    Text("Los estudios archivados que marques van en la copia con todas sus asignaturas, notas y vistas.")
                }
            }

            Section {
                Button(action: export) {
                    HStack {
                        Label("Exportar copia", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                    .contentShape(.rect)
                }
                .disabled(!canExport || isExporting)
                // Grey while there is nothing to save, blue otherwise (even while it works).
                .foregroundStyle(canExport ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }

            Section {
                Button("Importar copia", systemImage: "square.and.arrow.down") { backupCenter.isPicking = true }
            } header: {
                Text("Recuperar")
            } footer: {
                Text("Elige un archivo .grade (también puedes abrirlo con Grade desde Archivos o AirDrop). Puedes añadir sus asignaturas a las tuyas o sustituir tu estudio actual por el de la copia.")
            }
        }
        .alert("No se ha podido exportar", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("Vale") {}
        } message: {
            Text(exportError ?? "")
        }
        .navigationTitle("Copia de seguridad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Borrar datos": empty the grades or remove the subjects, of the whole degree or part of it, or
/// wipe everything.
struct EraseDataView: View {
    private enum Action: Identifiable {
        case grades, subjects, everything
        var id: Self { self }
    }

    @Environment(Library.self) private var library
    @State private var scope = DataScope.all
    @State private var confirming: Action?

    private func subjectsLabel(_ count: Int) -> String {
        count == 1 ? "1 asignatura" : "\(count) asignaturas"
    }

    private func dialogTitle(scopeName: String) -> String {
        switch confirming {
        case .everything: "¿Borrar todos los datos?"
        case .subjects: "¿Borrar las asignaturas de \(scopeName)?"
        default: "¿Borrar las notas de \(scopeName)?"
        }
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

            Section {
                Button("Borrar todos los datos", role: .destructive) { confirming = .everything }
            } footer: {
                Text("Deja Grade como recién instalada: el estudio actual con sus ajustes, asignaturas, notas, fechas, vistas y guías, y también los estudios archivados.")
            }
        }
        .navigationTitle("Borrar datos")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            dialogTitle(scopeName: scopeName),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            switch action {
            case .grades: Button("Borrar notas", role: .destructive) { library.clearGrades(in: scope) }
            case .subjects: Button("Borrar asignaturas", role: .destructive) { library.removeSubjects(in: scope) }
            case .everything: Button("Borrar todo", role: .destructive) { library.eraseAll() }
            }
        } message: { action in
            if action == .everything {
                Text("Se borra todo, también los estudios archivados. Si quieres conservar algo, haz antes una copia de seguridad. No se puede deshacer.")
            } else {
                Text("Afecta a \(subjectsLabel(count)). No se puede deshacer.")
            }
        }
    }
}
