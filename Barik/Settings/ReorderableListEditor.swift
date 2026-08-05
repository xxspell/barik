import SwiftUI
import UniformTypeIdentifiers

struct ReorderableDragItem: Equatable {
    let groupID: String
    let index: Int
}

struct ReorderableDropTarget: Equatable {
    let groupID: String
    let destinationIndex: Int
}

struct ReorderableDropDelegate: DropDelegate {
    let groupID: String
    let destinationIndex: Int
    @Binding var draggedItem: ReorderableDragItem?
    @Binding var dropTarget: ReorderableDropTarget?
    let onMove: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let currentDrag = draggedItem, currentDrag.groupID == groupID else {
            return
        }
        withAnimation(.easeInOut(duration: 0.14)) {
            dropTarget = .init(
                groupID: groupID,
                destinationIndex: currentDrag.index == destinationIndex
                    ? currentDrag.index
                    : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        withAnimation(.easeInOut(duration: 0.14)) {
            dropTarget = .init(groupID: groupID, destinationIndex: destinationIndex)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.14)) {
            if dropTarget?.groupID == groupID
                && dropTarget?.destinationIndex == destinationIndex {
                dropTarget = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            withAnimation(.easeInOut(duration: 0.14)) {
                draggedItem = nil
                dropTarget = nil
            }
        }
        guard let draggedItem, draggedItem.groupID == groupID else {
            return false
        }

        let adjustedDestination = adjustedDestinationIndex(
            sourceIndex: draggedItem.index,
            destinationIndex: destinationIndex
        )
        guard adjustedDestination != draggedItem.index else {
            return true
        }

        onMove(draggedItem.index, adjustedDestination)
        return true
    }

    private func adjustedDestinationIndex(sourceIndex: Int, destinationIndex: Int) -> Int {
        if destinationIndex > sourceIndex {
            return max(0, destinationIndex - 1)
        }
        return destinationIndex
    }
}

struct ReorderableInsertionZone: View {
    let isTargeted: Bool

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: isTargeted ? 18 : 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isTargeted ? Color.accentColor.opacity(0.55) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.spring(response: 0.18, dampingFraction: 0.9), value: isTargeted)
    }
}

struct ReorderableListEditor<Item: Identifiable, RowContent: View>: View {
    let groupID: String
    let items: [Item]
    let onMove: (Int, Int) -> Void
    @ViewBuilder let rowContent: (Item, Int, Bool) -> RowContent

    @State private var draggedItem: ReorderableDragItem?
    @State private var dropTarget: ReorderableDropTarget?

    var body: some View {
        VStack(spacing: 8) {
            ReorderableInsertionZone(
                isTargeted: dropTarget == .init(groupID: groupID, destinationIndex: 0)
            )
            .onDrop(
                of: [UTType.plainText],
                delegate: ReorderableDropDelegate(
                    groupID: groupID,
                    destinationIndex: 0,
                    draggedItem: $draggedItem,
                    dropTarget: $dropTarget,
                    onMove: onMove
                )
            )

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                rowContent(
                    item,
                    index,
                    draggedItem?.groupID == groupID && draggedItem?.index == index
                )
                .onDrag {
                    draggedItem = .init(groupID: groupID, index: index)
                    return NSItemProvider(object: "\(index)" as NSString)
                }

                ReorderableInsertionZone(
                    isTargeted: dropTarget == .init(groupID: groupID, destinationIndex: index + 1)
                )
                .onDrop(
                    of: [UTType.plainText],
                    delegate: ReorderableDropDelegate(
                        groupID: groupID,
                        destinationIndex: index + 1,
                        draggedItem: $draggedItem,
                        dropTarget: $dropTarget,
                        onMove: onMove
                    )
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .animation(
            .spring(response: 0.22, dampingFraction: 0.9),
            value: items.map(\.id)
        )
    }
}
