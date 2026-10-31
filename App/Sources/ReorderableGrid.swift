import SwiftUI

/// The home-screen wobble: a small, slightly different rotation per tile so they don't move in step.
struct Wiggle: ViewModifier {
    let seed: Int
    @State private var tilted = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(tilted ? 1.6 : -1.6))
            .animation(
                .easeInOut(duration: 0.11 + Double(seed % 4) * 0.015).repeatForever(autoreverses: true),
                value: tilted
            )
            .onAppear { tilted = true }
    }
}

/// A grid of subject tiles that, while editing, wobble and can be dragged: the tile follows the
/// finger and the others slide out of the way live, like icons on the Home Screen.
///
/// Reordering works on fixed slots. When a drag starts the slots (each tile's frame, in order)
/// are captured; as the finger moves, the dragged tile takes whichever slot its centre is nearest
/// and the rest shift along. Tiles all have the same height, so a slot is always the same shape
/// whichever tile sits in it.
struct ReorderableGrid<Normal: View, Trailing: View>: View {
    let records: [SubjectRecord]
    let isEditing: Bool
    let columns: [GridItem]
    /// One slim row per subject (the list view) instead of tall cards.
    var isCompact = false
    /// Called with the new order of the records' ids once a drag ends.
    let commit: ([SubjectRecord.ID]) -> Void
    /// Called when a tile's − badge is tapped.
    let onDelete: (SubjectRecord) -> Void
    @ViewBuilder let normal: (SubjectRecord) -> Normal
    @ViewBuilder let trailing: () -> Trailing

    @Environment(Library.self) private var library
    @State private var order: [SubjectRecord.ID]?
    @State private var frames: [SubjectRecord.ID: CGRect] = [:]
    @State private var slots: [CGRect] = []
    @State private var dragging: SubjectRecord.ID?
    @State private var grabOffset = CGSize.zero
    @State private var finger = CGPoint.zero
    /// True while a tile's drag is in progress. A gesture the system cancels (a call, a
    /// notification pulled down) never calls `onEnded`, but this always resets, so the drag is
    /// finished either way instead of leaving a tile stuck under the finger.
    @GestureState private var isPressing = false

    private let space = "reorderableGrid"

    private var displayed: [SubjectRecord] {
        guard let order else { return records }
        let byID = Dictionary(records.map { ($0.id, $0) }) { first, _ in first }
        // A subject added or deleted mid-drag still shows (or goes) instead of trapping.
        let ordered = order.compactMap { byID[$0] }
        return ordered + records.filter { !order.contains($0.id) }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(displayed) { record in
                if isEditing {
                    editableTile(record)
                } else {
                    normal(record)
                }
            }
            if isEditing { trailing() }
        }
        .coordinateSpace(.named(space))
        .onChange(of: isEditing) { _, editing in
            if !editing { reset() }
        }
        .onChange(of: isPressing) { _, pressing in
            if !pressing { finish() }
        }
        // Once the committed order is back in `records`, the grid can follow them again. The
        // order is the same, so nothing moves.
        .onChange(of: records.map(\.id)) { _, ids in
            if dragging == nil, ids == order { order = nil }
        }
    }

    private func editableTile(_ record: SubjectRecord) -> some View {
        let isDragging = dragging == record.id
        return SubjectTile(record: record, isCompact: isCompact, rounding: library.degree.rounding)
            // Inside the tile, before the wobble, so the badge is part of the card and tilts with it.
            .overlay(alignment: .topLeading) { deleteBadge(for: record) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[record.id] = $0 }
            .modifier(Wiggle(seed: Int(record.id.uuid.1)))
            .scaleEffect(isDragging ? 1.06 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.22 : 0), radius: 14, y: 8)
            .offset(isDragging ? dragOffset : .zero)
            .zIndex(isDragging ? 1 : 0)
            .onTapGesture {}
            .gesture(reorderGesture(for: record))
    }

    /// The − at a tile's top-left corner. It steps aside while any tile is being dragged.
    private func deleteBadge(for record: SubjectRecord) -> some View {
        Button { onDelete(record) } label: {
            Image(systemName: "minus")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color(.systemGray), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The circle sits a little outside the card's corner.
        .offset(x: -14, y: -14)
        .opacity(dragging == nil ? 1 : 0)
        .allowsHitTesting(dragging == nil)
        .accessibilityLabel("Eliminar \(record.subject.name)")
    }

    /// Where the dragged tile sits relative to the slot it currently occupies in the layout.
    private var dragOffset: CGSize {
        guard let dragging, let index = displayed.firstIndex(where: { $0.id == dragging }), slots.indices.contains(index) else {
            return .zero
        }
        let origin = slots[index].origin
        return CGSize(width: finger.x - grabOffset.width - origin.x, height: finger.y - grabOffset.height - origin.y)
    }

    /// Already in edit mode, so a plain drag moves the tile — no hold first, like the Home Screen.
    /// The few points of slack keep a tap on the tile from counting as a drag.
    private func reorderGesture(for record: SubjectRecord) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
            .updating($isPressing) { _, state, _ in state = true }
            .onChanged { drag in
                if dragging == nil { begin(record, at: drag.startLocation) }
                finger = drag.location
                moveIfNeeded()
            }
            .onEnded { _ in finish() }
    }

    private func begin(_ record: SubjectRecord, at start: CGPoint) {
        let ids = displayed.map(\.id)
        let captured = ids.compactMap { frames[$0] }
        guard captured.count == ids.count, let own = frames[record.id] else { return }
        slots = captured
        order = ids
        grabOffset = CGSize(width: start.x - own.minX, height: start.y - own.minY)
        finger = start
        withAnimation(.snappy) { dragging = record.id }
    }

    private func moveIfNeeded() {
        guard let dragging, var ids = order, let current = ids.firstIndex(of: dragging), slots.indices.contains(current) else { return }
        let size = slots[current].size
        let center = CGPoint(
            x: finger.x - grabOffset.width + size.width / 2,
            y: finger.y - grabOffset.height + size.height / 2
        )
        func distance(_ slot: CGRect) -> Double {
            hypot(slot.midX - center.x, slot.midY - center.y)
        }
        guard let target = slots.indices.min(by: { distance(slots[$0]) < distance(slots[$1]) }), target != current else { return }
        ids.move(fromOffsets: [current], toOffset: target > current ? target + 1 : target)
        withAnimation(.snappy) { order = ids }
    }

    /// Keeps showing `order` until `records` catch up: switching back to them in the same update
    /// as the commit sent the tiles that had moved flying off and back.
    private func finish() {
        guard dragging != nil, let order else { return }
        commit(order)
        withAnimation(.snappy) { dragging = nil }
    }

    private func reset() {
        withAnimation(.snappy) {
            dragging = nil
            order = nil
        }
    }
}
