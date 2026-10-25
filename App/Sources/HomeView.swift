import Engine
import SwiftUI

/// The home screen: the selected course at a glance, then one card per subject with the two
/// things the brief says must be visible — the current grade and what's still needed. The course
/// is switched from the chips under the title.
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
                if library.courses.count > 1 {
                    CoursePicker(courses: library.courses, selection: Binding(
                        get: { course?.id },
                        set: { selectedCourseID = $0?.uuidString ?? "" }
                    ))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if let course, !course.subjects.isEmpty {
                    Section {
                        TermSummary(statuses: course.subjects.map { SubjectProgress($0).status })
                    } header: {
                        Text("Cómo va el curso")
                    }

                    Section {
                        ForEach(course.subjects) { record in
                            NavigationLink(value: record.id) {
                                SubjectCard(record: record, progress: SubjectProgress(record))
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Editar", systemImage: "slider.horizontal.3") { editing = record }
                                    .tint(.accentColor)
                            }
                            .contextMenu {
                                Button("Editar evaluación", systemImage: "slider.horizontal.3") { editing = record }
                            }
                        }
                    } header: {
                        Text("Asignaturas")
                    } footer: {
                        Text("Toca una asignatura para poner tus notas. Desliza a la izquierda para cambiar cómo se evalúa.")
                    }
                }
            }
            .overlay {
                if course?.subjects.isEmpty ?? true {
                    ContentUnavailableView(
                        "Sin asignaturas",
                        systemImage: "books.vertical",
                        description: Text("Puedes recuperar las de ejemplo desde Ajustes.")
                    )
                }
            }
            .navigationTitle(course?.name ?? "Asignaturas")
            .navigationDestination(for: SubjectRecord.ID.self) { id in
                SubjectDetailView(recordID: id)
            }
            .sheet(item: $editing) { record in
                SubjectEditorView(record: record)
            }
        }
    }
}

/// The courses as a row of chips under the title, so switching course is visible at a glance
/// instead of hidden in the title's menu.
private struct CoursePicker: View {
    let courses: [Course]
    @Binding var selection: Course.ID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(courses) { course in
                    let isSelected = course.id == selection
                    Button {
                        withAnimation(.snappy) { selection = course.id }
                    } label: {
                        Text(course.name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct TermSummary: View {
    let statuses: [PassStatus]

    var body: some View {
        HStack(spacing: 0) {
            SummaryStat(count: statuses.count { $0 == .guaranteed }, label: "Aprobadas", tint: .green)
            Divider()
            SummaryStat(count: statuses.count { $0 == .possible }, label: "En juego", tint: .orange)
            Divider()
            SummaryStat(count: statuses.count { $0 == .impossible }, label: "No llegan", tint: .red)
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
                VStack(alignment: .trailing, spacing: 0) {
                    SwiftUI.Group {
                        if progress.enteredCount > 0 {
                            Text(progress.worst, format: .number.precision(.fractionLength(1)))
                        } else {
                            Text("—")
                        }
                    }
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(progress.enteredCount > 0 ? .primary : .tertiary)
                    .contentTransition(.numericText())
                    Text("de 10")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            line("Sin notas todavía · toca para empezar", icon: "circle.dashed", tint: .secondary)
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
