import SwiftUI

/// What the menu bar asks of a screen that may not be on show.
@MainActor
@Observable
final class MenuActions {
    /// Goes up each time "Nueva asignatura" is chosen; the subjects screen watches it.
    var newSubjectRequests = 0
}

/// The menu bar: what the iPhone keeps in its screens' buttons, with the Mac's usual shortcuts.
struct GradeCommands: Commands {
    @Binding var selectedTab: AppTab
    let backupCenter: BackupImportCenter
    let actions: MenuActions

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Ajustes…") { selectedTab = .account }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Nueva asignatura") {
                selectedTab = .subjects
                actions.newSubjectRequests += 1
            }
            .keyboardShortcut("n")
            Divider()
            Button("Importar copia…") { backupCenter.isPicking = true }
                .keyboardShortcut("o")
        }
        CommandGroup(before: .toolbar) {
            Button("Calendario") { selectedTab = .calendar }
                .keyboardShortcut("1")
            Button("Asignaturas") { selectedTab = .subjects }
                .keyboardShortcut("2")
            Button("Cuenta") { selectedTab = .account }
                .keyboardShortcut("3")
            Divider()
        }
        CommandGroup(replacing: .help) {
            Link("Soporte de Grade", destination: URL(string: "https://grade.migueltaibo.com/soporte/")!)
        }
    }
}
