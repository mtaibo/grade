import Engine
import SwiftUI

/// Cuenta → Plantillas: the degrees whose subjects come already set up with their teaching
/// guide's evaluation. Every subject belongs to one; inside it you take the whole degree or just
/// the subjects you pick, and edit any of them afterwards.
struct TemplatesView: View {
    var body: some View {
        List {
            Section {
                ForEach(DegreeTemplate.all) { template in
                    NavigationLink {
                        TemplateView(template: template)
                    } label: {
                        AccountRow(title: template.name, detail: "\(template.university) · \(Self.subjectsLabel(template.entries.count))", symbol: "graduationcap")
                    }
                }
            } footer: {
                Text("Asignaturas ya preparadas con la evaluación de su guía docente. Entra en tu grado para añadirlo entero o solo las asignaturas que quieras.")
            }
        }
        .navigationTitle("Plantillas")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func subjectsLabel(_ count: Int) -> String {
        count == 1 ? "1 asignatura" : "\(count) asignaturas"
    }
}

/// One degree, by year and term: tick the subjects to take (none ticked takes them all), ⓘ shows
/// how each is evaluated.
struct TemplateView: View {
    let template: DegreeTemplate

    @Environment(Library.self) private var library
    /// Picked entries, by index in the template.
    @State private var selected: Set<Int> = []
    @State private var result: (added: Int, skipped: Int)?
    /// The entry whose evaluation is open.
    @State private var detail: Int?

    private var degree: DegreeSettings { library.degree }

    /// Entry indices of one year and term, in the template's order.
    private func indices(year: Int, term: Int) -> [Int] {
        template.entries.indices.filter { template.entries[$0].year == year && template.entries[$0].term == term }
    }

    private var buttonTitle: String {
        selected.isEmpty ? "Añadir todas" : "Añadir \(TemplatesView.subjectsLabel(selected.count))"
    }

    var body: some View {
        List {
            ForEach(template.years, id: \.self) { year in
                // A template term past what the degree has goes in its last term, as `apply` does.
                ForEach(1...max(template.entries.map(\.term).max() ?? 1, 1), id: \.self) { term in
                    let indices = indices(year: year, term: term)
                    if !indices.isEmpty {
                        Section {
                            ForEach(indices, id: \.self) { index in
                                row(index)
                            }
                        } header: {
                            HStack {
                                Text("\(degree.yearLabel(year)) · \(degree.termLabel(degree.absoluteTerm(year: year, relative: min(term, degree.termsPerYear))))")
                                Spacer()
                                let all = Set(indices)
                                Button(all.isSubset(of: selected) ? "Ninguna" : "Todas") {
                                    if all.isSubset(of: selected) { selected.subtract(all) } else { selected.formUnion(all) }
                                }
                                .font(.footnote.weight(.semibold))
                                .textCase(nil)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detail) { index in
            let entry = template.entries[index]
            SubjectTemplateView(subject: entry.subject, year: entry.year, term: entry.term)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    result = library.apply(template, only: selected.isEmpty ? nil : selected)
                    selected = []
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text(selected.isEmpty ? "Marca las que quieras, o añade el grado entero." : "Cada una va a su año y su cuatrimestre.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.bar)
        }
        .alert("Plantilla añadida", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("Vale") {}
        } message: {
            if let result {
                Text(result.skipped == 0
                     ? "Se han añadido \(TemplatesView.subjectsLabel(result.added))."
                     : "Se han añadido \(TemplatesView.subjectsLabel(result.added)). Las otras \(result.skipped) ya las tenías.")
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let entry = template.entries[index]
        let isSelected = selected.contains(index)
        return HStack(spacing: 12) {
            Button {
                if isSelected { selected.remove(index) } else { selected.insert(index) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.subject.name)
                            .foregroundStyle(.primary)
                        Text(SubjectTemplateView.summary(of: entry.subject))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            // A button rather than a NavigationLink, so the row doesn't get a chevron next to the ⓘ.
            Button {
                detail = index
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cómo se evalúa \(entry.subject.name)")
        }
    }
}

/// One subject of a degree: how it's evaluated, and adding just this one, to its own year and
/// term or wherever you choose.
struct SubjectTemplateView: View {
    let subject: Subject

    @Environment(Library.self) private var library
    @State private var year: Int
    /// Position within the year; `nil` is the whole year.
    @State private var relativeTerm: Int?
    @State private var isAdded = false

    init(subject: Subject, year: Int, term: Int) {
        self.subject = subject
        _year = State(initialValue: year)
        _relativeTerm = State(initialValue: term)
    }

    /// "6 ECTS · Media ponderada de 3 partes".
    static func summary(of subject: Subject) -> String {
        let ects = "\(subject.ectsCredits.formatted()) ECTS"
        switch subject.root {
        case .group(let group):
            let parts = group.children.count == 1 ? "1 parte" : "\(group.children.count) partes"
            return "\(ects) · \(group.combination.kind.label) de \(parts)"
        case .formula: return "\(ects) · Fórmula"
        default: return ects
        }
    }

    private var degree: DegreeSettings { library.degree }

    private var alreadyThere: Bool {
        library.courses.first { $0.year == year }?.subjects.contains { $0.subject.name == subject.name } ?? false
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Créditos", value: "\(subject.ectsCredits.formatted()) ECTS")
                LabeledContent("Evaluación", value: subject.root.asFormula != nil ? "Fórmula" : subject.root.asGroup?.combination.kind.label ?? "Nota única")
            }

            if let group = subject.root.asGroup {
                Section("Partes") {
                    ForEach(group.children) { child in
                        LabeledContent {
                            Text("\((child.weight * 100).formatted(.number.precision(.fractionLength(0...1)))) %")
                                .monospacedDigit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(child.node.title)
                                Text(child.node.rowSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if let formula = subject.root.asFormula {
                Section("Variables") {
                    ForEach(formula.variables.keys.sorted(), id: \.self) { Text($0) }
                }
            }

            Section {
                Picker(degree.displayYearName, selection: $year) {
                    ForEach(1...max(degree.years, year), id: \.self) { Text(degree.yearLabel($0)).tag($0) }
                }
                Picker(degree.termName.isEmpty ? "Cuatrimestre" : degree.termName, selection: $relativeTerm) {
                    Text("Todo el año").tag(Int?.none)
                    ForEach(1...max(degree.termsPerYear, 1), id: \.self) { n in
                        Text(degree.termLabel(degree.absoluteTerm(year: year, relative: n))).tag(Int?.some(n))
                    }
                }
            } header: {
                Text("Dónde añadirla")
            } footer: {
                if alreadyThere {
                    Text("Ya tienes una asignatura llamada «\(subject.name)» en \(degree.yearLabel(year)). Se añadiría otra.")
                } else {
                    Text("Viene puesta donde va en el grado; cámbialo si la cursas en otro momento.")
                }
            }
        }
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // A template term past what the degree has goes in its last one.
            if let term = relativeTerm, term > degree.termsPerYear { relativeTerm = degree.termsPerYear }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                library.addSubject(subject, year: year, term: relativeTerm.map { degree.absoluteTerm(year: year, relative: $0) })
                isAdded = true
            } label: {
                Text("Añadir solo esta")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .alert("Asignatura añadida", isPresented: $isAdded) {
            Button("Vale") {}
        } message: {
            Text("«\(subject.name)» está en \(degree.yearLabel(year))\(relativeTerm.map { " · " + degree.termLabel(degree.absoluteTerm(year: year, relative: $0)) } ?? ", todo el año"). Puedes editar su evaluación desde la asignatura.")
        }
    }
}
