//
//  CalendarWidget.swift
//  DynamicNotch
//
//  Compact "next event" view backed by EventKit. Shows the upcoming event
//  for the next 24 h or a friendly empty state if nothing is on the books.
//
//  Permission: requested lazily on first appear. If the user denies, the
//  widget renders a one-shot prompt asking them to enable Full Calendar
//  access in System Settings.
//

import EventKit
import SwiftUI

enum AgendaAccess: Equatable {
    case granted, notDetermined, denied
}

@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    @Published var nextEvent: EKEvent?
    @Published private(set) var access: AgendaAccess = CalendarStore.access(for: EKEventStore.authorizationStatus(for: .event))
    @Published private(set) var todayEvents: [AgendaEntry] = []
    @Published private(set) var tomorrowEvents: [AgendaEntry] = []

    private let store = EKEventStore()
    private var refreshTimer: Timer?

    private init() {}

    nonisolated static func access(for status: EKAuthorizationStatus) -> AgendaAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Relit l'autorisation ; si l'accès est accordé, lance le suivi (sans invite).
    func refreshAccess() {
        access = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        if access == .granted, refreshTimer == nil { startObserving() }
    }

    /// Demande l'accès (invite système), puis relit l'autorisation.
    func requestAccess() {
        Task {
            await requestAndRefresh()
            refreshAccess()
        }
    }

    // MARK: lifecycle

    /// Request access if needed and start polling. Polling cadence (60 s) is
    /// fine for "next event" — not real-time, doesn't drain battery.
    func startObserving() {
        Task { await self.requestAndRefresh() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stopObserving() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: access

    private func requestAndRefresh() async {
        do {
            // EKEventStore.requestFullAccessToEvents(...) is macOS 14+.
            // For older targets the symbol falls back to the deprecated
            // requestAccess(to:); we use #available to keep the deployment
            // target reasonable while staying compliant on modern macOS.
            if #available(macOS 14, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = await withCheckedContinuation { cont in
                    store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
                }
            }
            refresh()
        } catch {
            Log.app.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh() {
        let now = Date()
        let until = now.addingTimeInterval(60 * 60 * 24)
        let predicate = store.predicateForEvents(withStart: now, end: until, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        nextEvent = events.first

        let startOfToday = Calendar.current.startOfDay(for: now)
        let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday)!
        let dayPredicate = store.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: nil)
        let entries = store.events(matching: dayPredicate).map { event in
            AgendaEntry(
                id: AgendaEntry.makeID(eventIdentifier: event.eventIdentifier, title: event.title, start: event.startDate),
                title: event.title ?? "Sans titre",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                color: event.calendar?.color
            )
        }
        let split = AgendaPlanner.split(entries, now: now)
        todayEvents = split.today
        tomorrowEvents = split.tomorrow
    }
}

