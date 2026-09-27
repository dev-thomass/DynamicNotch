//
//  MediaKey.swift
//  DynamicNotch
//
//  Touches système volume / luminosité, décodées depuis les événements
//  NX_SYSDEFINED (sous-type 8), et calcul des pas de réglage.
//

import AppKit

enum MediaKey: Equatable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    /// Codes `NX_KEYTYPE_*` d'IOKit (hidsystem/ev_keymap.h).
    init?(keyCode: Int) {
        switch keyCode {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        default: return nil
        }
    }
}

struct MediaKeyEvent: Equatable {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    /// ⌥⇧ maintenus : pas fin (1/64).
    let fine: Bool

    /// Décode un événement système : `data1` porte le code de touche (bits 16–31),
    /// l'état (bits 8–15 : 0x0A appui, 0x0B relâchement) et la répétition (bit 0).
    static func decode(subtype: Int, data1: Int, modifiers: NSEvent.ModifierFlags) -> MediaKeyEvent? {
        guard subtype == 8 else { return nil }
        guard let key = MediaKey(keyCode: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let state = (data1 & 0xFF00) >> 8
        guard state == 0x0A || state == 0x0B else { return nil }
        return MediaKeyEvent(
            key: key,
            isDown: state == 0x0A,
            isRepeat: data1 & 0x1 == 1,
            fine: modifiers.contains(.option) && modifiers.contains(.shift)
        )
    }
}

enum LevelStep {
    static let coarse = 1.0 / 16
    static let fine = 1.0 / 64

    /// Niveau suivant, recalé sur la grille du pas (comme macOS) et borné à [0, 1].
    static func next(level: Double, up: Bool, fine: Bool) -> Double {
        let step = fine ? Self.fine : coarse
        let index = (level / step).rounded() + (up ? 1 : -1)
        return min(1, max(0, index * step))
    }
}
