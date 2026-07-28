//
//  CaffeineViews.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Transient banner shown across the closed notch when a Keep Awake session
/// starts or stops. Mirrors the geometry of the battery notification so the two
/// read as the same class of thing.
struct CaffeineLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var caffeine = CaffeineManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        NotchBannerLayout {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            HStack(spacing: 6) {
                if caffeine.isActive, Defaults[.caffeineShowCountdown],
                   let remaining = caffeine.formattedRemaining {
                    Text(remaining)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(caffeine.isActive ? Color.effectiveAccent : .gray)
                    .imageScale(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }

    private var title: String {
        guard caffeine.isActive else {
            return NSLocalizedString(
                "caffeine_activity_stopped",
                comment: "Notch banner shown when Keep Awake turns off"
            )
        }
        if let duration = caffeine.activeDuration, duration.timeInterval != nil {
            return String(
                format: NSLocalizedString(
                    "caffeine_activity_started_for",
                    comment: "Notch banner: Keep Awake started for a duration"
                ),
                duration.localizedString
            )
        }
        return NSLocalizedString(
            "caffeine_activity_started",
            comment: "Notch banner shown when Keep Awake turns on indefinitely"
        )
    }
}

/// Keep Awake button in the opened notch header.
///
/// Always visible while the feature is on, so it can start a session as well as
/// stop one — the cup fills in when running. The cup toggles; the chevron beside
/// it sets how long for, so a duration never means a trip to settings.
struct CaffeineHeaderIndicator: View {
    @ObservedObject private var caffeine = CaffeineManager.shared
    @Default(.caffeineShowCountdown) private var showCountdown

    var body: some View {
        Capsule()
            .fill(.black)
            .frame(width: contentWidth, height: 30)
            .overlay {
                HStack(spacing: 2) {
                    toggleButton
                    durationMenu
                }
            }
            .contextMenu { durationItems }
    }

    private var toggleButton: some View {
        Button {
            caffeine.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(caffeine.isActive ? Color.effectiveAccent : .gray)
                    .imageScale(.small)
                if showsCountdown, let remaining = caffeine.formattedRemaining {
                    Text(remaining)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText)
    }

    /// The setter. A plain click opens it — the duration list used to be on
    /// right-click only, which nothing on screen advertised.
    private var durationMenu: some View {
        Menu {
            durationItems
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.gray)
                .frame(width: 12, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(NSLocalizedString("caffeine_pick_duration", comment: "Tooltip on the Keep Awake duration menu"))
    }

    @ViewBuilder
    private var durationItems: some View {
        if caffeine.isActive {
            Button("Turn Off Keep Awake") { caffeine.deactivate() }
            if caffeine.expiresAt != nil {
                Button("Add 15 Minutes") { caffeine.extend(by: 15 * 60) }
            }
            Divider()
        }
        ForEach(CaffeineDuration.presets) { preset in
            Button(preset.localizedString) { caffeine.activate(for: preset) }
        }
        Divider()
        Toggle(
            NSLocalizedString("caffeine_remember_duration", comment: "Menu item: reuse this duration next time"),
            isOn: rememberBinding
        )
    }

    /// Writes the last picked length back to the default, so the next plain
    /// click on the cup runs for the same length.
    private var rememberBinding: Binding<Bool> {
        Binding(
            get: { Defaults[.caffeineDefaultDuration] == caffeine.activeDuration },
            set: { isOn in
                guard isOn, let duration = caffeine.activeDuration else { return }
                Defaults[.caffeineDefaultDuration] = duration
            }
        )
    }

    private var showsCountdown: Bool {
        showCountdown && caffeine.isActive
    }

    /// Widen the capsule only when a countdown is actually being drawn; the
    /// chevron always needs its own room.
    private var contentWidth: CGFloat {
        (showsCountdown && caffeine.formattedRemaining != nil ? 68 : 30) + 14
    }

    private var helpText: String {
        caffeine.isActive
            ? NSLocalizedString(
                "caffeine_indicator_help",
                comment: "Tooltip on the notch Keep Awake indicator while running"
            )
            : NSLocalizedString(
                "caffeine_indicator_help_off",
                comment: "Tooltip on the notch Keep Awake indicator while idle"
            )
    }
}

/// Persistent reminder on the *closed* notch that a session is running.
///
/// Sits to the right of the cutout, mirroring how the music live activity uses
/// the space either side of it, so a glance at an unfocused notch shows how much
/// time is left.
struct CaffeineClosedIndicator: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var caffeine = CaffeineManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Balances the trailing content so the opaque spacer stays centred
            // on the physical notch.
            Color.clear
                .frame(width: trailingWidth, height: closedNotchHeight)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(Color.effectiveAccent)
                    .font(.system(size: 11))
                if let remaining = caffeine.formattedRemaining {
                    Text(remaining)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: trailingWidth, alignment: .leading)
            .padding(.leading, 4)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }

    /// Indefinite sessions show only the cup, so they need less room.
    private var trailingWidth: CGFloat {
        caffeine.formattedRemaining == nil ? 24 : 62
    }
}
