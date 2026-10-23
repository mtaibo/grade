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

    /// Only the leaves with a valid, parsed number — what the engine sees as "entered".
    @State private var values: [String: Double] = [:]
    /// What's actually in each text field, kept separately so a half-typed "7." isn't erased.
    @State private var texts: [String: String] = [:]
    @FocusState private var focusedLeaf: String?

    private var leafNames: [String] { subject.root.allLeafNames() }

    var body: some View {
        Form {
            Section("Notas") {
                ForEach(leafNames, id: \.self) { name in
                    GradeRow(
                        name: name,
                        scaleMax: scaleMax(for: name),
                        text: textBinding(for: name)
                    )
                    .focused($focusedLeaf, equals: name)
                }
            }

            Section("Resultado") {
                ResultSummary(root: subject.root, inputs: values)
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
        values = GradeStore.load(for: subject.name)
        texts = values.mapValues(Self.format)
    }

    private func textBinding(for name: String) -> Binding<String> {
        Binding(
            get: { texts[name] ?? "" },
            set: { newValue in
                texts[name] = newValue
                if let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                    values[name] = min(max(parsed, 0), scaleMax(for: name))
                } else {
                    values.removeValue(forKey: name)
                }
                GradeStore.save(values, for: subject.name)
            }
        )
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}

private struct GradeRow: View {
    let name: String
    let scaleMax: Double
    @Binding var text: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.monospacedDigit())
                .frame(width: 56)
            Text("/ \(scaleMax.formatted())")
                .font(.caption)
                .foregroundStyle(.secondary)
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
