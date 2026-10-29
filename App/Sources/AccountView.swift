import Engine
import SwiftUI

/// The account tab, four modules top to bottom: your studies (the current one and any archived),
/// your record, your data (backups and deletes) and about the app.
struct AccountView: View {
    @Environment(Library.self) private var library
    /// Same size as the other tabs' titles.
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 40

    static let website = URL(string: "https://www.migueltaibo.com")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // The title is part of the content, like in the other tabs, so it scrolls away
                // instead of collapsing into the navigation bar.
                Text("Cuenta")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))

                Section("Estudios") {
                    NavigationLink {
                        CurrentStudyView()
                    } label: {
                        AccountRow(title: "Estudio actual", detail: library.degree.displayName, symbol: library.degree.studyType.symbol)
                    }
                    ForEach(library.archives.reversed()) { study in
                        NavigationLink {
                            ArchivedStudyView(id: study.id)
                        } label: {
                            AccountRow(
                                title: study.degree.displayName,
                                detail: "Archivado el \(study.archivedAt.formatted(date: .abbreviated, time: .omitted))",
                                symbol: "archivebox"
                            )
                        }
                    }
                }

                Section {
                    RecordStats(summary: RecordSummary(library.courses))
                    NavigationLink {
                        RecordView()
                    } label: {
                        Label("Ver expediente", systemImage: "chart.bar.doc.horizontal")
                    }
                } header: {
                    Text("Expediente")
                } footer: {
                    Text("Tu media por año, por \(library.degree.termName.isEmpty ? "periodo" : library.degree.termName.lowercased()) y la de todo el estudio.")
                }

                Section("Datos") {
                    NavigationLink {
                        BackupView()
                    } label: {
                        AccountRow(title: "Copia de seguridad", detail: "Exportar o importar tus datos", symbol: "externaldrive")
                    }
                    NavigationLink {
                        EraseDataView()
                    } label: {
                        AccountRow(title: "Borrar datos", detail: "Notas o asignaturas", symbol: "trash")
                    }
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: version)
                    LabeledContent("Autor", value: "Miguel Taibo")
                    Link(destination: Self.website) {
                        LabeledContent("Web") {
                            Text("www.migueltaibo.com")
                                .foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        RoadmapView()
                    } label: {
                        Text("Próximas implementaciones")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A navigation row with an icon, a title and a line saying what's inside.
struct AccountRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
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
