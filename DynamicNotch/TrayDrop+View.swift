//
//  TrayDrop+View.swift
//  DynamicNotch
//
//  Widget Files. Refondu pour utiliser le DSDropZone, et présente en bas
//  deux actions discrètes : une corbeille drop-zone (déposer un fichier
//  pour le supprimer) + un bouton "Tout supprimer" avec confirmation.
//

import SwiftUI

struct TrayView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State private var targeting = false
    @State private var trashTargeting = false

    var storageTime: String {
        switch tvm.selectedFileStorageTime {
        case .oneHour:   return "une heure"
        case .oneDay:    return "un jour"
        case .twoDays:   return "deux jours"
        case .threeDays: return "trois jours"
        case .oneWeek:   return "une semaine"
        case .never:     return "toujours"
        case .custom:
            let unit: String
            switch tvm.customStorageTimeUnit {
            case .hours:  unit = "heures"
            case .days:   unit = "jours"
            case .weeks:  unit = "semaines"
            case .months: unit = "mois"
            case .years:  unit = "ans"
            }
            return "\(tvm.customStorageTime) \(unit)"
        }
    }

    var body: some View {
        DSDropZone(isTargeted: targeting, isLoading: tvm.isLoading > 0) {
            content.padding(DS.Spacing.sm)
        }
        .onDrop(of: [.data], isTargeted: $targeting) { providers in
            DispatchQueue.global().async { tvm.load(providers) }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Plateau de fichiers"))
        .accessibilityHint(Text("Glissez des fichiers ici pour les conserver \(storageTime)."))
    }

    @ViewBuilder
    private var content: some View {
        if tvm.isEmpty {
            emptyState
        } else {
            populated
        }
    }

    // MARK: empty

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("Glissez vos fichiers ici")
                .font(DS.Typography.bodyEmphasis)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Conservés pendant \(storageTime)")
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: populated

    private var populated: some View {
        VStack(spacing: DS.Spacing.xs) {
            // Items
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: vm.spacing) {
                    ForEach(tvm.items) { item in
                        DropItemView(item: item, vm: vm, tvm: tvm)
                    }
                }
                .padding(.horizontal, DS.Spacing.xs)
            }
            // Actions discrètes en bas-droite
            HStack(spacing: 6) {
                Spacer()
                trashDropZone
                clearAllButton
            }
            .padding(.horizontal, DS.Spacing.xs)
        }
    }

    // MARK: actions

    /// Corbeille drop-zone : si l'utilisateur drag un item du tray
    /// (DropItemView a `.draggable(item)`) et le relâche dessus, le
    /// fichier correspondant est supprimé. Match par nom de fichier
    /// (les noms sont uniques dans notre storage UUID/filename).
    private var trashDropZone: some View {
        Image(systemName: "trash")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(trashTargeting ? .white : DS.Color.textTertiary)
            .frame(width: 26, height: 18)
            .background(
                Capsule().fill(trashTargeting
                               ? DS.Color.destructive
                               : DS.Color.surfaceRaisedStrong)
            )
            .overlay(
                Capsule().strokeBorder(
                    trashTargeting ? DS.Color.destructive : DS.Color.borderSubtle,
                    lineWidth: 0.5
                )
            )
            .onDrop(of: [.fileURL, .data], isTargeted: $trashTargeting) { providers in
                handleTrashDrop(providers)
                return true
            }
            .help(Text("Glissez un fichier ici pour le supprimer"))
            .accessibilityLabel(Text("Corbeille — glissez un fichier ici pour le supprimer"))
    }

    /// Bouton "Tout supprimer" avec confirmation. Affiche le compte des
    /// items pour que l'utilisateur sache exactement ce qu'il efface.
    private var clearAllButton: some View {
        Button {
            confirmAndClearAll()
        } label: {
            Image(systemName: "xmark.bin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 26, height: 18)
                .background(Capsule().fill(DS.Color.surfaceRaisedStrong))
                .overlay(Capsule().strokeBorder(DS.Color.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(Text("Tout supprimer (\(tvm.items.count) fichier(s))"))
        .accessibilityLabel(Text("Supprimer tous les fichiers du tray"))
    }

    private func handleTrashDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let fileName = url.lastPathComponent
                Task { @MainActor in
                    // Match par nom de fichier, supprime le premier item qui
                    // correspond (les noms sont uniques par UUID parent dir).
                    if let item = TrayDrop.shared.items.first(where: { $0.fileName == fileName }) {
                        TrayDrop.shared.delete(item.id)
                    }
                }
            }
        }
    }

    private func confirmAndClearAll() {
        let count = tvm.items.count
        guard count > 0 else { return }
        let title = "Tout supprimer ?"
        let message = "\(count) fichier(s) seront retirés du tray. Vos originaux sur le disque ne sont pas affectés."
        if NSAlert.popConfirm(title: title, message: message, confirm: "Tout supprimer", destructive: true) {
            tvm.removeAll()
        }
    }
}
