import Engine
import SwiftUI

/// "Estudio actual", from the account tab: what you study and how it's divided, its templates,
/// and archiving it to start another.
struct CurrentStudyView: View {
    @Environment(Library.self) private var library
    @State private var isArchiving = false

    private var degree: Binding<DegreeSettings> {
        Binding(get: { library.degree }, set: { library.updateDegree($0) })
    }

    private var studyType: Binding<StudyType> {
        Binding(get: { library.degree.studyType }, set: { library.updateDegree(library.degree.switching(to: $0)) })
    }

    private var termName: String {
        library.degree.termName.isEmpty ? "Cuatrimestre" : library.degree.termName
    }

    var body: some View {
        let subjectCount = library.courses.reduce(0) { $0 + $1.subjects.count }
        List {
            Section {
                Picker("Tipo", selection: studyType) {
                    ForEach(StudyType.allCases) { type in
                        Label(type.label, systemImage: type.symbol).tag(type)
                    }
                }
                LabeledContent("Nombre") {
                    TextField(library.degree.studyType.label, text: degree.name)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
                LabeledContent("Centro") {
                    TextField("Opcional", text: degree.institution)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
            } footer: {
                Text("Por ahora Grade está pensada para la universidad. Al cambiar el tipo se ponen sus años y periodos habituales.")
            }

            Section {
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
            } header: {
                Text("Organización")
            } footer: {
                Text("Se usa en los títulos, p. ej. «2º Año · 1º \(termName)». Si cambias cuántos periodos hay por año, cada asignatura conserva su año y su posición dentro de él.")
            }

            Section {
                Button("Archivar y empezar otro", systemImage: "archivebox") { isArchiving = true }
                    .disabled(subjectCount == 0)
            } footer: {
                Text("Guarda este estudio con sus \(subjectCount) asignaturas y sus notas para consultarlo cuando quieras, y empieza uno nuevo vacío. Por ejemplo, al pasar del instituto a la universidad.")
            }
        }
        .navigationTitle("Estudio actual")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isArchiving) {
            ArchiveStudySheet()
        }
    }
}

/// Asks what the new study is before putting the current one away.
private struct ArchiveStudySheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var newType = StudyType.university

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Se archiva", value: library.degree.displayName)
                } footer: {
                    Text("Sus asignaturas, notas, fechas, vistas y guías quedan guardadas en «Estudios». Puedes volver a él en cualquier momento.")
                }
                Section("Nuevo estudio") {
                    Picker("Tipo", selection: $newType) {
                        ForEach(StudyType.allCases) { type in
                            Label(type.label, systemImage: type.symbol).tag(type)
                        }
                    }
                }
            }
            .navigationTitle("Archivar estudio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        library.archiveCurrentStudy(startingAs: newType)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// An archived study: what it was, its record, and going back to it or deleting it.
struct ArchivedStudyView: View {
    let id: ArchivedStudy.ID

    private enum Action: Identifiable {
        case resume, delete
        var id: Self { self }
    }

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirming: Action?

    var body: some View {
        if let study = library.archives.first(where: { $0.id == id }) {
            content(study)
        } else {
            // Resumed or deleted: the screen goes with it.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ study: ArchivedStudy) -> some View {
        let subjectCount = study.courses.reduce(0) { $0 + $1.subjects.count }
        return List {
            Section {
                LabeledContent("Tipo", value: study.degree.studyType.label)
                if !study.degree.institution.isEmpty {
                    LabeledContent("Centro", value: study.degree.institution)
                }
                LabeledContent("Organización", value: study.degree.summary)
                LabeledContent("Archivado", value: study.archivedAt.formatted(date: .long, time: .omitted))
            }

            Section("Expediente") {
                RecordStats(summary: RecordSummary(study.courses))
                NavigationLink {
                    RecordView(archived: study)
                } label: {
                    Label("Ver expediente", systemImage: "chart.bar.doc.horizontal")
                }
            }

            Section {
                Button("Volver a este estudio", systemImage: "arrow.uturn.backward") { confirming = .resume }
            } footer: {
                Text("Pasa a ser tu estudio actual, y el actual se archiva en su lugar.")
            }

            Section {
                Button("Eliminar estudio", systemImage: "trash", role: .destructive) { confirming = .delete }
            }
        }
        .navigationTitle(study.degree.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            confirming == .delete ? "¿Eliminar «\(study.degree.displayName)»?" : "¿Volver a «\(study.degree.displayName)»?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            switch action {
            case .resume: Button("Volver a este estudio") { library.resumeArchivedStudy(id: id) }
            case .delete: Button("Eliminar", role: .destructive) { library.deleteArchivedStudy(id: id) }
            }
        } message: { action in
            switch action {
            case .resume:
                if library.courses.contains(where: { !$0.subjects.isEmpty }) {
                    Text("«\(library.degree.displayName)» se archiva y puedes volver a él desde «Estudios».")
                } else {
                    Text("Tu estudio actual está vacío, así que no se archiva.")
                }
            case .delete: Text("Se borran sus \(subjectCount) asignaturas con sus notas. No se puede deshacer.")
            }
        }
    }
}
