import AppKit
import SwiftUI

// The iPhone's vocabulary on the Mac, so the screens they share read the same on both: modifiers
// that only mean something on a touch screen do nothing here.

enum TitleDisplayModeShim { case automatic, inline, large }
enum KeyboardTypeShim { case decimalPad, numberPad, numbersAndPunctuation, `default` }
enum AutocapitalizationShim { case never, words, sentences, characters }

extension View {
    func navigationBarTitleDisplayMode(_ mode: TitleDisplayModeShim) -> some View { self }
    func keyboardType(_ type: KeyboardTypeShim) -> some View { self }
    func textInputAutocapitalization(_ style: AutocapitalizationShim?) -> some View { self }
    func dismissesKeyboardOnBackgroundTap() -> some View { self }

    /// The Mac has no full-screen covers: a sheet, the same size as the window it comes from.
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) {
            content().frame(minWidth: 620, idealWidth: 720, minHeight: 620, idealHeight: 760)
        }
    }
}

/// Stands in for SwiftUI's `List` in this target. The app's lists are all settings-like screens of
/// sections, grouped cards on the iPhone; a `List` on the Mac has neither the cards nor the sections.
struct List<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}

extension ToolbarItemPlacement {
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var topBarLeading: ToolbarItemPlacement { .navigation }
}

extension NSColor {
    private static func adaptive(light: CGFloat, dark: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: alpha)
        }
    }

    // Cards lighter than the window in light and dark alike, like the iPhone's grouped screens.
    static let systemGroupedBackground = adaptive(light: 0.95, dark: 0.11)
    static let secondarySystemGroupedBackground = adaptive(light: 1, dark: 0.17)
    static let systemBackground = adaptive(light: 1, dark: 0.11)
    static let quaternaryLabel = NSColor.quaternaryLabelColor
    static let tertiarySystemFill = adaptive(light: 0.46, dark: 0.46, alpha: 0.12)
    static let quaternarySystemFill = adaptive(light: 0.46, dark: 0.46, alpha: 0.08)
}
