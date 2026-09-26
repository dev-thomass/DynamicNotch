//
//  NotchHeaderView.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/7.
//
//  Refactored on 2026-05-09 to use DSNotchHeader and replace the legacy
//  "tap title to cycle" navigation anti-pattern with explicit header buttons.
//

import SwiftUI

struct NotchHeaderView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        DSNotchHeader(
            title: title,
            showsBack: vm.contentType == .settings,
            onBack: { vm.closeSettings() },
            pageNav: nil,
            onAction: handle(action:)
        )
    }

    private var title: LocalizedStringKey {
        switch vm.contentType {
        case let .tab(tab): LocalizedStringKey(tab.title)
        case .settings: "Réglages"
        }
    }

    private func handle(action: DSNotchHeader.Action) {
        switch action {
        case .menu:
            // Provisoire : onglet suivant (la barre d'onglets arrive en tâche 3).
            let next = NotchTab(rawValue: ((vm.currentTab ?? vm.lastTab).rawValue + 1) % NotchTab.allCases.count) ?? .home
            vm.selectTab(next)
        case .settings:
            vm.showSettings()
        case .close:
            vm.notchClose()
        }
    }
}

#Preview {
    NotchHeaderView(vm: .init())
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}
