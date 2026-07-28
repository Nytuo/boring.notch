//
//  SystemStatsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// CPU, memory and network load beside the closed notch.
///
/// Uses both sides of the cutout like the download reading does, and stays put
/// rather than flashing: this is ambient information, not an event.
struct SystemStatsClosedIndicator: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var stats = SystemStatsManager.shared

    @Default(.systemStatsShowCPU) private var showCPU
    @Default(.systemStatsShowMemory) private var showMemory
    @Default(.systemStatsShowNetwork) private var showNetwork

    let closedNotchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if showCPU {
                    reading("cpu", SystemStatsManager.formatPercent(stats.cpuUsage), warn: stats.cpuUsage >= 0.85)
                }
                if showMemory {
                    reading("memorychip", SystemStatsManager.formatPercent(stats.memoryUsage), warn: stats.memoryUsage >= 0.9)
                }
            }
            .frame(width: Self.sideWidth, alignment: .trailing)
            .padding(.trailing, 4)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            HStack(spacing: 6) {
                if showNetwork {
                    reading("arrow.down", SystemStatsManager.formatRate(stats.downloadRate), warn: false)
                    reading("arrow.up", SystemStatsManager.formatRate(stats.uploadRate), warn: false)
                }
            }
            .frame(width: Self.sideWidth, alignment: .leading)
            .padding(.leading, 4)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }

    private func reading(_ icon: String, _ value: String, warn: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(warn ? .orange : Color.effectiveAccent)
            Text(value)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    /// Room for two readings a side without the notch resizing as figures move.
    static let sideWidth: CGFloat = 104

    /// Whether there is anything to show.
    @MainActor
    static var isActive: Bool {
        guard Defaults[.systemStatsEnabled], Defaults[.systemStatsShowOnClosedNotch] else { return false }
        return Defaults[.systemStatsShowCPU]
            || Defaults[.systemStatsShowMemory]
            || Defaults[.systemStatsShowNetwork]
    }
}

// MARK: - Tab

/// The stats tab: current load plus where it has been.
///
/// A single number says whether the machine is busy now; the graph says whether
/// it is climbing, which is the part worth opening a panel for.
struct SystemStatsView: View {
    @ObservedObject private var stats = SystemStatsManager.shared

    private var contentWidth: CGFloat { NotchViews.systemStats.contentWidth }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 10) {
                StatsCard(
                    title: "CPU",
                    icon: "cpu",
                    value: SystemStatsManager.formatPercent(stats.cpuUsage),
                    tint: stats.cpuUsage >= 0.85 ? .orange : Color.effectiveAccent,
                    series: [stats.history.map(\.cpu)],
                    seriesTints: [stats.cpuUsage >= 0.85 ? .orange : Color.effectiveAccent],
                    caption: cpuCaption
                )
                StatsCard(
                    title: "Memory",
                    icon: "memorychip",
                    value: SystemStatsManager.formatPercent(stats.memoryUsage),
                    tint: stats.memoryUsage >= 0.9 ? .orange : .purple,
                    series: [stats.history.map(\.memory)],
                    seriesTints: [stats.memoryUsage >= 0.9 ? .orange : .purple],
                    caption: memoryCaption
                )
            }
            .frame(maxWidth: .infinity)

            StatsCard(
                title: "Network",
                icon: "network",
                value: SystemStatsManager.formatRate(stats.downloadRate),
                tint: .cyan,
                series: [
                    stats.history.map { $0.download / stats.peakNetworkRate },
                    stats.history.map { $0.upload / stats.peakNetworkRate }
                ],
                seriesTints: [.cyan, .green],
                caption: networkCaption
            )
            .frame(maxWidth: .infinity)
        }
        .frame(width: contentWidth)
        .frame(maxHeight: .infinity)
        .onAppear { stats.start() }
    }

    private var cpuCaption: String {
        let peak = stats.history.map(\.cpu).max() ?? stats.cpuUsage
        return String(
            format: NSLocalizedString("stats_peak", comment: "Peak reading over the window"),
            SystemStatsManager.formatPercent(peak)
        )
    }

    private var memoryCaption: String {
        let used = Double(ProcessInfo.processInfo.physicalMemory) * stats.memoryUsage
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB]
        return "\(formatter.string(fromByteCount: Int64(used))) / \(formatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory)))"
    }

    private var networkCaption: String {
        "↓ \(SystemStatsManager.formatRate(stats.downloadRate))   ↑ \(SystemStatsManager.formatRate(stats.uploadRate))"
    }
}

/// One reading: heading, current value, graph, and a line of context.
private struct StatsCard: View {
    let title: LocalizedStringKey
    let icon: String
    let value: String
    let tint: Color
    /// Each series is already normalised to 0...1.
    let series: [[Double]]
    let seriesTints: [Color]
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            ZStack {
                // Faint gridlines give the curve a scale to be read against.
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider().overlay(Color.white.opacity(0.06))
                        Spacer(minLength: 0)
                    }
                }

                ForEach(Array(series.enumerated()), id: \.offset) { index, values in
                    let colour = seriesTints.indices.contains(index) ? seriesTints[index] : tint
                    ZStack {
                        Sparkline(values: values, closed: true)
                            .fill(
                                LinearGradient(
                                    colors: [colour.opacity(0.35), colour.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Sparkline(values: values, closed: false)
                            .stroke(colour, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(caption)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
    }
}

/// Plots a 0...1 series left to right, oldest first.
private struct Sparkline: Shape {
    let values: [Double]
    /// Closed shapes drop to the baseline at both ends so they can be filled.
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }

        let step = rect.width / CGFloat(values.count - 1)
        func point(_ index: Int) -> CGPoint {
            let value = min(1, max(0, values[index]))
            return CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - CGFloat(value) * rect.height)
        }

        if closed {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: point(0))
        } else {
            path.move(to: point(0))
        }

        for index in 1..<values.count {
            path.addLine(to: point(index))
        }

        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Header accessory

/// Live CPU load in the opened notch header, and the way into the graphs.
///
/// Stats have no tab of their own while this is showing — the icon is the
/// entrance, the same rule the weather and Bluetooth panels follow.
struct SystemStatsHeaderIndicator: View {
    @ObservedObject private var stats = SystemStatsManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    private var isSelected: Bool { coordinator.currentView == .systemStats }
    private var isBusy: Bool { stats.cpuUsage >= 0.85 }

    var body: some View {
        Button {
            withAnimation(.smooth) {
                coordinator.currentView = isSelected ? .player : .systemStats
            }
        } label: {
            Capsule()
                .fill(isSelected ? Color(nsColor: .secondarySystemFill) : .black)
                .frame(width: 62, height: 30)
                .overlay {
                    HStack(spacing: 3) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(isBusy ? .orange : Color.effectiveAccent)
                            .imageScale(.small)
                        Text(SystemStatsManager.formatPercent(stats.cpuUsage))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText)
        .onAppear { stats.start() }
    }

    private var helpText: String {
        "CPU \(SystemStatsManager.formatPercent(stats.cpuUsage))"
            + "   RAM \(SystemStatsManager.formatPercent(stats.memoryUsage))"
            + "   ↓ \(SystemStatsManager.formatRate(stats.downloadRate))"
            + "   ↑ \(SystemStatsManager.formatRate(stats.uploadRate))"
    }
}
