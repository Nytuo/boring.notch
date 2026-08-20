//
//  BoardWidgetContent.swift
//  boringNotch
//
//  F-11: the actual small views behind the board widgets Caffeine, Weather
//  and Clipboard contribute via `boardWidgets()`. Each just observes the
//  same manager its own tab/header icon already does — no new state.
//

import SwiftUI

struct BoardCaffeineWidgetView: View {
    @ObservedObject private var caffeine = CaffeineManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(caffeine.isActive ? Color.effectiveAccent : .gray)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("extension_caffeine_name", comment: "Extension name: Keep Awake"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                Text(caffeine.isActive
                    ? (caffeine.formattedRemaining ?? NSLocalizedString("board_caffeine_indefinite", comment: "Keep Awake is on with no timer"))
                    : NSLocalizedString("board_caffeine_off", comment: "Keep Awake is off"))
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { caffeine.isActive },
                set: { _ in caffeine.toggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }
}

struct BoardWeatherWidgetView: View {
    @ObservedObject private var weather = WeatherManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: weather.snapshot?.condition.symbolName(isDay: weather.snapshot?.isDay ?? true) ?? "cloud.sun.fill")
                .foregroundStyle(Color.effectiveAccent)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 1) {
                Text(weather.snapshot?.place.name ?? NSLocalizedString("extension_weather_name", comment: "Extension name: Weather"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let snapshot = weather.snapshot {
                    Text(snapshot.temperature.formattedTemperature())
                        .font(.caption2)
                        .foregroundStyle(.gray)
                } else {
                    Text(NSLocalizedString("board_weather_unavailable", comment: "No weather data yet"))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }

            Spacer()
        }
    }
}

struct BoardClipboardWidgetView: View {
    @ObservedObject private var clipboard = ClipboardManager.shared

    private var pinned: [ClipboardEntry] {
        Array(clipboard.entries.filter(\.isPinned).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(Color.effectiveAccent)
                Text(NSLocalizedString("board_clipboard_pinned", comment: "Board widget: pinned clipboard entries"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }

            if pinned.isEmpty {
                Text(NSLocalizedString("board_clipboard_none_pinned", comment: "No pinned clipboard entries yet"))
                    .font(.caption2)
                    .foregroundStyle(.gray)
            } else {
                ForEach(pinned) { entry in
                    Text(entry.previewText)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
        }
    }
}
