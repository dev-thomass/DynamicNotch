//
//  WeatherStore.swift
//  DynamicNotch
//
//  Météo de la ville choisie dans les réglages, rafraîchie toutes les 30 min.
//  Ville vide : aucune requête réseau.
//

import Foundation
import Observation

@MainActor
@Observable
final class WeatherStore {
    static let shared = WeatherStore()

    enum State: Equatable {
        case disabled
        case loading
        case loaded(WeatherSnapshot)
        case cityNotFound
        case failed
    }

    private(set) var state: State = .disabled

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var city = ""
    @ObservationIgnored private var place: WeatherPlace?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let refreshInterval: TimeInterval = 30 * 60

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Change de ville (vide = météo désactivée) et recharge.
    func setCity(_ newCity: String) {
        let trimmed = newCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != city || timer == nil else { return }
        city = trimmed
        place = nil
        timer?.invalidate()
        timer = nil
        task?.cancel()
        guard !trimmed.isEmpty else {
            state = .disabled
            return
        }
        state = .loading
        refresh()
        let newTimer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        newTimer.tolerance = 60
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func refresh() {
        guard !city.isEmpty else { return }
        task?.cancel()
        let city = city
        task = Task { [weak self] in
            await self?.load(city: city)
        }
    }

    private func load(city: String) async {
        do {
            let place = try await resolvedPlace(for: city)
            guard let place else {
                state = .cityNotFound
                return
            }
            guard let url = OpenMeteo.forecastURL(for: place) else { return }
            let (data, _) = try await session.data(from: url)
            guard !Task.isCancelled, city == self.city else { return }
            state = try .loaded(OpenMeteo.decodeSnapshot(data, place: place.name))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            Log.app.error("weather refresh failed: \(error.localizedDescription, privacy: .public)")
            // Garder la dernière météo connue plutôt qu'afficher une erreur.
            if case .loaded = state {
                return
            }
            state = .failed
        }
    }

    private func resolvedPlace(for city: String) async throws -> WeatherPlace? {
        if let place {
            return place
        }
        guard let url = OpenMeteo.geocodingURL(city: city) else { return nil }
        let (data, _) = try await session.data(from: url)
        let found = try OpenMeteo.decodePlace(data)
        if city == self.city {
            place = found
        }
        return found
    }
}
