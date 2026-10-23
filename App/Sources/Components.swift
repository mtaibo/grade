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
