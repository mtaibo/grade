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
    @ViewBuilder let content: () -> Content

    var body: some View { content() }

    static func == (lhs: Self, rhs: Self) -> Bool {
        #if os(macOS)
        lhs.value == rhs.value
        #else
        false
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
