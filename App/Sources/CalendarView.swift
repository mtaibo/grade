import Engine
import SwiftUI
import UIKit

/// A dated grade somewhere in the library — a lab hand-in, an assignment, an exam.
struct Deadline: Identifiable {
    let recordID: SubjectRecord.ID
    let subjectName: String
    let leafName: String
    let date: Date
    let kind: GradeCategory
    /// The subject's own icon and colour.
    let symbol: String
    let tint: Color
    /// The grade already entered for it, converted to its own scale, if any.
    let grade: Double?
    let scaleMax: Double

    var id: String { "\(recordID.uuidString)/\(leafName)" }
}

extension GradeCategory {
    var title: String {
        switch self {
        case .work: "Trabajos"
        case .quiz: "Controles"
        case .exam: "Exámenes"
        }
    }

    var singular: String {
        switch self {
        case .work: "Trabajo"
        case .quiz: "Control"
        case .exam: "Examen"
        }
    }

    var color: Color {
        switch self {
        case .work: .blue
        case .quiz: .orange
        case .exam: .red
        }
    }

    /// When several things fall on one day, the calendar dot takes the most important one's colour.
    var priority: Int {
        switch self {
        case .exam: 2
        case .quiz: 1
        case .work: 0
        }
    }
}

extension Library {
    var deadlines: [Deadline] {
        courses.flatMap(\.subjects).flatMap { record in
            let inputs = SubjectProgress.inputs(record, session: .ordinary)
            let style = SubjectStyle(record)
            let parts = record.subject.root.datedGrades.filter { record.subject.root.leaf(named: $0.name)?.asGrade?.isFinalExam != true }.map { item in
                let grade = record.subject.root.leaf(named: item.name)?.asGrade
                return Deadline(
                    recordID: record.id,
                    subjectName: record.subject.name,
                    leafName: item.name,
                    date: item.date,
                    kind: grade?.kind ?? .work,
                    symbol: style.symbol,
                    tint: style.tint,
                    grade: inputs[item.name],
                    scaleMax: grade?.scaleMax ?? 10
                )
            }
            let exams = Convocatoria.allCases.compactMap { session in
                record.examDate(for: session).map { date in
                    Deadline(recordID: record.id, subjectName: record.subject.name, leafName: "\(record.subject.root.examTitle ?? "Examen") · \(session.label)", date: date, kind: .exam, symbol: style.symbol, tint: style.tint, grade: nil, scaleMax: 10)
                }
            }
            return parts + exams
        }
        .sorted { $0.date < $1.date }
    }
}

/// "Calendario": a compact month with a coloured dot on every day something is due, and below it the
/// next three things (or the selected day's). The filter at the top right picks which kinds show.
struct CalendarView: View {
    @Environment(Library.self) private var library
    @State private var selectedDay: CalendarDay?
    @State private var isFiltering = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 40
    /// Per-device: which kinds are shown, stored as their raw values.
    @AppStorage("calendarKinds") private var storedKinds = GradeCategory.allCases.map(\.rawValue).joined(separator: ",")

    private var calendar: Calendar { .current }

    private var shownKinds: Set<GradeCategory> {
        Set(storedKinds.split(separator: ",").compactMap { GradeCategory(rawValue: String($0)) })
    }

    private var isFiltered: Bool { shownKinds.count < GradeCategory.allCases.count }

    /// The kind whose colour each marked day's dot takes.
    private func dayKinds(_ deadlines: [Deadline]) -> [CalendarDay: GradeCategory] {
        deadlines.reduce(into: [:]) { result, deadline in
            let day = CalendarDay(deadline.date, calendar: calendar)
            if let current = result[day], current.priority >= deadline.kind.priority { return }
            result[day] = deadline.kind
        }
    }

    private func visible(_ deadlines: [Deadline]) -> [Deadline] {
        if let selectedDay {
            return deadlines.filter { CalendarDay($0.date, calendar: calendar) == selectedDay }
        }
        let today = calendar.startOfDay(for: .now)
        return Array(deadlines.filter { $0.date >= today }.prefix(3))
    }

    private var listTitle: String {
        if let selectedDay, let day = calendar.date(from: selectedDay.components) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return "Próximas fechas"
    }

    private func toggle(_ kind: GradeCategory) {
        var kinds = shownKinds
        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
        storedKinds = GradeCategory.allCases.filter(kinds.contains).map(\.rawValue).joined(separator: ",")
    }

    var body: some View {
        // Worked out once per redraw: every subject's grades go into it.
        let allDeadlines = library.deadlines
        let shownKinds = shownKinds
        let deadlines = allDeadlines.filter { shownKinds.contains($0.kind) }
        let visible = visible(deadlines)
        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Calendario")
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)

                    MonthCalendar(dayKinds: dayKinds(deadlines), selection: $selectedDay)
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity)
                        .card(padding: 4)
                        .tourTarget("calendar.month")
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(listTitle)
                                .font(.title3.bold())
                            Spacer()
                            if selectedDay != nil {
                                Button("Ver próximas") { selectedDay = nil }
                                    .font(.subheadline)
                            }
                        }
                        .padding(.horizontal, 4)

                        if allDeadlines.isEmpty {
                            ContentUnavailableView(
                                "Sin fechas todavía",
                                systemImage: "calendar.badge.plus",
                                description: Text("Pon la fecha del examen en la ficha de cada asignatura, o la de una entrega desde Editar.")
                            )
                        } else if visible.isEmpty {
                            Text(selectedDay != nil ? "Nada este día." : isFiltered && deadlines.isEmpty ? "Nada con estos filtros." : "No queda nada pendiente. 🎉")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        } else {
                            ForEach(visible) { deadline in
                                NavigationLink(value: deadline.recordID) {
                                    DeadlineRow(deadline: deadline)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .tourTarget("calendar.list")
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isFiltering = true
                    } label: {
                        Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    }
                    .accessibilityLabel("Filtrar")
                    .popover(isPresented: $isFiltering) {
                        KindFilter(shown: shownKinds, toggle: toggle)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .navigationDestination(for: SubjectRecord.ID.self) { id in
                SubjectDetailView(recordID: id)
            }
        }
    }
}

/// The filter's list: a coloured dot per kind, tapped on and off.
private struct KindFilter: View {
    let shown: Set<GradeCategory>
    let toggle: (GradeCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(GradeCategory.allCases, id: \.self) { kind in
                Button { toggle(kind) } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(kind.color)
                            .frame(width: 12, height: 12)
                        Text(kind.title)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 24)
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .opacity(shown.contains(kind) ? 1 : 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(shown.contains(kind) ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 210)
    }
}

private struct DeadlineRow: View {
    let deadline: Deadline

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: deadline.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(deadline.tint.gradient, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(deadline.kind.color)
                        .frame(width: 9, height: 9)
                    Text(deadline.leafName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                Text(deadline.subjectName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            trailing
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deadline.kind.singular): \(deadline.leafName), \(deadline.subjectName)")
    }

    @ViewBuilder
    private var trailing: some View {
        if let grade = deadline.grade {
            VStack(alignment: .trailing, spacing: 2) {
                Text(grade, format: .number.precision(.fractionLength(0...2)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                Text("sobre \(deadline.scaleMax.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(RelativeDay(deadline.date).label)
                    .font(.subheadline)
                    .foregroundStyle(RelativeDay(deadline.date).isOverdue ? .red : .secondary)
                Text(deadline.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// "Hoy", "Mañana", "En 3 días", "Hace 2 días" — counted in calendar days, not 24h periods.
private struct RelativeDay {
    let days: Int

    init(_ date: Date, calendar: Calendar = .current) {
        days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    var isOverdue: Bool { days < 0 }

    var label: String {
        switch days {
        case 0: "Hoy"
        case 1: "Mañana"
        case 2...: "En \(days) días"
        case -1: "Ayer"
        default: "Hace \(-days) días"
        }
    }
}

/// A calendar day as a plain value. `DateComponents` can't be used as a `Set` key here: the ones
/// UIKit hands back and the ones built from a `Date` compare equal but can hash differently, so
/// lookups would succeed or fail depending on the run.
struct CalendarDay: Hashable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    init?(_ components: DateComponents) {
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    var components: DateComponents { DateComponents(year: year, month: month, day: day) }
}

/// UIKit's month calendar, since SwiftUI has no equivalent that can mark days: a dot on every day
/// in `dayKinds`, in its kind's colour, with single-day selection bound to `selection`.
private struct MonthCalendar: UIViewRepresentable {
    let dayKinds: [CalendarDay: GradeCategory]
    @Binding var selection: CalendarDay?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = .current
        view.locale = .current
        view.fontDesign = .rounded
        view.delegate = context.coordinator
        view.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let previous = context.coordinator.parent.dayKinds
        context.coordinator.parent = self
        let changed = Set(previous.keys).union(dayKinds.keys).filter { previous[$0] != dayKinds[$0] }
        if !changed.isEmpty {
            view.reloadDecorations(forDateComponents: changed.map(\.components), animated: true)
        }
        let selectionBehavior = view.selectionBehavior as? UICalendarSelectionSingleDate
        if selectionBehavior?.selectedDate.flatMap(CalendarDay.init) != selection {
            selectionBehavior?.setSelected(selection?.components, animated: true)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: size.height)
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: MonthCalendar

        init(parent: MonthCalendar) {
            self.parent = parent
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let day = CalendarDay(dateComponents), let kind = parent.dayKinds[day] else { return nil }
            return .default(color: UIColor(kind.color), size: .medium)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            parent.selection = dateComponents.flatMap(CalendarDay.init)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            true
        }
    }
}
