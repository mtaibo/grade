import SwiftUI

/// The app's colour: buttons, links, the tab bar, today in the calendar… Blue unless the user picks
/// another in Cuenta → Personalización. Kept on this device, like the other display preferences.
enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, indigo, purple, pink, red, orange, green, teal, graphite
    /// Whatever the colour picker was left on (`customAccentKey`).
    case custom

    static let storageKey = "accentColor"
    static let customAccentKey = "customAccentColor"

    var id: Self { self }

    static let presets: [AccentChoice] = allCases.filter { $0 != .custom }

    var name: String {
        switch self {
        case .blue: "Azul"
        case .indigo: "Índigo"
        case .purple: "Morado"
        case .pink: "Rosa"
        case .red: "Rojo"
        case .orange: "Naranja"
        case .green: "Verde"
        case .teal: "Turquesa"
        case .graphite: "Grafito"
        case .custom: "Personalizado"
        }
    }

    /// The custom colour comes from its own stored value: see `color(custom:)`.
    func color(custom: String) -> Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        case .custom: Color(hex: custom) ?? .blue
        }
    }
}

extension EnvironmentValues {
    /// The app's colour, for the places that need it as a `Color`: `.tint` covers styles, but
    /// `Color.accentColor` stays the system's blue whatever `.tint` says.
    @Entry var accent: Color = .blue
}

/// Puts the chosen colour on everything below it, the UIKit pieces (share sheet, alerts) included.
struct AppAccent: ViewModifier {
    @AppStorage(AccentChoice.storageKey) private var choice = AccentChoice.blue
    @AppStorage(AccentChoice.customAccentKey) private var custom = ""

    func body(content: Content) -> some View {
        let color = choice.color(custom: custom)
        content
            // The accent rather than `.tint`: an explicit tint also colours the toolbars' glass
            // buttons, which the system keeps white or black with the default accent.
            .accentColor(color)
            .environment(\.accent, color)
            #if os(iOS)
            .onChange(of: color, initial: true) {
                let uiColor = UIColor(color)
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    for window in scene.windows { window.tintColor = uiColor }
                }
            }
            #endif
    }
}

extension Color {
    /// `#RRGGBB`, how the custom colour is stored.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hex: String {
        let resolved = resolve(in: EnvironmentValues())
        let channel = { (value: Float) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(resolved.red), channel(resolved.green), channel(resolved.blue))
    }
}

// MARK: - Screens

/// Cuenta → Personalización → Color.
struct AccentColorView: View {
    @AppStorage(AccentChoice.storageKey) private var choice = AccentChoice.blue

    var body: some View {
        List {
            Section {
                AccentPicker()
            } footer: {
                Text("El de los botones, los enlaces y las pestañas. Los colores de tus asignaturas y de las notas no cambian.")
            }

            if choice != .blue {
                Section {
                    Button("Volver al azul") {
                        withAnimation { choice = .blue }
                    }
                }
            }
        }
        .navigationTitle("Color")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Cuenta's «Personalización» rows: the icon (iPhone only: the Mac's is fixed) and the colour.
struct PersonalizationSection: View {
    @AppStorage(AccentChoice.storageKey) private var choice = AccentChoice.blue
    #if os(iOS)
    @State private var icons = AppIconStore()
    #endif

    var body: some View {
        Section("Personalización") {
            #if os(iOS)
            NavigationLink {
                AppIconView(store: icons)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Icono")
                        Text(icons.current.name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    AppIconPreview(icon: icons.current, size: 26)
                }
            }
            #endif
            NavigationLink {
                AccentColorView()
            } label: {
                AccountRow(title: "Color", detail: choice.name, symbol: "paintpalette")
            }
        }
    }
}

/// The colours as a grid of dots, the chosen one ringed, then the colour picker for any other.
private struct AccentPicker: View {
    @AppStorage(AccentChoice.storageKey) private var choice = AccentChoice.blue
    @AppStorage(AccentChoice.customAccentKey) private var custom = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(AccentChoice.presets) { preset in
                dot(preset.color(custom: custom), isSelected: choice == preset, label: preset.name) {
                    choice = preset
                }
            }
            ColorPicker(selection: customBinding, supportsOpacity: false) {
                EmptyView()
            }
            .labelsHidden()
            .frame(width: 36, height: 36)
            .overlay {
                if choice == .custom { ring }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Otro color")
        }
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.2), value: choice)
    }

    /// Picking a colour also makes it the app's.
    private var customBinding: Binding<Color> {
        Binding {
            Color(hex: custom) ?? choice.color(custom: custom)
        } set: { color in
            custom = color.hex
            choice = .custom
        }
    }

    private func dot(_ color: Color, isSelected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .padding(3)
                .overlay { if isSelected { ring } }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var ring: some View {
        Circle()
            .strokeBorder(.primary.opacity(0.85), lineWidth: 2)
            .frame(width: 38, height: 38)
    }
}

// MARK: - Icon

#if os(iOS)
/// The colours the classic icon's plate and tick can take. Same names and order as the palette in
/// Icons/make_icons.py, which builds an icon for every pair of different ones.
enum IconColor: String, CaseIterable, Identifiable {
    case white = "White", black = "Black", red = "Red", orange = "Orange", green = "Green"
    case teal = "Teal", blue = "Blue", indigo = "Indigo", purple = "Purple", pink = "Pink"

    var id: Self { self }

    var name: String {
        switch self {
        case .white: "Blanco"
        case .black: "Negro"
        case .red: "Rojo"
        case .orange: "Naranja"
        case .green: "Verde"
        case .teal: "Turquesa"
        case .blue: "Azul"
        case .indigo: "Índigo"
        case .purple: "Morado"
        case .pink: "Rosa"
        }
    }

    var color: Color {
        switch self {
        case .white: .white
        case .black: .black
        case .red: Color(red: 1, green: 59 / 255, blue: 48 / 255)
        case .orange: Color(red: 1, green: 149 / 255, blue: 0)
        case .green: Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
        case .teal: Color(red: 48 / 255, green: 176 / 255, blue: 199 / 255)
        case .blue: Color(red: 0, green: 122 / 255, blue: 1)
        case .indigo: Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
        case .purple: Color(red: 175 / 255, green: 82 / 255, blue: 222 / 255)
        case .pink: Color(red: 1, green: 45 / 255, blue: 85 / 255)
        }
    }

    var isNeutral: Bool { self == .white || self == .black }
}

/// The other designs, each an icon of its own.
enum IconDesign: String, CaseIterable, Identifiable {
    case tree = "Tree", passing = "Passing", record = "Record"

    var id: Self { self }

    var name: String {
        switch self {
        case .tree: "Evaluación"
        case .passing: "Aprobado"
        case .record: "Expediente"
        }
    }
}

/// An icon the app ships with: the classic tick on any plate, or another design. iOS can only switch
/// to icons that are already in the app, so every pair of colours is one, made beforehand.
enum AppIconChoice: Hashable {
    case classic(background: IconColor, tick: IconColor)
    case design(IconDesign)

    static let standard = AppIconChoice.classic(background: .white, tick: .black)

    /// What `setAlternateIconName` takes; nil is the main icon, the App Store's.
    var alternateName: String? {
        switch self {
        case .standard: nil
        case .classic(let background, let tick): "AppIcon-\(background.rawValue)-\(tick.rawValue)"
        case .design(let design): "AppIcon-\(design.rawValue)"
        }
    }

    init(alternateName: String?) {
        let parts = (alternateName ?? "").split(separator: "-").map(String.init)
        if parts.count == 3, let background = IconColor(rawValue: parts[1]), let tick = IconColor(rawValue: parts[2]),
           background != tick {
            self = .classic(background: background, tick: tick)
        } else if parts.count == 2, let design = IconDesign(rawValue: parts[1]) {
            self = .design(design)
        } else {
            self = .standard
        }
    }

    var name: String {
        switch self {
        case .standard: "Clásico"
        case .classic(let background, let tick): "Clásico · \(tick.name.lowercased()) sobre \(background.name.lowercased())"
        case .design(let design): design.name
        }
    }
}

/// The icon on the home screen, and the one being picked: nothing changes until it's confirmed.
@MainActor @Observable
final class AppIconStore {
    /// The icon on the home screen.
    private(set) var current: AppIconChoice
    /// What the picker shows; becomes `current` with `apply()`.
    private(set) var draft: AppIconChoice
    /// The classic's colours in the picker, kept while another design is picked so going back to the
    /// classic brings them back.
    private(set) var background: IconColor = .white
    private(set) var tick: IconColor = .black

    init() {
        let current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName)
        self.current = current
        draft = current
        discardDraft()
    }

    var isClassic: Bool {
        if case .classic = draft { true } else { false }
    }

    var hasChanges: Bool { draft != current }

    /// Back to the icon on the home screen, as when the picker opens.
    func discardDraft() {
        draft = current
        if case .classic(let background, let tick) = current {
            self.background = background
            self.tick = tick
        } else {
            background = .white
            tick = .black
        }
    }

    func setBackground(_ color: IconColor) {
        guard color != tick else { return }
        background = color
        draft = .classic(background: color, tick: tick)
    }

    func setTick(_ color: IconColor) {
        guard color != background else { return }
        tick = color
        draft = .classic(background: background, tick: color)
    }

    func showClassic() {
        draft = .classic(background: background, tick: tick)
    }

    func select(_ design: IconDesign) {
        draft = .design(design)
    }

    /// Puts the picked icon on the home screen. iOS confirms it with an alert of its own.
    func apply() {
        let icon = draft
        guard icon != current, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = current
        current = icon
        UIApplication.shared.setAlternateIconName(icon.alternateName) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.current = previous }
        }
    }
}

/// How the previews show the icons. The home screen's own style (Settings → Home Screen) can't be
/// read by apps, and it's apart from the app's dark mode, so the user picks it; light to start with.
enum IconPreviewStyle: String, CaseIterable, Identifiable {
    case light, dark, clear, tinted

    static let storageKey = "iconPreviewStyle"

    var id: Self { self }

    var name: String {
        switch self {
        case .light: "Claro"
        case .dark: "Oscuro"
        case .clear: "Cristal"
        case .tinted: "Tintado"
        }
    }
}

/// The icon as the home screen shows it in the chosen style, rounded.
struct AppIconPreview: View {
    let icon: AppIconChoice
    let size: CGFloat
    @AppStorage(IconPreviewStyle.storageKey) private var style = IconPreviewStyle.light
    @Environment(\.accent) private var accent

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.225, style: .continuous) }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.primary.opacity(style == .clear ? 0.25 : 0.12), lineWidth: max(0.5, size / 120))
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .light, .dark:
            colored
        case .tinted:
            // The system paints the tinted image's light parts in the tint over a dark plate; here
            // in the app's colour.
            ZStack {
                LinearGradient(colors: [accent.mix(with: .black, by: 0.72), accent.mix(with: .black, by: 0.88)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(accent).mask { glyph }
            }
        case .clear:
            ZStack {
                Rectangle().fill(.white.opacity(0.92)).mask { glyph }
            }
            .background(.ultraThinMaterial)
            .background(Color(white: 0.45).opacity(0.35))
        }
    }

    /// The icon in light or dark.
    @ViewBuilder
    private var colored: some View {
        switch icon {
        case .classic(let background, let tick):
            let isDarkWhite = style == .dark && background == .white
            ZStack {
                if isDarkWhite {
                    // As the real icon: dark mode only changes a white plate.
                    LinearGradient(colors: [Color(white: 0.165), Color(white: 0.055)], startPoint: .top, endPoint: .bottom)
                } else {
                    background.color
                }
                Image("IconTick")
                    .resizable()
                    .interpolation(.high)
                    .foregroundStyle(isDarkWhite && tick == .black ? .white : tick.color)
            }
        case .design(let design):
            Image("IconPreview-\(design.rawValue)-\(style == .dark ? "Dark" : "Light")")
                .resizable()
                .interpolation(.high)
        }
    }

    /// The tinted image's light parts as a mask: what the tinted and clear styles paint.
    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .classic:
            Image("IconTick").resizable().interpolation(.high)
        case .design(let design):
            Image("IconPreview-\(design.rawValue)-Tinted")
                .resizable()
                .interpolation(.high)
                .luminanceToAlpha()
        }
    }
}

/// Personalización → Icono: the picked icon big, the designs, and the classic's two colours; ✓ puts it on the home screen.
struct AppIconView: View {
    @Bindable var store: AppIconStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(IconPreviewStyle.storageKey) private var previewStyle = IconPreviewStyle.light

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    AppIconPreview(icon: store.draft, size: 120)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    Text(store.draft.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                    Picker("Ver como", selection: $previewStyle) {
                        ForEach(IconPreviewStyle.allCases) { style in
                            Text(style.name).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 10)
                    Text("Elige el tema de tus iconos para ver cómo quedaría en tu iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section("Diseño") {
                HStack(spacing: 0) {
                    designButton(
                        title: "Clásico",
                        icon: .classic(background: store.background, tick: store.tick),
                        isSelected: store.isClassic,
                        action: store.showClassic
                    )
                    ForEach(IconDesign.allCases) { design in
                        designButton(title: design.name, icon: .design(design), isSelected: store.draft == .design(design)) {
                            store.select(design)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            if store.isClassic {
                Section {
                    ColorDots(selected: store.background, unavailable: store.tick, select: store.setBackground)
                } header: {
                    Text("Fondo")
                }
                Section {
                    ColorDots(selected: store.tick, unavailable: store.background, select: store.setTick)
                } header: {
                    Text("Tick")
                } footer: {
                    Text("El fondo y el tick no pueden ser del mismo color.")
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: store.draft)
        .animation(.snappy(duration: 0.25), value: previewStyle)
        .navigationTitle("Icono")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The home screen's icon changes only here, not on every tap above.
            ToolbarItem(placement: .confirmationAction) {
                SaveToolbarButton {
                    store.apply()
                    dismiss()
                }
                .disabled(!store.hasChanges)
                .accessibilityLabel("Cambiar icono")
            }
        }
        // Leaving without confirming forgets what was picked.
        .onAppear { store.discardDraft() }
    }

    private func designButton(title: String, icon: AppIconChoice, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppIconPreview(icon: icon, size: 58)
                    .padding(4)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 66 * 0.225, style: .continuous)
                                .strokeBorder(.tint, lineWidth: 2.5)
                        }
                    }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The palette as two rows of dots; the other part's colour is crossed out and can't be picked.
private struct ColorDots: View {
    let selected: IconColor
    let unavailable: IconColor
    let select: (IconColor) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(IconColor.allCases) { color in
                let isSelected = color == selected
                let isUnavailable = color == unavailable
                Button {
                    select(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .overlay {
                            // White and black need an edge on a card of their own colour.
                            Circle().strokeBorder(.primary.opacity(color.isNeutral ? 0.2 : 0), lineWidth: 1)
                        }
                        .overlay {
                            if isUnavailable {
                                Capsule()
                                    .fill(.secondary)
                                    .frame(width: 2.5, height: 36)
                                    .rotationEffect(.degrees(45))
                            }
                        }
                        .frame(width: 30, height: 30)
                        .opacity(isUnavailable ? 0.35 : 1)
                        .padding(3)
                        .overlay {
                            if isSelected {
                                Circle()
                                    .strokeBorder(.primary.opacity(0.85), lineWidth: 2)
                                    .frame(width: 38, height: 38)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isUnavailable)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}
#endif
