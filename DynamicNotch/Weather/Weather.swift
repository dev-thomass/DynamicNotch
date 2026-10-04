//
//  Weather.swift
//  DynamicNotch
//
//  Types et décodage de la météo Open-Meteo (https://open-meteo.com) :
//  gratuit, sans clé ni compte. Seules deux requêtes partent : la recherche
//  de la ville saisie dans les réglages, puis la météo de ses coordonnées.
//

import Foundation

/// Conditions WMO (`weather_code`) regroupées pour l'affichage.
enum WeatherCondition: Equatable {
    case clear, partlyCloudy, overcast, fog, drizzle, rain, snow, showers, thunderstorm, unknown

    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51 ... 57: self = .drizzle
        case 61 ... 67: self = .rain
        case 71 ... 77, 85, 86: self = .snow
        case 80 ... 82: self = .showers
        case 95 ... 99: self = .thunderstorm
        default: self = .unknown
        }
    }

    func systemImage(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .showers: "cloud.heavyrain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "thermometer.medium"
        }
    }

    var label: String {
        switch self {
        case .clear: "Dégagé"
        case .partlyCloudy: "Peu nuageux"
        case .overcast: "Couvert"
        case .fog: "Brouillard"
        case .drizzle: "Bruine"
        case .rain: "Pluie"
        case .snow: "Neige"
        case .showers: "Averses"
        case .thunderstorm: "Orage"
        case .unknown: "Météo"
        }
    }
}

struct WeatherPlace: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
}

struct WeatherSnapshot: Equatable {
    let place: String
    let temperature: Double
    let low: Double?
    let high: Double?
    let condition: WeatherCondition
    let isDay: Bool

    var temperatureText: String {
        "\(Int(temperature.rounded()))°"
    }

    var rangeText: String? {
        guard let low, let high else { return nil }
        return "\(Int(low.rounded()))° / \(Int(high.rounded()))°"
    }
}

enum OpenMeteo {
    static func geocodingURL(city: String) -> URL? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            .init(name: "name", value: city),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "fr"),
            .init(name: "format", value: "json")
        ]
        return components?.url
    }

    static func forecastURL(for place: WeatherPlace) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1")
        ]
        return components?.url
    }

    /// Première ville trouvée, `nil` si aucune.
    static func decodePlace(_ data: Data) throws -> WeatherPlace? {
        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
            }

            let results: [Result]?
        }
        guard let first = try JSONDecoder().decode(Response.self, from: data).results?.first else { return nil }
        return WeatherPlace(name: first.name, latitude: first.latitude, longitude: first.longitude)
    }

    static func decodeSnapshot(_ data: Data, place: String) throws -> WeatherSnapshot {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature2m: Double
                let weatherCode: Int
                let isDay: Int?
            }

            struct Daily: Decodable {
                let temperature2mMax: [Double?]
                let temperature2mMin: [Double?]
            }

            let current: Current
            let daily: Daily?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        return WeatherSnapshot(
            place: place,
            temperature: response.current.temperature2m,
            low: response.daily?.temperature2mMin.first ?? nil,
            high: response.daily?.temperature2mMax.first ?? nil,
            condition: WeatherCondition(code: response.current.weatherCode),
            isDay: (response.current.isDay ?? 1) == 1
        )
    }
}
