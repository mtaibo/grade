import Engine
import SwiftUI

/// The app's one real screen for now: pick one of the 3 reference subjects and see the engine
/// work on it. No SwiftData yet — `Subject.all` is the fixed reference data from
/// `Sources/Engine/ReferenceSubjects.swift`, the same trees `EngineTests` checks against. Entered
/// grades persist via `GradeStore` (`UserDefaults`), keyed by subject name.
struct SubjectListView: View {
    var body: some View {
        NavigationStack {
            List(Subject.all, id: \.name) { subject in
                NavigationLink(subject.name) {
                    SubjectDetailView(subject: subject)
                }
            }
            .navigationTitle("Asignaturas")
        }
    }
}

struct SubjectDetailView: View {
    let subject: Subject

    /// What the user typed: a value out of their own `outOf`, which may not match the leaf's
    /// own scale (e.g. a teacher grades out of 2 while the leaf's scale is 10).
    @State private var entries: [String: GradeEntry] = [:]
    /// The raw text in each field, kept separately so a half-typed "7." isn't erased.
    @State private var valueTexts: [String: String] = [:]
    @State private var outOfTexts: [String: String] = [:]
    @FocusState private var focusedLeaf: String?

    private var leafNames: [String] { subject.root.allLeafNames() }

    /// `entries` converted to each leaf's own scale — what the engine sees as "entered".
    private var inputs: [String: Double] {
        entries.reduce(into: [:]) { result, pair in
            let (name, entry) = pair
            guard entry.outOf > 0 else { return }
            let max = scaleMax(for: name)
            result[name] = min(Swift.max(entry.value / entry.outOf * max, 0), max)
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(leafNames, id: \.self) { name in
                    GradeRow(
                        name: name,
                        leafScaleMax: scaleMax(for: name),
                        convertedValue: inputs[name],
                        valueText: valueText(for: name),
                        outOfText: outOfText(for: name)
                    )
                    .focused($focusedLeaf, equals: name)
                }
            } header: {
                Text("Notas")
            } footer: {
                Text("Si el profesor te la dio sobre otra escala (p. ej. sobre 2), cambia el \"sobre\" — se convierte sola.")
            }

            Section("Resultado") {
                ResultSummary(root: subject.root, inputs: inputs)
            }
        }
        .navigationTitle(subject.name)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hecho") { focusedLeaf = nil }
            }
        }
        .onAppear(perform: load)
    }

    private func scaleMax(for name: String) -> Double {
        subject.root.leaf(named: name)?.scaleMax ?? 10
    }

    private func load() {
        entries = GradeStore.load(for: subject.name)
        valueTexts = entries.mapValues { Self.format($0.value) }
        outOfTexts = entries.mapValues { Self.format($0.outOf) }
    }

    private func valueText(for name: String) -> Binding<String> {
        Binding(
            get: { valueTexts[name] ?? "" },
            set: { newValue in
                valueTexts[name] = newValue
                update(name: name, valueText: newValue, outOfText: outOfTexts[name])
            }
        )
    }

    private func outOfText(for name: String) -> Binding<String> {
        Binding(
            get: { outOfTexts[name] ?? Self.format(scaleMax(for: name)) },
            set: { newValue in
                outOfTexts[name] = newValue
                update(name: name, valueText: valueTexts[name], outOfText: newValue)
            }
        )
    }

    /// Re-parses both fields for `name` and either stores a complete entry or drops it — a grade
    /// needs both a value and a positive "out of" to mean anything.
    private func update(name: String, valueText: String?, outOfText: String?) {
        let value = (valueText ?? "").replacingOccurrences(of: ",", with: ".")
        let outOf = (outOfText ?? "").replacingOccurrences(of: ",", with: ".")
        if let value = Double(value), let outOf = Double(outOf), outOf > 0 {
            entries[name] = GradeEntry(value: value, outOf: outOf)
        } else {
            entries.removeValue(forKey: name)
        }
        GradeStore.save(entries, for: subject.name)
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}

private struct GradeRow: View {
    let name: String
    let leafScaleMax: Double
    let convertedValue: Double?
    @Binding var valueText: String
    @Binding var outOfText: String

    private var showsConversion: Bool {
        guard let outOf = Double(outOfText.replacingOccurrences(of: ",", with: ".")) else { return false }
        return outOf != leafScaleMax && convertedValue != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                Spacer()
                TextField("—", text: $valueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.monospacedDigit())
                    .frame(width: 50)
                Text("/")
                    .foregroundStyle(.secondary)
                TextField("", text: $outOfText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34)
            }
            if showsConversion, let convertedValue {
                Text("= \(convertedValue.formatted(.number.precision(.fractionLength(0...2))))/\(leafScaleMax.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ResultSummary: View {
    let root: Node
    let inputs: [String: Double]

    private var worst: Double { root.evaluate(inputs, pendingFraction: 0) }
    private var best: Double { root.evaluate(inputs, pendingFraction: 1) }
    private var status: PassStatus { root.status(inputs) }
    private var threshold: Double { root.minimumThreshold ?? 5 }

    var body: some View {
        LabeledContent("Nota si no entra nada más") {
            Text(worst, format: .number.precision(.fractionLength(2)))
        }
        LabeledContent("Mejor nota posible") {
            Text(best, format: .number.precision(.fractionLength(2)))
        }
        StatusLabel(status: status)

        if status == .possible, let fraction = root.neededFraction(inputs, target: threshold) {
            Text("Con un \((fraction * 10).formatted(.number.precision(.fractionLength(1))))/10 de media en lo que falta, llegas al \(threshold.formatted()).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusLabel: View {
    let status: PassStatus

    var body: some View {
        switch status {
        case .guaranteed:
            Label("Aprobado asegurado", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .possible:
            Label("Aprobado posible", systemImage: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        case .impossible:
            Label("Aprobado imposible", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    SubjectListView()
}
