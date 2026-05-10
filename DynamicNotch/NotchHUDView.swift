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
    }

    private func observeBrightness() {
        // Source 1 : event clavier intercepté (immédiat, mode CGEvent.tapCreate)
        MediaKeyInterceptor.shared.brightnessChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.showBrightness(level: level)
            }
            .store(in: &cancellables)
        // Source 2 : polling 1Hz du BrightnessManager (mode lecture seule
        // ou changement externe — slider menubar, ambient sensor, etc.)
        BrightnessManager.shared.$level
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.showBrightness(level: level)
            }
            .store(in: &cancellables)
    }
}
