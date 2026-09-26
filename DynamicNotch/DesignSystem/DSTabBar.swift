//
//  DSTabBar.swift
//  DynamicNotch
//
//  Barre d'onglets de la rangée de l'encoche : icônes 14 pt, pastille de
//  sélection qui glisse d'un onglet à l'autre, rebond à la sélection.
//

import SwiftUI

struct DSTabBar: View {
    let selection: NotchTab
    let onSelect: (NotchTab) -> Void

    @Namespace private var pill
    @State private var bounces: [NotchTab: Int] = [:]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    bounces[tab, default: 0] += 1
                    onSelect(tab)
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .symbolEffect(.bounce, value: bounces[tab, default: 0])
                        .foregroundStyle(tab == selection ? DS.Color.textPrimary : DS.Color.textSecondary)
                        .frame(width: 30, height: 26)
                        .background {
                            if tab == selection {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "selection", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(tab.title))
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .animation(DS.Motion.micro, value: selection)
    }
}
