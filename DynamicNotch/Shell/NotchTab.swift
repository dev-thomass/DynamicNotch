//
//  NotchTab.swift
//  DynamicNotch
//
//  Onglets du panneau ouvert, dans l'ordre d'affichage de la barre.
//

import SwiftUI

enum NotchTab: Int, CaseIterable, Codable, Identifiable {
    case home, files, timers, notes, agenda, clipboard

    var id: Int {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .files: "tray.full.fill"
        case .timers: "timer"
        case .notes: "note.text"
        case .agenda: "calendar"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .files: "Fichiers"
        case .timers: "Minuteurs"
        case .notes: "Notes"
        case .agenda: "Agenda"
        case .clipboard: "Presse-papiers"
        }
    }

    /// Hauteur du panneau (le corps de la coque) pour cet onglet.
    var panelHeight: CGFloat {
        switch self {
        case .home, .files, .timers: 190
        case .notes, .clipboard: 220
        case .agenda: 260
        }
    }

    /// Bord par lequel arrive le contenu quand on passe de `from` à `to` :
    /// depuis la droite si l'onglet visé est à droite (ou le même).
    static func slideEdge(from: NotchTab, to: NotchTab) -> Edge {
        to.rawValue >= from.rawValue ? .trailing : .leading
    }
}
