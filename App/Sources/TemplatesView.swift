import Engine
import SwiftUI

/// Cuenta → Plantillas: subjects already set up with their teaching guide's evaluation, either a
/// whole course at once or one subject on its own. Everything can be edited after adding it.
struct TemplatesView: View {
    /// Every bundled subject, grouped under the course template it belongs to, with the ones in no
    /// course last.
    private var subjectGroups: [(title: String, subjects: [Subject])] {
        var groups = DegreeTemplate.all.map { template in
            (title: "\(template.name) · \(template.university)", subjects: template.entries.map(\.subject))
        }
        let inCourses = groups.flatMap(\.subjects)
        let others = Subject.all.filter { !inCourses.contains($0) }
        if !others.isEmpty { groups.append((title: "Otras guías", subjects: others)) }
        return groups
    }

    var body: some View {
        List {
            Section {
                ForEach(DegreeTemplate.all) { template in
                    NavigationLink {
                        TemplateView(template: template)
                    } label: {
                        AccountRow(title: template.name, detail: "\(template.university) · \(template.entries.count) asignaturas", symbol: "graduationcap")
                    }
                }
            } header: {
                Text("Cursos completos")
            } footer: {
                Text("Añade de una vez todas las asignaturas de un curso, cada una en su año y su cuatrimestre.")
            }

            ForEach(subjectGroups, id: \.title) { group in
                Section {
                    ForEach(group.subjects.indices, id: \.self) { index in
                        let subject = group.subjects[index]
                        NavigationLink {
                            SubjectTemplateView(subject: subject)
                        } label: {
                            AccountRow(title: subject.name, detail: SubjectTemplateView.summary(of: subject), symbol: "book.closed")
                        }
                    }
                } header: {
                    if group.title == subjectGroups.first?.title {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Asignaturas sueltas")
                            Text(group.title)
                                .font(.footnote)
                                .textCase(nil)
                        }
                    } else {
                        Text(group.title)
                    }
                }
            }
        }
        .navigationTitle("Plantillas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One subject from a template: how it's evaluated, and where to add it.
struct SubjectTemplateView: View {
    let subject: Subject

    @Environment(Library.self) private var library
    @State private var year = 1
    /// Position within the year; `nil` is the whole year.
    @State private var relativeTerm: Int? = 1
    @State private var isAdded = false

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
                Picker("Año", selection: $year) {
                    ForEach(1...max(degree.years, 1), id: \.self) { Text(Period(year: $0).title).tag($0) }
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
                    Text("Ya tienes una asignatura llamada «\(subject.name)» en \(Period(year: year).title). Se añadiría otra.")
                }
            }
        }
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                library.addSubject(subject, year: year, term: relativeTerm.map { degree.absoluteTerm(year: year, relative: $0) })
                isAdded = true
            } label: {
                Text("Añadir a mi estudio")
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
            Text("«\(subject.name)» está en \(Period(year: year).title)\(relativeTerm.map { " · " + degree.termLabel(degree.absoluteTerm(year: year, relative: $0)) } ?? ", todo el año"). Puedes editar su evaluación desde la asignatura.")
        }
    }
}

/// What a template contains, by year and term, and the button that adds it to your degree.
struct TemplateView: View {
    let template: DegreeTemplate

    @Environment(Library.self) private var library
    @State private var result: (added: Int, skipped: Int)?

    var body: some View {
        List {
            ForEach(template.years, id: \.self) { year in
                ForEach(1...max(library.degree.termsPerYear, 1), id: \.self) { term in
                    let entries = template.entries(year: year, term: term)
                    if !entries.isEmpty {
                        Section("\(year)º Año · \(library.degree.termLabel(library.degree.absoluteTerm(year: year, relative: term)))") {
                            ForEach(entries.indices, id: \.self) { index in
                                LabeledContent(entries[index].subject.name, value: "\(entries[index].subject.ectsCredits.formatted()) ECTS")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                result = library.apply(template)
            } label: {
                Text("Añadir a mi carrera")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .alert("Plantilla añadida", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("Vale") {}
        } message: {
            if let result {
                Text(result.skipped == 0
                     ? "Se han añadido \(result.added) asignaturas."
                     : "Se han añadido \(result.added) asignaturas. Las otras \(result.skipped) ya las tenías.")
            }
        }
    }
}
