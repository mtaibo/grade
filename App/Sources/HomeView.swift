import Engine
import SwiftUI

/// The home screen: the selected course at a glance, then one card per subject with the two
/// things the brief says must be visible — the current grade and what's still needed. The course
/// is switched from the navigation title's menu.
struct HomeView: View {
    @Environment(Library.self) private var library
    /// Per-device convenience: reopen on the course last looked at.
    @AppStorage("selectedCourseID") private var selectedCourseID = ""
    @State private var editing: SubjectRecord?

    private var course: Course? {
        library.courses.first { $0.id.uuidString == selectedCourseID } ?? library.courses.first
    }

    var body: some View {
        NavigationStack {
            List {
                if let course {
                    Section {
                        TermSummary(statuses: course.subjects.map { SubjectProgress($0).status })
                    }

                    Section("Asignaturas") {
                        ForEach(course.subjects) { record in
                            NavigationLink(value: record.id) {
                                SubjectCard(record: record, progress: SubjectProgress(record))
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Editar", systemImage: "slider.horizontal.3") { editing = record }
                                    .tint(.accentColor)
                            }
                            .contextMenu {
                                Button("Editar asignatura", systemImage: "slider.horizontal.3") { editing = record }
                            }
                        }
                    }
                }
            }
            .navigationTitle(course?.name ?? "Mark")
            // Inline so the title menu's chevron shows — a large title hides the course switcher.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                Picker("Curso", selection: Binding(get: { course?.id.uuidString ?? "" }, set: { selectedCourseID = $0 })) {
                    ForEach(library.courses) { course in
                        Text(course.name).tag(course.id.uuidString)
                    }
                }
            }
            .navigationDestination(for: SubjectRecord.ID.self) { id in
                SubjectDetailView(recordID: id)
            }
            .sheet(item: $editing) { record in
                SubjectEditorView(record: record)
            }
        }
    }
}

private struct TermSummary: View {
    let statuses: [PassStatus]

    var body: some View {
        HStack(spacing: 0) {
            SummaryStat(count: statuses.count { $0 == .guaranteed }, label: "Aseguradas", tint: .green)
            Divider()
            SummaryStat(count: statuses.count { $0 == .possible }, label: "En juego", tint: .orange)
            Divider()
            SummaryStat(count: statuses.count { $0 == .impossible }, label: "Sin opción", tint: .red)
        }
        .padding(.vertical, 4)
    }
}

private struct SummaryStat: View {
    let count: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(count, format: .number)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(count > 0 ? tint : .secondary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct SubjectCard: View {
    let record: SubjectRecord
    let progress: SubjectProgress

    /// Which sitting the numbers are for, plus its exam date when there is one.
    private var sessionLine: String? {
        let date = record.examDate(for: progress.session)
        guard progress.session == .extraordinary || date != nil else { return nil }
        let label = progress.session.label
        guard let date else { return label }
        return "\(label) · examen \(date.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var tint: Color {
        guard progress.enteredCount > 0 else { return .secondary }
        return progress.status.tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.subject.name)
                        .font(.title3.weight(.semibold))
                    if let sessionLine {
                        Text(sessionLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(progress.worst, format: .number.precision(.fractionLength(1)))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(progress.enteredCount > 0 ? .primary : .tertiary)
                    .contentTransition(.numericText())
            }

            GradeRangeBar(
                worst: progress.worst,
                best: progress.enteredCount > 0 ? progress.best : 0,
                threshold: progress.threshold,
                tint: tint
            )

            StatusLine(progress: progress)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct StatusLine: View {
    let progress: SubjectProgress

    var body: some View {
        if progress.enteredCount == 0 {
            line("Sin notas todavía", icon: "circle.dashed", tint: .secondary)
        } else {
            switch progress.status {
            case .guaranteed:
                line("Aprobada", icon: "checkmark.circle.fill", tint: .green)
            case .impossible:
                line("Ya no llega al \(progress.threshold.formatted())", icon: "xmark.circle.fill", tint: .red)
            case .possible:
                if let needed = progress.neededAverage {
                    line("Necesitas un **\(needed.formatted(.number.precision(.fractionLength(1))))** en lo que falta", icon: "target", tint: .orange)
                }
            }
        }
    }

    private func line(_ text: LocalizedStringKey, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(tint)
    }
}

#Preview {
    HomeView()
        .environment(Library(fileURL: .temporaryDirectory.appending(path: "preview-library.json")))
}
