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
    /// Whether the first-launch welcome has been through (or wasn't needed: there was a study).
    /// Its key is from when the end of it offered a guided tour.
    @AppStorage("tourOffered") private var hasOnboarded = false
    /// A fresh install: the welcome, then how to start (a copy, your own study or the defaults).
    @State private var isOnboarding = false
    /// «Volver a ver los consejos» bumps it: the tabs are rebuilt so every tip is asked for again.
    @AppStorage("tipsGeneration") private var tipsGeneration = 0
    #if os(macOS)
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
        GradeTips.configure()
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
                HomeView(isCurrentTab: selectedTab == .subjects)
            }
            Tab("Cuenta", systemImage: "person.crop.circle", value: .account) {
                AccountView(isCurrentTab: selectedTab == .account)
            }
        }
        .id([appSession.uuidString, String(tipsGeneration)])
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        // The iPhone's grouped look, sheets included, rather than the Mac's two-column forms.
        .formStyle(.grouped)
        // Fields draw their own background where they need one, as on the iPhone.
        .textFieldStyle(.plain)
        // No bar across the top: the buttons float over the content, which scrolls under them.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(SidebarToggleFix().id(appSession))
        #else
        // No scroll bars anywhere: every list, form and scroll view below (sheets included) inherits it.
        .scrollIndicators(.hidden)
        #endif
        .modifier(BackupImportHost(center: backupCenter, library: library))
        .environment(library)
        .environment(backupCenter)
        #if os(macOS)
        .environment(menuActions)
        #endif
        .environment(cloud)
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
            // The tips come back too, as on a fresh install: what TipKit remembers isn't a preference.
            let generation = GradeTips.generation
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
            tipsGeneration = generation + 1
            GradeTips.setShown(true)
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
            hasOnboarded = true
            isOnboarding = false
        }
        .onAppear {
            guard !hasOnboarded else { return }
            let isEmpty = library.courses.allSatisfy(\.subjects.isEmpty) && library.archives.isEmpty
            if isEmpty { isOnboarding = true } else { hasOnboarded = true }
        }
        .fullScreenCover(isPresented: $isOnboarding) {
            OnboardingView {
                hasOnboarded = true
                library.needsOnboarding = false
                isOnboarding = false
            }
            .environment(library)
        }
    }
}

enum AppTab: Hashable {
    case calendar, subjects, account
}
