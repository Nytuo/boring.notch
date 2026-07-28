//
//  ScreenshotViews.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Banner shown across the closed notch the moment a screenshot is taken.
struct ScreenshotLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var screenshots = ScreenshotManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        NotchBannerLayout {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .foregroundStyle(Color.effectiveAccent)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screenshot captured")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(screenshots.latest?.fileName ?? "")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            thumbnail
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = screenshots.latest?.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: max(12, closedNotchHeight - 12))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

/// Preview with actions, in the opened notch.
///
/// A screenshot is almost always taken to be done something with straight
/// away — copied, dragged somewhere, or deleted because it was wrong. This puts
/// those within one click instead of a trip to the Desktop.
struct ScreenshotOpenNotchBar: View {
    @ObservedObject private var screenshots = ScreenshotManager.shared
    @Default(.boringShelf) private var shelfEnabled

    /// Height the opened panel makes room for.
    static let height: CGFloat = 62

    var body: some View {
        HStack(spacing: 10) {
            preview

            VStack(alignment: .leading, spacing: 1) {
                Text("Screenshot captured")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(screenshots.latest?.fileName ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            action("doc.on.doc", "Copy") { screenshots.copyToPasteboard() }
            if shelfEnabled {
                action("tray.and.arrow.down", "Add to Shelf") { screenshots.addToShelf() }
            }
            action("magnifyingglass", "Reveal in Finder") { screenshots.revealInFinder() }
            action("trash", "Delete", destructive: true) { screenshots.deleteFile() }
            action("xmark", "Dismiss") { screenshots.dismiss() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: Self.height - 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let screenshot = screenshots.latest {
            let image = screenshot.thumbnail
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: 56, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            // Dragging the preview straight into another app is the fastest
            // route of all, and costs nothing to offer.
            .onDrag { NSItemProvider(contentsOf: screenshot.url) ?? NSItemProvider() }
        }
    }

    private func action(
        _ icon: String,
        _ label: String,
        destructive: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(destructive ? .red : .white)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
