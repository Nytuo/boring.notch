//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    // Re-render the accessory row when the arrangement or any feature toggle
    // that feeds it changes.
    @Default(.notchHeaderItems) private var headerItems
    @Default(.showMirror) private var showMirror
    @Default(.weatherEnabled) private var weatherEnabled
    @Default(.weatherShowInNotch) private var weatherShowInNotch
    @Default(.caffeineEnabled) private var caffeineEnabled
    @Default(.caffeineNotchIcon) private var caffeineNotchIcon
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.bluetoothNotchIcon) private var bluetoothNotchIcon
    @Default(.systemStatsEnabled) private var systemStatsEnabled
    @Default(.systemStatsNotchIcon) private var systemStatsNotchIcon

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                // Show the strip whenever there is somewhere to go. This used
                // to be gated on the shelf being enabled, which would strand
                // every other tab when the shelf was turned off.
                if showsTabStrip {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isOSDType(coordinator.sneakPeekState(for: vm.screenUUID).type) && coordinator.shouldShowSneakPeek(on: vm.screenUUID) && Defaults[.showOpenNotchOSD] {
                        OpenNotchOSD(
                             type: coordinator.binding(for: vm.screenUUID).type,
                             value: coordinator.binding(for: vm.screenUUID).value,
                             icon: coordinator.binding(for: vm.screenUUID).icon,
                             accent: coordinator.binding(for: vm.screenUUID).accent
                        )
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        ForEach(NotchLayoutResolver.headerItems()) { item in
                            headerAccessory(item)
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    /// The strip is worth showing once more than one destination exists, or
    /// when the shelf has content to return to. It also has to stay up while a
    /// tabless destination (one reached from a header icon) is on screen,
    /// otherwise there is no way back out of it.
    private var showsTabStrip: Bool {
        if tabs.count > 1 { return true }
        if !tabs.contains(where: { $0.view == coordinator.currentView }) { return true }
        return !tvm.isEmpty && Defaults[.boringShelf]
    }

    /// Renders one configured accessory. Order comes from the layout settings;
    /// visibility comes from each item's own feature toggle.
    @ViewBuilder
    private func headerAccessory(_ item: NotchHeaderItem) -> some View {
        switch item {
        case .mirror:
            Button {
                vm.toggleCameraPreview()
            } label: {
                Capsule()
                    .fill(.black)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "web.camera")
                            .foregroundColor(.white)
                            .padding()
                            .imageScale(.medium)
                    }
            }
            .buttonStyle(PlainButtonStyle())

        case .weather:
            WeatherHeaderIndicator()

        case .caffeine:
            CaffeineHeaderIndicator()

        case .bluetooth:
            BluetoothHeaderIndicator()

        case .systemStats:
            SystemStatsHeaderIndicator()

        case .battery:
            BoringBatteryView(
                batteryWidth: 30,
                isCharging: batteryModel.isCharging,
                isInLowPowerMode: batteryModel.isInLowPowerMode,
                isPluggedIn: batteryModel.isPluggedIn,
                levelBattery: batteryModel.levelBattery,
                maxCapacity: batteryModel.maxCapacity,
                timeToFullCharge: batteryModel.timeToFullCharge,
                timeToDischarge: batteryModel.timeToDischarge,
                maxAdapterWatts: batteryModel.maxAdapterWatts,
                isForNotification: false
            )
        }
    }

    func isOSDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
