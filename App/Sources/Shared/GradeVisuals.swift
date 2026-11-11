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

/// The final grade, in the colour of its band, once the ring would be full.
struct FinalGradeBadge: View {
    let grade: Double
    var hasHonors = false
    /// The watch's size.
    var isCompact = false

    var body: some View {
        let tint = GradeBand.color(for: grade)
        Text(hasHonors ? "\(grade.formatted(.number.precision(.fractionLength(0...2)))) MH" : grade.formatted(.number.precision(.fractionLength(0...2))))
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(tint == .yellow ? Color.orange : tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, isCompact ? 6 : 10)
            .padding(.vertical, isCompact ? 2 : 4)
            .background(tint.opacity(0.18), in: Capsule())
            .accessibilityLabel("Nota final \(grade.formatted(.number.precision(.fractionLength(0...2))))\(hasHonors ? ", matrícula de honor" : "")")
    }
}

/// A small circle that fills as grades are entered.
struct CompletionRing: View {
    let entered: Int
    let total: Int

    private var fraction: Double { min(Double(entered) / Double(max(total, 1)), 1) }
    private var isComplete: Bool { entered >= total }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isComplete ? AnyShapeStyle(.green) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 28, height: 28)
        .animation(.snappy, value: fraction)
        .accessibilityLabel("\(entered) de \(total) notas")
    }
}
