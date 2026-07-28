//
//  WeatherManager.swift
//  boringNotch
//

import Combine
import CoreLocation
import Defaults
import Foundation
import SwiftUI

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let service = WeatherService()
    private let locationManager = CLLocationManager()
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Set while waiting for the first location fix so the delegate callback
    /// knows to kick off a fetch rather than just recording the coordinates.
    private var awaitingFixForRefresh = false

    private override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        // City-level accuracy is all a forecast needs, and it is much cheaper
        // on battery than the default best-accuracy setting.
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        Defaults.publisher(.weatherEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.start()
                    } else {
                        self?.stop()
                    }
                }
            }
            .store(in: &cancellables)

        // Any of these change what a forecast means, so refetch rather than
        // converting client-side.
        for publisher in [
            Defaults.publisher(.weatherLocationMode).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.weatherTemperatureUnit).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.weatherWindSpeedUnit).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.weatherManualPlace).map { _ in () }.eraseToAnyPublisher()
        ] {
            publisher
                .sink { [weak self] in
                    Task { @MainActor in
                        guard Defaults[.weatherEnabled] else { return }
                        self?.refresh()
                    }
                }
                .store(in: &cancellables)
        }

        if Defaults[.weatherEnabled] {
            start()
        }
    }

    // MARK: Lifecycle

    func start() {
        refresh()
        startPolling()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        pollTask?.cancel()
        pollTask = nil
        locationManager.stopUpdatingLocation()
        snapshot = nil
        lastError = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let minutes = max(5, Defaults[.weatherRefreshMinutes])
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    // MARK: Permission

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    var needsLocationPermission: Bool {
        Defaults[.weatherLocationMode] == .automatic
            && (authorizationStatus == .denied || authorizationStatus == .restricted)
    }

    // MARK: Refresh

    func refresh() {
        guard Defaults[.weatherEnabled] else { return }

        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            self.isRefreshing = true
            defer { self.isRefreshing = false }

            do {
                guard let place = try await self.resolvePlace() else {
                    // resolvePlace has already requested a fix or permission;
                    // the delegate will call back into refresh().
                    return
                }
                guard !Task.isCancelled else { return }

                let snapshot = try await self.service.fetchForecast(
                    for: place,
                    temperatureUnit: Defaults[.weatherTemperatureUnit],
                    windSpeedUnit: Defaults[.weatherWindSpeedUnit]
                )
                guard !Task.isCancelled else { return }

                self.snapshot = snapshot
                self.lastError = nil
            } catch is CancellationError {
                return
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Returns the place to forecast for, or `nil` when a location fix has been
    /// requested and the result must wait for the delegate.
    private func resolvePlace() async throws -> WeatherPlace? {
        if Defaults[.weatherLocationMode] == .manual {
            guard let place = Defaults[.weatherManualPlace] else {
                lastError = NSLocalizedString(
                    "weather_error_no_place",
                    comment: "No manual weather location has been chosen"
                )
                return nil
            }
            return place
        }

        switch authorizationStatus {
        case .notDetermined:
            awaitingFixForRefresh = true
            locationManager.requestWhenInUseAuthorization()
            return nil
        case .denied, .restricted:
            lastError = NSLocalizedString(
                "weather_error_location_denied",
                comment: "Location permission was denied"
            )
            return nil
        default:
            break
        }

        if let coordinate = locationManager.location?.coordinate {
            let cached = Defaults[.weatherResolvedPlace]
            // Reuse the cached name while the device has not meaningfully moved,
            // to avoid a reverse-geocode on every refresh.
            if let cached, cached.distance(to: coordinate) < 5_000 {
                return WeatherPlace(
                    name: cached.name,
                    subtitle: cached.subtitle,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
            let place = await service.describePlace(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            Defaults[.weatherResolvedPlace] = place
            return place
        }

        awaitingFixForRefresh = true
        locationManager.requestLocation()
        return nil
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            guard Defaults[.weatherEnabled] else { return }
            switch status {
            case .authorized, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.lastError = NSLocalizedString(
                    "weather_error_location_denied",
                    comment: "Location permission was denied"
                )
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locations.last != nil else { return }
        Task { @MainActor in
            guard self.awaitingFixForRefresh else { return }
            self.awaitingFixForRefresh = false
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.awaitingFixForRefresh = false
            // A transient failure should not wipe a forecast that is still
            // perfectly usable, so only surface the error when nothing is shown.
            if self.snapshot == nil {
                self.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - Helpers

private extension WeatherPlace {
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
