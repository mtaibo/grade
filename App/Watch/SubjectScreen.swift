import Engine
import SwiftUI

/// One subject: how it stands, then its notes by section. Tapping a note opens its input.
struct SubjectScreen: View {
    let recordID: SubjectRecord.ID
    /// The term it was opened from, for a subject graded per term (relative to its year).
    let term: Int?

    @Environment(WatchStore.self) private var store
    @State private var editing: EditedNote?

    var body: some View {
        if let record = store.record(id: recordID), let degree = store.snapshot?.degree {
            content(record, degree: degree)
        } else {
            Text("Esta asignatura ya no está en tu iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func content(_ record: SubjectRecord, degree: DegreeSettings) -> some View {
        let session = record.activeSession
        let scope = PartItem.termScope(of: record, session: session, term: term, termsPerYear: degree.termsPerYear)
        let items = scope?.items ?? PartItem.items(of: record, session: session)
        let progress = SubjectProgress(record, session: session, rounding: degree.rounding, part: scope?.node)
        let tint = SubjectStyle(record).tint
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Here and not as the bar's title, which long names don't fit next to the clock.
                Text(record.subject.name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(3)
                    .padding(.horizontal, 6)
                if !record.isUndecided {
                    SummaryCard(progress: progress, session: session)
                }
                ForEach(items) { item in
                    PartSection(item: item, record: record, session: session, tint: tint) { editing = $0 }
                }
            }
            .padding(.horizontal, 2)
        }
        .sheet(item: $editing) { note in
            GradeEntryScreen(note: note, record: record, session: session)
        }
    }
}

/// What opens the grade input.
struct EditedNote: Identifiable {
    let name: String
    let grade: Grade
    var id: String { name }
}

/// The big number, the bar from the iPhone's grade card, and the one sentence that matters.
private struct SummaryCard: View {
    let progress: SubjectProgress
    let session: Convocatoria

    private var hasGrades: Bool { progress.enteredCount > 0 }

    private var barTint: Color {
        progress.isComplete ? GradeBand.color(for: progress.worst) : .accentColor
    }

    private var verdict: (text: String, tint: Color)? {
        if progress.isNotPresented { return ("No presentado", .secondary) }
        if progress.missesARequirement { return ("No cumples un requisito", .red) }
        guard hasGrades else { return nil }
        switch progress.status {
        case .guaranteed:
            return ("Ya has aprobado", .green)
        case .impossible:
            return ("No llegas al \(progress.threshold.formatted())", .red)
        case .possible:
            guard let needed = progress.neededAverage else { return nil }
            return ("Necesitas un \(needed.formatted(.number.precision(.fractionLength(1)))) de media", .accentColor)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(progress.worst, format: .number.precision(.fractionLength(0...2)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(hasGrades ? .primary : .tertiary)
                    .contentTransition(.numericText())
                Text("/ 10")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if progress.hasHonors {
                    Text("MH")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(GradeBand.color(for: 10))
                }
            }
            GradeRangeBar(worst: progress.worst, best: hasGrades ? progress.best : 0, threshold: progress.threshold, tint: barTint)
            if let verdict {
                Text(verdict.text)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(verdict.tint)
            }
            if session == .extraordinary {
                Text(session.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchCard.fill, in: .rect(cornerRadius: WatchCard.cornerRadius))
        .animation(.snappy, value: progress.worst)
    }
}

/// A part of the evaluation: a note on its own is a tile; several go under the part's name.
private struct PartSection: View {
    let item: PartItem
    let record: SubjectRecord
    let session: Convocatoria
    let tint: Color
    let onOpen: (EditedNote) -> Void

    private var notes: [Grade] { item.node.grades }

    private var weight: String? {
        guard let percent = item.weightPercent else { return nil }
        let text = percent.formatted(.number.precision(.fractionLength(0...1)))
        return item.isMaximum ? "hasta \(text) %" : "\(text) %"
    }

    var body: some View {
        if notes.count == 1, let grade = notes.first {
            NoteRow(grade: grade, title: item.node.title, caption: weight, record: record, session: session, tint: tint) {
                onOpen(EditedNote(name: grade.name, grade: grade))
            }
        } else if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.node.title)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if let weight {
                        Text(weight)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                ForEach(notes, id: \.name) { grade in
                    NoteRow(grade: grade, title: grade.name, caption: nil, record: record, session: session, tint: tint) {
                        onOpen(EditedNote(name: grade.name, grade: grade))
                    }
                }
            }
        }
    }
}

private struct NoteRow: View {
    let grade: Grade
    let title: String
    let caption: String?
    let record: SubjectRecord
    let session: Convocatoria
    let tint: Color
    let onTap: () -> Void

    private var isLocked: Bool { session == .extraordinary && record.isLockedInExtraordinary(grade.name) }
    private var isCarriedOver: Bool { record.isCarriedOver(grade.name, in: session) }
    private var hasEntry: Bool { record.entry(for: grade.name, in: session) != nil }

    private var subtitle: String? {
        if isLocked { return "No se recupera" }
        if isCarriedOver { return "De la ordinaria" }
        return caption
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if hasEntry {
                    Text(record.displayedEntry(for: grade, in: session))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isCarriedOver ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor, in: .circle)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(WatchCard.fill, in: .rect(cornerRadius: WatchCard.cornerRadius))
            .contentShape(.rect(cornerRadius: WatchCard.cornerRadius))
        }
        .buttonStyle(TilePress())
        .disabled(isLocked)
    }
}
