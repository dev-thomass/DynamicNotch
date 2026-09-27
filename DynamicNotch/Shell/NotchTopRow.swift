//
//  NotchTopRow.swift
//  DynamicNotch
//
//  Rangée du haut du panneau ouvert, à hauteur de l'encoche (32 pt au moins) : les onglets à
//  gauche de l'encoche physique, la batterie et le menu « … » à droite.
//

import SwiftUI

struct NotchTopRow: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var battery = BatteryMonitor.shared
    /// Canal du HUD de l'encoche (`NotchViewModel.hud`).
    @ObservedObject var hud: HUDController

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
        // Au moins 32 pt : sans encoche (24 pt), les contrôles de 26 à 30 pt tiennent.
        .frame(height: max(vm.deviceNotchRect.height, 32))
    }

    /// ZStack : pendant le passage onglets ↔ réglages, les deux contenus se
    /// superposent au lieu de s'aligner côte à côte (l'encoche ne bouge pas).
    private var leading: some View {
        ZStack(alignment: .trailing) {
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
    }

    private var trailing: some View {
        HStack(spacing: 10) {
            if let state = hud.current {
                HStack(spacing: 6) {
                    Image(systemName: HUDIcon.systemImage(kind: state.kind, level: state.level, isMuted: state.isMuted))
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    HUDLevelBar(level: state.level, dimmed: state.isMuted, height: 4)
                        .frame(width: 60)
                }
                .foregroundStyle(DS.Color.textSecondary)
                .animation(DS.Motion.micro, value: state)
                .transition(.opacity)
            } else if battery.hasBattery {
                Text("\(battery.percent) %")
                    .font(DS.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textSecondary)
                    .contentTransition(.numericText(value: Double(battery.percent)))
                    .animation(DS.Motion.micro, value: battery.percent)
                    .transition(.opacity)
            }
            moreMenu
        }
        .animation(DS.Motion.micro, value: hud.current != nil)
    }

    /// Bouton « … » : ouvre le menu natif sous le pointeur.
    private var moreMenu: some View {
        DSIconButton("ellipsis", label: "Plus") { NotchMoreMenu.show(for: vm) }
            .accessibilityLabel(Text("Plus d'options"))
    }
}

/// Menu natif du bouton « … » : réglages, vider les fichiers, quitter
/// (+ simulation d'activité en Debug).
@MainActor
enum NotchMoreMenu {
    static func show(for vm: NotchViewModel) {
        let menu = NSMenu()
        menu.addItem(MenuActionItem("Réglages…") { vm.showSettings() })
        menu.addItem(MenuActionItem("Vider les fichiers…") { NotchActions.confirmAndClearTray(vm) })
        #if DEBUG
            menu.addItem(simulationItem(for: vm))
        #endif
        menu.addItem(.separator())
        menu.addItem(MenuActionItem("Quitter DynamicNotch") { NotchActions.confirmAndQuit(vm) })
        // Après le relâchement du bouton, pour qu'il ne reste pas enfoncé
        // pendant le suivi modal du menu.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        }
    }

    #if DEBUG
        private static func simulationItem(for vm: NotchViewModel) -> NSMenuItem {
            let submenu = NSMenu()
            for name in ActivityID.samples.map(\.debugName) + ["hudVolume", "hudBrightness"] {
                submenu.addItem(MenuActionItem(name) {
                    vm.notchClose()
                    // Laisser le panneau se fermer : ouvert, il suspend les activités.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        MainActor.assumeIsolated { ActivitySimulator.run(name) }
                    }
                })
            }
            let item = NSMenuItem(title: "Simuler une activité", action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }
    #endif
}

/// Élément de menu porteur de sa propre action. Il est sa propre cible :
/// la cible d'un `NSMenuItem` est faible, mais le menu retient l'élément.
private final class MenuActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        preconditionFailure("init(coder:) n'est pas pris en charge")
    }

    @objc private func fire() {
        MainActor.assumeIsolated { handler() }
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
