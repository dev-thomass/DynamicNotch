//
//  TrayDrop+DropItemView.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/8.
//

import Foundation
import Pow
import SwiftUI
import UniformTypeIdentifiers

struct DropItemView: View {

    /// Extensions whose tap-to-open could execute foreign code. We always
    /// prompt the user before handing one of these to NSWorkspace.
    private static let executableExtensions: Set<String> = [
        "app", "pkg", "dmg", "command", "tool", "scpt", "scptd",
        "workflow", "shortcut", "applescript", "jar"
    ]

    let item: TrayDrop.DropItem
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State var hover = false

    var body: some View {
        VStack {
            Image(nsImage: item.workspacePreviewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 64)
                .accessibilityHidden(true)
            Text(item.fileName)
                .multilineTextAlignment(.center)
                .font(.system(.footnote, design: .rounded))
                .frame(maxWidth: 64)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.fileName))
        .accessibilityHint(Text("Double-cliquez pour ouvrir. Maintenez Option et cliquez sur le X pour supprimer."))
        .accessibilityAddTraits(.isButton)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale),
            removal: .movingParts.poof
        ))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .scaleEffect(hover ? 1.05 : 1.0)
        .animation(vm.animation, value: hover)
        .draggable(item)
        .onTapGesture {
            guard !vm.optionKeyPressed else { return }
            // Guard against opening executables/installers without confirmation
            // (a malicious .app dropped into the tray could otherwise be one
            // tap away from running). Defer the workspace launch until *after*
            // the notch close animation finishes — 0.25 s matches DS.Motion.base
            // and feels instantaneous, vs. the previous 0.5 s which read as lag.
            let fileURL = item.storageURL
            vm.notchClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                openTappedItem(at: fileURL)
            }
        }
        .overlay {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.red)
                .background(Color.white.clipShape(Circle()).padding(1))
                .frame(width: vm.spacing, height: vm.spacing)
                .opacity(vm.optionKeyPressed ? 1 : 0)
                .scaleEffect(vm.optionKeyPressed ? 1 : 0.5)
                .animation(vm.animation, value: vm.optionKeyPressed)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: vm.spacing / 2, y: -vm.spacing / 2)
                .onTapGesture { tvm.delete(item.id) }
                .accessibilityLabel(Text("Supprimer \(item.fileName)"))
        }
    }

    /// Open a tapped tray item, prompting the user first if the file is the
    /// kind of thing that could run foreign code on launch.
    private func openTappedItem(at url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.executableExtensions.contains(ext) {
            let title = "Ouvrir un fichier exécutable ?"
            let message = "« \(url.lastPathComponent) » est un fichier \(ext.uppercased()). L'ouvrir peut exécuter du code sur votre Mac. Ne continuez que si vous faites confiance à la source."
            guard NSAlert.popConfirm(
                title: title,
                message: message,
                confirm: "Ouvrir",
                destructive: true
            ) else { return }
        }
        NSWorkspace.shared.open(url)
    }
}
