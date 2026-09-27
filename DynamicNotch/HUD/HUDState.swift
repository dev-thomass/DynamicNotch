//
//  HUDState.swift
//  DynamicNotch
//
//  Ce que montre le HUD : type, niveau, muet ; et l'icône correspondante.
//

import Foundation

enum HUDKind: Hashable {
    case volume, brightness
}

struct HUDState: Equatable {
    var kind: HUDKind
    var level: Double
    var isMuted: Bool = false

    var percent: Int { Int((level * 100).rounded()) }
}

enum HUDIcon {
    static func systemImage(kind: HUDKind, level: Double, isMuted: Bool) -> String {
        switch kind {
        case .volume:
            if isMuted { return "speaker.slash.fill" }
            if level <= 0 { return "speaker.fill" }
            if level < 1.0 / 3 { return "speaker.wave.1.fill" }
            if level < 2.0 / 3 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}
