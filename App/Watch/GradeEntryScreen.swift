import Engine
import SwiftUI
import WatchKit

/// Entering one note: letter chips, or the number with a keypad. The Digital Crown nudges it by a
/// tenth, and ✓ saves. It takes up the whole screen, like the iPhone's card takes the top of it.
struct GradeEntryScreen: View {
    let note: EditedNote
    let record: SubjectRecord
    let session: Convocatoria

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var entry: GradeEntry? { record.entry(for: note.name, in: session) }

    private func save(_ entry: GradeEntry?) {
        store.setEntry(entry, forLeaf: note.name, in: record.id, session: session)
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }

    var body: some View {
        SwiftUI.Group {
            if case .letters(let scale) = note.grade.inputStyle {
                LetterEntry(title: note.name, scale: scale, selected: entry?.letter, onSave: save, onClose: { dismiss() })
            } else {
                NumberEntry(title: note.name, grade: note.grade, entry: entry, onSave: save, onClose: { dismiss() })
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The ✗, the name and the ✓ across the top of the input.
private struct NumberEntry: View {
    let title: String
    let grade: Grade
    let entry: GradeEntry?
    let onSave: (GradeEntry?) -> Void
    let onClose: () -> Void

    @State private var text: String
    @State private var crown: Double
    /// Still showing the saved grade: the first digit starts a new one instead of adding to it.
    @State private var isShowingSaved: Bool

    init(title: String, grade: Grade, entry: GradeEntry?, onSave: @escaping (GradeEntry?) -> Void, onClose: @escaping () -> Void) {
        self.title = title
        self.grade = grade
        self.entry = entry
        self.onSave = onSave
        self.onClose = onClose
        let isPercent = grade.inputStyle == .percent
        let shown = entry.flatMap { $0.outOf > 0 ? $0.value / $0.outOf * (isPercent ? 100 : grade.scaleMax) : nil }
        let start = shown.map { Self.format($0) } ?? ""
        _text = State(initialValue: start)
        _crown = State(initialValue: shown ?? 0)
        _isShowingSaved = State(initialValue: shown != nil)
    }

    private var isPercent: Bool { grade.inputStyle == .percent }
    private var limit: Double { isPercent ? 100 : grade.scaleMax }
    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var isOver: Bool { (value ?? 0) > limit }
    private var canSave: Bool { value != nil && !isOver }
    private var step: Double { limit > 20 ? 1 : 0.1 }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    var body: some View {
        VStack(spacing: 4) {
            display
            keypad
        }
        .padding(.horizontal, 4)
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: limit, by: step, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, new in
            // Set by a key press as well, when it already matches there's nothing to do.
            if abs((value ?? -1) - new) > step / 2 {
                text = Self.format(new)
                isShowingSaved = false
            }
        }
    }

    private var display: some View {
        HStack(spacing: 4) {
            CircleButton(symbol: "xmark", label: "Cancelar", action: onClose)
            VStack(spacing: -2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(text.isEmpty ? "–" : text)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isOver ? Color.red : (text.isEmpty ? Color.secondary : Color.primary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(isPercent ? "%" : "/\(Self.format(grade.scaleMax))")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)
            CircleButton(symbol: "checkmark", label: "Guardar", isProminent: true) {
                if let value { onSave(GradeEntry(value: value, outOf: limit)) }
            }
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
        }
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [",", "0", "⌫"]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        KeyButton(key: key) { press(key) }
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        if isShowingSaved, key != "⌫" { text = "" }
        isShowingSaved = false
        switch key {
        case "⌫":
            if !text.isEmpty { text.removeLast() }
        case ",":
            if !text.contains(",") { text = text.isEmpty ? "0," : text + "," }
        default:
            // Two decimals at most; a leading zero gives way to the digit.
            if let comma = text.firstIndex(of: ","), text.distance(from: comma, to: text.endIndex) > 2 { return }
            text = text == "0" ? key : text + key
        }
        crown = min(value ?? 0, limit)
        WKInterfaceDevice.current().play(.click)
    }
}

private struct KeyButton: View {
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SwiftUI.Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Text(key)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchCard.fill, in: .rect(cornerRadius: 11))
            .contentShape(.rect)
        }
        .buttonStyle(TilePress())
        .accessibilityLabel(key == "⌫" ? "Borrar" : key)
    }
}

private struct CircleButton: View {
    let symbol: String
    let label: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(isProminent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(WatchCard.fill), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(TilePress())
        .accessibilityLabel(label)
    }
}

/// Letter grades as chips: tapping one saves it, tapping the current one clears it.
private struct LetterEntry: View {
    let title: String
    let scale: [LetterGrade]
    let selected: String?
    let onSave: (GradeEntry?) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    CircleButton(symbol: "xmark", label: "Cancelar", action: onClose)
                    Text(title)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
                    ForEach(scale) { letter in
                        let isSelected = letter.letter == selected
                        Button {
                            onSave(isSelected ? nil : GradeEntry(value: letter.value, outOf: 10, letter: letter.letter))
                        } label: {
                            Text(letter.letter)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(WatchCard.fill), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(TilePress())
                        .accessibilityLabel("\(letter.letter), \(letter.value.formatted()) sobre 10")
                    }
                }
            }
        }
    }
}
