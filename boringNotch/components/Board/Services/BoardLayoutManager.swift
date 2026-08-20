//
//  BoardLayoutManager.swift
//  boringNotch
//
//  F-11: per-screen board persistence and reconciliation. Widget order
//  reuses `NotchLayoutResolver.reconcile` — generic over any `Hashable`, so
//  the same self-healing merge `NotchTabItem`/`NotchHeaderItem` get for
//  free applies here to widget ids.
//

import Defaults
import SwiftUI

@MainActor
final class BoardLayoutManager: ObservableObject {
    static let shared = BoardLayoutManager()

    private init() {}

    /// Every widget contributed by a currently-enabled extension, in
    /// registration order.
    func availableWidgets() -> [BoardWidgetDescriptor] {
        ExtensionRegistry.shared.extensions
            .filter(\.isEnabled)
            .flatMap { $0.boardWidgets() }
    }

    /// The board for `screenUUID`, reconciled against `availableWidgets()`:
    /// widgets whose extension is now disabled (or removed) drop out,
    /// widgets not yet placed are appended at their default size. Stored
    /// order and chosen sizes are preserved.
    func reconciledLayout(for screenUUID: String, available: [BoardWidgetDescriptor]) -> [BoardPlacement] {
        let stored = Defaults[.boardLayoutsByScreen][screenUUID]?.placements ?? []
        let availableIDs = available.map(\.id)

        let orderedIDs = NotchLayoutResolver.reconcile(stored.map(\.widgetID), all: availableIDs)
        let sizeByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.widgetID, $0.size) })
        let defaultSizeByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0.defaultSize) })

        return orderedIDs.compactMap { id in
            guard let size = sizeByID[id] ?? defaultSizeByID[id] else { return nil }
            return BoardPlacement(widgetID: id, size: size)
        }
    }

    func setPlacements(_ placements: [BoardPlacement], for screenUUID: String) {
        var all = Defaults[.boardLayoutsByScreen]
        all[screenUUID] = BoardLayout(placements: placements)
        Defaults[.boardLayoutsByScreen] = all
    }

    func removeWidget(_ widgetID: String, for screenUUID: String) {
        var placements = Defaults[.boardLayoutsByScreen][screenUUID]?.placements ?? []
        placements.removeAll { $0.widgetID == widgetID }
        setPlacements(placements, for: screenUUID)
    }

    func addWidget(_ widget: BoardWidgetDescriptor, for screenUUID: String) {
        var placements = Defaults[.boardLayoutsByScreen][screenUUID]?.placements ?? []
        guard !placements.contains(where: { $0.widgetID == widget.id }) else { return }
        placements.append(BoardPlacement(widgetID: widget.id, size: widget.defaultSize))
        setPlacements(placements, for: screenUUID)
    }

    func setSize(_ size: BoardWidgetSize, for widgetID: String, on screenUUID: String) {
        var placements = Defaults[.boardLayoutsByScreen][screenUUID]?.placements ?? []
        guard let index = placements.firstIndex(where: { $0.widgetID == widgetID }) else { return }
        placements[index].size = size
        setPlacements(placements, for: screenUUID)
    }
}
