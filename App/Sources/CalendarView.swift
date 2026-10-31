import Engine
import SwiftUI

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
    /// The scroll view's height, so the empty state can sit in the middle of the screen.
    @State private var viewportHeight: CGFloat = 0
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
                    // Nothing dated yet: only the empty state, with no title, month, list or filter.
                    if !allDeadlines.isEmpty {
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

                    if !allDeadlines.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            FoldingHeader(title: "Próximas fechas", isExpanded: showsList) { showList(!isListShown) }
                                .font(.title3.bold())
                                .padding(.horizontal, 4)

                            VStack(alignment: .leading, spacing: 10) {
                                if visible.isEmpty {
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

                    if allDeadlines.isEmpty {
                        ContentUnavailableView(
                            "Sin fechas todavía",
                            systemImage: "calendar.badge.plus",
                            description: Text("Pon la fecha del examen en la ficha de cada asignatura, o la de una entrega desde Editar.")
                        )
                        // Takes the rest of the screen and sits in its middle.
                        .frame(maxHeight: .infinity)
                    }
                }
                .animation(.smooth(duration: 0.4), value: showsMonth)
                .animation(.smooth(duration: 0.4), value: showsList)
                .animation(.smooth(duration: 0.3), value: selectedDay)
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !allDeadlines.isEmpty {
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

/// A calendar day as a plain value, to key days by. `DateComponents` made it flaky: two that
/// compare equal can hash differently, so lookups succeeded or failed depending on the run.
struct CalendarDay: Hashable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    var components: DateComponents { DateComponents(year: year, month: month, day: day) }
}

/// The month, drawn here rather than with `UICalendarView`, which can't show the days of the months
/// either side: they fill the first and last weeks, in a dim grey. A dot marks every day in
/// `dayKinds`, in its kind's colour; tapping a day picks it into `selection` and tapping it again
/// unpicks it (a dimmed day moves to its own month first). Swipe or the arrows change month.
private struct MonthCalendar: View {
    let dayKinds: [CalendarDay: GradeCategory]
    @Binding var selection: CalendarDay?
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    /// Which way the last change went, so the new month slides in from that side.
    @State private var step = 1

    private var calendar: Calendar { .current }

    /// "LUN", "MAR"… starting on the locale's first day of the week.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first]).map { $0.replacingOccurrences(of: ".", with: "").uppercased() }
    }

    /// Every day on screen: from the start of the week holding the 1st to the end of the one
    /// holding the last day.
    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let start = calendar.dateInterval(of: .weekOfMonth, for: interval.start)?.start,
              let end = calendar.dateInterval(of: .weekOfMonth, for: interval.end.addingTimeInterval(-1))?.end
        else { return [] }
        var days: [Date] = []
        var day = start
        while day < end, let next = calendar.date(byAdding: .day, value: 1, to: day) {
            days.append(day)
            day = next
        }
        return days
    }

    private var title: String {
        let text = month.formatted(.dateTime.month(.wide).year())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func move(_ months: Int) {
        guard let new = calendar.date(byAdding: .month, value: months, to: month) else { return }
        step = months
        withAnimation(.smooth(duration: 0.3)) { month = new }
    }

    private func tap(_ day: Date) {
        let key = CalendarDay(day, calendar: calendar)
        if !calendar.isDate(day, equalTo: month, toGranularity: .month) {
            move(day < month ? -1 : 1)
        }
        withAnimation(.snappy) { selection = selection == key ? nil : key }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 24) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .contentTransition(.numericText())
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Mes anterior")
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Mes siguiente")
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 10)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let key = CalendarDay(day, calendar: calendar)
                    DayCell(
                        date: day,
                        kind: dayKinds[key],
                        isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                        isSelected: selection == key,
                        isToday: calendar.isDateInToday(day)
                    ) { tap(day) }
                }
            }
            .id(month)
            .transition(.asymmetric(
                insertion: .move(edge: step > 0 ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: step > 0 ? .leading : .trailing).combined(with: .opacity)
            ))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .clipped()
        .contentShape(.rect)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                let width = drag.translation.width
                guard abs(width) > 50, abs(width) > abs(drag.translation.height) else { return }
                move(width < 0 ? 1 : -1)
            }
        )
    }
}

private struct DayCell: View {
    let date: Date
    let kind: GradeCategory?
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    private var numberStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color(.systemBackground)) }
        // Today stays blue even among the other month's days, just as dimmed as they are.
        if isToday { return isInMonth ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.35)) }
        if !isInMonth { return AnyShapeStyle(Color(.quaternaryLabel)) }
        return AnyShapeStyle(.primary)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.title3, design: .rounded).weight(isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberStyle)
                    .frame(width: 40, height: 40)
                    .background {
                        if isSelected { Circle().fill(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)) }
                    }
                Circle()
                    .fill(kind?.color ?? .clear)
                    .frame(width: 6, height: 6)
                    .opacity(isInMonth ? 1 : 0.3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(kind.map(\.singular) ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
