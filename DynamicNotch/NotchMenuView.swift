//
//  NotchMenuView.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/11.
//
//  Refactored on 2026/05/09 to:
//  - use the Design System (DSIconTile) instead of the bespoke ColorButton,
//  - add confirmation dialogs on destructive actions (Clear / Quit) so a
//    stray click can never wipe the tray or kill the app silently,
//  - differentiate destructive (Quit, red) from cautionary (Clear, orange)
//    so the user reads the hierarchy at a glance.
//

import SwiftUI

struct NotchMenuView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            settingsTile
            clearTile
            quitTile
        }
    }

    // MARK: tiles

    private var settingsTile: some View {
        DSIconTile(
            systemImage: "gear",
            title: "Réglages",
            tone: .brand
        ) {
            vm.showSettings()
        }
    }

    private var clearTile: some View {
        DSIconTile(
            systemImage: "trash",
            title: "Vider",
            tone: .warning
        ) {
            confirmAndClear()
        }
    }

    private var quitTile: some View {
        DSIconTile(
            systemImage: "power",
            title: "Quitter",
            tone: .destructive
        ) {
            confirmAndQuit()
        }
    }

    // MARK: confirmations

    private func confirmAndClear() {
        let count = tvm.items.count
        guard count > 0 else {
            vm.notchClose()
            return
        }
        let title = "Vider tous les fichiers stockés ?"
        let message = "\(count) fichier(s) seront supprimés de DynamicNotch. Vos originaux sur le disque ne sont pas affectés."
        if NSAlert.popConfirm(title: title, message: message, confirm: "Vider", destructive: true) {
            tvm.removeAll()
        }
        vm.notchClose()
    }

    private func confirmAndQuit() {
        let title = "Quitter DynamicNotch ?"
        let message = "L'encoche cessera de répondre jusqu'à ce que vous relanciez DynamicNotch."
        if NSAlert.popConfirm(title: title, message: message, confirm: "Quitter", destructive: true) {
            vm.notchClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.terminate(nil)
            }
        }
    }
}

#Preview {
    NotchMenuView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
