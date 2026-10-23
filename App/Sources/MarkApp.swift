import SwiftUI

@main
struct MarkApp: App {
    @State private var library = Library()
    /// Calendar sits leftmost, but the app still opens on the subjects.
    @State private var selectedTab = AppTab.subjects

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Calendario", systemImage: "calendar", value: .calendar) {
                    CalendarView()
                }
                Tab("Asignaturas", systemImage: "books.vertical", value: .subjects) {
                    HomeView()
                }
                Tab("Expediente", systemImage: "chart.bar.doc.horizontal", value: .record) {
                    RecordView()
                }
                Tab("Ajustes", systemImage: "gearshape", value: .settings) {
                    SettingsView()
                }
            }
            .environment(library)
        }
    }
}

private enum AppTab: Hashable {
    case calendar, subjects, record, settings
}
