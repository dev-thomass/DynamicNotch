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

@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    @Published var nextEvent: EKEvent?
    @Published var authorizationDenied: Bool = false

    private let store = EKEventStore()
    private var refreshTimer: Timer?

    private init() {}

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
                let granted = try await store.requestFullAccessToEvents()
                authorizationDenied = !granted
            } else {
                let granted: Bool = await withCheckedContinuation { cont in
                    store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
                }
                authorizationDenied = !granted
            }
            refresh()
        } catch {
            Log.app.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
            authorizationDenied = true
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
    }
}

struct CalendarWidgetView: View {
    @StateObject var vm: NotchViewModel
    @StateObject private var store = CalendarStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .semibold))
                Text("Prochain événement")
                    .font(DS.Typography.captionSmall)
                Spacer()
            }
            .foregroundStyle(DS.Color.textTertiary)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
        .dsRimLight()
        .onAppear { store.startObserving() }
    }

    @ViewBuilder
    private var content: some View {
        if store.authorizationDenied {
            denied
        } else if let event = store.nextEvent {
            eventCard(event)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func eventCard(_ event: EKEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title ?? "Événement sans titre")
                .font(DS.Typography.bodyEmphasis)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
            Text(formatTime(event))
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .monospacedDigit()
            if let loc = event.location, !loc.isEmpty {
                Text(loc)
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("Rien dans les 24 prochaines heures")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var denied: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: "lock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.warning)
            Text("Accès au calendrier refusé")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textPrimary)
            Button("Ouvrir les Réglages") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Color.brand)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatTime(_ event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let now = Date()
        let cal = Calendar.current
        if cal.isDateInToday(event.startDate) {
            return formatter.string(from: event.startDate)
        }
        if cal.isDateInTomorrow(event.startDate) {
            return "Demain " + formatter.string(from: event.startDate)
        }
        let rel = RelativeDateTimeFormatter()
        rel.dateTimeStyle = .named
        return rel.localizedString(for: event.startDate, relativeTo: now)
    }
}
