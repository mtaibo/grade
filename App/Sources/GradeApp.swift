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
    /// «Volver a ver los consejos» bumps it: Asignaturas is rebuilt so its tips are asked for again
    /// (the other screens make theirs each time they're drawn), without Cuenta jumping to the top.
    @AppStorage("tipsGeneration") private var tipsGeneration = 0
    #if os(macOS)
    @State private var menuActions = MenuActions()
    @State private var pushes = MacPushCount()
    @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
    #else
    @UIApplicationDelegateAdaptor private var appDelegate: PhoneAppDelegate
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
        // Decided before the first frame, so a fresh install opens straight on the welcome instead
        // of showing the home screen with the welcome sliding up over it.
        if !UserDefaults.standard.bool(forKey: "tourOffered") {
            let isEmpty = library.courses.allSatisfy(\.subjects.isEmpty) && library.archives.isEmpty
            if isEmpty {
                _isOnboarding = State(initialValue: true)
            } else {
                UserDefaults.standard.set(true, forKey: "tourOffered")
            }
        }
    }

    var body: some Scene {
        #if os(macOS)
        // One window: there's one study, and closing it ends the app.
        Window("Grade", id: "main") {
            root
                .frame(minWidth: 820, minHeight: 560)
                .environment(pushes)
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
                .onAppear { appDelegate.cloud = cloud }
        }
        .backgroundTask(.appRefresh(CloudSync.backgroundTask)) {
            await cloud.runBackgroundSync()
        }
        #endif
    }

    /// The welcome or the app, in the window's place rather than one over the other.
    private var root: some View {
        ZStack {
            if isOnboarding {
                OnboardingView {
                    hasOnboarded = true
                    library.needsOnboarding = false
                    isOnboarding = false
                }
                .transition(.opacity)
            } else {
                tabs
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: isOnboarding)
        .modifier(BackupImportHost(center: backupCenter, library: library))
        .environment(library)
        .environment(backupCenter)
        #if os(macOS)
        .environment(menuActions)
        #endif
        .environment(cloud)
        // iCloud announces changes with a push, which can come late or not at all: while the app is
        // on screen it also asks, so what's done on another device shows up on its own. On screen
        // includes not being in front: a Mac window behind another one is still being looked at.
        .task(id: scenePhase) {
            guard scenePhase != .background else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: cloud.pollInterval)
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
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Calendario", systemImage: "calendar", value: .calendar) {
                CalendarView(isCurrentTab: selectedTab == .calendar)
            }
            Tab("Asignaturas", systemImage: "books.vertical", value: .subjects) {
                HomeView(isCurrentTab: selectedTab == .subjects)
                    // Its tips are kept in a group made once: a new one asks for them again.
                    .id(tipsGeneration)
            }
            Tab("Cuenta", systemImage: "person.crop.circle", value: .account) {
                AccountView(isCurrentTab: selectedTab == .account)
            }
        }
        .id(appSession)
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
    }
}

enum AppTab: Hashable {
    case calendar, subjects, account
}
