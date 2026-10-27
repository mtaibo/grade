import Engine
import SwiftUI

/// Edits a subject's details and evaluation tree on a draft, committed only on "Guardar" — the
/// modular part of the app: any subject's structure can be reshaped to match its real syllabus.
struct SubjectEditorView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    /// Seeded once from the record being edited; the library only changes on save.
    @State private var draft: SubjectRecord
    /// Leaf renames made while editing (original name → current name), so stored grades follow.
    @State private var renames: [String: String] = [:]

    init(record: SubjectRecord) {
        _draft = State(initialValue: record)
    }

    private var duplicateLeafNames: [String] {
        let names = draft.subject.root.allLeafNames()
        return Array(Set(names.filter { name in names.count { $0 == name } > 1 })).sorted()
    }

    private var canSave: Bool {
        !draft.subject.name.trimmingCharacters(in: .whitespaces).isEmpty && duplicateLeafNames.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asignatura") {
                    TextField("Nombre", text: $draft.subject.name)
                    Stepper(value: $draft.subject.ectsCredits, in: 0...30, step: 0.5) {
                        LabeledContent("Créditos ECTS", value: draft.subject.ectsCredits.formatted())
                    }
                    Stepper(value: $draft.subject.root.passThreshold, in: 0...10, step: 0.5) {
                        LabeledContent("Nota para aprobar", value: draft.subject.root.passThreshold.formatted())
                    }
                }

                NodeContentsSections(node: $draft.subject.root, onRenameLeaf: recordRename)

                if !duplicateLeafNames.isEmpty {
                    Section {
                        Label(
                            "Hay notas con el mismo nombre (\(duplicateLeafNames.formatted(.list(type: .and)))). Cambia uno para poder guardar.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Editar asignatura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func recordRename(from old: String, to new: String) {
        if let original = renames.first(where: { $0.value == old })?.key {
            renames[original] = new
        } else {
            renames[old] = new
        }
    }

    /// Moves grades onto renamed leaves and drops grades for leaves that no longer exist.
    private func save() {
        var record = draft
        let leaves = Set(record.subject.root.allLeafNames())
        func migrated(_ entries: [String: GradeEntry]) -> [String: GradeEntry] {
            var moved: [String: GradeEntry] = [:]
            for (name, entry) in entries {
                moved[renames[name] ?? name] = entry
            }
            return moved.filter { leaves.contains($0.key) }
        }
        record.entries = migrated(record.entries)
        record.extraordinaryEntries = migrated(record.extraordinaryEntries)
        library.update(record)
        dismiss()
    }
}

/// The editable contents of one node — reused for the subject's root and, recursively, for any
/// group inside it.
private struct NodeContentsSections: View {
    @Binding var node: Node
    let onRenameLeaf: (String, String) -> Void

    var body: some View {
        if let group = Binding($node.asGroup) {
            GroupSections(group: group, onRenameLeaf: onRenameLeaf)
        } else if let formula = Binding($node.asFormula) {
            FormulaSections(formula: formula, onRenameLeaf: onRenameLeaf)
        } else if let grade = Binding($node.asGrade) {
            GradeSettingsSections(grade: grade)
        } else {
            Section {
                Text("Este tipo de componente todavía no se puede editar desde la app.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GroupSections: View {
    @Binding var group: Engine.Group
    let onRenameLeaf: (String, String) -> Void

    private var combinationKind: Binding<CombinationKind> {
        Binding(
            get: { group.combination.kind },
            set: { group.combination = Engine.Group.Combination(kind: $0, bestOf: group.combination.bestOfCount ?? 1) }
        )
    }

    private var totalWeight: Double { group.children.reduce(0) { $0 + $1.weight } }

    var body: some View {
        Section {
            Picker("Cómo se calcula", selection: combinationKind) {
                ForEach(CombinationKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            if let count = group.combination.bestOfCount {
                Stepper(value: Binding(get: { count }, set: { group.combination = .bestOf($0) }), in: 1...max(group.children.count, 1)) {
                    LabeledContent("Cuántas cuentan", value: count.formatted())
                }
            }
        } footer: {
            Text(group.combination.kind.explanation)
        }

        Section {
            ForEach($group.children) { $child in
                NavigationLink {
                    ComponentEditorView(child: $child, onRenameLeaf: onRenameLeaf)
                } label: {
                    ComponentRow(child: child)
                }
            }
            .onDelete { group.children.remove(atOffsets: $0) }

            Menu {
                Button("Una nota", systemImage: "number") { add(.grade(Grade(name: uniqueName("Nota nueva")))) }
                Menu("Varias notas", systemImage: "square.grid.3x2") {
                    ForEach([3, 4, 5, 6, 8, 10, 12], id: \.self) { count in
                        Button("\(count) notas") { addMany(count) }
                    }
                }
                Button("Grupo de notas", systemImage: "square.stack") {
                    add(.group(Engine.Group(name: uniqueName("Grupo nuevo"), combination: .weightedAverage, children: [])))
                }
            } label: {
                Label("Añadir parte", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Partes")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !group.children.isEmpty, group.combination == .weightedAverage {
                    if weightsAreOff {
                        Label("Los pesos suman \(totalPercent) %. Normalmente suman 100 %; si no, se reparten en proporción.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Los pesos suman 100 %.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Text(group.children.isEmpty
                     ? "Añade las partes que aparecen en la guía docente: exámenes, prácticas, trabajos…"
                     : "Toca una parte para cambiar su nombre, su peso o cómo se pone la nota. Desliza a la izquierda para borrarla.")
            }
        }
    }

    private var weightsAreOff: Bool { abs(totalWeight - 1) > 0.001 }

    private var totalPercent: String {
        (totalWeight * 100).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// A new part takes whatever weight is still unassigned, so adding one rarely leaves the
    /// weights summing to something other than 100 %.
    private func add(_ node: Node) {
        let remaining = group.combination == .weightedAverage ? max(0, 1 - totalWeight) : 0
        group.children.append(WeightedChild(weight: remaining, node: node))
    }

    /// "Prueba 1" … "Prueba N", weighted equally — the usual "media de las prácticas".
    private func addMany(_ count: Int) {
        let start = (1...).first { !Set(group.children.map(\.node.title)).contains("Prueba \($0)") } ?? 1
        for number in start..<(start + count) {
            group.children.append(WeightedChild(weight: 1 / Double(count), node: .grade(Grade(name: "Prueba \(number)"))))
        }
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(group.children.map(\.node.title))
        guard taken.contains(base) else { return base }
        return (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) }!
    }
}

private struct FormulaSections: View {
    @Binding var formula: Formula
    let onRenameLeaf: (String, String) -> Void

    var body: some View {
        Section {
            Text(formula.expression.display)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        } header: {
            Text("Fórmula")
        } footer: {
            Text("Esta asignatura se calcula con una fórmula de su guía docente. Por ahora puedes editar sus variables, no la fórmula.")
        }

        Section("Variables") {
            ForEach(formula.variables.keys.sorted(), id: \.self) { key in
                let variable = Binding(
                    get: { formula.variables[key] ?? .grade(Grade(name: key)) },
                    set: { formula.variables[key] = $0 }
                )
                NavigationLink {
                    LeafEditorView(node: variable, onRenameLeaf: onRenameLeaf)
                        .navigationTitle(key)
                } label: {
                    LabeledContent {
                        Text("sobre \(variable.wrappedValue.scaleMax.formatted())")
                    } label: {
                        Text("\(Text(key).bold())  \(variable.wrappedValue.title)")
                    }
                }
            }
        }
    }
}

/// One part of a group: its name and weight, plus either its scale (a grade) or its own parts
/// (a nested group).
private struct ComponentEditorView: View {
    @Binding var child: WeightedChild
    let onRenameLeaf: (String, String) -> Void

    var body: some View {
        Form {
            Section {
                NameField(node: $child.node, onRenameLeaf: onRenameLeaf)
                LabeledContent("Peso") {
                    HStack(spacing: 4) {
                        TextField("0", value: Binding(get: { child.weight * 100 }, set: { child.weight = $0 / 100 }), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            }

            if child.node.asGrade != nil || child.node.isGroupOfGrades {
                NoteCountSection(node: $child.node)
            }

            if child.node.asGroup != nil {
                NodeContentsSections(node: $child.node, onRenameLeaf: onRenameLeaf)
            } else if let grade = Binding($child.node.asGrade) {
                GradeSettingsSections(grade: grade)
            }
        }
        .navigationTitle(child.node.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// How many notes make up a part: one, or several averaged (two lab practicals, ten quizzes…).
/// Changing it reshapes the part in place instead of deleting and re-creating it.
private struct NoteCountSection: View {
    @Binding var node: Node

    var body: some View {
        let count = node.noteCount
        Section {
            Stepper(value: Binding(get: { node.noteCount }, set: { node.resizeNotes(to: $0) }), in: 1...20) {
                LabeledContent("Cuántas notas", value: count.formatted())
            }
        } footer: {
            Text(count == 1
                 ? "Una sola nota. Súbelo si en clase hay varias (por ejemplo, dos prácticas): la parte será su media. La nota ya puesta de esta parte se borra."
                 : "La parte se calcula con estas \(count) notas. Más abajo puedes cambiar el nombre y el peso de cada una.")
        }
    }
}

/// A formula variable: renameable, with its own scale.
private struct LeafEditorView: View {
    @Binding var node: Node
    let onRenameLeaf: (String, String) -> Void

    var body: some View {
        Form {
            Section {
                NameField(node: $node, onRenameLeaf: onRenameLeaf)
            }
            if let grade = Binding($node.asGrade) {
                GradeSettingsSections(grade: grade)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NameField: View {
    @Binding var node: Node
    let onRenameLeaf: (String, String) -> Void

    var body: some View {
        TextField("Nombre", text: Binding(
            get: { node.title },
            set: { newName in
                let oldName = node.title
                node.title = newName
                if node.isLeaf { onRenameLeaf(oldName, newName) }
            }
        ))
    }
}

/// An optional due date: off by default, and when switched on it starts at today 23:59 — the
/// usual deadline for a hand-in.
private struct DateFields: View {
    @Binding var date: Date?

    var body: some View {
        Toggle("Fecha de entrega o examen", isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? Self.defaultDate : nil }
        ))
        if let date = Binding($date) {
            DatePicker("Fecha", selection: date, displayedComponents: [.date, .hourAndMinute])
        }
    }

    private static var defaultDate: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
    }
}

/// Everything about one grade: how the teacher gives it, whether it survives to the extraordinary
/// sitting, and its due date.
private struct GradeSettingsSections: View {
    @Binding var grade: Grade

    private static let defaultLetters = [
        LetterGrade(letter: "A", value: 10),
        LetterGrade(letter: "B", value: 7.5),
        LetterGrade(letter: "C", value: 5),
        LetterGrade(letter: "D", value: 2.5),
        LetterGrade(letter: "E", value: 0),
    ]

    private var style: Binding<InputStyleKind> {
        Binding(
            get: {
                switch grade.inputStyle ?? .points {
                case .points: .points
                case .percent: .percent
                case .letters: .letters
                }
            },
            set: { kind in
                switch kind {
                case .points: grade.inputStyle = nil
                case .percent: grade.inputStyle = .percent
                case .letters:
                    if case .letters = grade.inputStyle { return }
                    grade.inputStyle = .letters(Self.defaultLetters)
                }
            }
        )
    }

    private var letters: Binding<[LetterGrade]> {
        Binding(
            get: { if case .letters(let scale) = grade.inputStyle { scale } else { [] } },
            set: { grade.inputStyle = .letters($0) }
        )
    }

    private var keepsForExtraordinary: Binding<Bool> {
        Binding(
            get: {
                switch grade.recovery {
                case .notRecoverable, .savedForExtraordinary, .savedForNextYear, .partiallyRecoverableInFinal: true
                case .recoverableInExtraordinary, nil: false
                }
            },
            set: { keeps in
                if keeps, !keepsForExtraordinary.wrappedValue { grade.recovery = .savedForExtraordinary }
                if !keeps { grade.recovery = nil }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Cómo te la dan", selection: style) {
                ForEach(InputStyleKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            ScaleField(scaleMax: $grade.scaleMax)
        } header: {
            Text("Cómo te dan la nota")
        } footer: {
            Text("Elige cómo la escribirás: en puntos (puedes cambiar sobre cuánto al ponerla), en porcentaje o con letras.")
        }

        if case .letters = grade.inputStyle {
            Section {
                ForEach(letters) { $letter in
                    HStack {
                        TextField("Letra", text: $letter.letter)
                            .font(.headline)
                        Spacer()
                        TextField("0", value: $letter.value, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("/ 10").foregroundStyle(.secondary)
                    }
                }
                .onDelete { letters.wrappedValue.remove(atOffsets: $0) }
                Button("Añadir letra", systemImage: "plus") {
                    letters.wrappedValue.append(LetterGrade(letter: "", value: 0))
                }
            } header: {
                Text("Equivalencia de las letras")
            } footer: {
                Text("Lo que vale cada letra, sobre 10.")
            }
        }

        Section {
            Toggle("Es el examen final", isOn: Binding(
                get: { grade.isFinalExam == true },
                set: { grade.isFinalExam = $0 ? true : nil }
            ))
        } footer: {
            Text("Va en su propia tarjeta, con huecos para la ordinaria y la extraordinaria.")
        }

        Section {
            Toggle("Se guarda para la extraordinaria", isOn: keepsForExtraordinary)
        } footer: {
            Text("Si está activado, en la extraordinaria aparece ya puesta con la nota de la ordinaria (y puedes cambiarla). Si no, se repite y empieza vacía, como un examen.")
        }

        Section {
            DateFields(date: $grade.date)
        } footer: {
            Text("Si tiene fecha, aparece en el Calendario.")
        }
    }
}

private enum InputStyleKind: String, CaseIterable, Identifiable {
    case points, percent, letters

    var id: Self { self }

    var label: String {
        switch self {
        case .points: "Puntos"
        case .percent: "Porcentaje"
        case .letters: "Letras"
        }
    }
}

private struct ScaleField: View {
    @Binding var scaleMax: Double

    var body: some View {
        LabeledContent("Nota máxima") {
            TextField("10", value: $scaleMax, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ComponentRow: View {
    let child: WeightedChild

    var body: some View {
        LabeledContent {
            Text("\((child.weight * 100).formatted(.number.precision(.fractionLength(0...1)))) %")
                .monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(child.node.title)
                Text(child.node.kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
