//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews

    init(item: NotchTabItem) {
        id = item.rawValue
        label = item.label
        icon = item.iconName
        view = item.view
    }
}

/// Tabs available right now, in the user's configured order. Tabs whose feature
/// is switched off are omitted so the strip has no dead destinations.
@MainActor
var tabs: [TabModel] {
    NotchLayoutResolver.tabItems().map(TabModel.init(item:))
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    // Re-render when any of the preferences feeding `tabs` change.
    @Default(.notchTabOrder) private var tabOrder
    @Default(.boringShelf) private var shelfEnabled
    @Default(.showCalendar) private var calendarEnabled
    @Default(.weatherEnabled) private var weatherEnabled
    @Default(.weatherShowInNotch) private var weatherShowInNotch
    @Default(.clipboardHistoryEnabled) private var clipboardEnabled
    @Default(.clipboardShowInNotch) private var clipboardShowInNotch
    @Default(.appSwitcherEnabled) private var appSwitcherEnabled
    @Default(.appSwitcherShowTab) private var appSwitcherShowTab
    @Default(.clockEnabled) private var clockEnabled
    @Default(.clockShowInNotch) private var clockShowInNotch
    @Default(.systemStatsEnabled) private var systemStatsEnabled
    @Default(.systemStatsNotchIcon) private var systemStatsNotchIcon
    @Default(.bluetoothNotchIcon) private var bluetoothNotchIcon

    @Namespace var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
