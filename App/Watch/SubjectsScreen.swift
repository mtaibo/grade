import Engine
import SwiftUI

/// The watch's home: the period's name and one tile per subject, like the iPhone's list.
struct SubjectsScreen: View {
    @Environment(WatchStore.self) private var store
    @State private var isPickingPeriod = false

    var body: some View {
        if let snapshot = store.snapshot, let period = store.period {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    header(period, degree: snapshot.degree)
                    ForEach(snapshot.subjects(in: period)) { record in
                        NavigationLink {
                            SubjectScreen(recordID: record.id, term: record.isPerTerm ? period.term.map(snapshot.degree.relativeTerm) : nil)
                        } label: {
                            SubjectTileRow(record: record, part: part(of: record, period: period, degree: snapshot.degree), rounding: snapshot.degree.rounding)
                        }
                        .buttonStyle(TilePress())
                    }
                }
                .padding(.horizontal, 4)
            }
            .sheet(isPresented: $isPickingPeriod) {
                PeriodPicker(degree: snapshot.degree)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Abre Grade en tu iPhone")
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Tus asignaturas aparecerán aquí.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func part(of record: SubjectRecord, period: Period, degree: DegreeSettings) -> Node? {
        guard record.isPerTerm, let term = period.term else { return nil }
        return PartItem.termScope(of: record, session: record.activeSession, term: degree.relativeTerm(term), termsPerYear: degree.termsPerYear)?.node
    }

    private func header(_ period: Period, degree: DegreeSettings) -> some View {
        Button {
            if store.periods.count > 1 { isPickingPeriod = true }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(period.title(in: degree))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(period.subtitle(in: degree) ?? "Final")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if store.periods.count > 1 {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }
}

/// A subject as a tile: its icon, its name and how far it's gone.
private struct SubjectTileRow: View {
    let record: SubjectRecord
    let part: Node?
    let rounding: GradeRounding

    var body: some View {
        let style = SubjectStyle(record)
        let progress = SubjectProgress(record, rounding: rounding, part: part)
        HStack(spacing: 7) {
            Image(systemName: style.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(style.tint.gradient, in: .rect(cornerRadius: 8))
            Text(record.subject.name)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if progress.isNotPresented {
                Text("NP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            } else if progress.isComplete {
                FinalGradeBadge(grade: progress.worst, hasHonors: progress.hasHonors, isCompact: true)
            } else if progress.leafCount > 0 {
                CompletionRing(entered: progress.enteredCount, total: progress.leafCount)
                    .scaleEffect(0.72)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 50)
        .background(WatchCard.fill, in: .rect(cornerRadius: WatchCard.cornerRadius))
        .contentShape(.rect(cornerRadius: WatchCard.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// The periods with subjects, by year, like the iPhone's switcher.
private struct PeriodPicker: View {
    let degree: DegreeSettings

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let years = Dictionary(grouping: store.periods, by: \.year)
        List {
            ForEach(years.keys.sorted(), id: \.self) { year in
                Section(degree.yearLabel(year)) {
                    ForEach(years[year] ?? [], id: \.self) { period in
                        Button {
                            store.pickedPeriod = period
                            dismiss()
                        } label: {
                            HStack {
                                Text(period.subtitle(in: degree) ?? "Final")
                                Spacer()
                                if period == store.period {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The watch's version of the iPhone's raised cards.
enum WatchCard {
    static let cornerRadius: CGFloat = 16
    static let fill = Color.white.opacity(0.13)
}

/// Tiles give a little under the finger, like on the iPhone.
struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
