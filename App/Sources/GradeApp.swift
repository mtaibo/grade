import SwiftUI

@main
struct GradeApp: App {
    @State private var library = Library()
    /// Calendar sits leftmost, but the app still opens on the subjects.
    @State private var selectedTab = AppTab.subjects
    @State private var backupCenter = BackupImportCenter()
    @State private var tour = Tour()
    /// The guided tour is offered once, on the first launch; after that it's in Cuenta → Tutoriales.
    @AppStorage("tourOffered") private var tourOffered = false
    @State private var isOfferingTour = false
    /// A fresh install: the welcome, what you study and your template, then the tour.
    @State private var isOnboarding = false
    @State private var tourWindow: TourWindow?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Calendario", systemImage: "calendar", value: .calendar) {
                    CalendarView(isCurrentTab: selectedTab == .calendar)
                }
                Tab("Asignaturas", systemImage: "books.vertical", value: .subjects) {
                    HomeView()
                }
                Tab("Cuenta", systemImage: "person.crop.circle", value: .account) {
                    AccountView()
                }
            }
            // Rebuilt when a tour starts or ends, so no screen keeps the other library's state.
            .id(tour.session)
            // No scroll bars anywhere: every list, form and scroll view below (sheets included) inherits it.
            .scrollIndicators(.hidden)
            // Imports always go into the real library, even if a file is opened mid-tour.
            .modifier(BackupImportHost(center: backupCenter, library: library))
            // During a tour the app shows a throwaway study instead of the real one.
            .environment(tour.sandbox ?? library)
            .environment(backupCenter)
            .environment(tour)
            .onChange(of: [tour.session.uuidString, String(tour.index)]) {
                if let tab = tour.current?.tab { selectedTab = tab }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { library.reloadIfNeeded() }
            }
            .onChange(of: tour.isActive) { _, isActive in
                tourWindow?.isHidden = !isActive
                if !isActive { selectedTab = tour.returnTab }
            }
            .onAppear {
                if tourWindow == nil, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    tourWindow = TourWindow(scene: scene, tour: tour)
                }
                if !tourOffered {
                    let isEmpty = library.courses.allSatisfy(\.subjects.isEmpty) && library.archives.isEmpty
                    if isEmpty { isOnboarding = true } else { isOfferingTour = true }
                }
            }
            .fullScreenCover(isPresented: $isOnboarding) {
                OnboardingView { startsTour in
                    tourOffered = true
                    isOnboarding = false
                    if startsTour { tour.startGeneral(returningTo: .subjects) }
                }
                .environment(library)
            }
            .alert("¿Te enseño cómo funciona?", isPresented: $isOfferingTour) {
                Button("Empezar el tour") {
                    tourOffered = true
                    tour.startGeneral(returningTo: .subjects)
                }
                Button("Ahora no", role: .cancel) { tourOffered = true }
            } message: {
                Text("Un recorrido guiado de un par de minutos con un estudio de prueba. Puedes hacerlo cuando quieras desde Cuenta → Tutoriales.")
            }
        }
    }
}

enum AppTab: Hashable {
    case calendar, subjects, account
}
