import Engine
import SwiftUI

/// A home-screen view made by hand: any subjects, from any year or term, shown together. For when
/// the degree's own split doesn't match someone's real semester — a repeated subject, one brought
/// forward from a later year, one validated.
struct CustomSelection: Identifiable, Codable, Equatable {
    /// What the home screen shows as the big title.
    enum Title: Codable, Equatable, Hashable {
        /// The year and term of the subject furthest along in the degree.
        case automatic
        /// A year and term picked by hand (`term` nil for "Todo el año").
        case period(year: Int, term: Int?)
        /// Free text.
        case name(String)
    }

    var id = UUID()
    var title: Title = .automatic
    /// In the order the home screen shows them.
    var subjectIDs: [SubjectRecord.ID] = []
}

extension Library {
    /// The big title and the line under it for a custom view, as the home screen shows them.
    func heading(for selection: CustomSelection) -> (title: String, subtitle: String?) {
        switch selection.title {
        case .name(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return (trimmed.isEmpty ? "Mi vista" : trimmed, nil)
        case .period(let year, let term):
            let period = Period(year: year, term: term)
            return (period.title, period.subtitle(in: degree))
        case .automatic:
            guard let period = furthestPeriod(of: selection.subjectIDs) else { return ("Mi vista", nil) }
            return (period.title, period.subtitle(in: degree))
        }
    }

    /// The latest year and term among these subjects; a year-long one counts as its year's last.
    func furthestPeriod(of ids: [SubjectRecord.ID]) -> Period? {
        ids.compactMap(period(of:)).max { lhs, rhs in
            (lhs.year, lhs.term ?? .max) < (rhs.year, rhs.term ?? .max)
        }
    }
}

// MARK: - "Vista"

/// Where the home screen's view is chosen: one of the degree's periods, or a custom view. Reached
/// from the home screen's "…" menu.
struct HomeViewsScreen: View {
    let periods: [Period]
    let current: HomeSelection
    let onSelect: (HomeSelection) -> Void

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CustomSelection?

    var body: some View {
        Form {
            ForEach(Dictionary(grouping: periods, by: \.year).sorted { $0.key < $1.key }, id: \.key) { year, options in
                Section(Period(year: year).title) {
                    ForEach(options, id: \.self) { option in
                        SelectableRow(
                            title: option.term.map(library.degree.termLabel) ?? "Todo el año",
                            detail: count(in: option),
                            isSelected: current == .period(option)
                        ) {
                            choose(.period(option))
                        }
                    }
                }
            }

            Section {
                ForEach(library.selections) { selection in
                    let heading = library.heading(for: selection)
                    HStack {
                        SelectableRow(
                            title: [heading.title, heading.subtitle].compactMap { $0 }.joined(separator: " · "),
                            detail: subjectsLabel(selection.subjectIDs.count),
                            isSelected: current == .custom(selection.id)
                        ) {
                            choose(.custom(selection.id))
                        }
                        Button("Editar", systemImage: "info.circle") { editing = selection }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { library.deleteSelection(id: library.selections[index].id) }
                }
                Button {
                    editing = CustomSelection()
                } label: {
                    Label("Nueva vista", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
            } header: {
                Text("Personalizadas")
            } footer: {
                Text("Junta las asignaturas que llevas de verdad este cuatrimestre, sean del año que sean: una que repites, una adelantada o una convalidada.")
            }
        }
        .navigationTitle("Vistas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { selection in
            CustomSelectionEditor(selection: selection, isNew: !library.selections.contains { $0.id == selection.id }) { saved in
                choose(.custom(saved.id))
            }
        }
    }

    private func choose(_ selection: HomeSelection) {
        onSelect(selection)
        dismiss()
    }

    private func count(in period: Period) -> String {
        let count = library.courses.first { $0.year == period.year }?.subjects.count { $0.term == period.term } ?? 0
        return subjectsLabel(count)
    }

    private func subjectsLabel(_ count: Int) -> String {
        count == 1 ? "1 asignatura" : "\(count) asignaturas"
    }
}

/// What the home screen shows: one of the degree's periods or a custom view.
enum HomeSelection: Hashable {
    case period(Period)
    case custom(CustomSelection.ID)
}

/// A row that picks something: its name, a short count under it and a ✓ when it's the current one.
private struct SelectableRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Editor

/// Creates or edits a custom view: what it's called on the home screen and which subjects it holds.
struct CustomSelectionEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CustomSelection
    let isNew: Bool
    let onSaved: (CustomSelection) -> Void

    init(selection: CustomSelection, isNew: Bool, onSaved: @escaping (CustomSelection) -> Void) {
        _draft = State(initialValue: selection)
        self.isNew = isNew
        self.onSaved = onSaved
    }

    private enum TitleMode: Hashable, CaseIterable {
        case automatic, period, name

        var label: String {
            switch self {
            case .automatic: "Automático"
            case .period: "Periodo"
            case .name: "Nombre"
            }
        }
    }

    private var mode: Binding<TitleMode> {
        Binding(
            get: {
                switch draft.title {
                case .automatic: .automatic
                case .period: .period
                case .name: .name
                }
            },
            set: { mode in
                switch mode {
                case .automatic: draft.title = .automatic
                case .period:
                    let start = library.furthestPeriod(of: draft.subjectIDs) ?? Period(year: 1, term: 1)
                    draft.title = .period(year: start.year, term: start.term)
                case .name: draft.title = .name("")
                }
            }
        )
    }

    private var year: Binding<Int> {
        Binding(
            get: { if case .period(let year, _) = draft.title { year } else { 1 } },
            set: { newYear in
                guard case .period(_, let term) = draft.title else { return }
                // Keeps the term's position within the year: 1st of year 2 → 1st of year 3.
                let relative = term.map(library.degree.relativeTerm)
                draft.title = .period(year: newYear, term: relative.map { library.degree.absoluteTerm(year: newYear, relative: $0) })
            }
        )
    }

    private var term: Binding<Int?> {
        Binding(
            get: { if case .period(_, let term) = draft.title { term } else { nil } },
            set: { newTerm in
                guard case .period(let year, _) = draft.title else { return }
                draft.title = .period(year: year, term: newTerm)
            }
        )
    }

    private var name: Binding<String> {
        Binding(
            get: { if case .name(let name) = draft.title { name } else { "" } },
            set: { draft.title = .name($0) }
        )
    }

    /// Every period that has subjects, with them, oldest first.
    private var groups: [(period: Period, subjects: [SubjectRecord])] {
        library.courses.flatMap { course in
            Dictionary(grouping: course.subjects, by: \.term)
                .map { (Period(year: course.year, term: $0.key), $0.value) }
        }
        .sorted { ($0.period.year, $0.period.term ?? .max) < ($1.period.year, $1.period.term ?? .max) }
    }

    /// "Cuatrimestre", or whatever the degree calls its terms.
    private var termName: String {
        let name = library.degree.termName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? DegreeSettings.defaultTermName : name
    }

    private var preview: String {
        let heading = library.heading(for: draft)
        return [heading.title, heading.subtitle].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Título", selection: mode) {
                        ForEach(TitleMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    switch mode.wrappedValue {
                    case .automatic:
                        LabeledContent("Se verá", value: preview)
                    case .period:
                        Picker("Año", selection: year) {
                            ForEach(1...library.degree.years, id: \.self) { year in
                                Text(Period(year: year).title).tag(year)
                            }
                        }
                        Picker(termName, selection: term) {
                            ForEach(1...library.degree.termsPerYear, id: \.self) { relative in
                                let absolute = library.degree.absoluteTerm(year: year.wrappedValue, relative: relative)
                                Text(library.degree.termLabel(absolute)).tag(Int?.some(absolute))
                            }
                            Text("Todo el año").tag(Int?.none)
                        }
                    case .name:
                        InlineField("Nombre") {
                            TextField("Mi vista", text: name)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Título en la pantalla principal")
                } footer: {
                    switch mode.wrappedValue {
                    case .automatic: Text("El año y el cuatrimestre de la asignatura más avanzada de las que elijas.")
                    case .period: Text("Cualquiera, aunque no coincida con el de las asignaturas: por ejemplo, el curso en el que estás aunque arrastres alguna de antes.")
                    case .name: Text("Lo que quieras que ponga arriba.")
                    }
                }

                ForEach(groups, id: \.period) { group in
                    Section {
                        ForEach(group.subjects) { record in
                            SubjectToggleRow(record: record, isOn: draft.subjectIDs.contains(record.id)) {
                                toggle(record.id)
                            }
                        }
                    } header: {
                        Text([group.period.title, group.period.subtitle(in: library.degree) ?? "Todo el año"].joined(separator: " · "))
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            library.deleteSelection(id: draft.id)
                            dismiss()
                        } label: {
                            Label("Eliminar vista", systemImage: "trash")
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                    }
                }
            }
            .dismissesKeyboardOnBackgroundTap()
            .navigationTitle(isNew ? "Nueva vista" : "Editar vista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        library.saveSelection(draft)
                        onSaved(draft)
                        dismiss()
                    }
                    .tint(.blue)
                    .disabled(draft.subjectIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: SubjectRecord.ID) {
        if let index = draft.subjectIDs.firstIndex(of: id) {
            draft.subjectIDs.remove(at: index)
        } else {
            draft.subjectIDs.append(id)
        }
    }
}

/// A subject with its icon and a ✓ when it's in the view.
private struct SubjectToggleRow: View {
    let record: SubjectRecord
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        let style = SubjectStyle(record)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: style.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(style.tint.gradient, in: .rect(cornerRadius: 7))
                Text(record.subject.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
