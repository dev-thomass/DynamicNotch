//
//  PomodoroNotifier.swift
//  DynamicNotch
//
//  Notification macOS à la fin naturelle d'une phase Pomodoro, pour la voir
//  même quand l'encoche est masquée (app en plein écran, autre écran). Le son
//  « Glass » est déjà joué par ActivityWiring : la notification reste muette.
//

import Foundation
import UserNotifications

enum PomodoroNotifier {
    struct Message: Equatable {
        let title: String
        let body: String
    }

    /// Texte de la notification à l'entrée dans `phase`. `nil` pour `.idle`.
    static func message(enteringPhase phase: PomodoroModel.Phase, minutes: Int) -> Message? {
        switch phase {
        case .idle:
            nil
        case .work:
            Message(title: "Pause terminée", body: "On reprend : \(minutes) min de focus.")
        case .shortBreak:
            Message(title: "Focus terminé", body: "Pause de \(minutes) min.")
        case .longBreak:
            Message(title: "Focus terminé", body: "Pause longue de \(minutes) min, bien méritée.")
        }
    }

    /// Demande l'autorisation au premier appel, puis affiche la notification.
    static func notify(enteringPhase phase: PomodoroModel.Phase, minutes: Int) {
        guard let message = message(enteringPhase: phase, minutes: minutes) else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert]) else { return }
                let content = UNMutableNotificationContent()
                content.title = message.title
                content.body = message.body
                let request = UNNotificationRequest(
                    identifier: "pomodoro-phase",
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
            } catch {
                Log.app.error("pomodoro notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
