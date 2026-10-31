import Engine
import SwiftUI

/// The headline numbers: overall average, passed subjects and, when the study uses them, passed
/// credits.
struct RecordStats: View {
    let summary: RecordSummary

    var body: some View {
        HStack(spacing: 0) {
            RecordStat(value: RecordSummary.format(summary.average), label: "Media")
            Divider()
            RecordStat(value: "\(summary.passed.count)/\(summary.subjects.count)", label: "Aprobadas")
            if summary.usesCredits {
                Divider()
                RecordStat(value: summary.passedCredits.formatted(), label: "Créditos")
            }
        }
        .padding(.vertical, 4)
    }
}

/// "Expediente", pushed from the account tab: the overall numbers, then every year with its
/// average and, inside it, each term with its own. Shows the current study, or an archived one;
/// the current one's also lists the archived studies below, each opening its own.
struct RecordView: View {
    var archived: ArchivedStudy?
    @Environment(Library.self) private var library
    /// The order of the subjects inside each term, like home's but stored apart and only by name or
    /// grade (no hand-dragged order here).
    @AppStorage("recordSort") private var storedSort = SubjectSort.name
    @AppStorage("recordSortAscending") private var isAscending = true

    /// A "Personalizado" stored by an earlier version reads as by name.
    private var sort: Binding<SubjectSort> {
        Binding(get: { storedSort == .custom ? .name : storedSort }, set: { storedSort = $0 })
    }

    private var courses: [Course] { archived?.courses ?? library.courses }
    private var degree: DegreeSettings { archived?.degree ?? library.degree }

    /// The current study's record, with nothing to show of its own once it's been archived.
    private var showsStudy: Bool { archived != nil || library.hasStudy }
    private var pastStudies: [ArchivedStudy] { archived == nil ? library.archives.reversed() : [] }

    var body: some View {
        let summary = RecordSummary(courses, degree: degree)
        return List {
            if showsStudy {
                studySections(summary)
            }
            if !pastStudies.isEmpty {
                Section("Estudios anteriores") {
                    ForEach(pastStudies) { study in
                        NavigationLink {
                            RecordView(archived: study)
                        } label: {
                            PastStudyRow(study: study)
                        }
                    }
                }
            }
        }
        .overlay {
            if !showsStudy && pastStudies.isEmpty {
                ContentUnavailableView("Sin expediente", systemImage: "chart.bar.doc.horizontal", description: Text("Crea un estudio en Cuenta → Estudio actual."))
            }
        }
        .navigationTitle(archived.map { "Expediente · \($0.degree.displayName)" } ?? "Expediente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsStudy {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach([SubjectSort.name, .grade]) { option in
                            SubjectSortToggle(option: option, sort: sort, isAscending: $isAscending)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Ordenar")
                }
            }
        }
    }

    @ViewBuilder
    private func studySections(_ summary: RecordSummary) -> some View {
        Section {
            RecordStats(summary: summary)
        } footer: {
            Text(degree.usesCredits
                 ? "Las medias cuentan las asignaturas con todas las notas puestas, ponderadas por sus créditos. Llevas \(summary.passedCredits.formatted()) de \(summary.totalCredits.formatted()) créditos."
                 : "Las medias cuentan las asignaturas con todas las notas puestas, todas por igual.")
        }

        // One card per term; the year's name and average head its first one.
        ForEach(courses) { course in
            let terms = terms(of: course)
            ForEach(terms, id: \.self) { term in
                let subjects = sort.wrappedValue.sorted(course.subjects.filter { $0.term == term }, ascending: isAscending)
                Section {
                    ForEach(subjects) { record in
                        NavigationLink {
                            RecordSubjectView(record: record)
                        } label: {
                            RecordRow(record: record, progress: summary.progress(of: record), showsCredits: degree.usesCredits)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 10) {
                        if term == terms.first {
                            HStack(alignment: .firstTextBaseline) {
                                Text(course.name(in: degree))
                                Spacer()
                                Text("Media \(RecordSummary.format(summary.average(of: course.subjects)))")
                                    .monospacedDigit()
                            }
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .textCase(nil)
                            .padding(.bottom, 12)
                        }
                        TermHeader(
                            title: term.map(degree.termLabel) ?? "Todo el año",
                            average: summary.average(of: subjects)
                        )
                    }
                }
            }
        }
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
private struct TermHeader: View {
    let title: String
    let average: Double?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(RecordSummary.format(average))
                .monospacedDigit()
        }
    }
}

private struct RecordRow: View {
    let record: SubjectRecord
    let progress: SubjectProgress
    let showsCredits: Bool

    // Not `LabeledContent`: a long name would push the grade onto a line of its own.
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.subject.name)
                if showsCredits {
                    Text("\(record.subject.ectsCredits.formatted()) ECTS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RecordGrade(progress: progress)
        }
    }
}

/// The subject's final grade in its band's colour (purple from 9), or why there isn't one yet.
private struct RecordGrade: View {
    let progress: SubjectProgress

    var body: some View {
        if progress.isComplete {
            Text(progress.worst, format: .number.precision(.fractionLength(2)))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(GradeBand.color(for: progress.worst))
                .fixedSize()
        } else {
            Text(progress.isUndecided ? "Por definir" : "En curso")
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

/// One subject of the record: its final grade, then each section with its grade (or how many of
/// its notes are in) and, under a section of several notes, each of them. Read-only.
private struct RecordSubjectView: View {
    let record: SubjectRecord

    var body: some View {
        let progress = SubjectProgress(record)
        let inputs = progress.inputs
        let parts = Self.parts(of: record.subject.root)
        List {
            Section {
                HStack {
                    Text("Nota final")
                    Spacer()
                    RecordGrade(progress: progress)
                }
                if progress.session == .extraordinary {
                    LabeledContent("Convocatoria", value: Convocatoria.extraordinary.label)
                }
                LabeledContent("Notas puestas", value: "\(progress.enteredCount) de \(progress.leafCount)")
            }
            if !parts.isEmpty {
                Section("Secciones") {
                    ForEach(parts.indices, id: \.self) { index in
                        let part = parts[index]
                        PartRow(
                            title: part.node.title,
                            weight: record.isUndecided ? nil : part.weight,
                            value: value(of: part.node, inputs: inputs, session: progress.session)
                        )
                        if let group = part.node.asGroup, group.children.count > 1 {
                            ForEach(group.children) { child in
                                PartRow(
                                    title: child.node.title,
                                    value: value(of: child.node, inputs: inputs, session: progress.session),
                                    isNested: true
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(record.subject.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The subject's top-level sections and the share of the grade each carries, when fixed.
    private static func parts(of root: Node) -> [(node: Node, weight: Double?)] {
        switch root {
        case .group(let group):
            let total = group.children.reduce(0) { $0 + $1.weight }
            let isFixed = (group.combination == .weightedAverage || group.combination == .sum) && total > 0
            return group.children.map { ($0.node, isFixed ? $0.weight / total * 100 : nil) }
        case .formula(let formula):
            let keys = formula.expression.variableOrder.filter { formula.variables[$0] != nil }
                + formula.variables.keys.sorted().filter { !formula.expression.variableOrder.contains($0) }
            return keys.compactMap { key in formula.variables[key].map { ($0, nil) } }
        default:
            return []
        }
    }

    /// A note as it was given; a section, its grade out of 10 once all its notes are in ("Por
    /// definir" never works one out), else how many are.
    private func value(of node: Node, inputs: [String: Double], session: Convocatoria) -> (text: String, grade: Double?) {
        if let grade = node.asGrade {
            let text = record.displayedEntry(for: grade, in: session)
            let value = inputs[grade.name].map { grade.scaleMax > 0 ? $0 / grade.scaleMax * 10 : 0 }
            return (text, value)
        }
        let leaves = node.allLeafNames()
        let entered = leaves.count { inputs[$0] != nil }
        guard !record.isUndecided, !leaves.isEmpty, entered == leaves.count, node.scaleMax > 0 else {
            return (leaves.isEmpty || entered == 0 ? "—" : "\(entered) de \(leaves.count)", nil)
        }
        let grade = node.evaluate(inputs, pendingFraction: 0) / node.scaleMax * 10
        return (grade.formatted(.number.precision(.fractionLength(0...2))), grade)
    }
}

private struct PartRow: View {
    let title: String
    var weight: Double?
    let value: (text: String, grade: Double?)
    var isNested = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(isNested ? .secondary : .primary)
                .padding(.leading, isNested ? 16 : 0)
            if let weight {
                Text("\(weight.formatted(.number.precision(.fractionLength(0...1))))\u{00A0}%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 8)
            Text(value.text)
                .monospacedDigit()
                .fontWeight(isNested ? .regular : .semibold)
                .foregroundStyle(value.grade.map { isNested ? Color.primary : GradeBand.color(for: $0) } ?? Color.secondary)
                .fixedSize()
        }
        .font(isNested ? .subheadline : .body)
    }
}

/// An archived study in the current record: its name, when it was put away and its average.
private struct PastStudyRow: View {
    let study: ArchivedStudy

    var body: some View {
        LabeledContent {
            Text("Media \(RecordSummary.format(RecordSummary(study.courses, degree: study.degree).average))")
                .monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(study.degree.displayName)
                Text("Archivado el \(study.archivedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
