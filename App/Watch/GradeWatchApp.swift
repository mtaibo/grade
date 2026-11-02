import SwiftUI

@main
struct GradeWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SubjectsScreen()
            }
            .environment(store)
        }
    }
}
