import Engine
import SwiftUI

/// "Estudio actual", from the account tab: what you study and how it's divided, and archiving it.
/// With no current study (after archiving one) it's where a new one is created.
struct CurrentStudyView: View {
    @Environment(Library.self) private var library
    @State private var isArchiving = false

    private var degree: Binding<DegreeSettings> {
        Binding(get: { library.degree }, set: { library.updateDegree($0) })
    }

    var body: some View {
        Group {
            if library.hasStudy {
                current
            } else {
                NewStudyForm { library.startStudy($0) }
            }
        }
        .navigationTitle(library.hasStudy ? "Estudio actual" : "Nuevo estudio")
        .navigationBarTitleDisplayMode(.inline)
        // A solid bar, so the title reads as fixed while the rows scroll under it.
        .scrollEdgeEffectStyle(.hard, for: .top)
    }

    private var current: some View {
        let subjectCount = library.courses.reduce(0) { $0 + $1.subjects.count }
        return List {
            StudySettingsSections(degree: degree)

            Section {
                Button("Archivar", systemImage: "archivebox") { isArchiving = true }
                    .disabled(subjectCount == 0)
            } footer: {
                Text("Guarda este estudio con sus \(subjectCount) asignaturas y sus notas en «Archivo» para consultarlo o volver a él cuando quieras. Después puedes crear otro, por ejemplo al pasar del instituto a la universidad.")
            }
        }
        .confirmationDialog("¿Archivar «\(library.degree.displayName)»?", isPresented: $isArchiving, titleVisibility: .visible) {
            Button("Archivar") { library.archiveCurrentStudy() }
        } message: {
            Text("Sus asignaturas, notas, fechas, vistas y guías quedan guardadas en «Archivo». Te quedas sin estudio actual hasta que crees otro o vuelvas a uno archivado.")
        }
    }
}

/// The settings a study is made of — what it is and how it's divided — shared by the current
/// study's screen and the one that creates a new study.
struct StudySettingsSections: View {
    @Binding var degree: DegreeSettings

    private var studyType: Binding<StudyType> {
        Binding(get: { degree.studyType }, set: { degree = degree.switching(to: $0) })
    }

    private var termName: String {
        degree.termName.isEmpty ? DegreeSettings.defaultTermName : degree.termName
    }

    var body: some View {
        Section {
            Picker("Tipo", selection: studyType) {
                ForEach(StudyType.allCases) { type in
                    Label(type.label, systemImage: type.symbol).tag(type)
                }
            }
            InlineField("Nombre") {
                TextField(degree.studyType.label, text: $degree.name)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            InlineField("Centro") {
                TextField("Opcional", text: $degree.institution)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
        } footer: {
            Text("Por ahora Grade está pensada para la universidad. Al cambiar el tipo se ponen sus años y periodos habituales.")
        }

        Section {
            CountRow(title: "Años", value: $degree.years, range: 1...DegreeSettings.maxYears)
            InlineField("Nombre del año") {
                TextField(DegreeSettings.defaultYearName, text: $degree.yearName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            CountRow(title: "Periodos por año", value: $degree.termsPerYear, range: 1...DegreeSettings.maxTermsPerYear)
            InlineField("Nombre del periodo") {
                TextField(DegreeSettings.defaultTermName, text: $degree.termName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            Toggle("Créditos", isOn: $degree.usesCredits)
        } header: {
            Text("Organización")
        } footer: {
            Text("Se usa en los títulos, p. ej. «2º \(degree.displayYearName) · 1º \(termName)». Si cambias cuántos periodos hay por año, cada asignatura conserva su año y su posición dentro de él. Sin créditos, no se muestran y todas las asignaturas cuentan igual en la media.")
        }
    }
}

/// A count with the app's glass − and + buttons, like the year in a new subject.
private struct CountRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Text(value.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                StepButton(systemImage: "minus", label: "\(title): uno menos", isEnabled: value > range.lowerBound) { value -= 1 }
                StepButton(systemImage: "plus", label: "\(title): uno más", isEnabled: value < range.upperBound) { value += 1 }
            }
            .animation(.snappy, value: value)
        }
    }
}

/// Sets up a new study from scratch: its settings, then "Crear estudio".
struct NewStudyForm: View {
    let onCreate: (DegreeSettings) -> Void
    @State private var draft = DegreeSettings()

    var body: some View {
        List {
            StudySettingsSections(degree: $draft)
            Section {
                Button("Crear estudio", systemImage: "plus.circle") { onCreate(draft) }
            } footer: {
                Text("Todo esto se puede cambiar después en Cuenta → Estudio actual.")
            }
        }
    }
}

/// "Nuevo estudio" as a sheet, for when adding a subject finds there's no study yet.
struct NewStudySheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NewStudyForm { degree in
                library.startStudy(degree)
                dismiss()
            }
            .navigationTitle("Nuevo estudio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
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
                RecordStats(summary: RecordSummary(study.courses, degree: study.degree))
                NavigationLink {
                    RecordView(archived: study)
                } label: {
                    Label("Ver expediente", systemImage: "chart.bar.doc.horizontal")
                }
            }

            Section {
                Button("Volver a este estudio", systemImage: "arrow.uturn.backward") { confirming = .resume }
            } footer: {
                Text(library.hasStudy ? "Pasa a ser tu estudio actual, y el actual se archiva en su lugar." : "Pasa a ser tu estudio actual.")
            }

            Section {
                Button("Eliminar estudio", systemImage: "trash", role: .destructive) { confirming = .delete }
                    // In a list the icon takes the accent colour, not the destructive red.
                    .foregroundStyle(.red)
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
