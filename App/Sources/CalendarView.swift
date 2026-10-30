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
/// next six things, three more at a time with "Ver más". It opens on the list alone: unfolding the
/// month (from the chevron by its title) folds the list, and a day picked on it shows that day's
/// dates above the list. The filter at the top right picks which kinds show.
struct CalendarView: View {
    /// Whether the Calendario tab is the one on screen: leaving it puts "Ver más" back to the start.
    let isCurrentTab: Bool
    @Environment(Library.self) private var library
    @Environment(Tour.self) private var tour: Tour?
    @State private var selectedDay: CalendarDay?
    @State private var isFiltering = false
    /// How many upcoming dates the list shows; "Ver más" adds `pageSize` more.
    @State private var upcomingCount = CalendarView.initialCount
    @State private var isMonthShown = false
    @State private var isListShown = true
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 40
    /// Per-device: which kinds are shown, stored as their raw values.
    @AppStorage("calendarKinds") private var storedKinds = GradeCategory.allCases.map(\.rawValue).joined(separator: ",")

    private static let initialCount = 6
    private static let pageSize = 3

    private var calendar: Calendar { .current }

    /// The tour points at the month and the list, so it unfolds them while it does.
    private var showsMonth: Bool { isMonthShown || tour?.current?.target == "calendar.month" }
    private var showsList: Bool { isListShown || tour?.current?.target == "calendar.list" }

    private func upcoming(_ deadlines: [Deadline]) -> [Deadline] {
        let today = calendar.startOfDay(for: .now)
        return deadlines.filter { $0.date >= today }
    }

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

    private func title(of day: CalendarDay) -> String {
        calendar.date(from: day.components)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? ""
    }

    /// The month and the list take turns: one opens as the other folds, from either chevron. A day
    /// picked on the month goes when the month does, and a folded list starts again from the first
    /// few, once it's out of sight so the fold doesn't jump.
    private func showList(_ shown: Bool) {
        withAnimation(.smooth(duration: 0.4)) {
            isListShown = shown
            isMonthShown = !shown
            if shown { selectedDay = nil }
        } completion: {
            if !isListShown { upcomingCount = Self.initialCount }
        }
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
        let upcoming = upcoming(deadlines)
        let visible = Array(upcoming.prefix(upcomingCount))
        let hasMore = upcoming.count > visible.count
        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 0) {
                        FoldingHeader(title: "Calendario", isExpanded: showsMonth) { showList(isMonthShown) }
                            .font(.system(size: titleSize, weight: .bold, design: .rounded))
                            .padding(.leading, 4)

                        MonthCalendar(dayKinds: dayKinds(deadlines), selection: $selectedDay)
                            .frame(maxWidth: 320)
                            .frame(maxWidth: .infinity)
                            .card(padding: 4)
                            .tourTarget("calendar.month")
                            .padding(.top, 28)
                            .folded(!showsMonth)
                    }

                    if let day = selectedDay {
                        let dayDeadlines = deadlines.filter { CalendarDay($0.date, calendar: calendar) == day }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(title(of: day))
                                    .font(.title3.bold())
                                    .accessibilityAddTraits(.isHeader)
                                Spacer()
                                Button { selectedDay = nil } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Quitar el día")
                            }
                            .padding(.horizontal, 4)

                            if dayDeadlines.isEmpty {
                                Text("Nada este día.")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            } else {
                                ForEach(dayDeadlines) { deadline in
                                    NavigationLink(value: deadline.recordID) {
                                        DeadlineRow(deadline: deadline)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        FoldingHeader(title: "Próximas fechas", isExpanded: showsList) { showList(!isListShown) }
                            .font(.title3.bold())
                            .padding(.horizontal, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            if allDeadlines.isEmpty {
                                ContentUnavailableView(
                                    "Sin fechas todavía",
                                    systemImage: "calendar.badge.plus",
                                    description: Text("Pon la fecha del examen en la ficha de cada asignatura, o la de una entrega desde Editar.")
                                )
                            } else if visible.isEmpty {
                                Text(isFiltered && deadlines.isEmpty ? "Nada con estos filtros." : "No queda nada pendiente. 🎉")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            } else {
                                ForEach(visible) { deadline in
                                    NavigationLink(value: deadline.recordID) {
                                        DeadlineRow(deadline: deadline)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if hasMore {
                                    Button {
                                        withAnimation { upcomingCount += Self.pageSize }
                                    } label: {
                                        Label("Ver más", systemImage: "chevron.down")
                                            .labelStyle(TrailingIconLabelStyle())
                                            .font(.subheadline.weight(.medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                }
                            }
                        }
                        .folded(!showsList)
                    }
                    .tourTarget("calendar.list")
                }
                .animation(.smooth(duration: 0.4), value: showsMonth)
                .animation(.smooth(duration: 0.4), value: showsList)
                .animation(.smooth(duration: 0.3), value: selectedDay)
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
            .onChange(of: isCurrentTab) {
                if !isCurrentTab { upcomingCount = Self.initialCount }
            }
        }
    }
}

/// A section title with a chevron right after it that folds the section away: up while it's
/// shown, down while it's folded, like the expandable cards in a subject. Takes its font from the environment.
private struct FoldingHeader: View {
    let title: String
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Mostrado" : "Oculto")
        .accessibilityHint(isExpanded ? "Toca para ocultar" : "Toca para mostrar")
    }
}

extension View {
    /// Shrinks the view to nothing from the bottom up, fading as it goes, instead of removing it:
    /// the month keeps its state (the month it's on, the selected day) and isn't rebuilt each time,
    /// and what's below slides up with its bottom edge.
    func folded(_ isFolded: Bool) -> some View {
        modifier(Folded(isFolded: isFolded))
    }
}

private struct Folded: ViewModifier {
    let isFolded: Bool
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .opacity(isFolded ? 0 : 1)
            .scaleEffect(isFolded ? 0.96 : 1, anchor: .top)
            .frame(height: isFolded ? 0 : height, alignment: .top)
            .clipped()
            .allowsHitTesting(!isFolded)
            .accessibilityHidden(isFolded)
    }
}

/// The icon after the title, as in "Ver más ⌄".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon
                .font(.caption.weight(.bold))
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

        /// UIKit has no way to unpick a day; tapping the picked one again does it here.
        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            guard let day = dateComponents.flatMap(CalendarDay.init), day == parent.selection else { return true }
            selection.setSelected(nil, animated: true)
            parent.selection = nil
            return false
        }
    }
}
