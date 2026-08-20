//
//  BoardModels.swift
//  boringNotch
//
//  F-11: the board is a per-display, user-composed grid of widgets
//  contributed by enabled extensions — `NotchLayout.swift` gives ordering,
//  this gives position (well, order) + size on top of it, persisted per
//  screen. `Defaults` keys declared in their own file per CLAUDE.md.
//

import Defaults
import SwiftUI

enum BoardWidgetSize: String, CaseIterable, Codable {
    case small
    case wide
    case large

    var label: String {
        switch self {
        case .small: return NSLocalizedString("board_size_small", comment: "Board widget size: small")
        case .wide: return NSLocalizedString("board_size_wide", comment: "Board widget size: wide")
        case .large: return NSLocalizedString("board_size_large", comment: "Board widget size: large")
        }
    }

    /// Card height at each size. Width always fills the board's content
    /// width — see F-11 note in `BoardView` on why this isn't a
    /// multi-column grid.
    var height: CGFloat {
        switch self {
        case .small: return 56
        case .wide: return 96
        case .large: return 160
        }
    }
}

/// One widget's placement on a screen's board.
struct BoardPlacement: Codable, Hashable {
    var widgetID: String
    var size: BoardWidgetSize
}

/// A screen's whole board: which widgets, in what order, at what size.
/// `Codable` is enough to satisfy `Defaults.Serializable` — the package
/// bridges any `Codable` type automatically.
struct BoardLayout: Codable, Defaults.Serializable {
    var placements: [BoardPlacement] = []
}

/// What an extension contributes to the board (F-11's `boardWidgets()`).
/// `content` is rebuilt on every call rather than cached, so it always
/// reflects the extension's live state — the same reason `settingsView` on
/// `BoringExtension` is a computed property, not stored.
struct BoardWidgetDescriptor: Identifiable {
    /// Board-wide unique id — `"<extension manifest id>.<local name>"`,
    /// e.g. `"com.theboringteam.extension.caffeine.countdown"`. This is what
    /// `BoardPlacement.widgetID` stores.
    let id: String
    /// Owning extension's manifest id, so a board auto-heals when the
    /// extension is disabled — see `BoardLayoutManager.reconciledLayout`.
    let extensionID: String
    let title: String
    let iconName: String
    let defaultSize: BoardWidgetSize
    let content: AnyView

    init(localID: String, extensionID: String, title: String, iconName: String, defaultSize: BoardWidgetSize, content: AnyView) {
        self.id = "\(extensionID).\(localID)"
        self.extensionID = extensionID
        self.title = title
        self.iconName = iconName
        self.defaultSize = defaultSize
        self.content = content
    }
}

extension Defaults.Keys {
    static let boardEnabled = Key<Bool>("boardEnabled", default: true)
    static let boardLayoutsByScreen = Key<[String: BoardLayout]>("boardLayoutsByScreen", default: [:])
}
