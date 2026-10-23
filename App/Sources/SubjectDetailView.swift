import Engine
import SwiftUI

/// One subject, laid out as cards instead of a settings-style list: the sitting (ordinaria /
/// extraordinaria), where you stand, that sitting's exam date, and one card per part with the input
/// that fits how its grade is given (points, a percentage, letters, or a grid for many small tests).
struct SubjectDetailView: View {
    let recordID: SubjectRecord.ID

    @Environment(Library.self) private var library
    /// `nil` until the user picks one; until then the record's active sitting is shown.
    @State private var pickedSession: Convocatoria?
    @State private var isEditing = false
    @FocusState private var focusedField: String?

    var body: some View {
        if let record = library.record(id: recordID) {
            content(record, session: pickedSession ?? record.activeSession)
        } else {
            ContentUnavailableView("Asignatura no encontrada", systemImage: "questionmark.folder")
        }
    }

    private func content(_ record: SubjectRecord, session: Convocatoria) -> some View {
        let progress = SubjectProgress(record, session: session)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(record.subject.name)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Convocatoria", selection: Binding(get: { session }, set: { pickedSession = $0 })) {
                    ForEach(Convocatoria.allCases) { session in
                        Text(session.label).tag(session)
                    }
                }
                .pickerStyle(.segmented)

                SummaryCard(progress: progress)

                ExamCard(session: session, date: Binding(
                    get: { record.examDate(for: session) },
                    set: { library.setExamDate($0, for: session, in: recordID) }
                ))

                PartsSection(record: record, session: session, progress: progress, focus: $focusedField) { leaf, entry in
                    library.setEntry(entry, forLeaf: leaf, in: recordID, session: session)
                }

                Text("Para cambiar las partes, sus pesos o cómo se pone cada nota, toca Editar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar") { isEditing = true }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hecho") { focusedField = nil }
            }
        }
        .sheet(isPresented: $isEditing) {
            SubjectEditorView(record: record)
        }
    }
}

// MARK: - Summary

private struct SummaryCard: View {
    let progress: SubjectProgress

    private var hasGrades: Bool { progress.enteredCount > 0 }
    private var tint: Color { hasGrades ? progress.status.tint : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Llevas")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(progress.worst, format: .number.precision(.fractionLength(0...2)))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("/ 10")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusPill(status: progress.status, hasGrades: hasGrades)
            }

            GradeRangeBar(worst: progress.worst, best: hasGrades ? progress.best : 0, threshold: progress.threshold, tint: tint)

            HStack {
                Text("Máximo posible \(progress.best.formatted(.number.precision(.fractionLength(0...2))))")
                Spacer()
                Text("Aprobado con \(progress.threshold.formatted())")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let needed = progress.neededAverage {
                Label {
                    Text("Necesitas un **\(needed.formatted(.number.precision(.fractionLength(1))))** de media en lo que falta.")
                } icon: {
                    Image(systemName: "target")
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            }
        }
        .card(padding: 18)
    }
}

private struct StatusPill: View {
    let status: PassStatus
    let hasGrades: Bool

    var body: some View {
        let (text, icon, tint): (String, String, Color) = if !hasGrades {
            ("Sin notas", "circle.dashed", .secondary)
        } else {
            switch status {
            case .guaranteed: ("Aprobada", "checkmark.circle.fill", .green)
            case .possible: ("En juego", "hourglass", .orange)
            case .impossible: ("Sin opción", "xmark.circle.fill", .red)
            }
        }
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Exam

private struct ExamCard: View {
    let session: Convocatoria
    @Binding var date: Date?

    private var subtitle: String {
        guard let date else { return "Sin fecha" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Hoy"
        case 1: return "Mañana"
        case 2...: return "En \(days) días"
        case -1: return "Fue ayer"
        default: return "Fue hace \(-days) días"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .background(.red.opacity(0.12), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Examen de la \(session.label.lowercased())")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if date == nil {
                    Button("Añadir fecha") {
                        date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Quitar fecha", systemImage: "xmark.circle.fill") { date = nil }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            if let date = Binding($date) {
                DatePicker("Fecha del examen", selection: date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
        .card()
    }
}

// MARK: - Parts

private struct PartsSection: View {
    let record: SubjectRecord
    let session: Convocatoria
    let progress: SubjectProgress
    var focus: FocusState<String?>.Binding
    let onEntry: (String, GradeEntry?) -> Void

    var body: some View {
        let root = record.subject.root
        VStack(spacing: 12) {
            if case .group(let group) = root {
                let total = group.combination == .weightedAverage ? group.children.reduce(0) { $0 + $1.weight } : 1
                ForEach(group.children) { child in
                    PartCard(
                        node: child.node,
                        weightPercent: total > 0 ? child.weight / total * 100 : nil,
                        contribution: contribution(of: child, total: total),
                        context: context
                    )
                }
            } else if case .formula(let formula) = root {
                ForEach(formula.variables.keys.sorted(), id: \.self) { key in
                    if let node = formula.variables[key] {
                        PartCard(node: node, weightPercent: nil, contribution: nil, context: context)
                    }
                }
                Text("Se calcula con la fórmula de su guía: \(formula.expression.display)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PartCard(node: root, weightPercent: nil, contribution: nil, context: context)
            }
        }
    }

    private var context: PartContext {
        PartContext(record: record, session: session, inputs: progress.inputs, focus: focus, onEntry: onEntry)
    }

    /// Points this part has earned towards the final 10, out of what it can give at most.
    private func contribution(of child: WeightedChild, total: Double) -> (earned: Double?, max: Double)? {
        guard total > 0, child.node.scaleMax > 0 else { return nil }
        let max = child.weight / total * 10
        let hasGrades = child.node.allLeafNames().contains { progress.inputs[$0] != nil }
        let earned = hasGrades ? max * child.node.evaluate(progress.inputs, pendingFraction: 0) / child.node.scaleMax : nil
        return (earned, max)
    }
}

/// What every card and input needs to read and write grades for the sitting on screen.
private struct PartContext {
    let record: SubjectRecord
    let session: Convocatoria
    let inputs: [String: Double]
    var focus: FocusState<String?>.Binding
    let onEntry: (String, GradeEntry?) -> Void
}

private struct PartCard: View {
    let node: Node
    let weightPercent: Double?
    let contribution: (earned: Double?, max: Double)?
    let context: PartContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(node.title)
                    .font(.headline)
                if let weightPercent {
                    Text("\(weightPercent.formatted(.number.precision(.fractionLength(0...1)))) %")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 8)
                if let contribution {
                    Text("\(contribution.earned.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—") / \(contribution.max.formatted(.number.precision(.fractionLength(0...2))))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            PartContent(node: node, context: context)
        }
        .card()
    }
}

/// The inputs inside a part: a single field for a grade, a compact grid for a group of many small
/// grades, or labelled rows (nested as needed) for anything else.
private struct PartContent: View {
    let node: Node
    let context: PartContext

    var body: some View {
        if let grade = node.asGrade {
            LeafInput(grade: grade, context: context, compact: false)
        } else if let group = node.asGroup {
            let allGrades = group.children.allSatisfy { $0.node.asGrade != nil }
            if allGrades && group.children.count >= 4 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 10)], spacing: 10) {
                    ForEach(group.children) { child in
                        if let grade = child.node.asGrade {
                            VStack(spacing: 4) {
                                Text(Self.shortName(grade.name))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                LeafInput(grade: grade, context: context, compact: true)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(grade.name)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.children) { child in
                        if let grade = child.node.asGrade {
                            HStack(alignment: .firstTextBaseline) {
                                Text(grade.name)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                LeafInput(grade: grade, context: context, compact: false)
                                    .fixedSize()
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(child.node.title)
                                    .font(.subheadline.weight(.semibold))
                                PartContent(node: child.node, context: context)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        } else {
            Text("Este tipo de parte todavía no se puede rellenar desde aquí.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Prueba 10" → "P10", anything else → its first few letters, so a grid cell stays narrow.
    static func shortName(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2, let last = words.last, Int(last) != nil, let first = words.first?.first {
            return "\(first)\(last)"
        }
        return String(name.prefix(7))
    }
}

/// The input for one grade, shaped by how the teacher gives it. In the extraordinary sitting, a
/// grade carried over from the ordinary one shows as such until it's re-entered.
private struct LeafInput: View {
    let grade: Grade
    let context: PartContext
    let compact: Bool

    @State private var text = ""
    @State private var outOfText = ""

    private var fieldID: String { "\(context.session.rawValue)/\(grade.name)" }
    private var entry: GradeEntry? { context.record.entry(for: grade.name, in: context.session) }
    private var isCarriedOver: Bool { context.record.isCarriedOver(grade.name, in: context.session) }
    private var overridesKeptGrade: Bool {
        context.session == .extraordinary
            && context.record.keepsForExtraordinary(grade.name)
            && context.record.extraordinaryEntries[grade.name] != nil
            && context.record.entries[grade.name] != nil
    }

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 4) {
            input
            if isCarriedOver {
                Text("De la ordinaria")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if overridesKeptGrade, !compact {
                Button("Volver a la de la ordinaria") { context.onEntry(grade.name, nil) }
                    .font(.caption)
            }
        }
        .onAppear(perform: seed)
        .onChange(of: entry) {
            if context.focus.wrappedValue != fieldID { seed() }
        }
    }

    @ViewBuilder
    private var input: some View {
        switch grade.inputStyle ?? .points {
        case .letters(let scale):
            LetterInput(scale: scale, selected: entry?.letter, compact: compact) { letter in
                context.onEntry(grade.name, letter.map { GradeEntry(value: $0.value, outOf: 10, letter: $0.letter) })
            }
        case .percent:
            HStack(spacing: 4) {
                valueField
                Text("%").foregroundStyle(.secondary)
            }
        case .points:
            if compact {
                valueField
            } else {
                HStack(spacing: 4) {
                    valueField
                    Text("/").foregroundStyle(.tertiary)
                    TextField("10", text: $outOfText)
                        .keyboardType(.decimalPad)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                        .focused(context.focus, equals: fieldID + "/outOf")
                        .onChange(of: outOfText) {
                            guard context.focus.wrappedValue == fieldID + "/outOf" else { return }
                            commitPoints()
                        }
                }
            }
        }
    }

    private var valueField: some View {
        TextField("—", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(compact ? .center : .trailing)
            .font(compact ? .title3.monospacedDigit().weight(.semibold) : .title2.monospacedDigit().weight(.semibold))
            .foregroundStyle(isCarriedOver ? .secondary : .primary)
            .frame(width: compact ? 56 : 72)
            .padding(.vertical, compact ? 0 : 4)
            .background(compact ? Color.clear : Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
            .focused(context.focus, equals: fieldID)
            .onChange(of: text) {
                guard context.focus.wrappedValue == fieldID else { return }
                if grade.inputStyle == .percent { commitPercent() } else { commitPoints() }
            }
    }

    private func seed() {
        guard let entry else {
            text = ""
            outOfText = Self.format(grade.scaleMax)
            return
        }
        if grade.inputStyle == .percent {
            text = Self.format(entry.outOf == 100 ? entry.value : entry.value / entry.outOf * 100)
        } else {
            text = Self.format(entry.value)
        }
        outOfText = Self.format(entry.outOf)
    }

    private func commitPoints() {
        let value = Self.parse(text)
        let outOf = compact ? (entry?.outOf ?? grade.scaleMax) : Self.parse(outOfText)
        guard let value, let outOf, outOf > 0 else {
            if text.isEmpty { context.onEntry(grade.name, nil) }
            return
        }
        context.onEntry(grade.name, GradeEntry(value: value, outOf: outOf))
    }

    private func commitPercent() {
        guard let value = Self.parse(text) else {
            if text.isEmpty { context.onEntry(grade.name, nil) }
            return
        }
        context.onEntry(grade.name, GradeEntry(value: value, outOf: 100))
    }

    private static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

/// Letter grades as chips (or a menu when space is tight); tapping the selected one clears it.
private struct LetterInput: View {
    let scale: [LetterGrade]
    let selected: String?
    let compact: Bool
    let onSelect: (LetterGrade?) -> Void

    var body: some View {
        if compact {
            Menu {
                ForEach(scale) { letter in
                    Button("\(letter.letter) (\(letter.value.formatted()))") { onSelect(letter) }
                }
                if selected != nil {
                    Button("Quitar", role: .destructive) { onSelect(nil) }
                }
            } label: {
                Text(selected ?? "—")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56)
            }
        } else {
            HStack(spacing: 6) {
                ForEach(scale) { letter in
                    let isSelected = letter.letter == selected
                    Button {
                        onSelect(isSelected ? nil : letter)
                    } label: {
                        Text(letter.letter)
                            .font(.headline)
                            .frame(minWidth: 36, minHeight: 36)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(letter.letter), \(letter.value.formatted()) sobre 10")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}
