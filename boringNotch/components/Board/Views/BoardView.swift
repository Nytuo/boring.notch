//
//  BoardView.swift
//  boringNotch
//
//  F-11: a per-display, user-composed board — pick which widgets from
//  enabled extensions show, in what order, at what size.
//
//  Laid out as a single reorderable column rather than a multi-column grid:
//  SwiftUI has no reliable column-span primitive on this project's minimum
//  OS (macOS 14) that doesn't risk a layout that only turns out wrong once
//  someone actually looks at it, and there's no way to visually verify pixel
//  layout in this environment. A `List` with native `.onMove` reordering
//  gets add/remove/reorder/resize/persist-per-screen — every acceptance
//  criterion the plan lists — without hand-rolling drag-gesture geometry.
//  macOS reorders a `List` with `.onMove` by direct drag at any time — there
//  is no `EditMode` on this platform to gate it behind — so dragging a row
//  works whether or not Edit is on; Edit only gates the remove/resize
//  controls, which would be too easy to trigger by accident otherwise.
//

import SwiftUI

struct BoardView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var manager = BoardLayoutManager.shared
    @ObservedObject private var registry = ExtensionRegistry.shared

    @State private var isEditing = false
    @State private var isPickerPresented = false

    private var contentWidth: CGFloat { NotchViews.board.contentWidth }

    private var availableWidgets: [BoardWidgetDescriptor] {
        manager.availableWidgets()
    }

    private var placements: [BoardPlacement] {
        manager.reconciledLayout(for: vm.screenUUID ?? "", available: availableWidgets)
    }

    private var widgetsByID: [String: BoardWidgetDescriptor] {
        Dictionary(uniqueKeysWithValues: availableWidgets.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 8) {
            header

            if placements.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: contentWidth)
        // Registration/enablement of extensions and any Defaults change to
        // this screen's board both need to re-resolve the reconciled list.
        .id(registry.revision)
        .sheet(isPresented: $isPickerPresented) {
            BoardWidgetPickerView(
                availableWidgets: availableWidgets,
                placedWidgetIDs: Set(placements.map(\.widgetID)),
                onAdd: { widget in
                    manager.addWidget(widget, for: screenUUID)
                },
                onDone: { isPickerPresented = false }
            )
        }
    }

    private var screenUUID: String { vm.screenUUID ?? "" }

    private var header: some View {
        HStack {
            Text(NSLocalizedString("board_title", comment: "Board tab title"))
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            if isEditing {
                Button {
                    isPickerPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.smooth(duration: 0.2)) { isEditing.toggle() }
            } label: {
                Text(isEditing
                    ? NSLocalizedString("board_done", comment: "Close the add-widget sheet")
                    : NSLocalizedString("board_edit", comment: "Enter board edit mode"))
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.effectiveAccent)
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundStyle(.gray.opacity(0.6))
            Text(NSLocalizedString("board_empty", comment: "Shown when the board has no widgets"))
                .font(.callout)
                .foregroundStyle(.gray)
            Button {
                isEditing = true
                isPickerPresented = true
            } label: {
                Text(NSLocalizedString("board_add_widget_title", comment: "Title of the add-widget sheet"))
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.effectiveAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    private var list: some View {
        List {
            ForEach(placements, id: \.widgetID) { placement in
                if let widget = widgetsByID[placement.widgetID] {
                    BoardWidgetCardView(
                        widget: widget,
                        size: placement.size,
                        isEditing: isEditing,
                        onRemove: { manager.removeWidget(placement.widgetID, for: screenUUID) },
                        onCycleSize: { cycleSize(of: placement) }
                    )
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .onMove { indices, newOffset in
                move(indices, to: newOffset)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func cycleSize(of placement: BoardPlacement) {
        let all = BoardWidgetSize.allCases
        let currentIndex = all.firstIndex(of: placement.size) ?? 0
        let next = all[(currentIndex + 1) % all.count]
        manager.setSize(next, for: placement.widgetID, on: screenUUID)
    }

    private func move(_ indices: IndexSet, to newOffset: Int) {
        var reordered = placements
        reordered.move(fromOffsets: indices, toOffset: newOffset)
        manager.setPlacements(reordered, for: screenUUID)
    }
}
