//
//  HomeTabView.swift
//  DynamicNotch
//
//  Accueil : aujourd'hui (date + deux prochains événements), fichiers
//  récents (zone de dépôt) et quatre actions rapides.
//

import SwiftUI

struct HomeTabView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var calendar = CalendarStore.shared
    @ObservedObject private var tray = TrayDrop.shared
    @ObservedObject private var stopwatch = StopwatchModel.shared
    @ObservedObject private var pomodoro = PomodoroModel.shared
    @State private var filesTargeted = false

    /// Largeur utile (640 − 2 × 16) moins deux espacements de 10, en 3,2 parts.
    private let unit: CGFloat = (640 - 32 - 20) / 3.2

    var body: some View {
        HStack(spacing: 10) {
            todayModule.frame(width: unit * 1.2)
            filesModule.frame(width: unit)
            actionsModule.frame(width: unit)
        }
        .onAppear { calendar.refreshAccess() }
    }

    // MARK: aujourd'hui

    private var todayModule: some View {
        DSModule(
            Date().formatted(.dateTime.weekday(.wide)).capitalized,
            action: calendar.access == .granted ? { vm.selectTab(.agenda) } : nil
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(DS.Typography.displayMedium)
                    .foregroundStyle(DS.Color.textPrimary)
                todayDetail
            }
        }
    }

    @ViewBuilder
    private var todayDetail: some View {
        switch calendar.access {
        case .granted:
            let upcoming = AgendaPlanner.upcoming(calendar.todayEvents, now: Date(), limit: 2)
            if upcoming.isEmpty {
                Text("Rien de prévu")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            ForEach(upcoming) { entry in
                HStack(spacing: 6) {
                    Text(entry.start.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.textSecondary)
                    Text(entry.title)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                }
                .font(DS.Typography.caption)
            }
        case .notDetermined:
            Button("Autoriser l'agenda") { calendar.requestAccess() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.brand)
        case .denied:
            Button("Autoriser dans Réglages Système") { openCalendarPrivacy() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.brand)
        }
    }

    // MARK: fichiers

    private var filesModule: some View {
        DSModule("Fichiers", action: { vm.selectTab(.files) }) {
            VStack(alignment: .leading, spacing: 8) {
                if tray.items.isEmpty {
                    Text("Glissez des fichiers ici")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(tray.items.prefix(3))) { item in
                            Image(nsImage: item.workspacePreviewImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        if tray.items.count > 3 {
                            Text("+\(tray.items.count - 3)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    Text("\(tray.items.count) fichier(s)")
                        .font(DS.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.textSecondary)
                        .contentTransition(.numericText(value: Double(tray.items.count)))
                        .animation(DS.Motion.micro, value: tray.items.count)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(filesTargeted ? 0.35 : 0), lineWidth: 1)
        )
        .animation(DS.Motion.micro, value: filesTargeted)
        .onDrop(of: [.data], isTargeted: $filesTargeted) { providers in
            vm.hapticSender.send()
            DispatchQueue.global().async { TrayDrop.shared.load(providers) }
            return true
        }
    }

    // MARK: actions

    private var actionsModule: some View {
        DSModule {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    action("dot.radiowaves.up.forward", "AirDrop") {
                        ShareView.pickFilesAndSend(.airdrop, vm: vm)
                    }
                    action(stopwatch.running ? "pause.fill" : "stopwatch", "Chrono") {
                        if !stopwatch.running { vm.hapticSender.send() }
                        stopwatch.toggle()
                    }
                }
                GridRow {
                    action(pomodoro.isRunning ? "pause.fill" : "brain.head.profile", "Pomodoro") {
                        if !pomodoro.isRunning { vm.hapticSender.send() }
                        pomodoro.performPrimary()
                    }
                    action("square.and.pencil", "Note") { vm.selectTab(.notes) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func action(_ systemImage: String, _ title: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 3) {
            DSIconButton(systemImage, label: title, size: .large, action: perform)
            Text(title)
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
        }
    }

    private func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
