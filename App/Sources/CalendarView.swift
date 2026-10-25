import Engine
import SwiftUI
import UIKit

/// A dated grade somewhere in the library — a lab hand-in, an assignment, an exam.
struct Deadline: Identifiable {
    let recordID: SubjectRecord.ID
    let subjectName: String
    let leafName: String
    let date: Date
    /// The grade already entered for it, converted to its own scale, if any.
    let grade: Double?
    let scaleMax: Double

    var id: String { "\(recordID.uuidString)/\(leafName)" }
}

extension Library {
    var deadlines: [Deadline] {
        courses.flatMap(\.subjects).flatMap { record in
            let progress = SubjectProgress(record, session: .ordinary)
            let parts = record.subject.root.datedGrades.map { item in
                Deadline(
                    recordID: record.id,
                    subjectName: record.subject.name,
                    leafName: item.name,
                    date: item.date,
                    grade: progress.inputs[item.name],
                    scaleMax: record.subject.root.leaf(named: item.name)?.scaleMax ?? 10
                )
            }
            let exams = Convocatoria.allCases.compactMap { session in
                record.examDate(for: session).map { date in
                    Deadline(recordID: record.id, subjectName: record.subject.name, leafName: "Examen · \(session.label)", date: date, grade: nil, scaleMax: 10)
                }
            }
            return parts + exams
        }
        .sorted { $0.date < $1.date }
    }
}

/// "Calendario": a month view with a dot on every day something is due, and below it either the
/// selected day's deadlines or everything still to come.
struct CalendarView: View {
    @Environment(Library.self) private var library
    @State private var selectedDay: CalendarDay?

    private var calendar: Calendar { .current }

    private var deadlines: [Deadline] { library.deadlines }

    private var markedDays: Set<CalendarDay> {
        Set(deadlines.map { CalendarDay($0.date, calendar: calendar) })
    }

    private var visible: [Deadline] {
        if let selectedDay {
            return deadlines.filter { CalendarDay($0.date, calendar: calendar) == selectedDay }
        }
        let today = calendar.startOfDay(for: .now)
        return deadlines.filter { $0.date >= today }
    }

    private var listTitle: String {
        if let selectedDay, let day = calendar.date(from: selectedDay.components) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return "Próximas fechas"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthCalendar(markedDays: markedDays, selection: $selectedDay)
                }

                Section {
                    if deadlines.isEmpty {
                        ContentUnavailableView(
                            "Sin fechas todavía",
                            systemImage: "calendar.badge.plus",
                            description: Text("Pon la fecha del examen en la ficha de cada asignatura, o la de una entrega desde Editar.")
                        )
                    } else if visible.isEmpty {
                        Text(selectedDay == nil ? "No queda nada pendiente. 🎉" : "Nada este día.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visible) { deadline in
                            NavigationLink(value: deadline.recordID) {
                                DeadlineRow(deadline: deadline)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(listTitle)
                        Spacer()
                        if selectedDay != nil {
                            Button("Ver todas") { selectedDay = nil }
                                .font(.subheadline)
                                .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Calendario")
            .navigationDestination(for: SubjectRecord.ID.self) { id in
                SubjectDetailView(recordID: id)
            }
        }
    }
}

private struct DeadlineRow: View {
    let deadline: Deadline

    var body: some View {
        HStack(spacing: 14) {
            DayBadge(date: deadline.date)
            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.leafName)
                    .font(.headline)
                Text(deadline.subjectName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        if let grade = deadline.grade {
            VStack(alignment: .trailing, spacing: 2) {
                Text(grade, format: .number.precision(.fractionLength(0...2)))
                    .font(.headline.monospacedDigit())
                Text("sobre \(deadline.scaleMax.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(RelativeDay(deadline.date).label)
                .font(.subheadline)
                .foregroundStyle(RelativeDay(deadline.date).isOverdue ? .red : .secondary)
        }
    }
}

private struct DayBadge: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.month(.abbreviated))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.red)
            Text(date, format: .dateTime.day())
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: 44, height: 44)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
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

/// UIKit's month calendar, since SwiftUI has no equivalent that can mark days: a dot on every
/// day in `markedDays`, single-day selection bound to `selection` (cleared from "Ver todas").
private struct MonthCalendar: UIViewRepresentable {
    let markedDays: Set<CalendarDay>
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
        let previous = context.coordinator.parent.markedDays
        context.coordinator.parent = self
        let changed = previous.symmetricDifference(markedDays)
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
            guard let day = CalendarDay(dateComponents), parent.markedDays.contains(day) else { return nil }
            return .default(color: .systemOrange, size: .medium)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            parent.selection = dateComponents.flatMap(CalendarDay.init)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            true
        }
    }
}
