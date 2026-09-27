//
//  SystemControls.swift
//  DynamicNotch
//
//  Interfaces des réglages système utilisés par le HUD. Les implémentations
//  réelles parlent à CoreAudio et DisplayServices ; les tests utilisent des doublures.
//

import Foundation

@MainActor
protocol VolumeControl: AnyObject {
    /// La sortie actuelle permet-elle de régler le volume principal ?
    var isSettable: Bool { get }
    /// 0…1
    var level: Double { get }
    var isMuted: Bool { get }
    func setLevel(_ level: Double)
    func setMuted(_ muted: Bool)
    /// Volume ou muet modifié (par nous ou ailleurs), sur la file principale.
    var onVolumeChange: (() -> Void)? { get set }
    /// Sortie audio par défaut changée, sur la file principale.
    var onDeviceChange: (() -> Void)? { get set }
}

@MainActor
protocol BrightnessControl: AnyObject {
    /// Écran intégré présent et réglable.
    var isAvailable: Bool { get }
    /// 0…1 (0 si indisponible)
    var level: Double { get }
    func setLevel(_ level: Double)
}
