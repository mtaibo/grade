import Engine
import SwiftUI

extension View {
    /// The rounded, raised surface every card in the app sits on.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}

/// The words that depend on the device the screens are on.
enum Device {
    #if os(macOS)
    static let name = "Mac"
    static let tap = "Haz clic"
    static let tapOn = "Haz clic en"
    #else
    static let name = "iPhone"
    static let tap = "Toca"
    static let tapOn = "Toca"
    #endif
}

extension View {
    /// Sheets on the Mac are as small as their content, which for a form is next to nothing.
    @ViewBuilder
    func macSheetSize(width: CGFloat = 560, height: CGFloat = 680) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }

    /// Keeps a screen's cards to a comfortable width on a wide window, centred.
    @ViewBuilder
    func macReadableWidth(_ width: CGFloat = 760) -> some View {
        #if os(macOS)
        frame(maxWidth: width).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    /// Room above a screen's title, which the top of a window would crowd; level with Cuenta's.
    @ViewBuilder
    func macTopMargin() -> some View {
        #if os(macOS)
        padding(.top, 20)
        #else
        self
        #endif
    }

    /// A thinner scroll bar for the `ScrollView` holding this view. Goes on its content.
    @ViewBuilder
    func macThinScrollBar() -> some View {
        #if os(macOS)
        background(ThinScrollBar())
        #else
        self
        #endif
    }

    /// One width for every row's icon, so their text lines up. The iPhone's lists already do this.
    @ViewBuilder
    func macRowIcon() -> some View {
        #if os(macOS)
        frame(width: 24)
        #else
        self
        #endif
    }
}

/// A pushed screen that takes a binding, for the destination of a `NavigationLink`. On the Mac a
/// screen that reads such a binding and is pushed from another one loops: rebuilding its parent gives
/// the link a new destination, which updates the navigation, which rebuilds the parent, until AppKit
/// ends the app ("more Update Constraints in Window passes than there are views in the window").
/// So its parent only rebuilds it when `value`, what the screen shows and edits, has changed.
struct StableDestination<Value: Equatable, Content: View>: View, Equatable {
    let value: Value
    /// Whether it's one of the editor's inner screens, which need the way back.
    var isCounted = true
    @ViewBuilder let content: () -> Content

    #if os(macOS)
    @Environment(MacPushCount.self) private var pushes: MacPushCount?
    #endif

    var body: some View {
        content()
            #if os(macOS)
            .onAppear { if isCounted { pushes?.open += 1 } }
            .onDisappear { if isCounted { pushes?.open -= 1 } }
            #endif
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        #if os(macOS)
        lhs.value == rhs.value
        #else
        false
        #endif
    }
}

#if os(macOS)
/// Counts the `StableDestination`s open above the editor, which hides the way back for its own ✗:
/// on the Mac that reaches the screens pushed from it too, and its `onDisappear` doesn't fire when
/// one is pushed. Lives at the root because pushed screens inherit from the window's stack, not
/// from the screen they were pushed from.
@Observable
final class MacPushCount {
    var open = 0
}
#endif

/// The ✗ and the blue ✓ of a screen that edits something. The roles draw them on the iPhone; on
/// the Mac they come out as the words «Cerrar» and «Aceptar».
struct CloseToolbarButton: View {
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        Button("Cerrar", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .keyboardShortcut(.cancelAction)
        #else
        Button(role: .close, action: action)
        #endif
    }
}

struct SaveToolbarButton: View {
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        Button("Guardar", systemImage: "checkmark", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.blue)
        #else
        Button(role: .confirm, action: action)
            .tint(.blue)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Where those two go: a sheet's places on the iPhone; on the Mac,
    /// where a sheet would put them in a strip along its bottom, the window's bar.
    static var closeAction: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .cancellationAction
        #endif
    }

    static var saveAction: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .confirmationAction
        #endif
    }
}

extension Binding {
    /// Like SwiftUI's `Binding(_: Binding<Value?>)`, which force-unwraps on every read: when the
    /// value turns `nil` (a date switched off, a group turned into a single grade) a view that
    /// hasn't been torn down yet can still read it and crash. This one keeps answering with the
    /// last value it had, and ignores writes once the value is gone.
    init?(unwrapping base: Binding<Value?>) {
        guard let initial = base.wrappedValue else { return nil }
        self.init(
            get: { base.wrappedValue ?? initial },
            set: { if base.wrappedValue != nil { base.wrappedValue = $0 } }
        )
    }
}

/// A labelled text field kept on one line: the label at its natural width, the field filling the
/// rest and scrolling within it. `LabeledContent` alone drops a long value under the label.
struct InlineField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .fixedSize()
            content
                // A Mac's form would show the field's own title as a second label.
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
