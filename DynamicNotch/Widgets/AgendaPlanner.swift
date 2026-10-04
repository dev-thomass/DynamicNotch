//
//  AgendaPlanner.swift
//  DynamicNotch
//
//  Tri et filtrage des événements du jour et du lendemain. Fonctions pures,
//  indépendantes d'EventKit pour être testables.
//

import AppKit

struct AgendaEntry: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor?

    /// Identifiant stable d'une occurrence : les occurrences d'un événement
    /// récurrent partagent `eventIdentifier`, on y ajoute donc le début.
    static func makeID(eventIdentifier: String?, title: String?, start: Date) -> String {
        "\(eventIdentifier ?? title ?? "event")-\(start.timeIntervalSince1970)"
    }
}

enum AgendaPlanner {
    /// Événements du jour de `now` et du lendemain ; « journée entière » d'abord, puis par heure.
    static func split(
        _ entries: [AgendaEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> (today: [AgendaEntry], tomorrow: [AgendaEntry]) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let startOfAfter = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow)!
        let today = entries.filter { $0.start < startOfTomorrow && $0.end > startOfToday }
        let tomorrow = entries
            .filter { $0.start < startOfAfter && $0.end > startOfTomorrow && $0.start >= startOfTomorrow }
        return (sorted(today), sorted(tomorrow))
    }

    /// Prochains événements horaires pas encore terminés.
    static func upcoming(_ today: [AgendaEntry], now: Date, limit: Int) -> [AgendaEntry] {
        Array(today.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }.prefix(limit))
    }

    private static func sorted(_ entries: [AgendaEntry]) -> [AgendaEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay
            }
            return lhs.start < rhs.start
        }
    }
}
