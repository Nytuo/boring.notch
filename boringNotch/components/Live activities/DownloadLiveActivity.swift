//
//  DownloadLiveActivity.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Banner shown across the closed notch while browser downloads are running.
struct DownloadLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var downloads = DownloadManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        NotchBannerLayout {
            HStack(spacing: 8) {
                icon

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            HStack {
                indicator
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }

    // MARK: Pieces

    @ViewBuilder
    private var icon: some View {
        switch Defaults[.selectedDownloadIconStyle] {
        case .onlyIcon:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.effectiveAccent)
                .imageScale(.large)
        case .onlyAppIcon:
            browserIcon
        case .iconAndAppIcon:
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.effectiveAccent)
                    .imageScale(.medium)
                browserIcon
            }
        }
    }

    /// Falls back to the generic download glyph when nothing is in flight and
    /// there is therefore no browser to attribute it to.
    @ViewBuilder
    private var browserIcon: some View {
        if let download = downloads.activeDownloads.first {
            AppIcon(for: download.browser.iconBundleID)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.effectiveAccent)
                .imageScale(.large)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if let download = downloads.activeDownloads.first {
            switch Defaults[.selectedDownloadIndicatorStyle] {
            case .percentage:
                Text(download.percentText ?? "…")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.gray)
            case .progress:
                if let progress = download.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color.effectiveAccent)
                        .frame(width: 60)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.medium)
        }
    }

    private var title: String {
        guard let download = downloads.activeDownloads.first else {
            // Name what landed when it is known — a download that never had a
            // partial file has nothing else to identify it by.
            return downloads.lastCompletedFileName ?? NSLocalizedString(
                "downloads_finished",
                comment: "All downloads have finished"
            )
        }
        if downloads.activeDownloads.count > 1 {
            return String(
                format: NSLocalizedString(
                    "downloads_multiple",
                    comment: "Several downloads in progress"
                ),
                downloads.activeDownloads.count
            )
        }
        return download.fileName
    }

    private var subtitle: String {
        guard let download = downloads.activeDownloads.first else {
            return downloads.lastCompletedFileName == nil
                ? ""
                : NSLocalizedString("downloads_finished", comment: "All downloads have finished")
        }
        return download.formattedProgress
    }
}

// MARK: - Closed notch

/// Compact progress kept beside the closed notch for as long as something is
/// downloading.
///
/// The banner above is a two-second flash when a download starts or finishes;
/// this is what makes a download visible in between, without having to open
/// anything.
struct DownloadClosedIndicator: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var downloads = DownloadManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Both sides carry content, and both are the same width, so the
            // opaque spacer stays centred on the physical notch.
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.effectiveAccent)
                    .font(.system(size: 11))

                Text(speedText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: Self.sideWidth, alignment: .trailing)
            .padding(.trailing, 4)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            Text(sizeText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.sideWidth, alignment: .leading)
                .padding(.leading, 4)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }

    /// Left of the notch: how fast, or how many while several run at once.
    private var speedText: String {
        let active = downloads.activeDownloads
        if active.count > 1 {
            return String(
                format: NSLocalizedString(
                    "downloads_multiple",
                    comment: "Several downloads in progress"
                ),
                active.count
            )
        }
        return active.first?.formattedSpeed ?? "…"
    }

    /// Right of the notch: how much of how much. Falls back to the bytes so far
    /// when the browser reports no total, which is all Safari ever gives.
    private var sizeText: String {
        guard let download = downloads.activeDownloads.first else { return "" }
        return download.formattedProgress
    }

    /// Room for "4.2 MB / 10 MB" without the notch resizing as figures grow.
    static let sideWidth: CGFloat = 96

    /// Kept for the chin-width calculation, which needs one side's width.
    static var trailingWidth: CGFloat { sideWidth }

    /// Whether there is anything to show.
    @MainActor
    static var isActive: Bool {
        Defaults[.enableDownloadListener] && !DownloadManager.shared.activeDownloads.isEmpty
    }
}

// MARK: - Opened notch

/// Downloads strip along the bottom of the opened notch.
///
/// Shown on every tab, because a download in flight is worth seeing whatever
/// else you opened the notch for.
struct DownloadOpenNotchBar: View {
    @ObservedObject private var downloads = DownloadManager.shared

    /// Two at a time keeps the strip one line tall; the rest are counted.
    private static let maxShown = 2

    /// Height the opened panel has to make room for, so the strip sits below
    /// the tab content instead of on top of it.
    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            ForEach(downloads.activeDownloads.prefix(Self.maxShown)) { download in
                row(for: download)
            }

            if downloads.activeDownloads.count > Self.maxShown {
                Text("+\(downloads.activeDownloads.count - Self.maxShown)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: Self.height - 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func row(for download: ActiveDownload) -> some View {
        HStack(spacing: 6) {
            AppIcon(for: download.browser.iconBundleID)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(download.fileName)
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let progress = download.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color.effectiveAccent)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Color.effectiveAccent)
                }
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(download.percentText ?? download.formattedProgress)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                if let speed = download.formattedSpeed {
                    Text(speed)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.gray)
                }
            }
            .lineLimit(1)
            .frame(width: 88, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
