//
//  TrayDrop+View.swift
//  DynamicNotch
//
//  Affichage du widget Files. Refondu pour utiliser le DSDropZone (plus
//  de bordure pointillée vintage), et tout en français.
//

import SwiftUI

struct TrayView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State private var targeting = false

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
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: vm.spacing) {
                    ForEach(tvm.items) { item in
                        DropItemView(item: item, vm: vm, tvm: tvm)
                    }
                }
                .padding(.horizontal, DS.Spacing.xs)
            }
            optionHint
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
    }

    /// Pastille discrète "⌥ pour supprimer" affichée tant qu'il y a des items.
    private var optionHint: some View {
        DSPill(
            "⌥ pour supprimer",
            systemImage: "option",
            tone: vm.optionKeyPressed ? .destructive : .neutral
        )
        .opacity(vm.optionKeyPressed ? 1.0 : 0.55)
        .animation(DS.Motion.fast, value: vm.optionKeyPressed)
    }
}
