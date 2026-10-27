import SwiftUI

/// Picks a subject's icon and colour, with the tile itself as the live preview.
struct CustomizeSubjectView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let record: SubjectRecord
    @State private var symbol: String
    @State private var colorName: String

    init(record: SubjectRecord) {
        self.record = record
        let style = SubjectStyle(record)
        _symbol = State(initialValue: style.symbol)
        _colorName = State(initialValue: style.colorName)
    }

    private let colorColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
    private let symbolColumns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    private var tint: Color { (SubjectColor(rawValue: colorName) ?? .blue).color }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SubjectTile(name: record.subject.name, symbol: symbol, tint: tint)
                        .frame(maxWidth: 190)
                        .frame(maxWidth: .infinity)

                    section("Color") {
                        LazyVGrid(columns: colorColumns, spacing: 12) {
                            ForEach(SubjectColor.allCases) { option in
                                Button { colorName = option.rawValue } label: {
                                    Circle()
                                        .fill(option.color.gradient)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            if option.rawValue == colorName {
                                                Image(systemName: "checkmark")
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .padding(2)
                                        .overlay {
                                            Circle().strokeBorder(option.rawValue == colorName ? option.color : .clear, lineWidth: 2)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.rawValue)
                                .accessibilityAddTraits(option.rawValue == colorName ? .isSelected : [])
                            }
                        }
                    }

                    section("Icono") {
                        LazyVGrid(columns: symbolColumns, spacing: 10) {
                            ForEach(SubjectStyle.pickableSymbols, id: \.self) { option in
                                Button { symbol = option } label: {
                                    Image(systemName: option)
                                        .font(.title3)
                                        .foregroundStyle(option == symbol ? Color.white : Color.primary)
                                        .frame(width: 52, height: 52)
                                        .background(option == symbol ? tint : Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option)
                                .accessibilityAddTraits(option == symbol ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Personalizar")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: symbol)
            .sensoryFeedback(.selection, trigger: colorName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        library.setStyle(symbol: symbol, colorName: colorName, for: record.id)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            content()
        }
    }
}
