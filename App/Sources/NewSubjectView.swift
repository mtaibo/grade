import SwiftUI

/// What the sheet does: make a subject in a period, or move an existing one to another.
enum SubjectPlacement: Identifiable {
    case create(Period)
    case move(SubjectRecord.ID, name: String, from: Period)

    var id: String {
        switch self {
        case .create: "create"
        case .move(let id, _, _): id.uuidString
        }
    }
}

/// A small form: name (when creating) plus the year and term the subject belongs to.
struct NewSubjectView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let placement: SubjectPlacement
    /// Called with the subject's new period once saved, so the home screen can follow it.
    /// Where the subject ended up, and its id (the new one when creating).
    var onSaved: (Period, SubjectRecord.ID) -> Void = { _, _ in }

    @State private var name = ""
    @State private var year: Int
    /// Position within the year (1 or 2); `nil` means the subject lasts the whole year.
    @State private var relativeTerm: Int?
    @FocusState private var nameFocused: Bool

    init(placement: SubjectPlacement, degree: DegreeSettings, onSaved: @escaping (Period, SubjectRecord.ID) -> Void = { _, _ in }) {
        self.placement = placement
        self.onSaved = onSaved
        let period: Period = switch placement {
        case .create(let period): period
        case .move(_, _, let period): period
        }
        _year = State(initialValue: period.year)
        _relativeTerm = State(initialValue: period.term.map(degree.relativeTerm))
    }

    private var degree: DegreeSettings { library.degree }

    private var isCreating: Bool {
        if case .create = placement { true } else { false }
    }

    private var canSave: Bool {
        !isCreating || !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCreating {
                    Section {
                        TextField("Nombre de la asignatura", text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                    }
                }

                Section {
                    Stepper(value: $year, in: 1...max(degree.years, year)) {
                        LabeledContent("Año", value: Period(year: year).title)
                    }
                    Picker(degree.termName.isEmpty ? "Cuatrimestre" : degree.termName, selection: $relativeTerm) {
                        Text("Todo el año").tag(Int?.none)
                        ForEach(1...max(degree.termsPerYear, 1), id: \.self) { n in
                            Text(degree.termLabel(degree.absoluteTerm(year: year, relative: n))).tag(Int?.some(n))
                        }
                    }
                } footer: {
                    Text("Si la asignatura dura todo el año, elige «Todo el año»: aparecerá en todos sus periodos.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Añadir" : "Mover", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear { nameFocused = isCreating }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch placement {
        case .create: "Nueva asignatura"
        case .move(_, let name, _): name
        }
    }

    private func save() {
        let term = relativeTerm.map { degree.absoluteTerm(year: year, relative: $0) }
        let id: SubjectRecord.ID
        switch placement {
        case .create:
            id = library.addSubject(
                name: name.trimmingCharacters(in: .whitespaces),
                year: year,
                term: term
            )
        case .move(let moved, _, _):
            id = moved
            library.move(moved, toYear: year, term: term)
        }
        onSaved(Period(year: year, term: term), id)
        dismiss()
    }
}
