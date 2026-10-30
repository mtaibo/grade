import Engine
import SwiftUI

/// 0…10 track: solid up to what's already secured, faint up to the best case still reachable,
/// with a tick at the pass threshold — the whole "where do I stand" in one line.
struct GradeRangeBar: View {
    let worst: Double
    let best: Double
    let threshold: Double
    let tint: Color
    var scale: Double = 10

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint.opacity(0.25))
                    .frame(width: width * fraction(best))
                Capsule().fill(tint)
                    .frame(width: width * fraction(worst))
                Rectangle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: 2, height: 12)
                    .offset(x: width * fraction(threshold) - 1)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func fraction(_ value: Double) -> Double {
        min(max(value / scale, 0), 1)
    }
}

/// The colour a finished grade (out of 10) gets: red below 5, yellow up to 7, green up to 9, purple
/// from 9. Only used once everything in a section is entered — until then bars stay blue.
enum GradeBand {
    static func color(for grade: Double) -> Color {
        switch grade {
        case ..<5: .red
        case ..<7: .yellow
        case ..<9: .green
        default: .purple
        }
    }
}

extension PassStatus {
    var tint: Color {
        switch self {
        case .guaranteed: .green
        case .possible: .orange
        case .impossible: .red
        }
    }
}

extension View {
    /// The rounded, raised surface every card in the app sits on.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
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
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
