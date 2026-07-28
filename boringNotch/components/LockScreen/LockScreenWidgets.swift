//
//  LockScreenWidgets.swift
//  boringNotch
//
//  Widgets rendered in the notch while the screen is locked.
//
//  macOS has no lock-screen widget API — that is an iOS/iPadOS feature, and
//  WidgetKit on macOS targets the desktop and Notification Center, neither of
//  which is visible when locked. What *is* possible is drawing above the lock
//  screen with a SkyLight window, which this app already does for the notch
//  itself (see BoringNotchSkyLightWindow). These widgets ride on that surface.
//

import Combine
import Defaults
import SwiftUI

// MARK: - Lock state

/// Publishes whether the screen is locked, so views can react to it.
///
/// The AppDelegate already listens for these distributed notifications to
/// manage windows; this exposes the same signal to SwiftUI.
@MainActor
final class LockScreenState: ObservableObject {
    static let shared = LockScreenState()

    @Published private(set) var isLocked = false

    private var observers: [Any] = []

    private init() {
        let center = DistributedNotificationCenter.default()
        observers.append(
            center.addObserver(
                forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = true }
            }
        )
        observers.append(
            center.addObserver(
                forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = false }
            }
        )
    }
}

// MARK: - Widget kinds

enum LockScreenWidget: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case clock
    case date
    case weather
    case battery
    case music
    case nextEvent

    var id: String { rawValue }

    static let defaultSelection: [LockScreenWidget] = [.clock, .date, .weather, .battery]

    var label: String {
        switch self {
        case .clock: return NSLocalizedString("lockwidget_clock", comment: "Lock screen widget: clock")
        case .date: return NSLocalizedString("lockwidget_date", comment: "Lock screen widget: date")
        case .weather: return NSLocalizedString("lockwidget_weather", comment: "Lock screen widget: weather")
        case .battery: return NSLocalizedString("lockwidget_battery", comment: "Lock screen widget: battery")
        case .music: return NSLocalizedString("lockwidget_music", comment: "Lock screen widget: now playing")
        case .nextEvent: return NSLocalizedString("lockwidget_next_event", comment: "Lock screen widget: next calendar event")
        }
    }

    var iconName: String {
        switch self {
        case .clock: return "clock"
        case .date: return "calendar"
        case .weather: return "cloud.sun"
        case .battery: return "battery.100"
        case .music: return "music.note"
        case .nextEvent: return "calendar.badge.clock"
        }
    }

    /// Whether the underlying feature is available to draw from.
    @MainActor
    var isAvailable: Bool {
        switch self {
        case .clock, .date, .battery:
            return true
        case .weather:
            return Defaults[.weatherEnabled]
        case .music:
            return true
        case .nextEvent:
            return Defaults[.showCalendar]
        }
    }
}

// MARK: - Container

/// Row of lock-screen widgets, split around the physical notch.
///
/// The notch is an opaque cutout, so nothing may be drawn behind it. Widgets
/// are dealt alternately into a left and a right group with an opaque spacer
/// the width of the notch between them, matching how the closed-notch live
/// activities lay themselves out.
struct LockScreenWidgetBar: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var lockState = LockScreenState.shared

    @Default(.lockScreenWidgetsEnabled) private var enabled
    @Default(.lockScreenWidgets) private var widgets

    let closedNotchHeight: CGFloat

    var body: some View {
        if enabled && lockState.isLocked && Defaults[.showOnLockScreen] {
            let visible = widgets.filter(\.isAvailable)
            let split = Self.split(visible)

            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    ForEach(split.leading) { LockScreenWidgetView(widget: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)

                // The dead zone. Opaque so nothing shows through the cutout.
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

                HStack(spacing: 14) {
                    ForEach(split.trailing) { LockScreenWidgetView(widget: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            }
            .frame(width: liveActivityWidth, height: closedNotchHeight)
            .transition(.opacity)
        }
    }

    /// Deals widgets either side of the notch, keeping the configured order
    /// within each side and putting the extra one on the left when the count
    /// is odd (the clock is first, and reads better on the left).
    static func split(_ widgets: [LockScreenWidget])
        -> (leading: [LockScreenWidget], trailing: [LockScreenWidget]) {
        let leadingCount = Int((Double(widgets.count) / 2).rounded(.up))
        return (
            leading: Array(widgets.prefix(leadingCount)),
            trailing: Array(widgets.dropFirst(leadingCount))
        )
    }
}

private struct LockScreenWidgetView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject private var weather = WeatherManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared

    /// Drives the clock. A shared timer beats one per widget, and one-second
    /// granularity is enough for a lock screen.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let widget: LockScreenWidget

    var body: some View {
        content
            .onReceive(tick) { now = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch widget {
        case .clock:
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 20, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)

        case .date:
            VStack(alignment: .leading, spacing: 0) {
                Text(now, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                Text(now, format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }

        case .weather:
            if let snapshot = weather.snapshot {
                HStack(spacing: 4) {
                    Image(systemName: snapshot.condition.symbolName(isDay: snapshot.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                    Text(snapshot.temperature.formattedTemperature())
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }

        case .battery:
            HStack(spacing: 4) {
                BoringBatteryView(
                    batteryWidth: 26,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isPluggedIn: batteryModel.isPluggedIn,
                    levelBattery: batteryModel.levelBattery,
                    maxAdapterWatts: batteryModel.maxAdapterWatts,
                    isForNotification: true
                )
            }

        case .music:
            if musicManager.isPlaying || !musicManager.isPlayerIdle {
                HStack(spacing: 5) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(musicManager.songTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(musicManager.artistName)
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 110, alignment: .leading)
                }
            }

        case .nextEvent:
            if let event = calendarManager.events.first(where: { $0.start > now }) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(nsColor: event.calendar.color))
                        .frame(width: 3, height: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.start, format: .dateTime.hour().minute())
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.gray)
                        Text(event.title)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 110, alignment: .leading)
                }
            }
        }
    }
}
