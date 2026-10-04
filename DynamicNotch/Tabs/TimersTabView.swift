//
//  TimersTabView.swift
//  DynamicNotch
//
//  Chrono et Pomodoro côte à côte.
//

import SwiftUI

struct TimersTabView: View {
    var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            StopwatchWidgetView(vm: vm)
            PomodoroWidgetView(vm: vm)
        }
    }
}
