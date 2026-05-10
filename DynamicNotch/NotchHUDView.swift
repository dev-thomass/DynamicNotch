//
//  NotchHUDView.swift
//  DynamicNotch
//
//  Désormais juste un *controller* — le rendu visuel du HUD volume/luminosité
//  est intégré dans `NotchWingsView` comme une "wing prioritaire" de la
//  silhouette de l'encoche. C'est strictement une extension de la forme
//  noire, pas une bulle séparée flottante.
//
//  Le `HUDController` expose `current: HUDKind?` que `WingsResolver`
//  consulte. Tant que `current != nil`, l'encoche s'élargit et affiche le
//  contenu HUD à droite (icône blanche + barre fine blanche).
//

import Combine
import SwiftUI

@MainActor
final class HUDController: ObservableObject {
    static let shared = HUDController()

    enum HUDKind: Equatable {
        case volume(level: Float, muted: Bool)
        case brightness(level: Float)
    }

    @Published private(set) var current: HUDKind?

    private var hideTask: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeMediaKeys()
        observeBrightness()
    }

    func showVolume(level: Float, muted: Bool) {
        current = .volume(level: level, muted: muted)
        scheduleHide()
    }

    func showBrightness(level: Float) {
        current = .brightness(level: level)
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.current = nil
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func observeMediaKeys() {
        // Source 1 : event clavier intercepté en mode CGEvent.tapCreate
        // (HUD natif supprimé). Immédiat, pas de race.
        MediaKeyInterceptor.shared.volumeChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.showVolume(level: level, muted: VolumeManager.shared.isMuted)
            }
            .store(in: &cancellables)
        MediaKeyInterceptor.shared.volumeMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.showVolume(level: VolumeManager.shared.level, muted: muted)
            }
            .store(in: &cancellables)
        // Source 2 : changement EXTERNE du volume détecté par le listener
        // CoreAudio installé dans VolumeManager (mode NSEvent fallback,
        // changement via menubar slider, AppleScript, etc.). Sans ça, en
        // mode lecture seule le système changeait le volume mais le HUD
        // ne se déclenchait jamais — l'utilisateur ne savait pas où il
        // en était.
        VolumeManager.shared.$level
            .removeDuplicates { abs($0 - $1) < 0.005 }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.showVolume(level: level, muted: VolumeManager.shared.isMuted)
            }
            .store(in: &cancellables)
        VolumeManager.shared.$isMuted
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.showVolume(level: VolumeManager.shared.level, muted: muted)
            }
            .store(in: &cancellables)
    }

    private func observeBrightness() {
        // Source UNIQUE : event clavier intercepté.
        // Le polling 1Hz du BrightnessManager déclenchait le HUD à chaque
        // micro-variation détectée (ambient light sensor, transitions
        // smooth du système) → HUD parasite qui apparaissait sans raison.
        // On garde le polling pour rester sync sur la valeur affichée,
        // mais sans déclencher le HUD.
        MediaKeyInterceptor.shared.brightnessChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.showBrightness(level: level)
            }
            .store(in: &cancellables)
    }
}
