//
//  WeatherModels.swift
//  boringNotch
//

import Defaults
import Foundation
import SwiftUI

// MARK: - Units

enum TemperatureUnit: String, CaseIterable, Identifiable, Defaults.Serializable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    /// Open-Meteo's query value for this unit.
    var apiValue: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var localizedString: String {
        switch self {
        case .celsius:
            return NSLocalizedString("weather_unit_celsius", comment: "Temperature unit: Celsius")
        case .fahrenheit:
            return NSLocalizedString("weather_unit_fahrenheit", comment: "Temperature unit: Fahrenheit")
        }
    }

    /// Matches the unit the user's locale would normally show.
    static var systemDefault: TemperatureUnit {
        if #available(macOS 13, *) {
            return Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        }
        return .celsius
    }
}

enum WindSpeedUnit: String, CaseIterable, Identifiable, Defaults.Serializable {
    case kmh
    case mph
    case ms
    case kn

    var id: String { rawValue }

    var apiValue: String { rawValue }

    var symbol: String {
        switch self {
        case .kmh: return "km/h"
        case .mph: return "mph"
        case .ms: return "m/s"
        case .kn: return "kn"
        }
    }
}

/// Where the coordinates used for a forecast come from.
enum WeatherLocationMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automatic
    case manual

    var id: String { rawValue }

    var localizedString: String {
        switch self {
        case .automatic:
            return NSLocalizedString("weather_location_automatic", comment: "Weather location: use current location")
        case .manual:
            return NSLocalizedString("weather_location_manual", comment: "Weather location: use a chosen place")
        }
    }
}

// MARK: - Place

/// A resolved place a forecast can be fetched for.
struct WeatherPlace: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id: String { "\(latitude),\(longitude)" }
    let name: String
    /// Region/country shown under the name to disambiguate same-named places.
    let subtitle: String?
    let latitude: Double
    let longitude: Double

    var displayName: String {
        if let subtitle, !subtitle.isEmpty {
            return "\(name), \(subtitle)"
        }
        return name
    }
}

// MARK: - Conditions

/// WMO weather interpretation codes, as returned by Open-Meteo.
///
/// The raw values are the codes themselves, so decoding is a direct lookup.
enum WeatherCondition: Int, CaseIterable {
    case clear = 0
    case mainlyClear = 1
    case partlyCloudy = 2
    case overcast = 3
    case fog = 45
    case depositingRimeFog = 48
    case drizzleLight = 51
    case drizzleModerate = 53
    case drizzleDense = 55
    case freezingDrizzleLight = 56
    case freezingDrizzleDense = 57
    case rainSlight = 61
    case rainModerate = 63
    case rainHeavy = 65
    case freezingRainLight = 66
    case freezingRainHeavy = 67
    case snowSlight = 71
    case snowModerate = 73
    case snowHeavy = 75
    case snowGrains = 77
    case rainShowersSlight = 80
    case rainShowersModerate = 81
    case rainShowersViolent = 82
    case snowShowersSlight = 85
    case snowShowersHeavy = 86
    case thunderstorm = 95
    case thunderstormSlightHail = 96
    case thunderstormHeavyHail = 99

    /// Unknown codes fall back to overcast rather than failing the whole decode.
    init(code: Int) {
        self = WeatherCondition(rawValue: code) ?? .overcast
    }

    /// SF Symbol for the condition. `isDay` swaps sun for moon where relevant.
    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear:
            return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mainlyClear:
            return isDay ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy:
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast:
            return "cloud.fill"
        case .fog, .depositingRimeFog:
            return "cloud.fog.fill"
        case .drizzleLight, .drizzleModerate, .drizzleDense:
            return "cloud.drizzle.fill"
        case .freezingDrizzleLight, .freezingDrizzleDense,
             .freezingRainLight, .freezingRainHeavy:
            return "cloud.sleet.fill"
        case .rainSlight, .rainModerate:
            return "cloud.rain.fill"
        case .rainHeavy:
            return "cloud.heavyrain.fill"
        case .snowSlight, .snowModerate, .snowHeavy, .snowGrains,
             .snowShowersSlight, .snowShowersHeavy:
            return "cloud.snow.fill"
        case .rainShowersSlight, .rainShowersModerate:
            return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .rainShowersViolent:
            return "cloud.heavyrain.fill"
        case .thunderstorm:
            return "cloud.bolt.fill"
        case .thunderstormSlightHail, .thunderstormHeavyHail:
            return "cloud.bolt.rain.fill"
        }
    }

    var localizedDescription: String {
        switch self {
        case .clear:
            return NSLocalizedString("weather_clear", comment: "Weather: clear sky")
        case .mainlyClear:
            return NSLocalizedString("weather_mainly_clear", comment: "Weather: mainly clear")
        case .partlyCloudy:
            return NSLocalizedString("weather_partly_cloudy", comment: "Weather: partly cloudy")
        case .overcast:
            return NSLocalizedString("weather_overcast", comment: "Weather: overcast")
        case .fog, .depositingRimeFog:
            return NSLocalizedString("weather_fog", comment: "Weather: fog")
        case .drizzleLight, .drizzleModerate, .drizzleDense:
            return NSLocalizedString("weather_drizzle", comment: "Weather: drizzle")
        case .freezingDrizzleLight, .freezingDrizzleDense:
            return NSLocalizedString("weather_freezing_drizzle", comment: "Weather: freezing drizzle")
        case .rainSlight, .rainModerate:
            return NSLocalizedString("weather_rain", comment: "Weather: rain")
        case .rainHeavy:
            return NSLocalizedString("weather_heavy_rain", comment: "Weather: heavy rain")
        case .freezingRainLight, .freezingRainHeavy:
            return NSLocalizedString("weather_freezing_rain", comment: "Weather: freezing rain")
        case .snowSlight, .snowModerate, .snowGrains:
            return NSLocalizedString("weather_snow", comment: "Weather: snow")
        case .snowHeavy:
            return NSLocalizedString("weather_heavy_snow", comment: "Weather: heavy snow")
        case .rainShowersSlight, .rainShowersModerate, .rainShowersViolent:
            return NSLocalizedString("weather_rain_showers", comment: "Weather: rain showers")
        case .snowShowersSlight, .snowShowersHeavy:
            return NSLocalizedString("weather_snow_showers", comment: "Weather: snow showers")
        case .thunderstorm:
            return NSLocalizedString("weather_thunderstorm", comment: "Weather: thunderstorm")
        case .thunderstormSlightHail, .thunderstormHeavyHail:
            return NSLocalizedString("weather_thunderstorm_hail", comment: "Weather: thunderstorm with hail")
        }
    }
}

// MARK: - Snapshot

struct HourlyForecast: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let temperature: Double
    let condition: WeatherCondition
    let isDay: Bool
    /// Chance of precipitation, 0...100.
    let precipitationProbability: Int?
}

struct DailyForecast: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let high: Double
    let low: Double
    let condition: WeatherCondition
    let precipitationProbability: Int?
}

/// Everything the UI needs for one place at one moment.
struct WeatherSnapshot: Equatable {
    let place: WeatherPlace
    let temperature: Double
    let apparentTemperature: Double
    let condition: WeatherCondition
    let isDay: Bool
    let humidity: Int?
    let windSpeed: Double?
    let todayHigh: Double?
    let todayLow: Double?
    let hourly: [HourlyForecast]
    let daily: [DailyForecast]
    let fetchedAt: Date

    static func == (lhs: WeatherSnapshot, rhs: WeatherSnapshot) -> Bool {
        lhs.place == rhs.place && lhs.fetchedAt == rhs.fetchedAt
    }
}

// MARK: - Formatting

extension Double {
    /// Rounds to whole degrees and appends the degree sign, e.g. `18°`.
    func formattedTemperature(includeUnit: Bool = false, unit: TemperatureUnit = .celsius) -> String {
        let rounded = Int(self.rounded())
        return includeUnit ? "\(rounded)\(unit.symbol)" : "\(rounded)°"
    }
}
