//
//  NotchContentView.swift
//  DynamicNotch
//
//  Corps du panneau ouvert : l'onglet courant ou les réglages.
//

import SwiftUI

struct NotchContentView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        switch vm.contentType {
        case let .tab(tab):
            tabContent(tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(tab)
                .transition(.tabSlide(from: vm.tabSlideEdge))
        case .settings:
            NotchSettingsView(vm: vm)
                .transition(.emerge)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: NotchTab) -> some View {
        switch tab {
        case .home:
            HomeTabView(vm: vm)
        case .files:
            FilesTabView(vm: vm)
        case .timers:
            TimersTabView(vm: vm)
        case .notes:
            NoteView(vm: vm)
        case .agenda:
            AgendaTabView()
        }
    }
}
