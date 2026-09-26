//
//  Activity.swift
//  DynamicNotch
//
//  Catalogue des activités affichables par l'encoche. Une même valeur sert en
//  mode ponctuel (état étendu) et persistant (ailes compactes) : c'est ce qui
//  permet l'animation continue de l'un à l'autre.
//

import Foundation

enum ActivityID: Hashable {
    case charging
    case unplugged
    case lowBattery(percent: Int)
    case pomodoroPhase
    case stopwatch
    case filesAdded(count: Int)
    case airDropSent
    case nowPlaying
    case calendarSoon

    /// Durée d'affichage en mode étendu quand l'activité est ponctuelle.
    var transientDuration: TimeInterval {
        switch self {
        case .charging: 2.2
        case .unplugged: 1.5
        case .lowBattery: 3
        case .pomodoroPhase: 2.5
        case .filesAdded, .airDropSent: 1.2
        case .nowPlaying: 2
        case .stopwatch, .calendarSoon: 2
        }
    }

    /// Priorité en mode persistant : la plus haute occupe les ailes.
    var persistentPriority: Int {
        switch self {
        case .pomodoroPhase: 40
        case .stopwatch: 30
        case .nowPlaying: 20
        case .calendarSoon: 15
        case .charging: 10
        case .unplugged, .lowBattery, .filesAdded, .airDropSent: 0
        }
    }

    /// Une valeur de chaque cas, pour la simulation et le rendu Debug.
    static let samples: [ActivityID] = [
        .charging, .unplugged, .lowBattery(percent: 10), .pomodoroPhase, .stopwatch,
        .filesAdded(count: 3), .airDropSent, .nowPlaying, .calendarSoon,
    ]

    /// Nom court (« charging », « lowBattery », …) pour la ligne de commande et les fichiers.
    var debugName: String {
        String(describing: self).components(separatedBy: "(").first ?? "activity"
    }
}

/// Ce que l'encoche doit afficher à un instant donné.
struct ActivityDisplay: Equatable {
    enum Mode: Equatable { case compact, expanded }
    let id: ActivityID
    let mode: Mode
}
