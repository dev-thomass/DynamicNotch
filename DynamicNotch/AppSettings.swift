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
import Observation

@Observable
final class AppSettings: PersistObservable {
    static let shared = AppSettings()

    private init() {}

    // MARK: display

    /// Quel écran héberge l'encoche. Voir `DisplayPreference`.
    @ObservationIgnored
    @PublishedPersist(key: "displayPreference", defaultValue: .builtInWithNotch)
    var displayPreference: DisplayPreference

    /// Force le mode "pilule" même sur les Mac qui ont une encoche matérielle.
    @ObservationIgnored
    @PublishedPersist(key: "forcePillMode", defaultValue: false)
    var forcePillMode: Bool

    /// Affiche l'encoche sur TOUS les écrans connectés simultanément (pas
    /// seulement celui désigné par `displayPreference`). Utile si tu utilises
    /// le HUD volume ou tu veux des wings batterie sur n'importe quel écran
    /// que tu regardes.
    @ObservationIgnored
    @PublishedPersist(key: "showOnAllScreens", defaultValue: false)
    var showOnAllScreens: Bool

    // MARK: behaviour

    /// Quand `false`, le survol n'enclenche plus l'aperçu (`.peek`).
    /// Certains trouvent l'effet visuellement bruyant.
    @ObservationIgnored
    @PublishedPersist(key: "popOnHoverEnabled", defaultValue: true)
    var popOnHoverEnabled: Bool

    /// Garde l'encoche visible même quand elle est fermée (pas de fade vers
    /// l'opacité 0.3 après 0.5 s). Pratique pour ceux qui aiment voir où
    /// elle se trouve en permanence.
    @ObservationIgnored
    @PublishedPersist(key: "alwaysVisibleWhenClosed", defaultValue: false)
    var alwaysVisibleWhenClosed: Bool

    /// Active la fermeture par la touche Escape quand l'encoche est ouverte.
    /// Désactivable pour ceux qui utilisent Esc dans une autre app et
    /// trouveraient gênant qu'elle ferme l'encoche en parallèle.
    @ObservationIgnored
    @PublishedPersist(key: "escClosesNotch", defaultValue: true)
    var escClosesNotch: Bool

    // MARK: pomodoro durations (in minutes)

    @ObservationIgnored
    @PublishedPersist(key: "pomodoroFocusMinutes", defaultValue: 25)
    var pomodoroFocusMinutes: Int

    @ObservationIgnored
    @PublishedPersist(key: "pomodoroShortBreakMinutes", defaultValue: 5)
    var pomodoroShortBreakMinutes: Int

    @ObservationIgnored
    @PublishedPersist(key: "pomodoroLongBreakMinutes", defaultValue: 15)
    var pomodoroLongBreakMinutes: Int

    @ObservationIgnored
    @PublishedPersist(key: "pomodoroCyclesBeforeLongBreak", defaultValue: 4)
    var pomodoroCyclesBeforeLongBreak: Int

    /// Notification macOS à la fin de chaque phase (visible même encoche masquée).
    @ObservationIgnored
    @PublishedPersist(key: "pomodoroNotifications", defaultValue: true)
    var pomodoroNotifications: Bool

    // MARK: clipboard

    /// Historique des textes copiés (onglet Presse-papiers), en mémoire seulement.
    @ObservationIgnored
    @PublishedPersist(key: "clipboardHistoryEnabled", defaultValue: true)
    var clipboardHistoryEnabled: Bool

    // MARK: shortcut

    /// Raccourci global ⌃⌥N pour ouvrir ou fermer l'encoche.
    @ObservationIgnored
    @PublishedPersist(key: "globalShortcutEnabled", defaultValue: true)
    var globalShortcutEnabled: Bool

    // MARK: weather

    /// Ville de la météo (Accueil). Vide : météo désactivée, aucune requête.
    @ObservationIgnored
    @PublishedPersist(key: "weatherCity", defaultValue: "")
    var weatherCity: String

    // MARK: wings (extensions latérales de l'encoche)

    /// Active globalement le système de wings — quand `false`, l'encoche
    /// reste à sa taille native même si batterie en charge / chrono actif.
    @ObservationIgnored
    @PublishedPersist(key: "wingsEnabled", defaultValue: true)
    var wingsEnabled: Bool

    /// Affiche l'icône batterie + pourcentage à gauche/droite quand la
    /// machine est branchée sur secteur.
    @ObservationIgnored
    @PublishedPersist(key: "wingBattery", defaultValue: true)
    var wingBattery: Bool

    /// Affiche `mm | ss` quand le chronomètre tourne.
    @ObservationIgnored
    @PublishedPersist(key: "wingStopwatch", defaultValue: true)
    var wingStopwatch: Bool

    /// Affiche le temps restant du pomodoro tant qu'une session est active.
    @ObservationIgnored
    @PublishedPersist(key: "wingPomodoro", defaultValue: true)
    var wingPomodoro: Bool

    /// Affiche le countdown vers le prochain événement (si dans < 60 min).
    @ObservationIgnored
    @PublishedPersist(key: "wingCalendar", defaultValue: true)
    var wingCalendar: Bool
}
