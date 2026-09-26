//
//  NotchTopRow.swift
//  DynamicNotch
//
//  Rangée du haut du panneau ouvert, à hauteur de l'encoche : les onglets à
//  gauche de l'encoche physique, la batterie et le menu « … » à droite.
//

import SwiftUI

struct NotchTopRow: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var battery = BatteryMonitor.shared

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            Color.clear
                .frame(width: vm.deviceNotchRect.width)
            trailing
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .frame(height: vm.deviceNotchRect.height)
    }

    @ViewBuilder
    private var leading: some View {
        switch vm.contentType {
        case let .tab(tab):
            DSTabBar(selection: tab) { vm.selectTab($0) }
        case .settings:
            HStack(spacing: 6) {
                DSIconButton("chevron.left", label: "Retour") { vm.closeSettings() }
                Text("Réglages")
                    .font(DS.Typography.bodyEmphasis)
                    .foregroundStyle(DS.Color.textPrimary)
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 10) {
            if battery.hasBattery {
                Text("\(battery.percent) %")
                    .font(DS.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textSecondary)
                    .contentTransition(.numericText(value: Double(battery.percent)))
                    .animation(DS.Motion.micro, value: battery.percent)
            }
            moreMenu
        }
    }

    /// Menu natif : réglages, vider les fichiers, quitter (+ simulation en Debug).
    private var moreMenu: some View {
        Menu {
            Button("Réglages…") { vm.showSettings() }
            Button("Vider les fichiers…") { NotchActions.confirmAndClearTray(vm) }
            #if DEBUG
                Menu("Simuler une activité") {
                    ForEach(ActivityID.samples.map(\.debugName), id: \.self) { name in
                        Button(name) {
                            vm.notchClose()
                            // Laisser le panneau se fermer : ouvert, il suspend les activités.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                MainActor.assumeIsolated { ActivitySimulator.run(name) }
                            }
                        }
                    }
                }
            #endif
            Divider()
            Button("Quitter DynamicNotch") { NotchActions.confirmAndQuit(vm) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Plus"))
        .accessibilityLabel(Text("Plus d'options"))
    }
}

/// Actions confirmées par une alerte (reprises de l'ancien menu de l'encoche).
@MainActor
enum NotchActions {
    static func confirmAndClearTray(_ vm: NotchViewModel) {
        let count = TrayDrop.shared.items.count
        guard count > 0 else {
            vm.notchClose()
            return
        }
        let title = "Vider tous les fichiers stockés ?"
        let message = "\(count) fichier(s) seront supprimés de DynamicNotch. Vos originaux sur le disque ne sont pas affectés."
        if NSAlert.popConfirm(title: title, message: message, confirm: "Vider", destructive: true) {
            TrayDrop.shared.removeAll()
        }
        vm.notchClose()
    }

    static func confirmAndQuit(_ vm: NotchViewModel) {
        let title = "Quitter DynamicNotch ?"
        let message = "L'encoche cessera de répondre jusqu'à ce que vous relanciez DynamicNotch."
        guard NSAlert.popConfirm(title: title, message: message, confirm: "Quitter", destructive: true) else { return }
        vm.notchClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.terminate(nil)
        }
    }
}
