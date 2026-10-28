import Engine
import SwiftUI

/// How the subjects are laid out on the home screen: big cards in a grid, or one slim row each.
enum SubjectLayout: String, CaseIterable, Identifiable {
    case cards, list

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .cards: "Cuadrícula"
        case .list: "Lista"
        }
    }

    var icon: String {
        switch self {
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

/// The home screen: the year and term as a big title, then one large card per subject — just the
/// name. Everything else lives inside the subject.
struct HomeView: View {
    @Environment(Library.self) private var library
    /// Per-device conveniences: reopen on the period last looked at, in the layout last chosen.
    @AppStorage("selectedYear") private var selectedYear = 0
    @AppStorage("selectedTerm") private var selectedTerm = 0
    @AppStorage("subjectLayout") private var layout = SubjectLayout.cards
    /// The custom view on screen, by id; empty when showing one of the degree's periods.
    @AppStorage("selectedCustomView") private var selectedCustomView = ""
    @State private var isChoosingView = false

    @State private var placement: SubjectPlacement?
    @State private var editing: SubjectRecord?
    @State private var customizing: SubjectRecord?
    @ScaledMetric(relativeTo: .largeTitle) private var yearSize = 32
    @ScaledMetric(relativeTo: .title) private var termSize = 24
    @State private var deleting: SubjectRecord?
    /// The "jiggle" mode: tiles wobble, can be dragged into a new order, and the gap after the
    /// last one offers a + to add a subject.
    @State private var isEditing = false
    @State private var viewportHeight: CGFloat = 0
    /// The "hold the background" tip: only shown after tapping the background itself.
    @State private var isShowingHint = false
    @State private var hintTask: Task<Void, Never>?

    /// Every period that has subjects, oldest first. A year with only year-long subjects is a
    /// period of its own.
    private var periods: [Period] {
        var result: [Period] = []
        for course in library.courses {
            let terms = Set(course.subjects.compactMap(\.term)).sorted()
            if terms.isEmpty {
                if !course.subjects.isEmpty { result.append(Period(year: course.year)) }
            } else {
                result += terms.map { Period(year: course.year, term: $0) }
            }
        }
        return result.sorted { ($0.year, $0.term ?? 0) < ($1.year, $1.term ?? 0) }
    }

    private func showHint() {
        isShowingHint = true
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { isShowingHint = false }
        }
    }

    private var period: Period {
        let stored = Period(year: selectedYear, term: selectedTerm == 0 ? nil : selectedTerm)
        return periods.contains(stored) ? stored : periods.first ?? Period(year: 1, term: 1)
    }

    /// The custom view on screen, if one is selected and still exists.
    private var customSelection: CustomSelection? {
        guard let id = UUID(uuidString: selectedCustomView) else { return nil }
        return library.selections.first { $0.id == id }
    }

    private var currentSelection: HomeSelection {
        customSelection.map { .custom($0.id) } ?? .period(period)
    }

    /// Where "Añadir asignatura" starts: the period on screen, or for a custom view the one its
    /// title names (picked by hand, or its furthest subject's).
    private var newSubjectPeriod: Period {
        guard let customSelection else { return period }
        if case .period(let year, let term) = customSelection.title { return Period(year: year, term: term) }
        return library.furthestPeriod(of: customSelection.subjectIDs) ?? period
    }

    private var customSubjects: [SubjectRecord] {
        customSelection?.subjectIDs.compactMap(library.record(id:)) ?? []
    }

    private var yearSubjects: [SubjectRecord] {
        library.courses.first { $0.year == period.year }?.subjects ?? []
    }

    private var termSubjects: [SubjectRecord] { yearSubjects.filter { $0.term == period.term } }

    /// Year-long subjects, listed under the term's own when one is selected.
    private var yearLongSubjects: [SubjectRecord] {
        period.term == nil ? [] : yearSubjects.filter { $0.term == nil }
    }

    private var columns: [GridItem] {
        layout == .list ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if periods.isEmpty {
                    EmptyHome { placement = .create(period) }
                        .padding(.top, 80)
                } else {
                    VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        if let customSelection {
                            if customSubjects.isEmpty {
                                ContentUnavailableView {
                                    Label("Vista vacía", systemImage: "rectangle.dashed")
                                } description: {
                                    Text("Sus asignaturas se han borrado. Elige otras o cambia de vista.")
                                } actions: {
                                    Button("Editar vistas") { isChoosingView = true }
                                }
                            } else {
                                grid(customSubjects, in: customSelection)
                            }
                        } else {
                            grid(termSubjects, canAdd: true)
                        }
                        if customSelection == nil, !yearLongSubjects.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Todo el año")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.leading, 4)
                                grid(yearLongSubjects)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)

                    }
                    // Fills the screen so a tap on the empty space can end editing.
                    .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
                    .background {
                        if isEditing {
                            Color.clear
                                .contentShape(.rect)
                                .onTapGesture { isEditing = false }
                        } else {
                            LongPressBackground(onTap: showHint) { isEditing = true }
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .overlay(alignment: .bottom) {
                if isShowingHint && !isEditing {
                    Text("Mantén pulsado el fondo para reordenar o añadir asignaturas")
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sensoryFeedback(.impact, trigger: isEditing)
            .animation(.snappy, value: isEditing)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: SubjectRecord.ID.self) { id in
                SubjectDetailView(recordID: id)
            }
            .navigationDestination(isPresented: $isChoosingView) {
                HomeViewsScreen(periods: periods, current: currentSelection) { selection in
                    withAnimation(.snappy) {
                        switch selection {
                        case .period(let period): select(period)
                        case .custom(let id): selectedCustomView = id.uuidString
                        }
                    }
                }
            }
            .sheet(item: $placement) { placement in
                NewSubjectView(placement: placement, degree: library.degree) { saved, id in
                    // A subject created from a custom view joins it.
                    if case .create = placement, var selection = customSelection {
                        selection.subjectIDs.append(id)
                        library.saveSelection(selection)
                    }
                    show(saved)
                }
            }
            .sheet(item: $editing) { record in
                SubjectEditorView(record: record)
            }
            .sheet(item: $customizing) { record in
                CustomizeSubjectView(record: record)
            }
            .alert(
                "¿Eliminar \(deleting?.subject.name ?? "la asignatura")?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
            ) {
                Button("Cancelar", role: .cancel) { deleting = nil }
                Button("Eliminar", role: .destructive) {
                    if let deleting { library.deleteSubject(id: deleting.id) }
                    deleting = nil
                }
            } message: {
                Text("Se borran también sus notas y fechas. No se puede deshacer.")
            }
        }
    }

    /// The year and term as the screen's title, big enough to read at a glance.
    private var header: some View {
        let heading: (title: String, subtitle: String?) = customSelection.map(library.heading(for:))
            ?? (period.title, period.subtitle(in: library.degree))
        return VStack(alignment: .leading, spacing: 0) {
            Text(heading.title)
                .font(.system(size: yearSize, weight: .bold, design: .rounded))
            if let subtitle = heading.subtitle {
                Text(subtitle)
                    .font(.system(size: termSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// `selection` set for a custom view: dragging reorders the view itself, not the subjects'
    /// years, and there's no + (subjects are added to a view from "Vista").
    private func grid(_ records: [SubjectRecord], canAdd: Bool = false, in selection: CustomSelection? = nil) -> some View {
        let ids = records.map(\.id)
        return ReorderableGrid(
            records: records,
            isEditing: isEditing,
            columns: columns,
            isCompact: layout == .list,
            commit: { order in
                if let selection {
                    let rest = selection.subjectIDs.filter { !ids.contains($0) }
                    library.reorderSelection(selection.id, to: order + rest)
                } else {
                    library.reorderSubjects(order, before: nil, among: ids)
                }
            },
            onDelete: { deleting = $0 },
            normal: { record in
                NavigationLink(value: record.id) {
                    SubjectTile(record: record, isCompact: layout == .list)
                }
                .buttonStyle(TilePressStyle())
                .contextMenu {
                    Button("Personalizar", systemImage: "paintpalette") { customizing = record }
                    Button("Mover", systemImage: "arrow.right.circle") {
                        placement = .move(record.id, name: record.subject.name, from: library.period(of: record.id) ?? Period(year: period.year, term: record.term))
                    }
                    Button("Editar evaluación", systemImage: "slider.horizontal.3") { editing = record }
                    Divider()
                    Button("Eliminar", systemImage: "trash", role: .destructive) { deleting = record }
                }
            },
            trailing: {
                if canAdd {
                    AddTile(isCompact: layout == .list) { placement = .create(newSubjectPeriod) }
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Listo") { isEditing = false }
                    .fontWeight(.semibold)
            }
        } else {
            if periods.count + library.selections.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        viewSwitcher
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Cambiar de vista")
                }
                // Keeps the two buttons as separate glass capsules instead of one joined pill.
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Diseño", selection: $layout) {
                        ForEach(SubjectLayout.allCases) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Añadir asignatura", systemImage: "plus") { placement = .create(newSubjectPeriod) }
                    Button("Editar vistas", systemImage: "rectangle.stack") { isChoosingView = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Más opciones")
            }
        }
    }

    /// The calendar button's menu: a quick jump to any period or custom view, ✓ on the current one.
    /// Views are created and changed from "Editar vistas".
    @ViewBuilder
    private var viewSwitcher: some View {
        ForEach(Dictionary(grouping: periods, by: \.year).sorted { $0.key < $1.key }, id: \.key) { year, options in
            Section(Period(year: year).title) {
                ForEach(options, id: \.self) { option in
                    switcherButton(option.term.map(library.degree.termLabel) ?? "Todo el año", isCurrent: currentSelection == .period(option)) {
                        select(option)
                    }
                }
            }
        }
        if !library.selections.isEmpty {
            Section("Personalizadas") {
                ForEach(library.selections) { selection in
                    let heading = library.heading(for: selection)
                    switcherButton([heading.title, heading.subtitle].compactMap { $0 }.joined(separator: " · "), isCurrent: currentSelection == .custom(selection.id)) {
                        selectedCustomView = selection.id.uuidString
                    }
                }
            }
        }
    }

    private func switcherButton(_ title: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy, action)
        } label: {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func select(_ period: Period) {
        selectedCustomView = ""
        selectedYear = period.year
        selectedTerm = period.term ?? 0
    }

    /// After adding or moving a subject, follow it — a year-long one shows in the year's first term.
    /// Not while a custom view is on screen: the subject stays in it wherever it moved.
    private func show(_ saved: Period) {
        guard customSelection == nil else { return }
        select(saved.term == nil ? periods.first { $0.year == saved.year } ?? saved : saved)
    }
}

/// One subject: a decorative icon and its name, with a small ring in the corner that fills as
/// its grades are entered.
struct SubjectTile: View {
    let name: String
    let symbol: String
    let tint: Color
    /// Grades entered and grades in total, recomputed from the subject each time. `nil` hides the ring.
    let count: (entered: Int, total: Int)?
    /// The subject's grade once every grade is in; it takes the ring's place.
    let finalGrade: Double?
    /// A slim row (icon, name, ring) instead of the tall card, for the list view.
    var isCompact = false

    init(record: SubjectRecord, isCompact: Bool = false) {
        let style = SubjectStyle(record)
        let progress = SubjectProgress(record)
        self.init(
            name: record.subject.name, symbol: style.symbol, tint: style.tint,
            count: (progress.enteredCount, progress.leafCount),
            finalGrade: progress.isComplete ? progress.worst : nil
        )
        self.isCompact = isCompact
    }

    init(name: String, symbol: String, tint: Color, count: (entered: Int, total: Int)? = nil, finalGrade: Double? = nil) {
        self.name = name
        self.symbol = symbol
        self.tint = tint
        self.count = count
        self.finalGrade = finalGrade
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(tint.gradient, in: .rect(cornerRadius: 11))
    }

    @ViewBuilder
    private var indicator: some View {
        if let finalGrade {
            FinalGradeBadge(grade: finalGrade)
        } else if let count, count.total > 0 {
            CompletionRing(entered: count.entered, total: count.total)
        }
    }

    var body: some View {
        Group {
            if isCompact {
                HStack(spacing: 14) {
                    icon
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    indicator
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 68)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                .contentShape(.rect(cornerRadius: 18))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    icon
                    Spacer(minLength: 10)
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .frame(height: 156)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
                .overlay(alignment: .topTrailing) {
                    indicator.padding(15)
                }
                .contentShape(.rect(cornerRadius: 22))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The final grade, in the colour of its band, once the ring would be full.
private struct FinalGradeBadge: View {
    let grade: Double

    var body: some View {
        let tint = GradeBand.color(for: grade)
        Text(grade, format: .number.precision(.fractionLength(0...2)))
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(tint == .yellow ? Color.orange : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .accessibilityLabel("Nota final \(grade.formatted(.number.precision(.fractionLength(0...2))))")
    }
}

/// A small circle that fills as grades are entered.
private struct CompletionRing: View {
    let entered: Int
    let total: Int

    private var fraction: Double { min(Double(entered) / Double(max(total, 1)), 1) }
    private var isComplete: Bool { entered >= total }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isComplete ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 28, height: 28)
        .animation(.snappy, value: fraction)
        .accessibilityLabel("\(entered) de \(total) notas")
    }
}

/// The blue round + that fills the gap after the last subject while editing.
private struct AddTile: View {
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: isCompact ? 44 : 56, height: isCompact ? 44 : 56)
                .background(Color.accentColor, in: .circle)
                .frame(maxWidth: .infinity, minHeight: isCompact ? 68 : 156)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityLabel("Añadir asignatura")
    }
}

struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

private struct EmptyHome: View {
    let add: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Sin asignaturas", systemImage: "books.vertical")
        } description: {
            Text("Añade las de este cuatrimestre o carga una plantilla desde la pestaña Cuenta.")
        } actions: {
            Button("Añadir asignatura", action: add)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    HomeView()
        .environment(Library(fileURL: .temporaryDirectory.appending(path: "preview-library.json")))
}
