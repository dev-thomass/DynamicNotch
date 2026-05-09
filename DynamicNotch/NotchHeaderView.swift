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
    @StateObject var vm: NotchViewModel

    var body: some View {
        DSNotchHeader(
            title: title,
            showsBack: vm.contentType != .normal,
            onBack: { vm.contentType = .normal },
            pageNav: pageNavConfig,
            onAction: handle(action:)
        )
        .animation(vm.animation, value: vm.contentType)
    }

    /// Affiche la navigation de pages dans le header uniquement quand on est
    /// en mode `.normal` (vue widgets) ET qu'il y a plus d'une page.
    /// L'animation `vm.animation` est appliquée pour un changement fluide.
    private var pageNavConfig: DSNotchHeader.PageNavigation? {
        guard vm.contentType == .normal, vm.widgetPages.count > 1 else { return nil }
        return .init(
            currentPage: vm.currentPage,
            totalPages: vm.widgetPages.count,
            onPrev: { withAnimation(vm.animation) { vm.previousPage() } },
            onNext: { withAnimation(vm.animation) { vm.nextPage() } }
        )
    }

    private var title: LocalizedStringKey {
        switch vm.contentType {
        case .normal:   "DynamicNotch"
        case .menu:     "Menu"
        case .settings: "Réglages"
        }
    }

    private func handle(action: DSNotchHeader.Action) {
        switch action {
        case .menu:
            vm.contentType = (vm.contentType == .menu) ? .normal : .menu
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
