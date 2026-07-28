//
//  WeatherView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Full weather panel shown as a notch tab.
struct WeatherView: View {
    @ObservedObject private var weather = WeatherManager.shared
    @Default(.weatherTemperatureUnit) private var unit
    @Default(.weatherShowHourlyForecast) private var showHourly
    @Default(.weatherShowDailyForecast) private var showDaily

    var body: some View {
        Group {
            if let snapshot = weather.snapshot {
                content(for: snapshot)
            } else {
                placeholder
            }
        }
    }

    // MARK: Loaded

    @ViewBuilder
    private func content(for snapshot: WeatherSnapshot) -> some View {
        // Laid out against the panel's full width: the conditions block keeps
        // its intrinsic size and the forecast takes everything left over, so
        // the hours spread out instead of bunching against a dead margin.
        HStack(alignment: .top, spacing: 20) {
            currentConditions(snapshot)
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 10) {
                if showHourly && !snapshot.hourly.isEmpty {
                    hourlyStrip(snapshot.hourly)
                    if showDaily && !snapshot.daily.isEmpty {
                        Divider().overlay(Color.white.opacity(0.12))
                    }
                }
                if showDaily && !snapshot.daily.isEmpty {
                    dailyList(snapshot.daily)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            // Drawn as an overlay rather than a `Divider`: a vertical divider
            // in an HStack expands to whatever height it is offered, which made
            // the panel as tall as the window however short the forecast was.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: NotchViews.weather.contentWidth, alignment: .topLeading)
    }

    @ViewBuilder
    private func currentConditions(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.condition.symbolName(isDay: snapshot.isDay))
                    .font(.system(size: 38))
                    .symbolRenderingMode(.multicolor)
                Text(snapshot.temperature.formattedTemperature())
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(snapshot.condition.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .lineLimit(1)

            Text(snapshot.place.name)
                .font(.caption)
                .foregroundStyle(.gray)
                .lineLimit(1)

            if let high = snapshot.todayHigh, let low = snapshot.todayLow {
                Text("H:\(high.formattedTemperature())  L:\(low.formattedTemperature())")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Text(String(
                format: NSLocalizedString(
                    "weather_feels_like",
                    comment: "Apparent temperature line"
                ),
                snapshot.apparentTemperature.formattedTemperature()
            ))
            .font(.caption2)
            .foregroundStyle(.gray)

            HStack(spacing: 10) {
                if let humidity = snapshot.humidity {
                    Label("\(humidity)%", systemImage: "humidity")
                }
                if let wind = snapshot.windSpeed {
                    Label(
                        "\(Int(wind.rounded())) \(Defaults[.weatherWindSpeedUnit].symbol)",
                        systemImage: "wind"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.gray)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func hourlyStrip(_ hours: [HourlyForecast]) -> some View {
        // Columns share the available width evenly rather than each taking its
        // own intrinsic size, so the strip lines up with the list beneath it.
        HStack(spacing: 0) {
            ForEach(hours.prefix(10)) { hour in
                VStack(spacing: 3) {
                    Text(hourLabel(hour.date))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                    Image(systemName: hour.condition.symbolName(isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 17))
                    Text(hour.temperature.formattedTemperature())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
    }

    private func dailyList(_ days: [DailyForecast]) -> some View {
        let shown = Array(days.prefix(7))
        // Bounds for the range bars, so every row is drawn on the same scale.
        let coldest = shown.map(\.low).min() ?? 0
        let warmest = shown.map(\.high).max() ?? 1
        let span = max(warmest - coldest, 0.1)

        return VStack(spacing: 4) {
            ForEach(shown) { day in
                HStack(spacing: 8) {
                    Text(dayLabel(day.date))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(width: 42, alignment: .leading)

                    Image(systemName: day.condition.symbolName(isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 13))
                        .frame(width: 20)

                    if let probability = day.precipitationProbability, probability > 0 {
                        Text("\(probability)%")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(Color.cyan.opacity(0.8))
                            .frame(width: 26, alignment: .leading)
                    } else {
                        Color.clear.frame(width: 26, height: 1)
                    }

                    Text(day.low.formattedTemperature())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.gray)
                        .frame(width: 34, alignment: .trailing)

                    temperatureRangeBar(low: day.low, high: day.high, coldest: coldest, span: span)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)

                    Text(day.high.formattedTemperature())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Where this day's low–high sits within the week's overall range. Turns a
    /// column of numbers into something readable at a glance, and gives the
    /// list a reason to use the panel's width.
    private func temperatureRangeBar(low: Double, high: Double, coldest: Double, span: Double) -> some View {
        GeometryReader { geo in
            let start = (low - coldest) / span
            let end = (high - coldest) / span
            let width = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.8), Color.orange.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, CGFloat(end - start) * width))
                    .offset(x: CGFloat(start) * width)
            }
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 8) {
            if weather.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Loading weather…")
                    .font(.caption)
                    .foregroundStyle(.gray)
            } else if weather.needsLocationPermission {
                Image(systemName: "location.slash")
                    .font(.title2)
                    .foregroundStyle(.gray)
                Text("Location access is off")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Button("Open Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
                    )
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else if let error = weather.lastError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.gray)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                Button("Retry") { weather.refresh() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            } else {
                Image(systemName: "cloud.sun")
                    .font(.title2)
                    .foregroundStyle(.gray)
                Text("No weather data")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: 260, height: 120)
    }

    // MARK: Labels

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return NSLocalizedString("weather_today_short", comment: "Short label for today")
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

/// Compact temperature + icon shown in the opened notch header.
///
/// This is the only way into the weather panel: weather has no tab of its own
/// while the icon is showing, so the icon doubles as the tab and toggles the
/// panel back to home on a second click.
struct WeatherHeaderIndicator: View {
    @ObservedObject private var weather = WeatherManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    private var isSelected: Bool { coordinator.currentView == .weather }

    var body: some View {
        if let snapshot = weather.snapshot {
            Button {
                withAnimation(.smooth) {
                    coordinator.currentView = isSelected ? .player : .weather
                }
            } label: {
                Capsule()
                    .fill(isSelected ? Color(nsColor: .secondarySystemFill) : .black)
                    .frame(width: 62, height: 30)
                    .overlay {
                        HStack(spacing: 3) {
                            Image(systemName: snapshot.condition.symbolName(isDay: snapshot.isDay))
                                .symbolRenderingMode(.multicolor)
                                .imageScale(.small)
                            Text(snapshot.temperature.formattedTemperature())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(PlainButtonStyle())
            .help(snapshot.condition.localizedDescription)
        }
    }
}
