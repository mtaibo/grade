import Engine
import SwiftUI

/// The record's numbers, worked out once per redraw: each subject's progress, and credit-weighted
/// averages over the subjects whose grades are all in — one still in progress has no final grade
/// yet to average (§2).
struct RecordSummary {
    let progress: [SubjectRecord.ID: SubjectProgress]
    let subjects: [SubjectRecord]

    init(_ courses: [Course]) {
        subjects = courses.flatMap(\.subjects)
        progress = Dictionary(subjects.map { ($0.id, SubjectProgress($0)) }) { first, _ in first }
    }

    func progress(of record: SubjectRecord) -> SubjectProgress {
        progress[record.id] ?? SubjectProgress(record)
    }

    private func completed(_ records: [SubjectRecord]) -> [SubjectRecord] {
        records.filter { progress(of: $0).isComplete }
    }

    func average(of records: [SubjectRecord]) -> Double? {
        let done = completed(records)
        let credits = done.reduce(0) { $0 + $1.subject.ectsCredits }
        guard credits > 0 else { return nil }
        return done.reduce(0) { $0 + progress(of: $1).worst * $1.subject.ectsCredits } / credits
    }

    var average: Double? { average(of: subjects) }

    var passed: [SubjectRecord] {
        completed(subjects).filter { progress(of: $0).status == .guaranteed }
    }

    var passedCredits: Double { passed.reduce(0) { $0 + $1.subject.ectsCredits } }
    var totalCredits: Double { subjects.reduce(0) { $0 + $1.subject.ectsCredits } }

    static func format(_ average: Double?) -> String {
        average?.formatted(.number.precision(.fractionLength(2))) ?? "—"
    }
}

/// The three headline numbers: overall average, passed subjects and passed credits.
struct RecordStats: View {
    let summary: RecordSummary

    var body: some View {
        HStack(spacing: 0) {
            RecordStat(value: RecordSummary.format(summary.average), label: "Media")
            Divider()
            RecordStat(value: "\(summary.passed.count)/\(summary.subjects.count)", label: "Aprobadas")
            Divider()
            RecordStat(value: summary.passedCredits.formatted(), label: "Créditos")
        }
        .padding(.vertical, 4)
    }
}

/// "Expediente", pushed from the account tab: the overall numbers, then every year with its
/// average and, inside it, each term with its own. Shows the current study, or an archived one.
struct RecordView: View {
    var archived: ArchivedStudy?
    @Environment(Library.self) private var library

    private var courses: [Course] { archived?.courses ?? library.courses }
    private var degree: DegreeSettings { archived?.degree ?? library.degree }

    var body: some View {
        let summary = RecordSummary(courses)
        return List {
            Section {
                RecordStats(summary: summary)
            } footer: {
                Text("Las medias cuentan las asignaturas con todas las notas puestas, ponderadas por sus créditos. Llevas \(summary.passedCredits.formatted()) de \(summary.totalCredits.formatted()) créditos.")
            }

            ForEach(courses) { course in
                Section {
                    ForEach(terms(of: course), id: \.self) { term in
                        let subjects = course.subjects.filter { $0.term == term }
                        TermRow(
                            title: term.map(degree.termLabel) ?? "Todo el año",
                            average: summary.average(of: subjects)
                        )
                        ForEach(subjects) { record in
                            RecordRow(record: record, progress: summary.progress(of: record))
                        }
                    }
                } header: {
                    HStack {
                        Text(course.name(in: degree))
                        Spacer()
                        Text("Media \(RecordSummary.format(summary.average(of: course.subjects)))")
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Expediente")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The course's terms in order, year-long subjects last.
    private func terms(of course: Course) -> [Int?] {
        let terms: [Int?] = Set(course.subjects.compactMap(\.term)).sorted()
        return course.subjects.contains { $0.term == nil } ? terms + [nil] : terms
    }
}

private struct RecordStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A term's heading inside its year, with the term's average.
private struct TermRow: View {
    let title: String
    let average: Double?

    var body: some View {
        LabeledContent {
            Text(RecordSummary.format(average))
                .monospacedDigit()
        } label: {
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .listRowBackground(Color.secondary.opacity(0.08))
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
