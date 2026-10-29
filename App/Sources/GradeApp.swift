import SwiftUI

@main
struct GradeApp: App {
    @State private var library = Library()
    /// Calendar sits leftmost, but the app still opens on the subjects.
    @State private var selectedTab = AppTab.subjects
    @State private var backupCenter = BackupImportCenter()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Calendario", systemImage: "calendar", value: .calendar) {
                    CalendarView()
                }
                Tab("Asignaturas", systemImage: "books.vertical", value: .subjects) {
                    HomeView()
                }
                Tab("Cuenta", systemImage: "person.crop.circle", value: .account) {
                    AccountView()
                }
            }
            // No scroll bars anywhere: every list, form and scroll view below (sheets included) inherits it.
            .scrollIndicators(.hidden)
            .modifier(BackupImportHost(center: backupCenter))
            .environment(library)
            .environment(backupCenter)
        }
    }
}

private enum AppTab: Hashable {
    case calendar, subjects, account
}
