//
//  VPNViews.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Banner shown across the closed notch when a VPN-shaped interface comes up.
struct VPNLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var vpn = VPNStatusManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        NotchBannerLayout {
            VStack(alignment: .trailing, spacing: 1) {
                Text(NSLocalizedString("vpn_connected", comment: "VPN connected"))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let name = vpn.interfaceName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            Image(systemName: "lock.shield.fill")
                .imageScale(.medium)
                .foregroundStyle(Color.effectiveAccent)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

/// Sticky header icon while connected — reappears once any transient ahead
/// of it clears, same "always visible while true" reasoning as the battery
/// and Keep Awake icons.
struct VPNHeaderIndicator: View {
    @ObservedObject private var vpn = VPNStatusManager.shared

    var body: some View {
        Image(systemName: "lock.shield.fill")
            .foregroundStyle(Color.effectiveAccent)
            .symbolRenderingMode(.hierarchical)
            .imageScale(.small)
            .help(vpn.interfaceName.map {
                String(format: NSLocalizedString("vpn_connected_via", comment: "VPN connected via <interface>"), $0)
            } ?? NSLocalizedString("vpn_connected", comment: "VPN connected"))
    }
}
