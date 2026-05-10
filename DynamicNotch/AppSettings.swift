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

    // MARK: wings (extensions latérales de l'encoche)

    /// Active globalement le système de wings — quand `false`, l'encoche
    /// reste à sa taille native même si batterie en charge / chrono actif.
    @PublishedPersist(key: "wingsEnabled", defaultValue: true)
    var wingsEnabled: Bool

    /// Affiche l'icône batterie + pourcentage à gauche/droite quand la
    /// machine est branchée sur secteur.
    @PublishedPersist(key: "wingBattery", defaultValue: true)
    var wingBattery: Bool

    /// Affiche `mm | ss` quand le chronomètre tourne.
    @PublishedPersist(key: "wingStopwatch", defaultValue: true)
    var wingStopwatch: Bool

    /// Affiche le temps restant du pomodoro tant qu'une session est active.
    @PublishedPersist(key: "wingPomodoro", defaultValue: true)
    var wingPomodoro: Bool

    /// Affiche le countdown vers le prochain événement (si dans < 60 min).
    @PublishedPersist(key: "wingCalendar", defaultValue: true)
    var wingCalendar: Bool

    // MARK: HUD système

    /// Quand `true`, on capture les touches volume/mute via `CGEvent.tapCreate`
    /// et on les CONSOMME → le HUD natif macOS ne s'affiche plus, seul le
    /// nôtre est visible. Demande la permission Accessibility ; sans elle
    /// on retombe sur le mode "lecture seule" (HUD natif coexistant).
    @PublishedPersist(key: "suppressNativeHUD", defaultValue: false)
    var suppressNativeHUD: Bool
}
