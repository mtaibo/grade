import SwiftUI

@main
struct GradeApp: App {
    @State private var library: Library
    @State private var cloud: CloudSync
    #if os(iOS)
    /// Lives from launch, not from the first screen: the watch can wake the app in the background.
    private let watchLink: WatchLink
    #endif
    /// Calendar sits leftmost, but the app still opens on the subjects.
    @State private var selectedTab = AppTab.subjects
    @State private var backupCenter = BackupImportCenter()
    @State private var tour = Tour()
    /// The guided tour is offered once, on the first launch; after that it's in Cuenta → Tutoriales.
    @AppStorage("tourOffered") private var tourOffered = false
    @State private var isOfferingTour = false
    /// A fresh install: the welcome, what you study and your template, then the tour.
    @State private var isOnboarding = false
    #if os(iOS)
    @State private var tourWindow: TourWindow?
    #else
    @State private var menuActions = MenuActions()
    @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
    #endif
    /// Changed after "Borrar todos los datos" so every tab starts over, Cuenta's pushed screens too.
    @State private var appSession = UUID()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let library = Library()
        let cloud = CloudSync(library: library)
        #if os(iOS)
        let watchLink = WatchLink(library: library)
        self.watchLink = watchLink
        #endif
        library.onChange = { fromCloud in
            if !fromCloud { cloud.noteLocalChange() }
            #if os(iOS)
            watchLink.noteChange()
            #endif
        }
        _library = State(initialValue: library)
        _cloud = State(initialValue: cloud)
    }

    var body: some Scene {
        #if os(macOS)
        // One window: there's one study, and closing it ends the app.
        Window("Grade", id: "main") {
            root
                .frame(minWidth: 820, minHeight: 560)
                .onAppear { appDelegate.cloud = cloud }
        }
        .defaultSize(width: 1120, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            GradeCommands(selectedTab: $selectedTab, backupCenter: backupCenter, actions: menuActions)
        }
        #else
        WindowGroup {
            root
        }
        .backgroundTask(.appRefresh(CloudSync.backgroundTask)) {
            await cloud.runBackgroundSync()
        }
        #endif
    }

    private var root: some View {
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
        .id([tour.session, appSession])
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        // The iPhone's grouped look, sheets included, rather than the Mac's two-column forms.
        .formStyle(.grouped)
        // Fields draw their own background where they need one, as on the iPhone.
        .textFieldStyle(.plain)
        #else
        // No scroll bars anywhere: every list, form and scroll view below (sheets included) inherits it.
        .scrollIndicators(.hidden)
        #endif
        // Imports always go into the real library, even if a file is opened mid-tour.
        .modifier(BackupImportHost(center: backupCenter, library: library))
        // During a tour the app shows a throwaway study instead of the real one.
        .environment(tour.sandbox ?? library)
        .environment(backupCenter)
        #if os(macOS)
        .environment(menuActions)
        #endif
        .environment(cloud)
        .environment(tour)
        .onChange(of: [tour.session.uuidString, String(tour.index)]) {
            if let tab = tour.current?.tab { selectedTab = tab }
        }
        // iCloud announces changes with a push, which can come late or not at all: while the app is
        // on screen it also asks, so what's done on another device shows up on its own.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await cloud.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                library.reloadIfNeeded()
                Task { await cloud.refresh() }
            case .background:
                cloud.syncBeforeSuspension()
            default:
                break
            }
        }
        // "Borrar todos los datos" is a fresh install: per-device preferences go too, and the
        // first-launch questions come back.
        .onChange(of: library.needsOnboarding) { _, needs in
            guard needs else { return }
            // Asked for on the spot, unlike other changes: it shouldn't linger in iCloud.
            Task { await cloud.syncNow() }
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
            selectedTab = .subjects
            appSession = UUID()
            Task {
                // Once the confirmation and the rebuilt tabs have settled.
                try? await Task.sleep(for: .milliseconds(400))
                isOnboarding = true
            }
        }
        // A new device has got its study from iCloud: nothing to ask or set up.
        .onChange(of: library.wasRestoredFromCloud) { _, restored in
            guard restored, isOnboarding else { return }
            tourOffered = true
            isOnboarding = false
        }
        #if os(iOS)
        .onChange(of: tour.isActive) { _, isActive in
            tourWindow?.isHidden = !isActive
            if !isActive { selectedTab = tour.returnTab }
        }
        #endif
        .onAppear {
            #if os(iOS)
            if tourWindow == nil, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                tourWindow = TourWindow(scene: scene, tour: tour)
            }
            #endif
            if !tourOffered {
                let isEmpty = library.courses.allSatisfy(\.subjects.isEmpty) && library.archives.isEmpty
                #if os(macOS)
                if isEmpty { isOnboarding = true } else { tourOffered = true }
                #else
                if isEmpty { isOnboarding = true } else { isOfferingTour = true }
                #endif
            }
        }
        .fullScreenCover(isPresented: $isOnboarding) {
            OnboardingView { startsTour in
                tourOffered = true
                library.needsOnboarding = false
                isOnboarding = false
                if startsTour { tour.startGeneral(degree: library.degree, returningTo: .subjects) }
            }
            .environment(library)
        }
        .alert("¿Te enseño cómo funciona?", isPresented: $isOfferingTour) {
            Button("Empezar el tour") {
                tourOffered = true
                tour.startGeneral(degree: library.degree, returningTo: .subjects)
            }
            Button("Ahora no", role: .cancel) { tourOffered = true }
        } message: {
            Text("Un recorrido guiado de un par de minutos con un estudio de prueba. Puedes hacerlo cuando quieras desde Cuenta → Tutoriales.")
        }
    }
}

enum AppTab: Hashable {
    case calendar, subjects, account
}
