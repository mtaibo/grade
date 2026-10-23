import Engine
import SwiftUI

/// The app's one real screen for now: pick one of the 3 reference subjects and see the engine
/// work on it. No persistence, no SwiftData yet — `Subject.all` is the fixed reference data from
/// `Sources/Engine/ReferenceSubjects.swift`, the same trees `EngineTests` checks against.
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

    @State private var values: [String: Double] = [:]
    @State private var entered: Set<String> = []

    private var leafNames: [String] { subject.root.allLeafNames() }
    private var inputs: [String: Double] { values.filter { entered.contains($0.key) } }

    var body: some View {
        Form {
            Section("Notas") {
                ForEach(leafNames, id: \.self) { name in
                    GradeRow(
                        name: name,
                        scaleMax: subject.root.leaf(named: name)?.scaleMax ?? 10,
                        value: binding(for: name),
                        isEntered: entered.contains(name)
                    )
                }
            }

            Section("Resultado") {
                ResultSummary(root: subject.root, inputs: inputs)
            }
        }
        .navigationTitle(subject.name)
    }

    private func binding(for name: String) -> Binding<Double> {
        Binding(
            get: { values[name] ?? 0 },
            set: { newValue in
                values[name] = newValue
                entered.insert(name)
            }
        )
    }
}

private struct GradeRow: View {
    let name: String
    let scaleMax: Double
    @Binding var value: Double
    let isEntered: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(name)
                Spacer()
                if isEntered {
                    Text(value, format: .number.precision(.fractionLength(1)))
                        .foregroundStyle(.secondary)
                } else {
                    Text("sin nota")
                        .foregroundStyle(.tertiary)
                }
            }
            Slider(value: $value, in: 0...scaleMax, step: 0.1)
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
