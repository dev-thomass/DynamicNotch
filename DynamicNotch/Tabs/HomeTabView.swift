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

    /// Largeur utile (640 − 2 × 16) moins deux espacements de 10, en 3,2 parts.
    private let unit: CGFloat = (640 - 32 - 20) / 3.2

    /// Chaque module observe seulement ses propres modèles : le Pomodoro qui
    /// avance deux fois par seconde ne réévalue ni l'agenda ni les aperçus.
    var body: some View {
        HStack(spacing: 10) {
            HomeTodayModule(vm: vm).frame(width: unit * 1.2)
            HomeFilesModule(vm: vm).frame(width: unit)
            HomeActionsModule(vm: vm).frame(width: unit)
        }
    }
}

// MARK: aujourd'hui

private struct HomeTodayModule: View {
    let vm: NotchViewModel
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        DSModule(
            Date().formatted(.dateTime.weekday(.wide)).capitalized,
            action: calendar.access == .granted ? { vm.selectTab(.agenda) } : nil
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(DS.Typography.displayMedium)
                    .foregroundStyle(DS.Color.textPrimary)
                detail
            }
        }
        .onAppear { calendar.refreshAccess() }
    }

    @ViewBuilder
    private var detail: some View {
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

    private func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: fichiers

private struct HomeFilesModule: View {
    let vm: NotchViewModel
    @ObservedObject private var tray = TrayDrop.shared
    @State private var targeted = false

    var body: some View {
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
        .overlay(targetHighlight)
        .animation(DS.Motion.micro, value: targeted)
        .onDrop(of: [.data], isTargeted: $targeted) { providers in
            vm.hapticSender.send()
            DispatchQueue.global().async { TrayDrop.shared.load(providers) }
            return true
        }
    }

    private var targetHighlight: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        return shape
            .fill(targeted ? DS.Color.dropZoneTargetedFill : .clear)
            .overlay(shape.strokeBorder(targeted ? DS.Color.dropZoneTargetedBorder : .clear, lineWidth: 1))
            .allowsHitTesting(false)
    }
}

// MARK: actions

private struct HomeActionsModule: View {
    let vm: NotchViewModel
    @ObservedObject private var stopwatch = StopwatchModel.shared
    @ObservedObject private var pomodoro = PomodoroModel.shared
    @State private var airDropTargeted = false

    var body: some View {
        DSModule {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    action("dot.radiowaves.up.forward", "AirDrop") {
                        ShareView.pickFilesAndSend(.airdrop, vm: vm)
                    }
                    .overlay(alignment: .top) {
                        Circle()
                            .strokeBorder(airDropTargeted ? DS.Color.dropZoneTargetedBorder : .clear, lineWidth: 1)
                            .frame(width: 36, height: 36)
                            .allowsHitTesting(false)
                    }
                    .animation(DS.Motion.micro, value: airDropTargeted)
                    .onDrop(of: [.data], isTargeted: $airDropTargeted) { providers in
                        vm.hapticSender.send()
                        ShareView.sendDropped(providers, type: .airdrop, vm: vm)
                        return true
                    }
                    action(stopwatch.running ? "pause.fill" : "play.fill", "Chrono") {
                        if !stopwatch.running {
                            vm.hapticSender.send()
                        }
                        stopwatch.toggle()
                    }
                }
                GridRow {
                    action(pomodoro.isRunning ? "pause.fill" : "brain.head.profile", "Pomodoro") {
                        if !pomodoro.isRunning {
                            vm.hapticSender.send()
                        }
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
}
