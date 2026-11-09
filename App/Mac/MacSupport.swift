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
    }
}

/// Stands in for SwiftUI's `Form` in this target: grouped, and on the same background as the screens
/// that aren't forms, where SwiftUI's would paint a grey of its own.
struct Form<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        SwiftUI.Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
    }
}

/// The system's scroll bar at its small size, shown for a moment so it's clear the list goes on.
struct ThinScrollBar: NSViewRepresentable {
    func makeNSView(context: Context) -> FixView { FixView() }
    func updateNSView(_ view: FixView, context: Context) {}

    final class FixView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                scrollView.verticalScroller?.controlSize = .small
                scrollView.flashScrollers()
            }
        }
    }
}

/// Keeps the sidebar's toggle beside the traffic lights, which SwiftUI has no modifier for. The toolbar
/// moves it into a » menu on the far side of the window when the sidebar is too narrow for it, and when
/// the window opens with the sidebar folded. Goes in the background of the tabs; rebuilt tabs need a new one.
struct SidebarToggleFix: NSViewRepresentable {
    func makeNSView(context: Context) -> FixView { FixView() }
    func updateNSView(_ view: FixView, context: Context) {}

    final class FixView: NSView {
        private static let width: CGFloat = 170
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Once SwiftUI has set up the split view and filled the toolbar.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, let content = window.contentView,
                      let sidebar = Self.sidebar(in: content) else { return }
                sidebar.minimumThickness = Self.width
                // SwiftUI puts its own minimum back each time the sidebar folds.
                observation = sidebar.observe(\.minimumThickness) { sidebar, _ in
                    if sidebar.minimumThickness != Self.width { sidebar.minimumThickness = Self.width }
                }
                // Folding or unfolding is what brings a clipped toggle back; this one isn't seen.
                if sidebar.isCollapsed {
                    sidebar.isCollapsed = false
                    window.layoutIfNeeded()
                    sidebar.isCollapsed = true
                }
            }
        }

        private static func sidebar(in view: NSView) -> NSSplitViewItem? {
            if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController {
                return controller.splitViewItems.first { $0.behavior == .sidebar }
            }
            return view.subviews.lazy.compactMap(sidebar).first
        }
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
