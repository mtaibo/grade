import Engine
import SwiftUI

/// "Expediente": the credit-weighted average the brief asks for (§2), over subjects whose grades
/// are all in — a subject still in progress has no final grade yet to average.
struct RecordView: View {
    @Environment(Library.self) private var library

    private var completed: [(record: SubjectRecord, progress: SubjectProgress)] {
        library.courses.flatMap(\.subjects)
            .map { ($0, SubjectProgress($0)) }
            .filter { $0.1.isComplete }
    }

    private var average: Double? {
        let credits = completed.reduce(0) { $0 + $1.record.subject.ectsCredits }
        guard credits > 0 else { return nil }
        return completed.reduce(0) { $0 + $1.progress.worst * $1.record.subject.ectsCredits } / credits
    }

    private var passedCredits: Double {
        completed.filter { $0.progress.status == .guaranteed }.reduce(0) { $0 + $1.record.subject.ectsCredits }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        RecordStat(
                            value: average?.formatted(.number.precision(.fractionLength(2))) ?? "—",
                            label: "Media ponderada"
                        )
                        Divider()
                        RecordStat(value: passedCredits.formatted(), label: "Créditos superados")
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("La media cuenta las asignaturas con todas las notas puestas, ponderadas por sus créditos.")
                }

                ForEach(library.courses) { course in
                    Section(course.name) {
                        ForEach(course.subjects) { record in
                            RecordRow(record: record, progress: SubjectProgress(record))
                        }
                    }
                }
            }
            .navigationTitle("Expediente")
        }
    }
}

private struct RecordStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordRow: View {
    let record: SubjectRecord
    let progress: SubjectProgress

    var body: some View {
        LabeledContent {
            if progress.isComplete {
                Text(progress.worst, format: .number.precision(.fractionLength(2)))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(progress.status.tint)
            } else {
                Text("En curso")
                    .foregroundStyle(.secondary)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.subject.name)
                Text("\(record.subject.ectsCredits.formatted()) ECTS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
