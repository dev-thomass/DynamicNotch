//
//  WingLayout.swift
//  DynamicNotch
//
//  Largeur des ailes compactes. On mesure la valeur la plus large possible de
//  chaque activité (« 100 % », « 00:00 », …) avec la police des ailes : la
//  coque ne « respire » pas quand les chiffres changent, et le calcul est
//  déterministe (pas de boucle de layout).
//

import AppKit

enum WingLayout {
    /// Marge entre le bord extérieur de l'aile et son contenu.
    static let padding: CGFloat = 12
    static let iconWidth: CGFloat = 24
    static let minimumWing: CGFloat = 36
    /// Même police que `DS.Typography.wing`.
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    /// Valeur la plus large affichée dans l'aile droite, `nil` pour un graphisme.
    static func template(for id: ActivityID) -> String? {
        switch id {
        case .charging, .unplugged, .lowBattery: "100 %"
        case .stopwatch, .pomodoroPhase: "00:00"
        case .calendarSoon: "60 min"
        case .nowPlaying, .filesAdded, .airDropSent: nil
        }
    }

    static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Largeur d'UNE aile. Les deux ailes sont égales pour que la coque reste
    /// centrée sur l'encoche physique.
    static func wingWidth(for id: ActivityID) -> CGFloat {
        let leading = iconWidth + padding
        let trailing = template(for: id).map { textWidth($0) + 2 * padding } ?? leading
        return max(minimumWing, leading, trailing)
    }

    /// Largeur ajoutée à l'encoche par les deux ailes, alignée au pixel.
    static func wingsWidth(for id: ActivityID, scale: CGFloat) -> CGFloat {
        pixelAligned(2 * wingWidth(for: id), scale: scale)
    }
}
