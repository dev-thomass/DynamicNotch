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
        case .settings:
            NotchSettingsView(vm: vm)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: NotchTab) -> some View {
        switch tab {
        case .home:
            HStack(spacing: vm.spacing) {
                ShareView(vm: vm, type: .airdrop)
                TrayView(vm: vm)
            }
        case .files:
            TrayView(vm: vm)
        case .timers:
            HStack(spacing: vm.spacing) {
                StopwatchWidgetView(vm: vm)
                PomodoroWidgetView(vm: vm)
            }
        case .notes:
            NoteView(vm: vm)
        case .agenda:
            CalendarWidgetView(vm: vm)
        }
    }
}
