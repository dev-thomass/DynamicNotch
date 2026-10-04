//
//  AgendaTabView.swift
//  DynamicNotch
//
//  La journée : événements du jour (ou de demain si la journée est vide).
//

import SwiftUI

struct AgendaTabView: View {
    private let calendar = CalendarStore.shared

    var body: some View {
        DSModule {
            switch calendar.access {
            case .granted:
                list
            case .notDetermined:
                prompt("Autoriser l'agenda") { calendar.requestAccess() }
            case .denied:
                prompt("Autoriser dans Réglages Système") {
                    if let url =
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .onAppear { calendar.refreshAccess() }
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                if !calendar.todayEvents.isEmpty {
                    section("Aujourd'hui", calendar.todayEvents)
                } else if !calendar.tomorrowEvents.isEmpty {
                    section("Demain", calendar.tomorrowEvents)
                } else {
                    Text("Rien de prévu aujourd'hui ni demain")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, _ entries: [AgendaEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(nsColor: entry.color ?? .systemBlue))
                        .frame(width: 8, height: 8)
                    Text(entry
                        .isAllDay ? "Journée" :
                        "\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: 104, alignment: .leading)
                    Text(entry.title)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                }
                .font(DS.Typography.body)
            }
        }
    }

    private func prompt(_ title: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(DS.Color.textSecondary)
            Button(title, action: perform)
                .buttonStyle(.plain)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.brand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
