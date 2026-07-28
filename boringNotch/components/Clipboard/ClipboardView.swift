//
//  ClipboardView.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

/// Clipboard history browser shown as a notch tab.
///
/// Entries are cards rather than list rows: the point of a clipboard history is
/// recognising what you copied, and a thumbnail or a few lines of the actual
/// text does that far faster than a truncated single line.
struct ClipboardView: View {
    @ObservedObject private var clipboard = ClipboardManager.shared
    @EnvironmentObject var vm: BoringViewModel

    private static let columnCount = 3
    private static let cardSpacing: CGFloat = 10
    private static let cardHeight: CGFloat = 104

    /// Fill the panel rather than hugging a narrow column: the wide envelope is
    /// already reserved for this tab, so leaving half of it empty is waste.
    private var contentWidth: CGFloat { NotchViews.clipboard.contentWidth }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Self.cardSpacing),
            count: Self.columnCount
        )
    }

    /// Height of the grid area, capped so a long history scrolls instead of
    /// pushing the panel past its envelope, and shrunk when there is little to
    /// show so a single card does not sit in a tall empty box.
    private var gridHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(clipboard.filteredEntries.count) / Double(Self.columnCount))))
        let natural = CGFloat(rows) * Self.cardHeight + CGFloat(rows - 1) * Self.cardSpacing
        return min(natural, 2 * Self.cardHeight + Self.cardSpacing)
    }

    var body: some View {
        VStack(spacing: 8) {
            searchField

            if clipboard.filteredEntries.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Self.cardSpacing) {
                        ForEach(clipboard.filteredEntries) { entry in
                            ClipboardCard(entry: entry, height: Self.cardHeight)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(height: gridHeight)
            }
        }
        .frame(width: contentWidth, alignment: .top)
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
                .font(.caption)
            TextField("Search clipboard", text: $clipboard.searchQuery)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white)
            if !clipboard.searchQuery.isEmpty {
                Button {
                    clipboard.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            Text("\(clipboard.filteredEntries.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.gray)
            Button {
                clipboard.clearHistory()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.gray)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Clear unpinned history")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.title2)
                .foregroundStyle(.gray)
            Text(clipboard.searchQuery.isEmpty ? "Clipboard history is empty" : "No matches")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
    }
}

/// A single history entry, shown as a preview tile.
private struct ClipboardCard: View {
    @ObservedObject private var clipboard = ClipboardManager.shared
    @State private var isHovering = false

    let entry: ClipboardEntry
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

            footer
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isHovering ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    entry.isPinned ? Color.effectiveAccent.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                actionButtons
                    .padding(5)
            } else if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.effectiveAccent)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            clipboard.copyToPasteboard(entry)
        }
        .help("Click to copy")
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        switch entry.payload {
        case .image:
            if let image = entry.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholderIcon("photo")
            }

        case .fileURLs(let urls):
            HStack(spacing: 6) {
                ForEach(urls.prefix(3), id: \.self) { url in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                if urls.count > 3 {
                    Text("+\(urls.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .overlay(alignment: .bottomLeading) {
                Text(entry.previewText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
            }

        case .text:
            Text(entry.multilineText ?? entry.previewText)
                .font(entry.isLink ? .system(size: 11) : .system(size: 11, design: .default))
                .foregroundStyle(entry.isLink ? Color.effectiveAccent : .white)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.top, 9)
        }
    }

    private func placeholderIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 5) {
            if let bundleID = entry.sourceBundleID {
                AppIcon(for: bundleID)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: entry.iconName)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .frame(width: 12)
            }

            Text(entry.kindLabel)
                .font(.system(size: 9))
                .foregroundStyle(.gray)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(entry.detailText)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.35))
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                clipboard.togglePin(entry)
            } label: {
                cardButtonIcon(entry.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "Unpin" : "Pin")

            Button {
                clipboard.delete(entry)
            } label: {
                cardButtonIcon("xmark")
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
    }

    private func cardButtonIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.black.opacity(0.55)))
    }
}
