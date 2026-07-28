//
//  WeatherSettingsView.swift
//  boringNotch
//

import CoreLocation
import Defaults
import SwiftUI

struct WeatherSettings: View {
    @ObservedObject private var weather = WeatherManager.shared

    @Default(.weatherEnabled) private var enabled
    @Default(.weatherLocationMode) private var locationMode
    @Default(.weatherManualPlace) private var manualPlace
    @Default(.weatherRefreshMinutes) private var refreshMinutes
    @Default(.weatherTemperatureUnit) private var temperatureUnit
    @Default(.weatherWindSpeedUnit) private var windSpeedUnit

    @State private var query: String = ""
    @State private var results: [WeatherPlace] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    private let service = WeatherService()

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .weatherEnabled) {
                    Text("Enable weather")
                }
                HelpText("Weather data by Open-Meteo. No account or API key required.")
            } header: {
                Text("General")
            }

            Section {
                statusRow
            } header: {
                Text("Current Conditions")
            }

            Section {
                Picker("Location", selection: $locationMode) {
                    ForEach(WeatherLocationMode.allCases) { mode in
                        Text(mode.localizedString).tag(mode)
                    }
                }
                .disabled(!enabled)

                if locationMode == .automatic {
                    automaticLocationRows
                } else {
                    manualLocationRows
                }
            } header: {
                Text("Location")
            }

            Section {
                Picker("Temperature", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.localizedString).tag(unit)
                    }
                }
                .disabled(!enabled)

                Picker("Wind speed", selection: $windSpeedUnit) {
                    ForEach(WindSpeedUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .disabled(!enabled)

                Stepper(value: $refreshMinutes, in: 5...240, step: 5) {
                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Text("\(refreshMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)
            } header: {
                Text("Units")
            }

            Section {
                Defaults.Toggle(key: .weatherShowInNotch) {
                    Text("Show weather in notch")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .weatherShowHourlyForecast) {
                    Text("Show hourly forecast")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .weatherShowDailyForecast) {
                    Text("Show daily forecast")
                }
                .disabled(!enabled)
            } header: {
                Text("Appearance")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Weather")
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: Rows

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 12) {
            if let snapshot = weather.snapshot {
                Image(systemName: snapshot.condition.symbolName(isDay: snapshot.isDay))
                    .font(.system(size: 24))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.temperature.formattedTemperature()) · \(snapshot.condition.localizedDescription)")
                        .font(.headline)
                    Text(snapshot.place.displayName)
                        .foregroundStyle(.secondary)
                }
            } else if let error = weather.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.yellow)
                    .frame(width: 30)
                Text(error)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                Text(enabled ? "Waiting for data…" : "Weather is off")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                weather.refresh()
            } label: {
                if weather.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Refresh")
                }
            }
            .disabled(!enabled || weather.isRefreshing)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var automaticLocationRows: some View {
        switch weather.authorizationStatus {
        case .denied, .restricted:
            HStack {
                Text("Location access denied")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
                    )
                }
            }
        case .notDetermined:
            HStack {
                Text("Location access not granted")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Allow") { weather.requestLocationPermission() }
            }
        default:
            if let place = weather.snapshot?.place {
                LabeledContent("Detected", value: place.displayName)
            } else {
                Text("Locating…").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var manualLocationRows: some View {
        if let place = manualPlace {
            LabeledContent("Selected", value: place.displayName)
        }

        TextField("Search for a city", text: $query)
            .textFieldStyle(.roundedBorder)
            .disabled(!enabled)
            .onChange(of: query) { _, newValue in
                scheduleSearch(newValue)
            }

        if isSearching {
            HStack {
                ProgressView().controlSize(.small)
                Text("Searching…").foregroundStyle(.secondary)
            }
        } else if let searchError {
            Text(searchError).foregroundStyle(.secondary)
        } else {
            ForEach(results) { place in
                Button {
                    manualPlace = place
                    results = []
                    query = ""
                } label: {
                    HStack {
                        Text(place.displayName)
                        Spacer()
                        if manualPlace == place {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.effectiveAccent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Search

    /// Debounces typing so a city search does not fire on every keystroke.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        searchError = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            do {
                let found = try await service.searchPlaces(matching: trimmed)
                guard !Task.isCancelled else { return }
                results = found
                if found.isEmpty {
                    searchError = NSLocalizedString(
                        "weather_no_results",
                        comment: "City search returned nothing"
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                searchError = error.localizedDescription
            }
        }
    }
}
