import Engine
import SwiftUI
import TipKit

/// The account tab, top to bottom: your studies (with the archive once something's been archived),
/// your record, your data (backups and deletes), the tips and about the app.
struct AccountView: View {
    /// Whether Cuenta is the tab on screen: its tip waits for the user to come back to it.
    let isCurrentTab: Bool
    @Environment(Library.self) private var library
    @AppStorage(GradeTips.shownKey) private var tipsShown = true
    /// Tips just turned back on from here: this screen's own waits until Cuenta is opened again,
    /// instead of popping up under the finger that asked for them.
    @AppStorage("accountTipWaits") private var accountTipWaits = false
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
                #if os(iOS)
                Text("Cuenta")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
                #endif

                // A card of its own, like the sections below, not a second card inside one.
                if !accountTipWaits {
                    Section {
                        TipView(AccountTip())
                            .tipBackground(Color.clear)
                            .tipImageSize(CGSize(width: 28, height: 28))
                            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    }
                }

                Section("Estudios") {
                    NavigationLink {
                        CurrentStudyView()
                    } label: {
                        AccountRow(
                            title: "Estudio actual",
                            detail: library.hasStudy ? library.degree.displayName : "Ninguno · \(Device.tap) para crear uno",
                            symbol: library.hasStudy ? library.degree.studyType.symbol : "plus.circle"
                        )
                    }
                    NavigationLink {
                        TemplatesView()
                    } label: {
                        AccountRow(title: "Plantillas", detail: "Cursos completos o asignaturas sueltas", symbol: "square.stack")
                    }
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
                    // Only a current study has numbers of its own; archived ones are inside.
                    if library.hasStudy {
                        RecordStats(summary: RecordSummary(library.courses, degree: library.degree))
                    }
                    NavigationLink {
                        RecordView()
                    } label: {
                        Label("Ver expediente", systemImage: "chart.bar.doc.horizontal")
                    }
                } header: {
                    Text("Expediente")
                } footer: {
                    Text(library.hasStudy
                         ? "Tu media por año, por \(library.degree.termName.isEmpty ? "periodo" : library.degree.termName.lowercased()) y la de todo el estudio, y la de tus estudios anteriores."
                         : "El expediente de tus estudios anteriores.")
                }

                Section("Datos") {
                    NavigationLink {
                        CloudSyncView()
                    } label: {
                        AccountRow(title: "iCloud", detail: "Sincroniza tus dispositivos", symbol: "icloud")
                    }
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

                Section {
                    Button {
                        accountTipWaits = true
                        GradeTips.showAgain()
                    } label: {
                        AccountRow(title: "Volver a ver los consejos", detail: "Salen otra vez en cada pantalla", symbol: "lightbulb")
                    }
                    .foregroundStyle(.primary)
                    Toggle(isOn: Binding(get: { tipsShown }, set: { shown in
                        if shown { accountTipWaits = true }
                        GradeTips.setShown(shown)
                    })) {
                        AccountRow(title: "Mostrar consejos", detail: tipsShown ? "Activados" : "Desactivados", symbol: "text.bubble")
                    }
                } header: {
                    Text("Consejos")
                } footer: {
                    Text("Pequeñas explicaciones que salen la primera vez que llegas a cada pantalla. Desactívalos si ya sabes cómo va.")
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
            .onChange(of: isCurrentTab) {
                if !isCurrentTab { accountTipWaits = false }
            }
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
            // Tinted even in a button row, whose text is the primary colour.
            Image(systemName: symbol)
                .foregroundStyle(.tint)
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
