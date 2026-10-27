import Engine
import SwiftUI

/// One subject, as a few calm cards: where you stand (folded until you want the detail), the exam
/// dates, and one card per part showing its grade. Nothing here edits the structure or the dates —
/// that lives in the "…" menu; tapping a part opens just its grade to fill in.
struct SubjectDetailView: View {
    let recordID: SubjectRecord.ID

    @Environment(Library.self) private var library
    /// `nil` until the user picks one; until then the record's active sitting is shown.
    @State private var pickedSession: Convocatoria?
    @State private var isEditing = false
    @State private var isEditingDates = false
    @State private var addingDateFor: Convocatoria?
    @State private var editingPartID: String?

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

                GradeCard(progress: progress, session: session, formula: record.subject.root.asFormula)

                ExamsCard(record: record) { addingDateFor = $0 }

                Text("Notas")
                    .font(.title3.bold())
                    .padding(.top, 8)
                    .padding(.horizontal, 4)

                VStack(spacing: 12) {
                    ForEach(PartItem.items(of: record)) { item in
                        Button { editingPartID = item.id } label: {
                            PartCard(item: item, record: record, session: session, progress: progress)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Editar", systemImage: "pencil") { isEditing = true }
                    Button("Modificar fechas", systemImage: "calendar") { isEditingDates = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Más opciones")
            }
        }
        .sheet(isPresented: $isEditing) {
            SubjectEditorView(record: record)
        }
        .sheet(isPresented: $isEditingDates) {
            DatesSheet(recordID: recordID)
        }
        .sheet(item: $addingDateFor) { session in
            ExamDateSheet(session: session) { library.setExamDate($0, for: session, in: recordID) }
        }
        .sheet(item: $editingPartID.asIdentifiable) { partID in
            PartSheet(recordID: recordID, partID: partID.value, session: Binding(get: { session }, set: { pickedSession = $0 }))
        }
    }
}

/// `sheet(item:)` wants an `Identifiable`; a bare string id isn't one.
private struct IDBox: Identifiable {
    let value: String
    var id: String { value }
}

private extension Binding where Value == String? {
    var asIdentifiable: Binding<IDBox?> {
        Binding<IDBox?>(get: { wrappedValue.map(IDBox.init) }, set: { wrappedValue = $0?.value })
    }
}

// MARK: - Grade

/// The grade up front with its bar; tap to unfold what's secured, what's still reachable, the pass
/// mark and what's needed.
private struct GradeCard: View {
    let progress: SubjectProgress
    let session: Convocatoria
    let formula: Formula?

    @State private var isExpanded = false

    private var hasGrades: Bool { progress.enteredCount > 0 }

    /// Calm while there's still room to move: only a sure pass or a lost one gets a colour of its own.
    private var tint: Color {
        guard hasGrades else { return .secondary }
        switch progress.status {
        case .guaranteed: return .green
        case .possible: return .accentColor
        case .impossible: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Oculta el detalle" : "Muestra el detalle")

            GradeRangeBar(worst: progress.worst, best: hasGrades ? progress.best : 0, threshold: progress.threshold, tint: tint)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    if hasGrades {
                        GradeRangeLegend(worst: progress.worst, best: progress.best, threshold: progress.threshold, tint: tint)
                    } else {
                        Text("Apruebas con un \(progress.threshold.formatted())")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let message = verdict {
                        Label {
                            Text(message)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: verdictIcon)
                        }
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tint.opacity(0.1), in: .rect(cornerRadius: 12))
                    }
                    if let formula {
                        Text(formula.expression.display)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(padding: 18)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(progress.worst, format: .number.precision(.fractionLength(0...2)))
                        .foregroundStyle(hasGrades ? .primary : .tertiary)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ 10")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if session == .extraordinary {
                    Text(session.label)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ProgressPill(progress: progress, hasGrades: hasGrades)
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(.rect)
    }

    /// The one sentence that answers "and so what?" for the numbers.
    private var verdict: LocalizedStringKey? {
        guard hasGrades else { return nil }
        switch progress.status {
        case .guaranteed:
            return "Ya tienes el aprobado, pase lo que pase en lo que falta."
        case .impossible:
            return "Aunque saques un 10 en todo lo que falta, no llegas al \(progress.threshold.formatted())."
        case .possible:
            guard let needed = progress.neededAverage else { return nil }
            return "Para aprobar necesitas un **\(needed.formatted(.number.precision(.fractionLength(1))))** de media en lo que falta."
        }
    }

    private var verdictIcon: String {
        switch progress.status {
        case .guaranteed: "checkmark.seal.fill"
        case .impossible: "exclamationmark.triangle.fill"
        case .possible: "target"
        }
    }
}

/// How far along you are ("3 de 5 notas"), not how worried to be; a sure pass or a lost one say so.
private struct ProgressPill: View {
    let progress: SubjectProgress
    let hasGrades: Bool

    var body: some View {
        let (text, icon, tint): (String, String?, Color) = if !hasGrades {
            ("Sin notas", nil, .secondary)
        } else {
            switch progress.status {
            case .guaranteed: ("Aprobada", "checkmark.circle.fill", .green)
            case .impossible: ("No llega", "xmark.circle.fill", .red)
            case .possible: ("\(progress.enteredCount) de \(progress.leafCount)", nil, .secondary)
            }
        }
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text).monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Exams

/// Both sittings in one card: just the date and how long is left. Changing a date is done from
/// the "…" menu, so it doesn't move by accident.
private struct ExamsCard: View {
    let record: SubjectRecord
    let onAddDate: (Convocatoria) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Examen", systemImage: "calendar")
                .font(.headline)
            ForEach(Array(Convocatoria.allCases.enumerated()), id: \.element) { index, session in
                if index > 0 { Divider() }
                ExamRow(session: session, date: record.examDate(for: session)) { onAddDate(session) }
            }
        }
        .card()
    }
}

private struct ExamRow: View {
    let session: Convocatoria
    let date: Date?
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.label)
                    .font(.subheadline.weight(.semibold))
                if let date {
                    Text(Self.remaining(until: date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let date {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.subheadline.weight(.semibold))
                    Text(date, format: .dateTime.hour().minute())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button("Añadir fecha", action: onAdd)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private static func remaining(until date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Hoy"
        case 1: return "Mañana"
        case 2...: return "Quedan \(days) días"
        case -1: return "Fue ayer"
        default: return "Hace \(-days) días"
        }
    }
}

/// Picks a first exam date. Once set it only changes from "Modificar fechas".
private struct ExamDateSheet: View {
    let session: Convocatoria
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Examen · \(session.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Every date of the subject in one place: both exams and the due date of each grade.
private struct DatesSheet: View {
    let recordID: SubjectRecord.ID

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let record = library.record(id: recordID) {
                Form {
                    Section("Examen") {
                        ForEach(Convocatoria.allCases) { session in
                            DateToggleRow(title: session.label, defaultHour: 9, date: Binding(
                                get: { record.examDate(for: session) },
                                set: { library.setExamDate($0, for: session, in: recordID) }
                            ))
                        }
                    }
                    let leaves = record.subject.root.allLeafNames().filter { record.subject.root.leaf(named: $0)?.asGrade != nil }
                    if !leaves.isEmpty {
                        Section("Pruebas y entregas") {
                            ForEach(leaves, id: \.self) { name in
                                DateToggleRow(title: name, defaultHour: 23, date: Binding(
                                    get: { record.subject.root.leaf(named: name)?.asGrade?.date },
                                    set: { library.setGradeDate($0, forLeaf: name, in: recordID) }
                                ))
                            }
                        }
                    }
                }
                .navigationTitle("Fechas")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hecho") { dismiss() }
                    }
                }
            }
        }
    }
}

private struct DateToggleRow: View {
    let title: String
    let defaultHour: Int
    @Binding var date: Date?

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? Calendar.current.date(bySettingHour: defaultHour, minute: defaultHour == 23 ? 59 : 0, second: 0, of: .now) : nil }
            ))
            if let date = Binding($date) {
                DatePicker("Fecha", selection: date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Parts

/// One top-level part of the evaluation, with the share of the grade it carries.
private struct PartItem: Identifiable {
    let id: String
    let node: Node
    let weightPercent: Double?
    /// Points toward the final 10, out of what the part can give at most.
    let maxPoints: Double?

    static func items(of record: SubjectRecord) -> [PartItem] {
        let root = record.subject.root
        if case .group(let group) = root {
            let total = group.combination == .weightedAverage ? group.children.reduce(0) { $0 + $1.weight } : 1
            return group.children.map { child in
                PartItem(
                    id: child.id.uuidString,
                    node: child.node,
                    weightPercent: total > 0 ? child.weight / total * 100 : nil,
                    maxPoints: total > 0 && child.node.scaleMax > 0 ? child.weight / total * 10 : nil
                )
            }
        } else if case .formula(let formula) = root {
            return formula.variables.keys.sorted().compactMap { key in
                formula.variables[key].map { PartItem(id: key, node: $0, weightPercent: nil, maxPoints: nil) }
            }
        } else {
            return [PartItem(id: "root", node: root, weightPercent: nil, maxPoints: nil)]
        }
    }

    func earnedPoints(_ inputs: [String: Double]) -> Double? {
        guard let maxPoints else { return nil }
        let hasGrades = node.allLeafNames().contains { inputs[$0] != nil }
        guard hasGrades else { return nil }
        return maxPoints * node.evaluate(inputs, pendingFraction: 0) / node.scaleMax
    }
}

/// A part at a glance: name, weight, what's in so far and a thin bar of its points. Read-only.
private struct PartCard: View {
    let item: PartItem
    let record: SubjectRecord
    let session: Convocatoria
    let progress: SubjectProgress

    private var leafNames: [String] { item.node.allLeafNames() }
    private var enteredCount: Int { leafNames.count { progress.inputs[$0] != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.node.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                if let weightPercent = item.weightPercent {
                    Text("\(weightPercent.formatted(.number.precision(.fractionLength(0...1)))) %")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 8)
                trailing
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let maxPoints = item.maxPoints {
                let earned = item.earnedPoints(progress.inputs) ?? 0
                ProgressBar(fraction: earned / maxPoints)
            }
            if let group = item.node.asGroup, group.children.count < 4, group.children.allSatisfy({ $0.node.asGrade != nil }) {
                VStack(spacing: 6) {
                    ForEach(group.children) { child in
                        if let grade = child.node.asGrade {
                            HStack {
                                Text(grade.name)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(display(of: grade))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        .card()
        .contentShape(.rect)
    }

    @ViewBuilder
    private var trailing: some View {
        if let grade = item.node.asGrade {
            Text(display(of: grade))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(record.entry(for: grade.name, in: session) == nil ? .tertiary : .primary)
        } else if leafNames.count > 1 {
            Text("\(enteredCount) de \(leafNames.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func display(of grade: Grade) -> String {
        guard let entry = record.entry(for: grade.name, in: session) else { return "—" }
        let number = { (value: Double) in value.formatted(.number.precision(.fractionLength(0...2))) }
        if let letter = entry.letter { return letter }
        switch grade.inputStyle ?? .points {
        case .percent:
            return "\(number(entry.outOf == 100 ? entry.value : entry.value / entry.outOf * 100)) %"
        case .points, .letters:
            return entry.outOf == 10 ? number(entry.value) : "\(number(entry.value)) / \(number(entry.outOf))"
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.accentColor)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Where a grade is actually typed: just that part's inputs. The sitting picker only shows up when
/// something in the part is retaken in the extraordinary sitting (usually the exam).
private struct PartSheet: View {
    let recordID: SubjectRecord.ID
    let partID: String
    @Binding var session: Convocatoria

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            if let record = library.record(id: recordID), let item = PartItem.items(of: record).first(where: { $0.id == partID }) {
                let progress = SubjectProgress(record, session: session)
                let retaken = item.node.allLeafNames().contains { !record.keepsForExtraordinary($0) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if retaken {
                            Picker("Convocatoria", selection: $session) {
                                ForEach(Convocatoria.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        PartContent(node: item.node, context: PartContext(
                            record: record, session: session, inputs: progress.inputs, focus: $focusedField
                        ) { leaf, entry in
                            library.setEntry(entry, forLeaf: leaf, in: recordID, session: session)
                        })
                        .card()
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(item.node.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hecho") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Hecho") { focusedField = nil }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// What every input needs to read and write grades for the sitting on screen.
private struct PartContext {
    let record: SubjectRecord
    let session: Convocatoria
    let inputs: [String: Double]
    var focus: FocusState<String?>.Binding
    let onEntry: (String, GradeEntry?) -> Void
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
                            .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: 12))
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
    private var isFocused: Bool { context.focus.wrappedValue == fieldID }
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
                    Text("sobre").font(.subheadline).foregroundStyle(.secondary)
                    TextField("10", text: $outOfText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 36)
                        .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: 8))
                        .accessibilityLabel("Sobre cuánto es la nota")
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
            .frame(width: compact ? 56 : 72, height: compact ? 36 : 44)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: isFocused ? 2 : 0)
            }
            .accessibilityLabel(grade.name)
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
