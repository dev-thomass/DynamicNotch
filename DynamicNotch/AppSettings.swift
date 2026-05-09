//
//  AppSettings.swift
//  DynamicNotch
//
//  Source de vérité unique pour toutes les préférences observables persistées
//  qui ne sont pas spécifiques à un widget. Les widgets gardent leurs propres
//  réglages dans leurs modèles (PomodoroDurations restent ici parce qu'elles
//  pilotent la valeur initiale du modèle au boot).
//

import Foundation
import SwiftUI

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private init() {}

    // MARK: display

    /// Quel écran héberge l'encoche. Voir `DisplayPreference`.
    @PublishedPersist(key: "displayPreference", defaultValue: .builtInWithNotch)
    var displayPreference: DisplayPreference

    /// Force le mode "pilule" même sur les Mac qui ont une encoche matérielle.
    /// Utile sur les écrans externes ou pour ceux qui préfèrent l'esthétique
    /// pilule à la silhouette à coins concaves.
    @PublishedPersist(key: "forcePillMode", defaultValue: false)
    var forcePillMode: Bool

    // MARK: appearance

    /// Multiplicateur d'opacité du shell quand l'encoche est au repos.
    /// 1.0 = totalement opaque (défaut), 0.4 = fantôme (pratique sur fond clair).
    @PublishedPersist(key: "notchOpacity", defaultValue: 1.0)
    var notchOpacity: Double

    // MARK: behaviour

    /// Quand `false`, le survol n'enclenche plus l'animation `.popping`.
    /// Certains trouvent l'effet visuellement bruyant.
    @PublishedPersist(key: "popOnHoverEnabled", defaultValue: true)
    var popOnHoverEnabled: Bool

    /// Garde l'encoche visible même quand elle est fermée (pas de fade vers
    /// l'opacité 0.3 après 0.5 s). Pratique pour ceux qui aiment voir où
    /// elle se trouve en permanence.
    @PublishedPersist(key: "alwaysVisibleWhenClosed", defaultValue: false)
    var alwaysVisibleWhenClosed: Bool

    /// Active la fermeture par la touche Escape quand l'encoche est ouverte.
    /// Désactivable pour ceux qui utilisent Esc dans une autre app et
    /// trouveraient gênant qu'elle ferme l'encoche en parallèle.
    @PublishedPersist(key: "escClosesNotch", defaultValue: true)
    var escClosesNotch: Bool

    // MARK: pomodoro durations (in minutes)

    @PublishedPersist(key: "pomodoroFocusMinutes", defaultValue: 25)
    var pomodoroFocusMinutes: Int

    @PublishedPersist(key: "pomodoroShortBreakMinutes", defaultValue: 5)
    var pomodoroShortBreakMinutes: Int

    @PublishedPersist(key: "pomodoroLongBreakMinutes", defaultValue: 15)
    var pomodoroLongBreakMinutes: Int

    @PublishedPersist(key: "pomodoroCyclesBeforeLongBreak", defaultValue: 4)
    var pomodoroCyclesBeforeLongBreak: Int
}
