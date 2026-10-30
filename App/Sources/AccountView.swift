import Engine
import SwiftUI

/// The account tab, top to bottom: your studies (with the archive once something's been archived),
/// your record, your data (backups and deletes), the tutorials and about the app.
struct AccountView: View {
    @Environment(Library.self) private var library
    @Environment(Tour.self) private var tour: Tour?
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
            ScrollViewReader { proxy in
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
                    .tourTarget("account.study")
                    .id("account.study")
                    NavigationLink {
                        TemplatesView()
                    } label: {
                        AccountRow(title: "Plantillas", detail: "Cursos completos o asignaturas sueltas", symbol: "square.stack")
                    }
                    .tourTarget("account.study")
                    if !library.archives.isEmpty {
                        NavigationLink {
                            ArchiveView()
                        } label: {
                            AccountRow(
                                title: "Archivo",
                                detail: library.archives.count == 1 ? "1 estudio archivado" : "\(library.archives.count) estudios archivados",
                                symbol: "archivebox"
                            )
                        }
                    }
                }

                Section {
                    RecordStats(summary: RecordSummary(library.courses))
                        .tourTarget("account.record")
                        .id("account.record")
                    NavigationLink {
                        RecordView()
                    } label: {
                        Label("Ver expediente", systemImage: "chart.bar.doc.horizontal")
                    }
                    .tourTarget("account.record")
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
                    .tourTarget("account.data")
                    .id("account.data")
                    NavigationLink {
                        EraseDataView()
                    } label: {
                        AccountRow(title: "Borrar datos", detail: "Notas o asignaturas", symbol: "trash")
                    }
                    .tourTarget("account.data")
                }

                Section {
                    Button {
                        tour?.startGeneral(returningTo: .account)
                    } label: {
                        AccountRow(title: "Tutorial general", detail: "Un recorrido guiado por toda la app", symbol: "figure.walk")
                    }
                    .foregroundStyle(.primary)
                    .tourTarget("account.tutorials")
                    .id("account.tutorials")
                    NavigationLink {
                        TourSectionsView()
                    } label: {
                        AccountRow(title: "Por sección", detail: "Cómo funciona cada pantalla", symbol: "rectangle.stack")
                    }
                    .tourTarget("account.tutorials")
                } header: {
                    Text("Tutoriales")
                } footer: {
                    Text("Se hacen con un estudio de prueba: tus asignaturas y notas no se tocan.")
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
            .onChange(of: tour?.current?.target) { _, target in
                // Brings the highlighted row on screen during a tour.
                guard let target, target.hasPrefix("account.") else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
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

/// "Archivo", from Estudios: the studies put away, newest first.
private struct ArchiveView: View {
    @Environment(Library.self) private var library

    var body: some View {
        List {
            ForEach(library.archives.reversed()) { study in
                NavigationLink {
                    ArchivedStudyView(id: study.id)
                } label: {
                    AccountRow(
                        title: study.degree.displayName,
                        detail: "Archivado el \(study.archivedAt.formatted(date: .abbreviated, time: .omitted))",
                        symbol: study.degree.studyType.symbol
                    )
                }
            }
        }
        .overlay {
            // After deleting the last one.
            if library.archives.isEmpty {
                ContentUnavailableView("Nada archivado", systemImage: "archivebox")
            }
        }
        .navigationTitle("Archivo")
        .navigationBarTitleDisplayMode(.inline)
    }
}
