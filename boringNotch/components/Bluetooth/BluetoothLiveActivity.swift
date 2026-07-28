//
//  BluetoothLiveActivity.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Banner shown across the closed notch when a Bluetooth device connects or
/// disconnects. Matches the battery notification's geometry.
struct BluetoothLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var bluetooth = BluetoothManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        if let event = bluetooth.lastEvent {
            NotchBannerLayout {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(event.device.name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(statusText(for: event))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

                HStack(spacing: 6) {
                    if Defaults[.bluetoothShowBatteryLevel],
                       let percent = event.device.batteryPercentText,
                       event.connected {
                        Text(percent)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.gray)
                    }
                    Image(systemName: event.device.iconName)
                        .imageScale(.medium)
                        .foregroundStyle(event.connected ? Color.effectiveAccent : .gray)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            }
            .frame(height: closedNotchHeight, alignment: .center)
        }
    }

    private func statusText(for event: BluetoothEvent) -> String {
        event.connected
            ? NSLocalizedString("bluetooth_connected", comment: "Bluetooth device connected")
            : NSLocalizedString("bluetooth_disconnected", comment: "Bluetooth device disconnected")
    }
}

/// List of currently connected devices, for the settings pane.
struct BluetoothDeviceList: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        if bluetooth.connectedDevices.isEmpty {
            Text("No devices connected")
                .foregroundStyle(.secondary)
        } else {
            ForEach(bluetooth.connectedDevices) { device in
                HStack(spacing: 10) {
                    Image(systemName: device.iconName)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text(device.name)
                    Spacer()
                    if let percent = device.batteryPercentText {
                        Text(percent)
                            .foregroundStyle(.secondary)
                            .font(.callout.monospacedDigit())
                    }
                }
            }
        }
    }
}

// MARK: - Header accessory

/// Connected Bluetooth accessories and their battery levels, in the opened
/// notch header.
///
/// The manager already tracks all of this for the connect/disconnect banner —
/// this is the part you can actually go and look at when you want to know
/// whether your headphones are about to die.
struct BluetoothHeaderIndicator: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    /// The device worth putting on the icon: the emptiest one that reports a
    /// level at all.
    private var lowest: BluetoothDeviceInfo? {
        bluetooth.connectedDevices
            .filter { $0.batteryLevel != nil }
            .min { ($0.batteryLevel ?? 1) < ($1.batteryLevel ?? 1) }
    }

    private var isLow: Bool {
        (lowest?.batteryLevel ?? 1) <= 0.2
    }

    private var isSelected: Bool { coordinator.currentView == .bluetooth }

    var body: some View {
        // The icon is the way into the devices panel: Bluetooth has no tab of
        // its own while this is showing, so clicking here is what opens it, and
        // clicking again goes back.
        Button {
            withAnimation(.smooth) {
                coordinator.currentView = isSelected ? .player : .bluetooth
            }
        } label: {
            Capsule()
                .fill(isSelected ? Color(nsColor: .secondarySystemFill) : .black)
                .frame(width: contentWidth, height: 30)
                .overlay {
                    // Icon only. The header shares the top of the screen with
                    // the camera housing, which is dead space that cannot be
                    // reclaimed, so nothing here spends width on something the
                    // panel behind it already says. A low battery still shows,
                    // as colour rather than digits.
                    Image(systemName: iconName)
                        .foregroundStyle(isLow ? .orange : Color.effectiveAccent)
                        .symbolRenderingMode(.hierarchical)
                        .imageScale(.small)
                }
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText)
        .contextMenu {
            if bluetooth.connectedDevices.isEmpty {
                Text("No devices connected")
            } else {
                ForEach(bluetooth.connectedDevices) { device in
                    Label {
                        if let percent = device.batteryPercentText {
                            Text("\(device.name) — \(percent)")
                        } else {
                            Text(device.name)
                        }
                    } icon: {
                        Image(systemName: device.iconName)
                    }
                }
            }
        }
    }

    /// Shows the emptiest device's own glyph, so a glance says *what* is low.
    private var iconName: String {
        lowest?.iconName ?? "wave.3.right.circle"
    }

    private var contentWidth: CGFloat { 30 }

    private var helpText: String {
        guard !bluetooth.connectedDevices.isEmpty else {
            return NSLocalizedString("No devices connected", comment: "Bluetooth header tooltip with nothing connected")
        }
        return bluetooth.connectedDevices
            .map { device in
                device.batteryPercentText.map { "\(device.name) \($0)" } ?? device.name
            }
            .joined(separator: "\n")
    }
}

// MARK: - Tab

/// Connected accessories and their battery levels.
///
/// Reached from the header icon rather than a tab of its own while that icon is
/// showing — the same rule the weather panel follows.
struct BluetoothDevicesView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    private var contentWidth: CGFloat { NotchViews.bluetooth.contentWidth }

    private static let cardHeight: CGFloat = 52
    private static let cardSpacing: CGFloat = 8
    /// Four rows before it scrolls, which is already a lot of accessories.
    private static let maxRows = 4

    private var columnCount: Int { bluetooth.connectedDevices.count > 3 ? 2 : 1 }

    /// Two columns once there are enough devices to need them.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    /// Exactly as tall as the rows need. The panel hugs its content, so a view
    /// that stretches leaves dead height below the last device.
    private var listHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(bluetooth.connectedDevices.count) / Double(columnCount))))
        let natural = CGFloat(rows) * Self.cardHeight + CGFloat(rows - 1) * Self.cardSpacing
        let ceiling = CGFloat(Self.maxRows) * Self.cardHeight + CGFloat(Self.maxRows - 1) * Self.cardSpacing
        return min(natural, ceiling)
    }

    var body: some View {
        Group {
            if bluetooth.connectedDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wave.3.right.circle")
                        .font(.title2)
                        .foregroundStyle(.gray)
                    Text("No devices connected")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 96)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: Self.cardSpacing) {
                        ForEach(bluetooth.connectedDevices) { device in
                            DeviceCard(device: device)
                                .frame(height: Self.cardHeight)
                        }
                    }
                }
                .frame(height: listHeight)
            }
        }
        .frame(width: contentWidth)
    }
}

private struct DeviceCard: View {
    let device: BluetoothDeviceInfo

    private var isLow: Bool { (device.batteryLevel ?? 1) <= 0.2 }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.iconName)
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isLow ? .orange : Color.effectiveAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let level = device.batteryLevel {
                    // A bar rather than a number alone: "22%" and "82%" look
                    // far too similar at a glance.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(isLow ? Color.orange : Color.green)
                                .frame(width: max(3, geo.size.width * level))
                        }
                    }
                    .frame(height: 4)
                } else {
                    Text("Battery level unavailable")
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                }
            }

            if let percent = device.batteryPercentText {
                Text(percent)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(isLow ? .orange : .white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
    }
}
