//
//  FunctionButtonBar.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Row of user-configured action buttons, shown at the bottom of the opened
/// notch's home view.
struct FunctionButtonBar: View {
    @Default(.functionButtons) private var buttons
    @Default(.functionButtonsEnabled) private var enabled
    @Default(.functionButtonsShowLabels) private var showLabels

    var body: some View {
        if enabled && !buttons.isEmpty {
            HStack(spacing: 6) {
                ForEach(buttons) { button in
                    FunctionButtonTile(button: button, showLabel: showLabels)
                }
            }
        }
    }
}

private struct FunctionButtonTile: View {
    @State private var isHovering = false

    let button: FunctionButton
    let showLabel: Bool

    var body: some View {
        Button {
            FunctionButtonRunner.run(button)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: button.effectiveIconName)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                if showLabel {
                    Text(button.title)
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            .frame(width: showLabel ? 46 : 30, height: showLabel ? 34 : 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.white.opacity(0.14) : Color(nsColor: .secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(button.title)
    }
}
