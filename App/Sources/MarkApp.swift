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
                Tab("Cuenta", systemImage: "person.crop.circle", value: .account) {
                    AccountView()
                }
            }
            .environment(library)
        }
    }
}

private enum AppTab: Hashable {
    case calendar, subjects, account
}
