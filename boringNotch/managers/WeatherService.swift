//
//  WeatherService.swift
//  boringNotch
//
//  Open-Meteo client. Chosen over WeatherKit because it needs no Apple
//  Developer account, no API key, and no attribution beyond its licence.
//

import CoreLocation
import Foundation

enum WeatherServiceError: LocalizedError {
    case badResponse(Int)
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return String(
                format: NSLocalizedString(
                    "weather_error_http",
                    comment: "Weather fetch failed with an HTTP status code"
                ),
                code
            )
        case .malformedPayload:
            return NSLocalizedString(
                "weather_error_payload",
                comment: "Weather response could not be understood"
            )
        }
    }
}

struct WeatherService {
    private static let forecastHost = "api.open-meteo.com"
    private static let geocodingHost = "geocoding-api.open-meteo.com"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Forecast

    func fetchForecast(
        for place: WeatherPlace,
        temperatureUnit: TemperatureUnit,
        windSpeedUnit: WindSpeedUnit
    ) async throws -> WeatherSnapshot {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.forecastHost
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
            ),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,weather_code,is_day,precipitation_probability"
            ),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: temperatureUnit.apiValue),
            URLQueryItem(name: "wind_speed_unit", value: windSpeedUnit.apiValue)
        ]

        guard let url = components.url else { throw WeatherServiceError.malformedPayload }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherServiceError.badResponse(http.statusCode)
        }

        let payload = try JSONDecoder().decode(ForecastPayload.self, from: data)
        return try makeSnapshot(from: payload, place: place)
    }

    // MARK: Geocoding

    /// Looks up places by name, for the manual-location picker.
    func searchPlaces(matching query: String) async throws -> [WeatherPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.geocodingHost
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else { throw WeatherServiceError.malformedPayload }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherServiceError.badResponse(http.statusCode)
        }

        let payload = try JSONDecoder().decode(GeocodingPayload.self, from: data)
        return (payload.results ?? []).map { result in
            WeatherPlace(
                name: result.name,
                subtitle: [result.admin1, result.country]
                    .compactMap { $0 }
                    .first,
                latitude: result.latitude,
                longitude: result.longitude
            )
        }
    }

    /// Reverse-geocodes coordinates to a display name.
    ///
    /// Open-Meteo's geocoding endpoint is forward-only (passing lat/lon returns
    /// an error), so this uses CoreLocation, which needs no key either.
    func describePlace(latitude: Double, longitude: Double) async -> WeatherPlace {
        let fallback = WeatherPlace(
            name: NSLocalizedString("weather_current_location", comment: "Fallback name for the user's location"),
            subtitle: nil,
            latitude: latitude,
            longitude: longitude
        )

        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return fallback
        }

        let name = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea
            ?? fallback.name

        // Keep the *device* coordinates: the placemark's own location is the
        // centre of the matched locality, which can be kilometres away.
        return WeatherPlace(
            name: name,
            subtitle: placemark.administrativeArea ?? placemark.country,
            latitude: latitude,
            longitude: longitude
        )
    }

    // MARK: Decoding

    private func makeSnapshot(from payload: ForecastPayload, place: WeatherPlace) throws -> WeatherSnapshot {
        guard let current = payload.current else { throw WeatherServiceError.malformedPayload }

        // Open-Meteo returns local wall-clock times without an offset when
        // `timezone=auto`, so parse them in the forecast's own time zone.
        let timeZone = TimeZone(identifier: payload.timezone ?? "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var hourly: [HourlyForecast] = []
        if let block = payload.hourly {
            let now = Date()
            for (index, timeString) in block.time.enumerated() {
                guard let date = formatter.date(from: timeString),
                      index < block.temperature2m.count,
                      index < block.weatherCode.count
                else { continue }
                // Only future hours are useful in the strip.
                guard date >= now.addingTimeInterval(-3600) else { continue }

                hourly.append(
                    HourlyForecast(
                        date: date,
                        temperature: block.temperature2m[index],
                        condition: WeatherCondition(code: block.weatherCode[index]),
                        isDay: (block.isDay?[safe: index] ?? 1) == 1,
                        precipitationProbability: block.precipitationProbability?[safe: index] ?? nil
                    )
                )
                if hourly.count >= 24 { break }
            }
        }

        var daily: [DailyForecast] = []
        if let block = payload.daily {
            for (index, dayString) in block.time.enumerated() {
                guard let date = dayFormatter.date(from: dayString),
                      index < block.temperature2mMax.count,
                      index < block.temperature2mMin.count,
                      index < block.weatherCode.count
                else { continue }

                daily.append(
                    DailyForecast(
                        date: date,
                        high: block.temperature2mMax[index],
                        low: block.temperature2mMin[index],
                        condition: WeatherCondition(code: block.weatherCode[index]),
                        precipitationProbability: block.precipitationProbabilityMax?[safe: index] ?? nil
                    )
                )
            }
        }

        return WeatherSnapshot(
            place: place,
            temperature: current.temperature2m,
            apparentTemperature: current.apparentTemperature ?? current.temperature2m,
            condition: WeatherCondition(code: current.weatherCode),
            isDay: (current.isDay ?? 1) == 1,
            humidity: current.relativeHumidity2m,
            windSpeed: current.windSpeed10m,
            todayHigh: daily.first?.high,
            todayLow: daily.first?.low,
            hourly: hourly,
            daily: daily,
            fetchedAt: Date()
        )
    }
}

// MARK: - Wire format

private struct ForecastPayload: Decodable {
    let timezone: String?
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?

    struct Current: Decodable {
        let temperature2m: Double
        let relativeHumidity2m: Int?
        let apparentTemperature: Double?
        let isDay: Int?
        let weatherCode: Int
        let windSpeed10m: Double?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case isDay = "is_day"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature2m: [Double]
        let weatherCode: [Int]
        let isDay: [Int]?
        let precipitationProbability: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
            case precipitationProbability = "precipitation_probability"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let precipitationProbabilityMax: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }
}

private struct GeocodingPayload: Decodable {
    let results: [Result]?

    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }
}

private extension Array {
    /// Open-Meteo occasionally returns shorter arrays for optional variables.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
