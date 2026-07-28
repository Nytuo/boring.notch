//
//  LayoutSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct LayoutSettings: View {
    @Default(.notchHeaderItems) private var headerItems
    @Default(.notchTabOrder) private var tabOrder
    @Default(.notchDefaultTab) private var defaultTab

    var body: some View {
        Form {
            Section {
                // Reconciled on read so an array stored by an older build still
                // shows every current item.
                let items = NotchLayoutResolver.reconcile(headerItems, all: NotchHeaderItem.allCases)
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        Image(systemName: item.iconName)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(item.label)
                        Spacer()
                        if !item.isEnabled {
                            customBadge(text: NSLocalizedString("layout_hidden", comment: "Layout item is hidden"))
                        }
                    }
                }
                .onMove { source, destination in
                    var updated = items
                    updated.move(fromOffsets: source, toOffset: destination)
                    headerItems = updated
                }

                Button("Reset order") {
                    headerItems = NotchHeaderItem.defaultOrder
                }
            } header: {
                Text("Notch Header Items")
            } footer: {
                HelpText("Drag to reorder the controls shown on the right of the opened notch. Items marked hidden are turned off in their own settings tab.")
            }

            Section {
                let items = NotchLayoutResolver.reconcile(tabOrder, all: NotchTabItem.allCases)
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        Image(systemName: item.iconName)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(item.label)
                        Spacer()
                        if item.isShadowedByHeaderItem {
                            customBadge(text: NSLocalizedString("layout_in_header", comment: "Tab is reached from its header icon instead"))
                        } else if !item.isEnabled {
                            customBadge(text: NSLocalizedString("layout_hidden", comment: "Layout item is hidden"))
                        }
                    }
                }
                .onMove { source, destination in
                    var updated = items
                    updated.move(fromOffsets: source, toOffset: destination)
                    tabOrder = updated
                }

                Picker("Default tab", selection: $defaultTab) {
                    ForEach(NotchTabItem.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }

                Button("Reset order") {
                    tabOrder = NotchTabItem.defaultOrder
                }
            } header: {
                Text("Notch Tabs")
            } footer: {
                HelpText("Drag to reorder the tab strip inside the opened notch. A feature with its own header icon gets no tab — click the icon to open it.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Layout")
    }
}
