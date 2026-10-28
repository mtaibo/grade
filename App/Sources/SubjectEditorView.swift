import Engine
import SwiftUI

/// Edits a subject's details and evaluation tree on a draft, committed only on the checkmark — the
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
                Section {
                    LabeledContent("Nombre") {
                        TextField("Nombre", text: $draft.subject.name)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Nombre de la asignatura. Toca para cambiarlo.")
                }

                NodeContentsSections(node: $draft.subject.root, isRoot: true, onRenameLeaf: recordRename)

                if !duplicateLeafNames.isEmpty {
                    Section {
                        Label(
                            "Hay notas con el mismo nombre (\(duplicateLeafNames.formatted(.list(type: .and)))). Cambia uno para poder guardar.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    NavigationLink {
                        AdvancedSubjectView(subject: $draft.subject)
                    } label: {
                        Label("Avanzado", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Opciones extra para personalizar la asignatura.")
                }
            }
            .navigationTitle("Editar asignatura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save)
                        .tint(.blue)
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
        record.subject.root.sanitize()
        record.subject.name = record.subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.moveExamGradeDates()
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

/// What rarely changes once a subject is set up: its credits and the grade it takes to pass.
private struct AdvancedSubjectView: View {
    @Binding var subject: Subject

    var body: some View {
        Form {
            Section {
                Stepper(value: $subject.ectsCredits, in: 0...30, step: 0.5) {
                    LabeledContent("Créditos ECTS", value: subject.ectsCredits.formatted())
                }
            } footer: {
                Text("Insertar texto")
            }
            Section {
                Stepper(value: $subject.root.passThreshold, in: 0...10, step: 0.5) {
                    LabeledContent("Nota para aprobar", value: subject.root.passThreshold.formatted())
                }
            } footer: {
                Text("Insertar texto")
            }
        }
        .navigationTitle("Avanzado")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The editable contents of one node — reused for the subject's root and, recursively, for any
/// group inside it.
private struct NodeContentsSections: View {
    @Binding var node: Node
    var isRoot = false
    let onRenameLeaf: (String, String) -> Void

    var body: some View {
        if node.asGroup != nil || node.asFormula != nil {
            CalculationSection(node: $node, allowsFormula: isRoot)
        }
        if let group = Binding(unwrapping: $node.asGroup) {
            GroupSections(group: group, isRoot: isRoot, onRenameLeaf: onRenameLeaf)
        } else if let formula = Binding(unwrapping: $node.asFormula) {
            FormulaSections(formula: formula, onRenameLeaf: onRenameLeaf)
        } else if let grade = Binding(unwrapping: $node.asGrade) {
            GradeSettingsSections(grade: grade)
        } else {
            Section {
                Text("Este tipo de componente todavía no se puede editar desde la app.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "Cómo se calcula": a weighted average, a hand-written formula or a sum of points. Switching
/// reshapes the node in place — the same parts become variables or sections — so nothing typed is
/// lost; cancelling the editor undoes it.
private struct CalculationSection: View {
    @Binding var node: Node
    /// Only the subject's own result can be a formula; a group inside it stays a group.
    let allowsFormula: Bool

    private enum Method: Hashable {
        case group(CombinationKind)
        case formula

        var label: String {
            switch self {
            case .group(let kind): kind.label
            case .formula: "Fórmula"
            }
        }
    }

    private var current: Method {
        if node.asFormula != nil { return .formula }
        return .group(node.asGroup?.combination.kind ?? .weightedAverage)
    }

    /// The three methods offered for now, plus whatever an existing subject already uses (the best,
    /// the worst…) so editing it doesn't silently change it.
    private var methods: [Method] {
        var methods: [Method] = [.group(.weightedAverage)]
        if allowsFormula { methods.append(.formula) }
        methods.append(.group(.sum))
        if !methods.contains(current) { methods.append(current) }
        return methods
    }

    private var selection: Binding<Method> {
        Binding(get: { current }, set: apply)
    }

    var body: some View {
        Section {
            Picker("Evaluación", selection: selection) {
                ForEach(methods, id: \.self) { method in
                    Text(method.label).tag(method)
                }
            }
            if let group = node.asGroup, let count = group.combination.bestOfCount {
                Stepper(
                    value: Binding(get: { count }, set: { node.asGroup?.combination = .bestOf($0) }),
                    in: 1...max(group.children.count, 1)
                ) {
                    LabeledContent("Cuántas cuentan", value: count.formatted())
                }
            }
        } footer: {
            Text("Tipo de evaluación de la asignatura: cómo se juntan sus notas en la final.")
        }
    }

    private func apply(_ method: Method) {
        guard method != current else { return }
        switch (node, method) {
        case (.formula(let formula), .group(let kind)):
            node = .group(formula.asGroup(kind: kind))
        case (.group(var group), .group(let kind)):
            group.combination = Engine.Group.Combination(kind: kind, bestOf: group.combination.bestOfCount ?? 1)
            node = .group(group)
        case (.group(var group), .formula):
            // A formula can only spell out fixed weights; anything else starts from equal ones.
            if group.combination != .weightedAverage, group.combination != .sum { group.combination = .weightedAverage }
            if group.children.reduce(0, { $0 + $1.weight }) <= 0 {
                for index in group.children.indices { group.children[index].weight = 1 / Double(group.children.count) }
            }
            node = .formula(group.asFormula()
                ?? Formula(name: group.name, expression: .constant(0), variables: [:], minimum: group.minimum))
        default:
            break
        }
    }
}

/// A section title with a green ✓ on its right edge when what's inside adds up, a red ✗ when it
/// doesn't, and nothing when there's nothing to check.
private struct CheckedHeader: View {
    let title: String
    let isValid: Bool?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let isValid {
                SwiftUI.Group {
                    if isValid {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                    }
                }
                .accessibilityLabel(isValid ? "Todo cuadra" : "Hay un error")
            }
        }
    }
}

/// Under a checked section: what's off when it doesn't add up, what the section is for otherwise.
private struct CheckFooter: View {
    let problem: String?
    let hint: String

    var body: some View {
        if let problem {
            Text(problem).foregroundStyle(.red)
        } else {
            Text(hint)
        }
    }
}

private struct GroupSections: View {
    @Binding var group: Engine.Group
    var isRoot = false
    let onRenameLeaf: (String, String) -> Void

    private var totalWeight: Double { group.children.reduce(0) { $0 + $1.weight } }

    /// A weighted average should share out exactly 100 %, and the subject's own sum exactly its 10
    /// points. A sum inside another part can add up to anything: its parent scales it.
    /// `nil` when there's nothing to check, `.some(nil)` when it adds up, else what's off.
    private var check: String?? {
        guard !group.children.isEmpty else { return nil }
        let isOff = abs(totalWeight - 1) > 0.001
        switch group.combination {
        case .weightedAverage:
            return .some(isOff ? "Los porcentajes suman \(formatted(totalWeight * 100))\u{00A0}%; deberían sumar 100\u{00A0}%." : nil)
        case .sum where isRoot:
            return .some(isOff ? "Los puntos suman \(formatted(totalWeight * 10)); deberían sumar 10." : nil)
        default:
            return nil
        }
    }

    var body: some View {
        Section {
            ForEach($group.children) { $child in
                NavigationLink {
                    ComponentEditorView(child: $child, combination: group.combination, onRenameLeaf: onRenameLeaf)
                } label: {
                    ComponentRow(title: child.node.title, subtitle: child.node.kindLabel, value: share(of: child))
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
                Label("Añadir sección", systemImage: "plus.circle.fill")
            }
        } header: {
            CheckedHeader(title: "Secciones", isValid: check.map { $0 == nil })
        } footer: {
            CheckFooter(problem: check ?? nil, hint: "Personaliza las secciones en las que se divide la nota final.")
        }
    }

    /// What a section counts for, in the group's own terms: its percentage or its points.
    private func share(of child: WeightedChild) -> String {
        switch group.combination {
        case .sum:
            let points = child.weight * 10
            return "\(formatted(points)) \(abs(points - 1) < 1e-9 ? "pt" : "pts")"
        case .weightedAverage:
            return "\(formatted(child.weight * 100))\u{00A0}%"
        case .max, .min, .bestOf:
            return ""
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// A new part takes whatever weight (or points) is still unassigned, so adding one rarely
    /// leaves the total off.
    private func add(_ node: Node) {
        let fills = group.combination == .weightedAverage || group.combination == .sum
        group.children.append(WeightedChild(weight: fills ? max(0, 1 - totalWeight) : 0, node: node))
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

    @State private var text = ""
    @State private var parseError: String?

    private var orderedKeys: [String] {
        let used = formula.expression.variableOrder.filter { formula.variables[$0] != nil }
        return used + formula.variables.keys.sorted().filter { !used.contains($0) }
    }

    /// The formula reads, and no mix of grades takes the result below 0 or above 10.
    /// What's off, or `nil` when it's fine.
    private var problem: String? {
        if parseError != nil { return "La fórmula tiene un error." }
        let range = formula.resultRange
        guard range.lowerBound < -0.001 || range.upperBound > 10.001 else { return nil }
        return "La fórmula puede dar de \(formatted(range.lowerBound)) a \(formatted(range.upperBound)); debería quedarse entre 0 y 10."
    }

    var body: some View {
        Section {
            TextField("Fórmula", text: $text, axis: .vertical)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text) { apply() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedKeys, id: \.self) { key in
                        InsertChip(label: key, bold: true) { text += key }
                    }
                    ForEach(["+", "-", "*", "/", "(", ")", ";", ">="], id: \.self) { token in
                        InsertChip(label: token) { text += " \(token) " }
                    }
                    ForEach(["min(", "max(", "si("], id: \.self) { token in
                        InsertChip(label: token) { text += token }
                    }
                }
            }
            if let parseError {
                Label(parseError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Fórmula")
        } footer: {
            Text("Insertar texto")
        }
        .onAppear { text = formula.expression.source }

        Section {
            ForEach(orderedKeys, id: \.self) { key in
                NavigationLink {
                    FormulaVariableEditor(key: key, formula: $formula, onRenameKey: renameKey, onRenameLeaf: onRenameLeaf)
                } label: {
                    ComponentRow(
                        title: "\(key) · \(formula.variables[key]?.title ?? key)",
                        subtitle: formula.variables[key]?.kindLabel ?? "",
                        value: share(of: key)
                    )
                }
                .deleteDisabled(formula.expression.variableOrder.contains(key))
            }
            .onDelete { offsets in
                for key in offsets.map({ orderedKeys[$0] }) where !formula.expression.variableOrder.contains(key) {
                    formula.variables[key] = nil
                }
            }
            Button("Añadir variable", systemImage: "plus.circle.fill", action: addVariable)
        } header: {
            CheckedHeader(title: "Variables", isValid: problem == nil)
        } footer: {
            CheckFooter(problem: problem, hint: "Personaliza las variables con las que se calcula la nota final.")
        }
    }

    /// How much of the final grade a variable can account for, estimated from the formula: one
    /// percentage for a fixed weight, a range when its weight moves with other grades.
    private func share(of key: String) -> String {
        let range = formula.contributionRange(of: key)
        let low = max(0, range.lowerBound) * 10, high = max(0, range.upperBound) * 10
        return high - low < 0.5 ? "\(formatted(high))\u{00A0}%" : "\(formatted(low))–\(formatted(high))\u{00A0}%"
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Applies the text as the formula as soon as it reads; until it does, the last good one stays.
    private func apply() {
        do {
            formula.expression = try Engine.Expression.parse(text, variables: Set(formula.variables.keys))
            parseError = nil
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func renameKey(_ old: String, _ new: String) {
        guard old != new, let variable = formula.variables[old] else { return }
        formula.variables[old] = nil
        formula.variables[new] = variable
        formula.expression = formula.expression.renamingVariable(old, to: new)
        text = formula.expression.source
    }

    private func addVariable() {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        let key = letters.first { formula.variables[$0] == nil } ?? "V\(formula.variables.count + 1)"
        let taken = Set(formula.variables.values.map(\.title))
        let name = taken.contains("Nota nueva") ? ((2...).lazy.map { "Nota nueva \($0)" }.first { !taken.contains($0) }!) : "Nota nueva"
        formula.variables[key] = .grade(Grade(name: name))
    }
}

private struct InsertChip: View {
    let label: String
    var bold = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.monospaced().weight(bold ? .bold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// One variable of a formula: its letter, its name and everything about how its grade is given.
private struct FormulaVariableEditor: View {
    let key: String
    @Binding var formula: Formula
    let onRenameKey: (String, String) -> Void
    let onRenameLeaf: (String, String) -> Void

    @State private var keyText: String
    @State private var keyError: String?

    init(key: String, formula: Binding<Formula>, onRenameKey: @escaping (String, String) -> Void, onRenameLeaf: @escaping (String, String) -> Void) {
        self.key = key
        _formula = formula
        self.onRenameKey = onRenameKey
        self.onRenameLeaf = onRenameLeaf
        _keyText = State(initialValue: key)
    }

    private var node: Binding<Node> {
        Binding(
            get: { formula.variables[key] ?? .grade(Grade(name: key)) },
            set: { formula.variables[key] = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Variable") {
                    TextField("Letra", text: $keyText)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospaced().bold())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                NameField(node: node, onRenameLeaf: onRenameLeaf)
            } footer: {
                if let keyError {
                    Label(keyError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Text("La letra es como se llama en la fórmula.")
                }
            }

            if node.wrappedValue.asGrade != nil || node.wrappedValue.isGroupOfGrades {
                NoteCountSection(node: node)
            }
            if node.wrappedValue.asGroup != nil {
                NodeContentsSections(node: node, onRenameLeaf: onRenameLeaf)
            } else if let grade = Binding(unwrapping: node.asGrade) {
                GradeSettingsSections(grade: grade)
            }
        }
        .navigationTitle(key)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: keyText) { keyError = validation(keyText) }
        .onDisappear {
            let trimmed = keyText.trimmingCharacters(in: .whitespaces)
            if validation(trimmed) == nil { onRenameKey(key, trimmed) }
        }
    }

    /// A letter or short name that the formula can read: starts with a letter, no spaces, not
    /// another variable and not a function name. `nil` when it's fine (or unchanged).
    private func validation(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if name == key { return nil }
        guard let first = name.first, first.isLetter, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return "Usa letras y números, empezando por una letra."
        }
        if ["min", "max", "mín", "máx", "si", "if"].contains(name.lowercased()) { return "«\(name)» es una función de la fórmula." }
        if formula.variables[name] != nil { return "Ya hay una variable «\(name)»." }
        return nil
    }
}

/// One part of a group: its name and weight, plus either its scale (a grade) or its own parts
/// (a nested group).
private struct ComponentEditorView: View {
    @Binding var child: WeightedChild
    /// How the parent combines its parts: a sum counts each in points, anything else in percent.
    let combination: Engine.Group.Combination
    let onRenameLeaf: (String, String) -> Void

    private var isPoints: Bool { combination == .sum }

    var body: some View {
        Form {
            Section {
                NameField(node: $child.node, onRenameLeaf: onRenameLeaf)
                LabeledContent(isPoints ? "Puntos" : "Peso") {
                    HStack(spacing: 4) {
                        TextField("0", value: Binding(
                            get: { child.weight * (isPoints ? 10 : 100) },
                            set: { child.weight = $0 / (isPoints ? 10 : 100) }
                        ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(isPoints ? "pts" : "%").foregroundStyle(.secondary)
                    }
                }
            }

            if child.node.asGrade != nil || child.node.isGroupOfGrades {
                NoteCountSection(node: $child.node)
            }

            if child.node.asGroup != nil {
                NodeContentsSections(node: $child.node, onRenameLeaf: onRenameLeaf)
            } else if let grade = Binding(unwrapping: $child.node.asGrade) {
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
        if let date = Binding(unwrapping: $date) {
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

    private var isKeptForExtraordinary: Bool {
        switch grade.recovery {
        case .notRecoverable, .savedForExtraordinary, .savedForNextYear, .partiallyRecoverableInFinal: true
        case .recoverableInExtraordinary, nil: false
        }
    }

    private var keepsForExtraordinary: Binding<Bool> {
        Binding(
            get: { isKeptForExtraordinary },
            set: { keeps in
                if keeps, !isKeptForExtraordinary { grade.recovery = .savedForExtraordinary }
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
            Picker("Tipo", selection: $grade.category) {
                Text("Automático (\(grade.kind.singular))").tag(GradeCategory?.none)
                ForEach(GradeCategory.allCases, id: \.self) { kind in
                    Text(kind.singular).tag(GradeCategory?.some(kind))
                }
            }
        } footer: {
            Text("Trabajo, control o examen: es el color con el que sale en el Calendario y lo que filtra.")
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
            if grade.isFinalExam == true {
                Label("Fecha en «Fechas»", systemImage: "calendar")
                    .foregroundStyle(.secondary)
            } else {
                DateFields(date: $grade.date)
            }
        } footer: {
            Text(grade.isFinalExam == true
                 ? "El examen final tiene una fecha por convocatoria; se pone desde «Fechas» en la asignatura."
                 : "Si tiene fecha, aparece en el Calendario.")
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

/// One section or variable in the list: its name, what it's made of underneath, and what it counts
/// for on the right.
private struct ComponentRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
