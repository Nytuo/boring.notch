//
//  LockScreenSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct LockScreenSettings: View {
    @Default(.showOnLockScreen) private var showOnLockScreen
    @Default(.lockScreenWidgetsEnabled) private var enabled
    @Default(.lockScreenWidgets) private var widgets

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .lockScreenWidgetsEnabled) {
                    Text("Show widgets on lock screen")
                }
                .disabled(!showOnLockScreen)
                HelpText("macOS has no lock screen widget API, so Boring Notch draws these itself above the lock screen.")
            } header: {
                Text("General")
            }

            Section {
                ForEach(LockScreenWidget.allCases) { widget in
                    HStack(spacing: 10) {
                        Image(systemName: widget.iconName)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(widget.label)
                        Spacer()
                        if !widget.isAvailable {
                            customBadge(text: NSLocalizedString("layout_hidden", comment: "Layout item is hidden"))
                        }
                        Toggle("", isOn: binding(for: widget))
                            .labelsHidden()
                            .disabled(!enabled || !showOnLockScreen)
                    }
                }

                Button("Reset to defaults") {
                    widgets = LockScreenWidget.defaultSelection
                }
                .disabled(!enabled)
            } header: {
                Text("Widgets")
            } footer: {
                HelpText("Widgets whose feature is switched off elsewhere are marked hidden and will not appear.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Lock Screen")
    }

    /// Selection is stored as an ordered array, so toggling appends or removes
    /// rather than flipping a flag — that keeps the display order stable.
    private func binding(for widget: LockScreenWidget) -> Binding<Bool> {
        Binding(
            get: { widgets.contains(widget) },
            set: { isOn in
                if isOn {
                    guard !widgets.contains(widget) else { return }
                    // Insert at the position implied by the canonical ordering
                    // so widgets do not jump to the end when re-enabled.
                    let canonical = LockScreenWidget.allCases
                    var updated = widgets
                    let targetIndex = canonical.firstIndex(of: widget) ?? canonical.count
                    let insertAt = updated.firstIndex {
                        (canonical.firstIndex(of: $0) ?? 0) > targetIndex
                    } ?? updated.count
                    updated.insert(widget, at: insertAt)
                    widgets = updated
                } else {
                    widgets.removeAll { $0 == widget }
                }
            }
        )
    }
}
