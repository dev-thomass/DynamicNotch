//
//  WeatherTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

final class WeatherConditionTests: XCTestCase {
    func test_wmoCodes_mapToConditions() {
        XCTAssertEqual(WeatherCondition(code: 0), .clear)
        XCTAssertEqual(WeatherCondition(code: 2), .partlyCloudy)
        XCTAssertEqual(WeatherCondition(code: 3), .overcast)
        XCTAssertEqual(WeatherCondition(code: 48), .fog)
        XCTAssertEqual(WeatherCondition(code: 55), .drizzle)
        XCTAssertEqual(WeatherCondition(code: 63), .rain)
        XCTAssertEqual(WeatherCondition(code: 86), .snow)
        XCTAssertEqual(WeatherCondition(code: 81), .showers)
        XCTAssertEqual(WeatherCondition(code: 95), .thunderstorm)
        XCTAssertEqual(WeatherCondition(code: 42), .unknown)
    }

    func test_clearSky_dependsOnDaylight() {
        XCTAssertEqual(WeatherCondition.clear.systemImage(isDay: true), "sun.max.fill")
        XCTAssertEqual(WeatherCondition.clear.systemImage(isDay: false), "moon.stars.fill")
    }
}

final class OpenMeteoTests: XCTestCase {
    func test_geocodingURL_encodesCity() throws {
        let url = try XCTUnwrap(OpenMeteo.geocodingURL(city: "Saint-Étienne"))
        XCTAssertEqual(url.host, "geocoding-api.open-meteo.com")
        XCTAssertTrue(url.absoluteString.contains("name=Saint-%C3%89tienne"))
    }

    func test_decodePlace_takesFirstResult() throws {
        let json = #"{"results":[{"name":"Paris","latitude":48.85,"longitude":2.35,"country":"France"}]}"#
        XCTAssertEqual(
            try OpenMeteo.decodePlace(Data(json.utf8)),
            WeatherPlace(name: "Paris", latitude: 48.85, longitude: 2.35)
        )
    }

    func test_decodePlace_noResult() throws {
        XCTAssertNil(try OpenMeteo.decodePlace(Data(#"{"generationtime_ms":0.5}"#.utf8)))
    }

    func test_decodeSnapshot() throws {
        let json = """
        {"current":{"time":"2026-10-04T18:00","temperature_2m":17.6,"weather_code":61,"is_day":0},\
        "daily":{"time":["2026-10-04"],"temperature_2m_max":[21.2],"temperature_2m_min":[11.8]}}
        """
        let snapshot = try OpenMeteo.decodeSnapshot(Data(json.utf8), place: "Paris")
        XCTAssertEqual(snapshot.condition, .rain)
        XCTAssertFalse(snapshot.isDay)
        XCTAssertEqual(snapshot.temperatureText, "18°")
        XCTAssertEqual(snapshot.rangeText, "12° / 21°")
    }
}
