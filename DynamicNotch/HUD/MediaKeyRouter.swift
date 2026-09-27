//
//  MediaKeyRouter.swift
//  DynamicNotch
//
//  Décide quelles touches consommer (réponse immédiate, lisible hors du
//  MainActor depuis le rappel du tap) et applique les touches consommées :
//  pas de volume ou de luminosité, muet, affichage du HUD, son de retour.
//

import Foundation

/// Instantané protégé par verrou : le rappel du tap le lit sans attendre le fil principal.
final class MediaKeyPolicy: @unchecked Sendable {
    struct Snapshot: Equatable {
        var replaceEnabled = false
        var trusted = false
        var volumeSettable = false
        var brightnessAvailable = false
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()

    func update(_ new: Snapshot) {
        lock.lock()
        snapshot = new
        lock.unlock()
    }

    var current: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func shouldConsume(_ key: MediaKey) -> Bool {
        let s = current
        guard s.replaceEnabled, s.trusted else { return false }
        return key.isVolume ? s.volumeSettable : s.brightnessAvailable
    }
}

@MainActor
final class MediaKeyRouter {
    let policy: MediaKeyPolicy
    var replaceEnabled = true
    var trusted = false

    private let volume: VolumeControl
    private let brightness: BrightnessControl
    private let hud: HUDController
    private let playFeedback: () -> Void

    init(
        volume: VolumeControl,
        brightness: BrightnessControl,
        hud: HUDController,
        policy: MediaKeyPolicy,
        playFeedback: @escaping () -> Void
    ) {
        self.volume = volume
        self.brightness = brightness
        self.hud = hud
        self.policy = policy
        self.playFeedback = playFeedback
        volume.onVolumeChange = { [weak self] in self?.volumeChangedExternally() }
        volume.onDeviceChange = { [weak self] in self?.refreshPolicy() }
    }

    /// Recalcule la réponse immédiate du tap.
    func refreshPolicy() {
        policy.update(MediaKeyPolicy.Snapshot(
            replaceEnabled: replaceEnabled,
            trusted: trusted,
            volumeSettable: volume.isSettable,
            brightnessAvailable: brightness.isAvailable
        ))
    }

    /// Applique une touche consommée. Les relâchements ne font rien.
    func apply(_ event: MediaKeyEvent) {
        guard event.isDown else { return }
        switch event.key {
        case .volumeUp, .volumeDown:
            let up = event.key == .volumeUp
            if up, volume.isMuted { volume.setMuted(false) }
            volume.setLevel(LevelStep.next(level: volume.level, up: up, fine: event.fine))
            showVolume()
            playFeedback()
        case .mute:
            volume.setMuted(!volume.isMuted)
            showVolume()
        case .brightnessUp, .brightnessDown:
            let up = event.key == .brightnessUp
            brightness.setLevel(LevelStep.next(level: brightness.level, up: up, fine: event.fine))
            hud.show(HUDState(kind: .brightness, level: brightness.level))
        }
    }

    /// Volume changé hors de nos touches (Centre de contrôle, autre app, cohabitation).
    func volumeChangedExternally() {
        showVolume()
    }

    private func showVolume() {
        hud.show(HUDState(kind: .volume, level: volume.level, isMuted: volume.isMuted))
    }
}
