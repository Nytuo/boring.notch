//
//  AppSwitcherView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Grid of running applications, shown as a notch tab.
struct AppSwitcherView: View {
    @ObservedObject private var switcher = AppSwitcherManager.shared
    @EnvironmentObject var vm: BoringViewModel

    private static let tileSpacing: CGFloat = 8
    private static let tileHeight: CGFloat = 74
    private static let maxColumns = 8

    /// The panel width is reserved for this tab either way, so the grid spans
    /// it and lets the tiles breathe rather than hugging a narrow block.
    private var contentWidth: CGFloat { NotchViews.apps.contentWidth }

    private static let tileWidth: CGFloat = {
        let available = NotchViews.apps.contentWidth - CGFloat(maxColumns - 1) * tileSpacing
        return floor(available / CGFloat(maxColumns))
    }()

    private var columnCount: Int {
        max(1, min(Self.maxColumns, switcher.apps.count))
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Self.tileWidth), spacing: Self.tileSpacing),
            count: columnCount
        )
    }

    /// Two rows of tiles before the grid starts scrolling, shrinking to one
    /// when that is all there is to show.
    private var gridHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(switcher.apps.count) / Double(Self.maxColumns))))
        let natural = CGFloat(rows) * Self.tileHeight + CGFloat(rows - 1) * Self.tileSpacing
        return min(natural, 2 * Self.tileHeight + Self.tileSpacing)
    }

    var body: some View {
        Group {
            if switcher.apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.title2)
                        .foregroundStyle(.gray)
                    Text("No running apps")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .frame(width: 200, height: 100)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: Self.tileSpacing) {
                        ForEach(switcher.apps) { app in
                            AppSwitcherTile(app: app, width: Self.tileWidth) {
                                switcher.activate(app)
                                vm.close()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: contentWidth, height: gridHeight)
            }
        }
        .onAppear { switcher.refresh() }
    }
}

private struct AppSwitcherTile: View {
    @ObservedObject private var switcher = AppSwitcherManager.shared
    @State private var isHovering = false

    let app: RunningApp
    let width: CGFloat
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .opacity(app.isHidden ? 0.45 : 1)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 34))
                        .foregroundStyle(.gray)
                        .frame(width: 44, height: 44)
                }

                // Running/active dot, mirroring the Dock's indicator.
                Circle()
                    .fill(app.isActive ? Color.effectiveAccent : Color.gray)
                    .frame(width: 5, height: 5)
                    .offset(y: 5)
            }

            Text(app.name)
                .font(.system(size: 10))
                .foregroundStyle(app.isHidden ? .gray : .white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.white.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Bring to Front") { switcher.activate(app) }
            Button("Hide") { switcher.hide(app) }
            Divider()
            Button("Quit", role: .destructive) { switcher.quit(app) }
        }
        .help(app.name)
    }
}
